defmodule TrifleApp.TraceAttachmentControllerTest do
  use TrifleApp.ConnCase
  import Trifle.OrganizationsFixtures
  import Trifle.BillingFixtures
  alias Trifle.Organizations
  alias Trifle.Traces.{TraceRecord, Driver}

  setup do
    user = Trifle.AccountsFixtures.user_fixture()
    org = organization_fixture(%{user: user})
    app_entitlement_fixture(org)
    path = Path.join(System.tmp_dir!(), "trace-download-#{Ecto.UUID.generate()}")
    reference = "download-#{Ecto.UUID.generate()}"

    {:ok, database} =
      Organizations.create_database_for_org(org, %{
        display_name: "Download source",
        driver: "postgres",
        host: "postgres",
        port: 5432,
        database_name: Trifle.Repo.config()[:database],
        username: Trifle.Repo.config()[:username],
        password: Trifle.Repo.config()[:password],
        trace_config: %{
          "index_name" => "trifle_traces",
          "data_driver" => "file",
          "data_path" => path,
          "retention_days" => 7,
          "gzip" => true
        }
      })

    config = Trifle.Traces.Source.Database.configuration(database)
    now = DateTime.utc_now()

    record = %TraceRecord{
      reference: reference,
      key: "jobs/download",
      parts: 1,
      first_at: now,
      last_at: now,
      expires_at: DateTime.add(now, 7, :day)
    }

    Driver.call(config.index_driver, :create, [record])

    Driver.call(config.data_driver, :write_part, [
      record,
      1,
      [%{type: :media, message: "report.txt"}]
    ])

    Driver.call(config.data_driver, :write_artifact, [
      record,
      "report.txt",
      [payload: "private attachment"]
    ])

    on_exit(fn ->
      Driver.call(config.index_driver, :delete, [reference])
      # Each test opens its own tenant pool; leaving them open exhausts Postgres.
      Trifle.DatabasePools.PostgresPoolSupervisor.stop_postgres_pool(database.id)
      File.rm_rf!(path)
    end)

    url =
      ~p"/traces/attachment?#{%{source_id: database.id, reference: reference, part: 1, row: 0}}"

    %{
      user: user,
      config: config,
      record: record,
      url: url,
      database_id: database.id,
      membership: %Organizations.OrganizationMembership{organization_id: org.id}
    }
  end

  defp restore_reader_config(nil), do: Application.delete_env(:trifle, Trifle.Traces.Reader)

  defp restore_reader_config(config),
    do: Application.put_env(:trifle, Trifle.Traces.Reader, config)

  test "authenticated downloads use persisted entries, and other organizations cannot fetch them",
       %{conn: conn, user: user, url: url} do
    response = conn |> log_in_user(user) |> get(url)
    assert response.status == 200
    assert response.resp_body == "private attachment"
    assert get_resp_header(response, "cache-control") == ["private, no-store"]
    assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    assert hd(get_resp_header(response, "content-disposition")) =~ "attachment"

    other = Trifle.AccountsFixtures.user_fixture()

    other_org =
      organization_fixture(%{
        user: other,
        name: "Other trace organization",
        slug: "other-trace-org"
      })

    app_entitlement_fixture(other_org)
    assert conn |> recycle() |> log_in_user(other) |> get(url) |> response(404)
    assert conn |> recycle() |> log_in_user(other) |> get(url <> "&inline=true") |> response(404)
    assert conn |> recycle() |> log_in_user(user) |> get(url <> "&row=-1") |> response(404)
  end

  test "downloads require login", %{conn: conn} do
    assert conn |> get(~p"/traces/attachment") |> redirected_to() == ~p"/users/log_in"
  end

  test "oversized downloads and inline previews return 413 without attachment contents", ctx do
    previous = Application.get_env(:trifle, Trifle.Traces.Reader)
    on_exit(fn -> restore_reader_config(previous) end)

    # The limit applies to the stored size; an entry cannot understate its way past it.
    Driver.call(ctx.config.data_driver, :write_part, [
      ctx.record,
      1,
      [%{type: :media, message: "report.txt", size: 1}]
    ])

    Application.put_env(:trifle, Trifle.Traces.Reader, max_artifact_bytes: 17)

    for suffix <- ["", "&inline=true"] do
      result = ctx.conn |> recycle() |> log_in_user(ctx.user) |> get(ctx.url <> suffix)
      assert response(result, 413) == "Attachment exceeds the configured size limit"
      refute result.resp_body =~ "private attachment"
    end

    Application.put_env(:trifle, Trifle.Traces.Reader, max_artifact_bytes: 18)
    result = ctx.conn |> recycle() |> log_in_user(ctx.user) |> get(ctx.url)
    assert response(result, 200) == "private attachment"
  end

  test "downloads are sent in chunks with their full length declared", ctx do
    previous = Application.get_env(:trifle, Trifle.Traces.Reader)
    on_exit(fn -> restore_reader_config(previous) end)
    Application.put_env(:trifle, Trifle.Traces.Reader, artifact_chunk_bytes: 1000)

    body = :crypto.strong_rand_bytes(4321)
    put_attachment(ctx, "dump.bin", body)

    result = ctx.conn |> log_in_user(ctx.user) |> get(ctx.url)
    assert result.state == :chunked
    assert response(result, 200) == body
    assert get_resp_header(result, "content-length") == ["4321"]
    assert get_resp_header(result, "content-type") == ["application/octet-stream"]

    assert hd(get_resp_header(result, "content-disposition")) =~
             ~s(attachment; filename="dump.bin")
  end

  test "a download that fails part-way is cut short instead of finishing normally", ctx do
    previous = Application.get_env(:trifle, Trifle.Traces.Reader)
    on_exit(fn -> restore_reader_config(previous) end)
    Application.put_env(:trifle, Trifle.Traces.Reader, artifact_chunk_bytes: 10)
    put_attachment(ctx, "dump.bin", :crypto.strong_rand_bytes(100))

    # The file shrinks after its size was read, as if storage dropped out mid-transfer.
    path =
      Path.join(
        ctx.config.data_driver.path,
        "7/jobs/download/#{ctx.record.reference}/artifacts/dump.bin"
      )

    {:ok, artifact} =
      Trifle.Traces.Reader.artifact(ctx.membership, ctx.database_id, ctx.record.reference, 1, 0)

    File.write!(path, "short")

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert_raise TrifleApp.TraceDownload.Interrupted, fn ->
          TrifleApp.TraceDownload.send_artifact(log_in_user(ctx.conn, ctx.user), artifact)
        end
      end)

    assert log =~ "[TraceDownload]"
    assert log =~ "interrupted"
  end

  test "images and videos are served inline with validated types and private headers", ctx do
    for {name, mime} <- [{"checkout.png", "image/png"}, {"fulfillment.webm", "video/webm"}] do
      body = File.read!(Path.join("priv/trace_seeds", name))
      put_attachment(ctx, name, body)

      # Match the Accept headers sent by actual image/video elements.
      accept = if mime == "image/png", do: "image/avif,image/webp,image/*,*/*;q=0.8", else: "*/*"
      conn = ctx.conn |> recycle() |> log_in_user(ctx.user) |> put_req_header("accept", accept)
      result = get(conn, ctx.url <> "&inline=true")
      assert response(result, 200) == body
      assert get_resp_header(result, "content-type") == [mime]
      assert get_resp_header(result, "cache-control") == ["private, no-store"]
      assert get_resp_header(result, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(result, "accept-ranges") == ["bytes"]
      assert hd(get_resp_header(result, "content-disposition")) =~ "inline;"

      download = ctx.conn |> recycle() |> log_in_user(ctx.user) |> get(ctx.url)
      assert response(download, 200) == body
      assert hd(get_resp_header(download, "content-disposition")) =~ "attachment;"
      assert get_resp_header(download, "content-type") == ["application/octet-stream"]
    end
  end

  test "single byte ranges permit seeking and invalid ranges do not leak a full body", ctx do
    body = File.read!("priv/trace_seeds/fulfillment.webm")
    put_attachment(ctx, "clip.webm", body)
    size = byte_size(body)

    for {range, first, last} <- [
          {"bytes=0-99", 0, 99},
          {"bytes=100-", 100, size - 1},
          {"bytes=-100", size - 100, size - 1},
          {"bytes=10-999999", 10, size - 1}
        ] do
      conn = ctx.conn |> recycle() |> log_in_user(ctx.user) |> put_req_header("range", range)
      result = get(conn, ctx.url <> "&inline=true")
      assert response(result, 206) == binary_part(body, first, last - first + 1)
      assert get_resp_header(result, "content-range") == ["bytes #{first}-#{last}/#{size}"]
      assert get_resp_header(result, "content-type") == ["video/webm"]
    end

    for range <- ["bytes=#{size}-", "bytes=5-4", "bytes=-0", "bytes=-"] do
      conn = ctx.conn |> recycle() |> log_in_user(ctx.user) |> put_req_header("range", range)
      result = get(conn, ctx.url <> "&inline=true")
      assert response(result, 416) == ""
      assert get_resp_header(result, "content-range") == ["bytes */#{size}"]
    end

    for headers <- [
          [{"range", "bytes=0-5,10-20"}],
          [{"range", "items=0-5"}],
          [{"range", "bytes=0-5"}, {"if-range", "\"old-version\""}]
        ] do
      conn =
        Enum.reduce(headers, ctx.conn |> recycle() |> log_in_user(ctx.user), fn {k, v}, c ->
          put_req_header(c, k, v)
        end)

      assert conn |> get(ctx.url <> "&inline=true") |> response(200) == body
    end
  end

  test "active content, disguised media and ordinary text cannot be served inline", ctx do
    for {name, body} <- [
          {"page.html", "<script>alert(1)</script>"},
          {"image.svg", "<svg onload='alert(1)'/>"},
          {"fake.png", "<script>alert(1)</script>"},
          {"fake.mp4", "<svg onload='alert(1)'/>"},
          {"report.txt", "private text"}
        ] do
      put_attachment(ctx, name, body)
      conn = ctx.conn |> recycle() |> log_in_user(ctx.user)
      assert conn |> get(ctx.url <> "&inline=true") |> response(415)
      assert conn |> recycle() |> log_in_user(ctx.user) |> get(ctx.url) |> response(200) == body
    end
  end

  test "inline previews still require login, a valid media row and a retained trace", ctx do
    put_attachment(ctx, "checkout.png", File.read!("priv/trace_seeds/checkout.png"))
    assert ctx.conn |> get(ctx.url <> "&inline=true") |> redirected_to() == ~p"/users/log_in"
    conn = ctx.conn |> recycle() |> log_in_user(ctx.user)
    assert conn |> get(ctx.url <> "&inline=true&row=9") |> response(404)

    Driver.call(ctx.config.data_driver, :write_part, [
      ctx.record,
      1,
      [%{type: :raw, message: "checkout.png"}]
    ])

    assert conn
           |> recycle()
           |> log_in_user(ctx.user)
           |> get(ctx.url <> "&inline=true")
           |> response(404)

    Driver.call(ctx.config.index_driver, :delete, [ctx.record.reference])

    assert conn
           |> recycle()
           |> log_in_user(ctx.user)
           |> get(ctx.url <> "&inline=true")
           |> response(404)
  end

  defp put_attachment(ctx, name, body) do
    Driver.call(ctx.config.data_driver, :write_part, [
      ctx.record,
      1,
      [%{type: :media, message: name}]
    ])

    Driver.call(ctx.config.data_driver, :write_artifact, [ctx.record, name, [payload: body]])
  end
end
