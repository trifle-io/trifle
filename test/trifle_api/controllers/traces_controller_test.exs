defmodule TrifleApi.TracesControllerTest do
  use TrifleApp.ConnCase

  import ExUnit.CaptureLog
  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import TrifleApi.TestHelpers

  alias Trifle.Organizations
  alias Trifle.Traces.{Configuration, Reader, TraceRecord}
  alias Trifle.Traces.Driver.Data.Memory, as: Payload
  alias Trifle.Traces.Driver.Index.Memory, as: Index

  defmodule TestReader do
    def search(scope, id, filters), do: Reader.search(scope, id, filters, opts())
    def detail(scope, id, reference), do: Reader.detail(scope, id, reference, opts())

    def contents(scope, id, reference, part),
      do: Reader.contents(scope, id, reference, part, opts())

    def attachments(scope, id, reference, after_part),
      do: Reader.attachments(scope, id, reference, after_part, opts())

    def artifact(scope, id, reference, part, row),
      do: Reader.artifact(scope, id, reference, part, row, opts())

    defp opts do
      {id, config} = Process.get(__MODULE__)
      [configuration: fn %{id: ^id} -> config end]
    end
  end

  setup do
    user = user_fixture()
    {:ok, org, _membership} = Organizations.create_organization_with_owner(%{name: "Acme"}, user)
    app_entitlement_fixture(org)

    {:ok, database} =
      Organizations.create_database_for_org(org, %{
        display_name: "Trace database",
        driver: "postgres",
        host: "postgres",
        port: 5432,
        database_name: "test",
        username: "test",
        password: "test",
        trace_config: %{
          "index_name" => "api_traces",
          "data_driver" => "file",
          "data_path" => "/tmp/api-traces",
          "retention_days" => 7,
          "gzip" => true
        }
      })

    config = Configuration.new(index_driver: Index.new(), data_driver: Payload.new())
    previous = Application.fetch_env(:trifle, :trace_reader)
    Application.put_env(:trifle, :trace_reader, TestReader)
    Process.put(TestReader, {database.id, config})

    on_exit(fn ->
      case previous do
        {:ok, reader} -> Application.put_env(:trifle, :trace_reader, reader)
        :error -> Application.delete_env(:trifle, :trace_reader)
      end
    end)

    started = DateTime.utc_now() |> DateTime.truncate(:second)

    record = %TraceRecord{
      reference: "calc-b",
      key: "jobs/calculation/worker",
      state: :success,
      tags: ["customer:42", "scheduled"],
      meta: [42, %{"enabled" => true}],
      context: %{"queue" => "default"},
      counters: %{states: %{success: 5}, types: %{media: 2}},
      first_at: started,
      last_at: DateTime.add(started, 125, :millisecond),
      duration: 125,
      expires_at: DateTime.add(started, 7, :day),
      bucket_name: "private-bucket",
      parts: 12,
      length: 5
    }

    Index.create(config.index_driver, record)

    for {reference, path, tags, state, duration, first_at} <- [
          {"calc-a", record.key, record.tags, :success, 125, started},
          {"older", record.key, ["customer:42"], :success, 125,
           DateTime.add(started, -1, :second)},
          {"wrong-state", record.key, record.tags, :error, 125, started},
          {"short", record.key, record.tags, :success, 10, started},
          {"sibling", "jobs/calculations", record.tags, :success, 125, started},
          {"too-recent", record.key, record.tags, :success, 125,
           DateTime.add(started, 1, :second)}
        ] do
      Index.create(config.index_driver, %{
        record
        | reference: reference,
          key: path,
          tags: tags,
          state: state,
          duration: duration,
          first_at: first_at,
          last_at: first_at,
          length: 0,
          parts: 0
      })
    end

    Payload.write_part(config.data_driver, record, 1, [
      %{type: :head, state: :success, at: DateTime.to_unix(started) + 0.125, message: "Started"},
      %{type: :media, message: "result.txt", size: 8},
      %{type: :raw, level: 1, message: "Result 42"}
    ])

    for part <- 2..12 do
      entries =
        case part do
          11 -> [%{type: :media, message: "private.log", size: 3}]
          12 -> [%{type: :text, message: "Finished"}]
          _ -> []
        end

      Payload.write_part(config.data_driver, record, part, entries)
    end

    Payload.write_artifact(config.data_driver, record, "result.txt", payload: "result42")
    Payload.write_artifact(config.data_driver, record, "private.log", payload: "log")

    read_token = create_scoped_token!(user, org.id, :database, database.id, true, false)
    write_token = create_scoped_token!(user, org.id, :database, database.id, false, true)

    %{
      id: database.id,
      token: read_token,
      write_token: write_token,
      record: record,
      config: config,
      user: user,
      org: org
    }
  end

  test "uses metrics authentication and enforces read grants on every route",
       %{conn: conn} = ctx do
    assert %{"errors" => %{"detail" => "Bad token"}} =
             conn |> get(~p"/api/v1/traces") |> json_response(401)

    assert %{"errors" => %{"detail" => "Missing X-Trifle-Source-Id header"}} =
             conn
             |> put_req_header("authorization", "Bearer #{ctx.token}")
             |> get(~p"/api/v1/traces")
             |> json_response(400)

    for path <- [
          ~p"/api/v1/traces",
          ~p"/api/v1/traces/calc-b",
          ~p"/api/v1/traces/calc-b/entries",
          ~p"/api/v1/traces/calc-b/attachments",
          ~p"/api/v1/traces/calc-b/attachments/unknown"
        ] do
      assert %{"errors" => %{"detail" => "Forbidden"}} =
               conn |> request(ctx.write_token, ctx.id, path) |> json_response(403)
    end

    {:ok, other} =
      Organizations.create_database_for_org(ctx.org, %{
        display_name: "Other database",
        driver: "sqlite",
        file_path: "/tmp/api-traces-other.sqlite"
      })

    assert %{"errors" => %{"detail" => "Forbidden"}} =
             conn |> request(ctx.token, other.id, ~p"/api/v1/traces") |> json_response(403)

    token = create_scoped_token!(ctx.user, ctx.org.id, :database, other.id, true, false)

    assert %{"errors" => %{"detail" => "Traces are unavailable for this source"}} =
             conn |> request(token, other.id, ~p"/api/v1/traces") |> json_response(404)
  end

  test "searches with index filters and paginates without skipping tied timestamps",
       %{conn: conn} =
         ctx do
    from = DateTime.add(ctx.record.first_at, -1, :second)
    to = DateTime.add(ctx.record.first_at, 1, :second)

    filters = %{
      path: "jobs/calculation",
      tags: "customer:42,scheduled",
      state: "success",
      duration_min: 100,
      from: DateTime.to_iso8601(from),
      to: DateTime.to_iso8601(to),
      limit: 1
    }

    assert %{
             "data" => [%{"reference" => "calc-b", "duration_ms" => 125} = summary],
             "pagination" => %{"next_cursor" => cursor}
           } = conn |> read(ctx, ~p"/api/v1/traces?#{filters}") |> json_response(200)

    refute Map.has_key?(summary, "meta")
    refute Map.has_key?(summary, "bucket_name")
    assert is_binary(cursor)

    assert %{
             "data" => [%{"reference" => "calc-a"}],
             "pagination" => %{"next_cursor" => nil}
           } =
             conn
             |> read(ctx, ~p"/api/v1/traces?#{Map.put(filters, :cursor, cursor)}")
             |> json_response(200)

    filters = Map.merge(filters, %{tags: ["scheduled", "customer:42"], tag_mode: "any", limit: 5})

    assert %{"data" => traces, "pagination" => %{"next_cursor" => nil}} =
             conn |> read(ctx, ~p"/api/v1/traces?#{filters}") |> json_response(200)

    assert Enum.map(traces, & &1["reference"]) == ["calc-b", "calc-a", "older"]

    assert %{"data" => [], "pagination" => %{"next_cursor" => nil}} =
             conn |> read(ctx, ~p"/api/v1/traces?path=missing") |> json_response(200)
  end

  test "returns full record metadata independently of payload availability",
       %{conn: conn} = ctx do
    assert %{
             "data" =>
               %{
                 "reference" => "calc-b",
                 "path" => "jobs/calculation/worker",
                 "meta" => [42, %{"enabled" => true}],
                 "context" => %{"queue" => "default"},
                 "counters" => %{"states" => %{"success" => 5}},
                 "part_count" => 12,
                 "entry_count" => 5,
                 "retention_days" => 7
               } = record
           } = conn |> read(ctx, ~p"/api/v1/traces/calc-b") |> json_response(200)

    refute Map.has_key?(record, "bucket_name")

    assert %{"errors" => %{"detail" => _}} =
             conn |> read(ctx, ~p"/api/v1/traces/unknown") |> json_response(404)

    Payload.delete(ctx.config.data_driver, ctx.record)

    assert %{"data" => %{"meta" => [42 | _]}} =
             conn |> read(ctx, ~p"/api/v1/traces/calc-b") |> json_response(200)

    capture_log(fn ->
      assert %{"errors" => %{"detail" => "Trace storage is unavailable"}} =
               conn |> read(ctx, ~p"/api/v1/traces/calc-b/entries") |> json_response(503)
    end)
  end

  test "reads entries in order within a part and continues to the next part",
       %{conn: conn} = ctx do
    assert %{
             "data" => [
               %{"part" => 1, "row" => 0, "type" => "head", "message" => "Started"} = entry
             ],
             "pagination" => %{"next" => %{"part" => 1, "row" => 1} = next}
           } = conn |> read(ctx, ~p"/api/v1/traces/calc-b/entries?limit=1") |> json_response(200)

    refute Map.has_key?(entry, "attachment")

    assert %{
             "data" => [
               %{"part" => 1, "row" => 1, "type" => "media", "size" => 8},
               %{"part" => 1, "row" => 2, "type" => "raw", "message" => "Result 42"}
             ],
             "pagination" => %{"next" => %{"part" => 2, "row" => 0}}
           } = conn |> read(ctx, ~p"/api/v1/traces/calc-b/entries?#{next}") |> json_response(200)

    assert %{"data" => [], "pagination" => %{"next" => %{"part" => 3, "row" => 0}}} =
             conn |> read(ctx, ~p"/api/v1/traces/calc-b/entries?part=2") |> json_response(200)

    assert %{
             "data" => [%{"part" => 12, "row" => 0, "message" => "Finished"}],
             "pagination" => %{"next" => nil}
           } = conn |> read(ctx, ~p"/api/v1/traces/calc-b/entries?part=12") |> json_response(200)

    assert %{"data" => [], "pagination" => %{"next" => nil}} =
             conn |> read(ctx, ~p"/api/v1/traces/calc-a/entries") |> json_response(200)

    for params <- [%{part: 13}, %{row: 3}] do
      assert %{"errors" => %{"detail" => _}} =
               conn
               |> read(ctx, ~p"/api/v1/traces/calc-b/entries?#{params}")
               |> json_response(404)
    end
  end

  test "returns matching file descriptors from attachment lists and media entries",
       %{conn: conn} = ctx do
    assert %{
             "data" => [
               %{
                 "name" => "result.txt",
                 "size" => 8,
                 "id" => id,
                 "download_url" => download_url
               } = descriptor
             ],
             "pagination" => %{"next_after_part" => 10}
           } = conn |> read(ctx, ~p"/api/v1/traces/calc-b/attachments") |> json_response(200)

    assert Enum.sort(Map.keys(descriptor)) == ~w(download_url id name size)
    assert download_url == ~p"/api/v1/traces/calc-b/attachments/#{id}"

    assert %{"data" => [_, %{"type" => "media", "attachment" => ^descriptor}, _]} =
             conn |> read(ctx, ~p"/api/v1/traces/calc-b/entries") |> json_response(200)

    assert %{
             "data" => [%{"name" => "private.log", "size" => 3}],
             "pagination" => %{"next_after_part" => nil}
           } =
             conn
             |> read(ctx, ~p"/api/v1/traces/calc-b/attachments?after_part=10")
             |> json_response(200)

    download =
      conn
      |> put_req_header("accept", "application/octet-stream")
      |> read(ctx, download_url)

    assert response(download, 200) == "result42"
    assert get_resp_header(download, "content-type") == ["application/octet-stream"]
    assert [disposition] = get_resp_header(download, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "result.txt"
    assert get_resp_header(download, "cache-control") == ["private, no-store"]
    assert get_resp_header(download, "x-content-type-options") == ["nosniff"]

    assert %{"errors" => %{"detail" => _}} =
             conn
             |> read(ctx, ~p"/api/v1/traces/calc-b/attachments/unknown")
             |> json_response(404)

    Payload.write_part(ctx.config.data_driver, ctx.record, 1, [
      %{type: :media, message: "oversized.txt", size: 64 * 1024 * 1024 + 1},
      %{type: :media, message: "../outside.txt", size: 1}
    ])

    assert %{
             "data" => [%{"name" => "oversized.txt", "download_url" => oversized_url}]
           } = conn |> read(ctx, ~p"/api/v1/traces/calc-b/attachments") |> json_response(200)

    assert %{"errors" => %{"detail" => "Attachment exceeds the configured size limit"}} =
             conn |> read(ctx, oversized_url) |> json_response(413)

    assert %{"errors" => %{"detail" => _}} =
             conn |> read(ctx, download_url) |> json_response(404)

    Payload.write_part(ctx.config.data_driver, ctx.record, 1, [
      %{type: :text, message: "result.txt"}
    ])

    assert %{"errors" => %{"detail" => _}} =
             conn |> read(ctx, oversized_url) |> json_response(404)
  end

  test "returns bad requests for invalid search and pagination parameters", %{conn: conn} = ctx do
    for path <- [
          ~p"/api/v1/traces?cursor=invalid",
          ~p"/api/v1/traces?limit=101",
          ~p"/api/v1/traces?tag_mode=invalid",
          ~p"/api/v1/traces?from=2026-12-01T00:00:00Z&to=2026-11-01T00:00:00Z",
          ~p"/api/v1/traces/calc-b/entries?part=0",
          ~p"/api/v1/traces/calc-b/entries?row=-1",
          ~p"/api/v1/traces/calc-b/attachments?after_part=a"
        ] do
      assert %{"errors" => %{"detail" => _}} = conn |> read(ctx, path) |> json_response(400)
    end
  end

  defp read(conn, ctx, path), do: request(conn, ctx.token, ctx.id, path)

  defp request(conn, token, id, path) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("x-trifle-source-id", id)
    |> get(path)
  end
end
