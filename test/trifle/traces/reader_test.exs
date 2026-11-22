defmodule Trifle.Traces.ReaderTest do
  use Trifle.DataCase, async: false
  import Trifle.OrganizationsFixtures
  import Trifle.BillingFixtures
  import ExUnit.CaptureLog
  alias Trifle.Chat.Tools
  alias Trifle.Organizations
  alias Trifle.Traces.{Reader, Configuration, TraceRecord}
  alias Trifle.Traces.Driver.Index.Postgres
  alias Trifle.Traces.Driver.Data.Memory

  defmodule S3Adapter do
    def get_object(objects, bucket, key) do
      send(self(), {:s3_read, bucket, key})
      Map.fetch!(objects, {bucket, key})
    end
  end

  defmodule BakerReader do
    def search(membership, id, filters),
      do: Reader.search(membership, id, filters, Process.get(__MODULE__))

    def contents(membership, id, reference, part),
      do: Reader.contents(membership, id, reference, part, Process.get(__MODULE__))

    def artifact(membership, id, reference, part, row),
      do: Reader.artifact(membership, id, reference, part, row, Process.get(__MODULE__))
  end

  setup do
    previous_reader_config = Application.get_env(:trifle, Reader)

    on_exit(fn ->
      if is_nil(previous_reader_config),
        do: Application.delete_env(:trifle, Reader),
        else: Application.put_env(:trifle, Reader, previous_reader_config)
    end)

    Application.delete_env(:trifle, Reader)
    org = organization_fixture()
    app_entitlement_fixture(org)

    {:ok, database} =
      Organizations.create_database_for_org(org, %{
        display_name: "Trace test",
        driver: "postgres",
        host: "postgres",
        port: 5432,
        database_name: "test",
        username: "test",
        password: "test",
        trace_config: %{
          "index_name" => "trifle_traces",
          "data_driver" => "file",
          "data_path" => "/tmp/trace-reader-test",
          "retention_days" => 7,
          "gzip" => false
        }
      })

    config = Configuration.new(index_driver: Postgres.new(Trifle.Repo), data_driver: Memory.new())
    opts = [configuration: fn _ -> config end]
    now = ~U[2026-09-12 12:00:00.000000Z]

    record = %TraceRecord{
      reference: "reader-test",
      key: "jobs/App.Worker",
      state: :success,
      first_at: now,
      last_at: now,
      expires_at: DateTime.add(now, 7, :day),
      duration: 30,
      tags: ["default", "scheduled"],
      parts: 2,
      length: 3,
      bucket_name: "bucket"
    }

    Postgres.create(config.index_driver, record)

    Memory.write_part(config.data_driver, record, 1, [
      %{type: :text, message: "<script>alert(1)</script>"},
      %{type: :media, message: "report.txt"}
    ])

    Memory.write_part(config.data_driver, record, 2, [%{type: :head, message: "Last entry"}])
    Memory.write_artifact(config.data_driver, record, "report.txt", payload: "hello")

    %{
      membership: %Organizations.OrganizationMembership{organization_id: org.id},
      database: database,
      config: config,
      opts: opts,
      record: record
    }
  end

  test "Postgres pagination works with the app's migrated timestamps", ctx do
    for n <- 1..22 do
      Postgres.create(ctx.config.index_driver, %{
        ctx.record
        | reference: "page-#{String.pad_leading(to_string(n), 2, "0")}"
      })
    end

    assert {:ok, %{traces: first, cursor: cursor}} =
             Reader.search(
               ctx.membership,
               ctx.database.id,
               [segment: "jobs/App.Worker"],
               ctx.opts
             )

    assert length(first) == 20
    assert is_binary(cursor)
    assert Enum.all?(first, &match?(%DateTime{}, &1.first_at))

    assert {:ok, %{traces: second, cursor: nil}} =
             Reader.search(
               ctx.membership,
               ctx.database.id,
               [segment: "jobs/App.Worker", cursor: cursor],
               ctx.opts
             )

    assert length(second) == 3
    assert length(Enum.uniq_by(first ++ second, & &1.reference)) == 23
  end

  describe "Baker trace tools" do
    setup %{opts: opts} do
      previous = Application.fetch_env(:trifle, :trace_reader)
      Process.put(BakerReader, opts)
      Application.put_env(:trifle, :trace_reader, BakerReader)

      on_exit(fn ->
        case previous do
          {:ok, reader} -> Application.put_env(:trifle, :trace_reader, reader)
          :error -> Application.delete_env(:trifle, :trace_reader)
        end
      end)
    end

    test "finds the latest five calculations by tag and path and reads each matching trace",
         ctx do
      source_id = ctx.database.id

      for n <- 1..7 do
        record = %{
          ctx.record
          | reference: "calculation-#{n}",
            key: "jobs/calculation/worker",
            first_at: DateTime.add(ctx.record.first_at, n, :second),
            tags: ["customer:42"],
            meta: [n],
            context: %{"worker" => "Calculation"},
            parts: 1,
            length: 1
        }

        Postgres.create(ctx.config.index_driver, record)

        Memory.write_part(ctx.config.data_driver, record, 1, [
          %{type: :raw, state: :success, level: 1, message: "Result #{n}"}
        ])
      end

      Postgres.create(ctx.config.index_driver, %{
        ctx.record
        | reference: "other-customer",
          key: "jobs/calculation",
          first_at: DateTime.add(ctx.record.first_at, 10, :second)
      })

      assert {:ok, %{sources: [%{id: ^source_id}], default_source_id: ^source_id}} =
               baker_tool("list_trace_sources", %{}, ctx)

      filters = %{path: "jobs/calculation", tags: ["customer:42"], limit: 5}

      assert {:ok, %{source_id: ^source_id, traces: traces, next_cursor: cursor}} =
               baker_tool("search_traces", filters, ctx)

      assert Enum.map(traces, & &1.reference) == Enum.map(7..3//-1, &"calculation-#{&1}")

      for {trace, n} <- Enum.zip(traces, 7..3//-1) do
        reference = trace.reference
        message = "Result #{n}"

        assert {:ok,
                %{
                  trace: %{reference: ^reference, url: "/traces?" <> _},
                  metadata: %{meta: [^n], context: %{"worker" => "Calculation"}},
                  entries: [%{type: :raw, level: 1, message: ^message}],
                  next: nil
                } = result} =
                 baker_tool("read_trace", %{source_id: source_id, reference: reference}, ctx)

        assert %{"entries" => [%{"message" => ^message}], "metadata" => %{"meta" => [^n]}} =
                 Tools.compact_tool_payload_for_model("read_trace", Jason.encode!(result))
      end

      assert {:ok, %{traces: [%{reference: "calculation-2"}, %{reference: "calculation-1"}]}} =
               baker_tool("search_traces", Map.put(filters, :cursor, cursor), ctx)

      assert {:ok, %{traces: [%{reference: "other-customer"}]}} =
               baker_tool("search_traces", %{path: "jobs/calculation", limit: 1}, ctx)
    end

    test "continues through long messages, metadata, stored parts, and text attachments", ctx do
      long_text = String.duplicate("東", 3001)
      record = %{ctx.record | reference: "long-trace", meta: %{"value" => long_text}}
      Postgres.create(ctx.config.index_driver, record)

      Memory.write_part(ctx.config.data_driver, record, 1, [
        %{type: :raw, message: long_text},
        %{type: :media, message: "result.txt", size: byte_size(long_text)}
      ])

      Memory.write_part(ctx.config.data_driver, record, 2, [%{type: :text, message: "Complete"}])
      Memory.write_artifact(ctx.config.data_driver, record, "result.txt", payload: long_text)

      assert {:ok, page} = baker_tool("read_trace", %{reference: record.reference}, ctx)
      assert [%{message: first, message_continues: true}] = page.entries
      assert String.valid?(first)
      refute Map.has_key?(page, :metadata)

      assert {:ok, second} = baker_tool("read_trace", page.next, ctx)

      assert [%{message: rest, message_continues: false}, %{type: :media, row: 1}] =
               second.entries

      assert first <> rest == long_text

      assert {:ok, %{part: 2, entries: [%{message: "Complete"}], next: nil}} =
               baker_tool("read_trace", second.next, ctx)

      assert {:ok, %{metadata_json_fragment: metadata_rest, next: nil}} =
               baker_tool("read_trace", page.next_metadata, ctx)

      assert Jason.decode!(page.metadata_json_fragment <> metadata_rest)["meta"]["value"] ==
               long_text

      assert {:ok, attachment} =
               baker_tool(
                 "read_trace",
                 %{reference: record.reference, section: "attachment", part: 1, row: 1},
                 ctx
               )

      assert {:ok, %{text: attachment_rest, next: nil}} =
               baker_tool("read_trace", attachment.next, ctx)

      assert attachment.text <> attachment_rest == long_text
    end

    test "applies workspace access checks to search, metadata, and payload reads", ctx do
      source = %{source_id: ctx.database.id, reference: ctx.record.reference}
      foreign = put_in(ctx.membership.organization_id, Ecto.UUID.generate())

      for {tool, args} <- [
            {"search_traces", Map.take(source, [:source_id])},
            {"read_trace", source},
            {"read_trace", Map.put(source, :section, "metadata")},
            {"read_trace", Map.merge(source, %{section: "attachment", part: 1, row: 1})}
          ] do
        assert {:error, %{error: "This trace source is unavailable."}} =
                 baker_tool(tool, args, foreign)
      end
    end
  end

  defp baker_tool(tool, args, ctx),
    do: Tools.execute(tool, Jason.encode!(args), %{membership: ctx.membership})

  test "Postgres and the trace reader preserve argument arrays and maps directly in meta", ctx do
    for arguments <- [
          [42, false, nil, %{"nested" => ["東京", 0]}],
          %{"args" => [1, 2], "options" => %{"enabled" => false, "value" => nil}}
        ] do
      record = %{
        ctx.record
        | reference: if(is_map(arguments), do: "args-map", else: "args-array"),
          meta: arguments,
          context: %{queue: "default", worker: "App.Worker"}
      }

      Postgres.create(ctx.config.index_driver, record)

      assert {:ok, persisted} =
               Reader.detail(ctx.membership, ctx.database.id, record.reference, ctx.opts)

      assert persisted.meta == arguments
      assert persisted.context == %{"queue" => "default", "worker" => "App.Worker"}
    end
  end

  test "filters honor segment boundaries, tags, duration, state and exclusive end", ctx do
    base = [
      segment: "jobs",
      state: "success",
      tags: %{all: ["default", "scheduled"]},
      duration_min: 30,
      from: ctx.record.first_at,
      to: DateTime.add(ctx.record.first_at, 1, :second)
    ]

    assert {:ok, %{traces: [_]}} = Reader.search(ctx.membership, ctx.database.id, base, ctx.opts)

    for {key, value} <- [
          segment: "job",
          state: "error",
          duration_min: 31,
          to: ctx.record.first_at,
          tags: %{any: ["missing"]}
        ] do
      assert {:ok, %{traces: []}} =
               Reader.search(
                 ctx.membership,
                 ctx.database.id,
                 Keyword.put(base, key, value),
                 ctx.opts
               )
    end

    assert {:error, :storage_unavailable} =
             Reader.search(ctx.membership, ctx.database.id, [cursor: "bad"], ctx.opts)
  end

  test "reads one part and only resolves artifacts through persisted media entries", ctx do
    args = [ctx.membership, ctx.database.id, ctx.record.reference]

    assert {:ok, [%{row: 0, part: 1}, %{row: 1, part: 1}]} =
             apply(Reader, :part, args ++ [1, ctx.opts])

    assert {:ok, [%{entry: %{message: "Last entry"}}]} =
             apply(Reader, :part, args ++ [2, ctx.opts])

    assert {:ok, %{name: "report.txt", body: "hello"}} =
             apply(Reader, :artifact, args ++ [1, 1, ctx.opts])

    assert {:error, :not_found} = apply(Reader, :artifact, args ++ [1, 0, ctx.opts])
    assert {:error, :not_found} = apply(Reader, :part, args ++ [3, ctx.opts])

    assert {:error, :not_found} =
             Reader.detail(ctx.membership, ctx.database.id, "missing", ctx.opts)
  end

  test "cross-organization and missing membership reads do not touch storage", ctx do
    opts = [configuration: fn _ -> flunk("must not connect") end]

    for membership <- [nil, %{organization_id: Ecto.UUID.generate()}] do
      assert {:error, :unavailable} = Reader.search(membership, ctx.database.id, [], opts)

      assert {:error, :unavailable} =
               Reader.part(membership, ctx.database.id, ctx.record.reference, 1, opts)

      assert {:error, :unavailable} =
               Reader.artifact(membership, ctx.database.id, ctx.record.reference, 1, 1, opts)

      assert {:error, :unavailable} =
               Reader.attachments(membership, ctx.database.id, ctx.record.reference, 0, opts)
    end
  end

  test "storage failures log their cause, operation, source and elapsed time", ctx do
    for failure <- [:raise, :exit] do
      opts = [
        configuration: fn _ ->
          case failure do
            :raise -> raise Mongo.Error, message: "query timed out after 5000ms"
            :exit -> exit({:timeout, {GenServer, :call, [:mongo, :checkout_session, 60_000]}})
          end
        end
      ]

      log =
        capture_log(fn ->
          assert {:error, :storage_unavailable} =
                   Reader.search(ctx.membership, ctx.database.id, [], opts)
        end)

      assert log =~ "[Traces.Reader] operation=search source_id=#{ctx.database.id}"
      assert log =~ ~r/elapsed_ms=\d+/

      if failure == :raise do
        assert log =~ "Mongo.Error"
        assert log =~ "query timed out after 5000ms"
      else
        assert log =~ "time out"
        assert log =~ "checkout_session"
      end
    end
  end

  test "expected missing trace results do not log storage failures", ctx do
    assert capture_log(fn ->
             assert {:error, :not_found} =
                      Reader.detail(ctx.membership, ctx.database.id, "missing", ctx.opts)
           end) == ""
  end

  test "oversized recorded attachments are rejected before reading their bodies", ctx do
    alias Trifle.Traces.Driver.Data.{S3, Encoding}
    prefix = "7/traces/jobs/App.Worker/reader-test/"
    artifact_key = prefix <> "artifacts/report.txt"

    for {limit, size} <- [{nil, 64 * 1024 * 1024 + 1}, {6, 7}] do
      if limit, do: Application.put_env(:trifle, Reader, max_artifact_bytes: limit)

      data =
        S3.new(
          buckets: ["bucket"],
          adapter: S3Adapter,
          gzip: true,
          client: %{
            {"bucket", prefix <> "data_1.json.gz"} =>
              Encoding.pack_entries([%{type: :media, message: "report.txt", size: size}], true)
          }
        )

      opts = [configuration: fn _ -> %{ctx.config | data_driver: data} end]

      assert {:error, :too_large} =
               Reader.artifact(ctx.membership, ctx.database.id, ctx.record.reference, 1, 0, opts)

      assert_received {:s3_read, "bucket", _part_key}
      refute_received {:s3_read, "bucket", ^artifact_key}
    end
  end

  test "attachment limit allows its boundary and checks bodies with missing or inaccurate sizes",
       ctx do
    Application.put_env(:trifle, Reader, max_artifact_bytes: 5)
    args = [ctx.membership, ctx.database.id, ctx.record.reference, 1, 0, ctx.opts]

    for size <- [nil, 0, 5] do
      Memory.write_part(ctx.config.data_driver, ctx.record, 1, [
        %{"type" => "media", "message" => "report.txt", "size" => size}
      ])

      Memory.write_artifact(ctx.config.data_driver, ctx.record, "report.txt", payload: "hello")
      assert {:ok, %{body: "hello"}} = apply(Reader, :artifact, args)

      Memory.write_artifact(ctx.config.data_driver, ctx.record, "report.txt", payload: "longer")
      assert {:error, :too_large} = apply(Reader, :artifact, args)
    end
  end

  test "attachment catalog scans bounded batches without downloading artifact bodies", ctx do
    record = %{ctx.record | parts: 12}
    Postgres.update(ctx.config.index_driver, record)

    for part <- 1..12 do
      Memory.write_part(ctx.config.data_driver, record, part, [
        %{type: :text, message: "Not an attachment"},
        %{"type" => "media", "message" => "file-#{part}.txt", "size" => part * 1024}
      ])
    end

    assert {:ok, %{attachments: first, next_part: 10}} =
             Reader.attachments(ctx.membership, ctx.database.id, record.reference, 0, ctx.opts)

    assert length(first) == 10
    assert hd(first) == %{name: "file-1.txt", size: 1024, part: 1, row: 1}

    assert {:ok, %{attachments: last, next_part: nil}} =
             Reader.attachments(ctx.membership, ctx.database.id, record.reference, 10, ctx.opts)

    assert Enum.map(last, & &1.part) == [11, 12]
    assert Enum.map(last, & &1.size) == [11 * 1024, 12 * 1024]

    for after_part <- [-1, 13, "bad"] do
      assert {:error, :not_found} =
               Reader.attachments(
                 ctx.membership,
                 ctx.database.id,
                 record.reference,
                 after_part,
                 ctx.opts
               )
    end
  end

  test "attachment catalogs exclude unsafe names and handle empty traces", ctx do
    Memory.write_part(ctx.config.data_driver, ctx.record, 1, [
      %{type: :media, message: "../secret"},
      %{type: :media, message: "good.txt"},
      %{type: :media, message: "bad\0name"}
    ])

    assert {:ok,
            %{attachments: [%{name: "good.txt", size: nil, part: 1, row: 1}], next_part: nil}} =
             Reader.attachments(
               ctx.membership,
               ctx.database.id,
               ctx.record.reference,
               0,
               ctx.opts
             )

    Postgres.update(ctx.config.index_driver, %{ctx.record | parts: 0})

    assert {:ok, %{attachments: [], next_part: nil}} =
             Reader.attachments(
               ctx.membership,
               ctx.database.id,
               ctx.record.reference,
               0,
               ctx.opts
             )
  end

  test "traversal in stored media names and missing payloads are rejected", ctx do
    for name <- ["../secret", "/secret", "..\\secret", "bad\0name"] do
      Memory.write_part(ctx.config.data_driver, ctx.record, 1, [%{type: :media, message: name}])

      assert {:error, :not_found} =
               Reader.artifact(
                 ctx.membership,
                 ctx.database.id,
                 ctx.record.reference,
                 1,
                 0,
                 ctx.opts
               )
    end

    Memory.delete(ctx.config.data_driver, ctx.record)

    assert {:ok, _} =
             Reader.detail(ctx.membership, ctx.database.id, ctx.record.reference, ctx.opts)

    assert {:error, :storage_unavailable} =
             Reader.part(ctx.membership, ctx.database.id, ctx.record.reference, 1, ctx.opts)
  end

  test "text previews are bounded and binary attachments are download only" do
    assert %{truncated: true, text: text} =
             Reader.preview(%{name: "report.txt", body: String.duplicate("東", 40_000)})

    assert String.length(text) == 32_768
    assert String.valid?(text)
    assert %{text: nil} = Reader.preview(%{name: "report.txt", body: <<255>>})
    assert %{text: nil} = Reader.preview(%{name: "image.png", body: "not displayed"})
  end

  test "reads compressed S3 parts and attachments from the recorded bucket after configuration changes",
       ctx do
    alias Trifle.Traces.Driver.Data.{S3, Encoding}
    prefix = "7/traces/jobs/App.Worker/reader-test/"

    objects = %{
      {"bucket", prefix <> "data_1.json.gz"} =>
        Encoding.pack_entries([%{type: :media, message: "report.txt", size: 7}], true),
      {"bucket", prefix <> "artifacts/report.txt"} => "S3 text"
    }

    data =
      S3.new(buckets: ["replacement-bucket"], adapter: S3Adapter, client: objects, gzip: true)

    opts = [configuration: fn _ -> %{ctx.config | data_driver: data} end]

    assert {:ok, %TraceRecord{bucket_name: "bucket"}} =
             Reader.detail(ctx.membership, ctx.database.id, ctx.record.reference, opts)

    assert {:ok, [%{entry: %{type: :media, size: 7}}]} =
             Reader.part(ctx.membership, ctx.database.id, ctx.record.reference, 1, opts)

    assert_received {:s3_read, "bucket", key}
    assert key == prefix <> "data_1.json.gz"

    Postgres.update(ctx.config.index_driver, %{ctx.record | parts: 1})

    assert {:ok, %{attachments: [%{name: "report.txt", size: 7}]}} =
             Reader.attachments(ctx.membership, ctx.database.id, ctx.record.reference, 0, opts)

    artifact_key = prefix <> "artifacts/report.txt"
    refute_received {:s3_read, "bucket", ^artifact_key}

    assert {:ok, %{body: "S3 text"}} =
             Reader.artifact(ctx.membership, ctx.database.id, ctx.record.reference, 1, 0, opts)
  end

  test "File reads unpack compressed parts and reject malicious record paths", ctx do
    alias Trifle.Traces.Driver.Data.File, as: FileData
    path = Path.join(System.tmp_dir!(), "trace-reader-#{Ecto.UUID.generate()}")
    data = FileData.new(path: path, gzip: true)
    on_exit(fn -> File.rm_rf!(path) end)
    FileData.write_part(data, ctx.record, 1, [%{type: :media, message: "report.txt"}])
    FileData.write_artifact(data, ctx.record, "report.txt", payload: "File text")
    opts = [configuration: fn _ -> %{ctx.config | data_driver: data} end]

    assert {:ok, %{body: "File text"}} =
             Reader.artifact(ctx.membership, ctx.database.id, ctx.record.reference, 1, 0, opts)

    Postgres.create(ctx.config.index_driver, %{
      ctx.record
      | reference: "unsafe",
        key: "../outside"
    })

    assert {:error, :not_found} = Reader.part(ctx.membership, ctx.database.id, "unsafe", 1, opts)
  end

  test "Mongo sources use the same scoped reader contract with a stubbed index", ctx do
    alias Trifle.Traces.Driver.Index.Memory, as: Index
    {:ok, database} = Organizations.update_database(ctx.database, %{driver: "mongo", port: 27017})
    index = Index.new()
    Index.create(index, ctx.record)

    opts = [
      configuration: fn database ->
        assert database.driver == "mongo"
        %{ctx.config | index_driver: index}
      end
    ]

    assert {:ok, %{traces: [_]}} =
             Reader.search(ctx.membership, database.id, [segment: "jobs"], opts)

    assert {:ok, %{body: "hello"}} =
             Reader.artifact(ctx.membership, database.id, ctx.record.reference, 1, 1, opts)
  end

  test "removing trace configuration revokes read access immediately", ctx do
    {:ok, _} = Organizations.update_database(ctx.database, %{trace_config: %{}})
    assert Reader.sources(ctx.membership) == []

    assert {:error, :unavailable} =
             Reader.detail(ctx.membership, ctx.database.id, ctx.record.reference, ctx.opts)
  end
end
