defmodule TrifleApp.TracesLive.Metadata do
  @moduledoc false

  alias Trifle.Traces.Driver.Data.Encoding

  def build(record, config) do
    record
    |> Map.from_struct()
    |> Map.put(:storage, storage(record, config))
  end

  # Resolve locations with the same layout as the payload drivers. The bucket
  # belongs to the record and may no longer be in the configured bucket list.
  defp storage(record, %{"data_driver" => "s3"} = config) do
    path =
      if record.bucket_name not in [nil, ""] do
        "s3://#{record.bucket_name}/#{record.retention}/#{config["data_prefix"]}/#{record.key}/#{record.reference}/"
      end

    storage_details("s3", path, config)
  end

  defp storage(record, %{"data_driver" => "file", "data_path" => root} = config) do
    path = Path.join([root, to_string(record.retention), record.key, record.reference]) <> "/"
    storage_details("file", path, config)
  end

  defp storage(_record, _config), do: nil

  defp storage_details(driver, path, config) do
    gzip = Map.get(config, "gzip", false)

    %{
      driver: driver,
      path: path,
      part_file_pattern: Encoding.part_name("{part}", gzip),
      artifacts_path: if(path, do: path <> "artifacts/"),
      gzip: gzip
    }
  end
end
