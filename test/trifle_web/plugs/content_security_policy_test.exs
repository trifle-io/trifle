defmodule TrifleWeb.Plugs.ContentSecurityPolicyTest do
  # Changes the global CSP mode.
  use TrifleApp.ConnCase, async: false

  import ExUnit.CaptureLog

  setup do
    previous = Application.get_env(:trifle, :csp_mode)

    on_exit(fn ->
      if is_nil(previous),
        do: Application.delete_env(:trifle, :csp_mode),
        else: Application.put_env(:trifle, :csp_mode, previous)
    end)

    :ok
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> List.first()

  describe "headers" do
    test "report-only by default: full policy reported, baseline enforced", %{conn: conn} do
      Application.delete_env(:trifle, :csp_mode)
      conn = get(conn, ~p"/users/log_in")

      assert header(conn, "content-security-policy") ==
               "object-src 'none'; base-uri 'self'; frame-ancestors 'self'"

      reported = header(conn, "content-security-policy-report-only")
      assert reported =~ "script-src 'self' 'nonce-"
      assert reported =~ "report-uri /csp-report"
      refute reported =~ "script-src 'self' 'unsafe-inline'"
      refute reported =~ "unsafe-eval"
    end

    test "the layout's inline scripts carry this response's nonce", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in")
      html = html_response(conn, 200)

      [_, nonce] =
        Regex.run(~r/'nonce-([^']+)'/, header(conn, "content-security-policy-report-only"))

      inline = Regex.scan(~r/<script(?![^>]*\bsrc=)[^>]*>/, html) |> List.flatten()

      assert inline != []
      assert Enum.all?(inline, &String.contains?(&1, ~s(nonce="#{nonce}")))
    end

    test "the nonce differs per response", %{conn: conn} do
      first = conn |> get(~p"/users/log_in") |> header("content-security-policy-report-only")

      second =
        build_conn() |> get(~p"/users/log_in") |> header("content-security-policy-report-only")

      refute first == second
    end

    test "enforce sends only the enforcing header", %{conn: conn} do
      Application.put_env(:trifle, :csp_mode, :enforce)
      conn = get(conn, ~p"/users/log_in")

      assert header(conn, "content-security-policy") =~ "script-src 'self' 'nonce-"
      assert header(conn, "content-security-policy-report-only") == nil
    end

    test "off leaves only Phoenix's own minimal policy and pages still render", %{conn: conn} do
      Application.put_env(:trifle, :csp_mode, :off)
      conn = get(conn, ~p"/users/log_in")

      assert html_response(conn, 200)
      assert header(conn, "content-security-policy") == "base-uri 'self'; frame-ancestors 'self';"
      assert header(conn, "content-security-policy-report-only") == nil
    end
  end

  describe "POST /csp-report" do
    defp post_report(body, content_type \\ "application/csp-report") do
      build_conn()
      |> put_req_header("content-type", content_type)
      |> post("/csp-report", body)
    end

    test "logs a violation once, with no query string from any URL field" do
      directive = "script-src-elem-#{System.unique_integer([:positive])}"

      body =
        Jason.encode!(%{
          "csp-report" => %{
            "effective-directive" => directive,
            "blocked-uri" => "https://cdn.example.com/x.js?key=blocked-secret#frag-secret",
            "document-uri" => "https://app.example.com/d/abc?token=document-secret",
            "source-file" => "https://app.example.com/d/abc?token=source-secret",
            "line-number" => 12,
            "script-sample" => "alert(1)\nsecond line"
          }
        })

      log =
        capture_log(fn ->
          for _ <- 1..3, do: assert(response(post_report(body), 204) == "")
        end)

      assert length(String.split(log, directive)) == 2

      assert log =~
               "would block #{directive} https://cdn.example.com/x.js on https://app.example.com/d/abc "

      assert log =~ "source https://app.example.com/d/abc:12"
      refute log =~ "secret"
      refute log =~ "second line\n"
    end

    test "the JSON content type gets the same treatment" do
      directive = "img-src-#{System.unique_integer([:positive])}"

      body =
        Jason.encode!(%{
          "csp-report" => %{
            "effective-directive" => directive,
            "blocked-uri" => "https://x.example.com/a?token=json-secret",
            "source-file" => "https://app.example.com/p?token=json-secret",
            "line-number" => String.duplicate("9", 500)
          }
        })

      log = capture_log(fn -> assert response(post_report(body, "application/json"), 204) end)

      assert log =~ directive
      refute log =~ "json-secret"
      # A line number that is not a small integer is dropped, not logged or keyed.
      assert log =~ "/p:nil"
      refute log =~ "9999"
    end

    test "oversized bodies are never parsed or kept, whatever the content type" do
      marker = "oversized-#{System.unique_integer([:positive])}"

      body =
        Jason.encode!(%{
          "csp-report" => %{
            "effective-directive" => marker,
            "line-number" => String.duplicate("A", 100_000)
          }
        })

      # Claimed by the JSON parser: refused with 413 before decoding.
      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        post_report(body, "application/json")
      end

      # Not claimed by a parser: the controller reads at most 16 KB and gives up.
      log = capture_log(fn -> assert response(post_report(body), 204) == "" end)
      refute log =~ marker
    end

    test "varied reports cannot grow the log or the cache without bound" do
      previous = Application.get_env(:trifle, Trifle.RateLimit, [])

      Application.put_env(:trifle, Trifle.RateLimit,
        enabled: true,
        policies: %{csp_report_log: {3, 60_000}, csp_report: {1_000, 60_000}}
      )

      on_exit(fn -> Application.put_env(:trifle, Trifle.RateLimit, previous) end)

      marker = "flood-#{System.unique_integer([:positive])}"
      before_size = Cachex.size!(:trifle_cache)

      log =
        capture_log(fn ->
          for n <- 1..25 do
            body =
              Jason.encode!(%{
                "csp-report" => %{"effective-directive" => marker, "line-number" => n}
              })

            assert response(post_report(body), 204) == ""
          end
        end)

      assert length(String.split(log, marker)) - 1 <= 3
      assert Cachex.size!(:trifle_cache) - before_size <= 3
    end

    test "accepts garbage without failing" do
      assert response(post_report("not json"), 204) == ""
      assert response(post_report(Jason.encode!(%{"csp-report" => "text"})), 204) == ""
      assert response(post_report(Jason.encode!([1, 2, 3]), "application/json"), 204) == ""
    end
  end
end
