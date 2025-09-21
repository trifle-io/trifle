defmodule Mix.Tasks.Export.Dashboard do
  use Mix.Task

  @shortdoc "Export a dashboard to PDF/PNG via headless Chrome"

  @moduledoc """
  Usage:
    mix export.dashboard --id DASHBOARD_ID [--format pdf|png] [--out /path/out.ext]
    mix export.dashboard --id DASHBOARD_ID --headful [--devtools]

  Options:
    --id       Dashboard UUID (required)
    --format   pdf or png (default: pdf)
    --out      Output filepath (default: /tmp/trifle_export_<id>.<ext>)
    --headful  Launch Chrome with a visible window for debugging
    --devtools Auto-open devtools for tabs (with --headful)
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          id: :string,
          format: :string,
          out: :string,
          headful: :boolean,
          devtools: :boolean
        ],
        aliases: []
      )

    id = opts[:id] || abort!("--id is required")
    format = (opts[:format] || "pdf") |> String.downcase()
    out = opts[:out] || default_out_path(id, format)

    exporter = TrifleApp.Exporters.ChromeExporter

    if opts[:headful] do
      case exporter.public_dashboard_url(id, print: true) do
        {:ok, url, cleanup} ->
          case exporter.chrome_path() do
            {:ok, chrome} ->
              profile = tmp_profile_dir()

              args = [
                "--no-first-run",
                "--no-default-browser-check",
                "--disable-extensions",
                "--disable-dev-shm-usage",
                "--new-window",
                "--user-data-dir=#{profile}"
              ]

              args = if opts[:devtools], do: args ++ ["--auto-open-devtools-for-tabs"], else: args
              args = args ++ [url]
              Mix.shell().info("Launching Chrome headful for #{url} ... (close Chrome to finish)")
              {out, status} = System.cmd(chrome, args, stderr_to_stdout: true)
              File.rm_rf(profile)
              cleanup.()
              Mix.shell().info("Chrome exited with status #{status}")

              if String.trim(out) != "" do
                Mix.shell().info(String.slice(out, 0, 2000))
              end

            {:error, _} ->
              abort!("Chrome binary not found. Set CHROME_PATH or install Chromium/Chrome")
          end

        {:error, reason} ->
          abort!("Failed to build public URL: #{inspect(reason)}")
      end
    else
      Mix.shell().info("Exporting dashboard #{id} as #{format} -> #{out}")

      res =
        case format do
          "pdf" -> exporter.export_dashboard_pdf(id)
          "png" -> exporter.export_dashboard_png(id)
          other -> abort!("Unsupported --format #{inspect(other)}")
        end

      case res do
        {:ok, bin} when is_binary(bin) and byte_size(bin) > 0 ->
          File.write!(out, bin)
          Mix.shell().info("OK: wrote #{byte_size(bin)} bytes to #{out}")

        {:ok, _} ->
          Mix.shell().error("ERROR: exporter returned empty binary")

        {:error, reason} ->
          Mix.shell().error("ERROR: #{inspect(reason)}")
      end
    end
  end

  defp default_out_path(id, format) do
    ext = (format == "png" && ".png") || ".pdf"

    Path.join(
      System.tmp_dir!(),
      "trifle_export_" <> String.replace(id, ~r/[^a-zA-Z0-9_-]+/, "_") <> ext
    )
  end

  defp tmp_profile_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "trifle_chrome_debug_" <> Integer.to_string(System.system_time(:millisecond))
      )

    File.mkdir_p!(dir)
    dir
  end

  defp abort!(msg) do
    Mix.raise(msg)
  end
end
