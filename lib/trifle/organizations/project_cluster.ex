defmodule Trifle.Organizations.ProjectCluster do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @drivers ["mongo"]
  @statuses ["active", "coming_soon"]
  @visibilities ["public", "restricted", "private"]

  schema "project_clusters" do
    field :name, :string
    field :code, :string
    field :driver, :string
    field :status, :string, default: "active"
    field :visibility, :string, default: "public"
    field :is_default, :boolean, default: false
    field :region, :string
    field :country, :string
    field :city, :string
    field :host, :string
    field :port, :integer
    field :database_name, Trifle.Encrypted.Binary
    field :username, Trifle.Encrypted.Binary
    field :password, Trifle.Encrypted.Binary
    field :auth_database, Trifle.Encrypted.Binary
    field :config, :map, default: %{}
    field :last_check_at, :utc_datetime
    field :last_check_status, :string, default: "pending"
    field :last_error, :string

    has_many :project_cluster_accesses, Trifle.Organizations.ProjectClusterAccess
    has_many :projects, Trifle.Organizations.Project

    timestamps()
  end

  def drivers, do: @drivers
  def statuses, do: @statuses
  def visibilities, do: @visibilities

  def default_port("mongo"), do: 27017
  def default_port(_), do: nil

  def requires_host?("mongo"), do: true
  def requires_host?(_), do: true

  def requires_port?("mongo"), do: true
  def requires_port?(_), do: true

  def requires_username?("mongo"), do: false
  def requires_username?(_), do: true

  def requires_password?("mongo"), do: false
  def requires_password?(_), do: true

  def requires_database_name?("mongo"), do: true
  def requires_database_name?(_), do: false

  def default_config_options("mongo") do
    %{
      "pool_size" => 5,
      "pool_timeout" => 5000,
      "timeout" => 5000,
      "collection_name" => "trifle_stats",
      "expire_after" => nil,
      "joined_identifiers" => "partial"
    }
  end

  def default_config_options(_), do: %{}

  def changeset(cluster, attrs) do
    cluster
    |> cast(attrs, [
      :name,
      :code,
      :driver,
      :status,
      :visibility,
      :is_default,
      :region,
      :country,
      :city,
      :host,
      :port,
      :database_name,
      :username,
      :password,
      :auth_database,
      :config
    ])
    |> validate_required([:name, :code, :driver, :status, :visibility])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:code, min: 1, max: 64)
    |> validate_format(:code, ~r/^[a-z0-9][a-z0-9\-]*$/,
      message: "must contain lowercase letters, numbers, and hyphens"
    )
    |> validate_inclusion(:driver, @drivers)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:visibility, @visibilities)
    |> unique_constraint(:code)
    |> unique_constraint(:is_default, name: :project_clusters_is_default_index)
    |> validate_conditional_fields()
    |> validate_number(:port, greater_than: 0, less_than: 65536)
    |> put_default_config()
  end

  defp validate_conditional_fields(changeset) do
    driver = get_field(changeset, :driver)
    status = get_field(changeset, :status)

    if status == "coming_soon" do
      changeset
    else
      changeset
      |> maybe_validate_required_field(:host, requires_host?(driver))
      |> maybe_validate_required_field(:port, requires_port?(driver))
      |> maybe_validate_required_field(:username, requires_username?(driver))
      |> maybe_validate_required_field(:password, requires_password?(driver))
      |> maybe_validate_required_field(:database_name, requires_database_name?(driver))
    end
  end

  defp maybe_validate_required_field(changeset, field, true) do
    validate_required(changeset, [field])
  end

  defp maybe_validate_required_field(changeset, _field, false), do: changeset

  defp put_default_config(changeset) do
    case get_field(changeset, :driver) do
      nil ->
        changeset

      driver ->
        config = get_field(changeset, :config) || %{}
        default_config = default_config_options(driver)
        merged_config = Map.merge(default_config, config)
        normalized_config = normalize_config_values(merged_config)
        put_change(changeset, :config, normalized_config)
    end
  end

  defp normalize_config_values(config) when is_map(config) do
    config
    |> Enum.map(fn {key, value} -> {key, normalize_config_value(key, value)} end)
    |> Enum.into(%{})
  end

  defp normalize_config_value("joined_identifiers", "true"), do: "full"
  defp normalize_config_value("joined_identifiers", "false"), do: nil
  defp normalize_config_value("joined_identifiers", "full"), do: "full"
  defp normalize_config_value("joined_identifiers", "partial"), do: "partial"
  defp normalize_config_value("joined_identifiers", "null"), do: nil
  defp normalize_config_value("joined_identifiers", ""), do: nil
  defp normalize_config_value("expire_after", ""), do: nil

  defp normalize_config_value("expire_after", val) when is_binary(val) do
    case Integer.parse(val) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp normalize_config_value(_key, value), do: value

  def is_setup?(%__MODULE__{} = cluster) do
    cluster.last_check_status == "success"
  end

  def check_status(%__MODULE__{} = cluster) do
    try do
      {setup_exists, error_msg} =
        case cluster.driver do
          "mongo" -> mongo_exists_direct?(cluster)
          driver -> {false, "Unsupported cluster driver: #{driver}"}
        end

      status =
        cond do
          error_msg -> "error"
          setup_exists -> "success"
          true -> "pending"
        end

      {:ok, updated_cluster} = update_check_status(cluster, status, error_msg)

      if error_msg do
        {:error, updated_cluster, error_msg}
      else
        {:ok, updated_cluster, setup_exists}
      end
    rescue
      error ->
        error_msg = Exception.message(error)
        {:ok, updated_cluster} = update_check_status(cluster, "error", error_msg)
        {:error, updated_cluster, error_msg}
    end
  end

  def setup(%__MODULE__{} = cluster) do
    try do
      config = cluster.config || %{}

      case cluster.driver do
        "mongo" ->
          with {:ok, url} <- build_mongo_url(cluster),
               {:ok, conn} <- Mongo.start_link(url: url) do
            collection_name = config["collection_name"] || "trifle_stats"

            joined_identifiers =
              normalize_joined_identifiers(Map.get(config, "joined_identifiers", "partial"))

            expire_after = parse_expire_after(config["expire_after"])

            result =
              Trifle.Stats.Driver.MongoProject.setup!(
                conn,
                collection_name,
                joined_identifiers,
                expire_after
              )

            GenServer.stop(conn)

            case result do
              :ok -> {:ok, "MongoDB collection and indexes created successfully"}
              {:error, reason} -> {:error, "MongoDB setup failed: #{inspect(reason)}"}
              other -> {:error, "MongoDB setup returned unexpected result: #{inspect(other)}"}
            end
          else
            {:error, reason} when is_binary(reason) ->
              {:error, reason}

            {:error, reason} ->
              {:error, "Failed to connect to MongoDB: #{inspect(reason)}"}
          end

        driver ->
          {:error, "Unsupported cluster driver: #{driver}"}
      end
    rescue
      error -> {:error, "Setup failed: #{Exception.message(error)}"}
    end
  end

  defp update_check_status(cluster, status, error) do
    attrs = %{
      last_check_at: DateTime.utc_now() |> DateTime.truncate(:second),
      last_check_status: status,
      last_error: error
    }

    cluster
    |> Ecto.Changeset.change(attrs)
    |> Trifle.Repo.update()
  end

  defp mongo_exists_direct?(cluster) do
    config = cluster.config || %{}
    collection_name = config["collection_name"] || "trifle_stats"

    with {:ok, url} <- build_mongo_url(cluster),
         {:ok, conn} <-
           Mongo.start_link(url: url, pool_size: 1, timeout: 2000, pool_timeout: 2000) do
      result =
        try do
          collections =
            conn
            |> Mongo.show_collections()
            |> Enum.to_list()

          Enum.member?(collections, collection_name)
        rescue
          _ -> false
        end

      GenServer.stop(conn)
      {result, nil}
    else
      {:error, reason} when is_binary(reason) ->
        {false, reason}

      {:error, reason} ->
        {false, "Failed to connect to MongoDB: #{inspect(reason)}"}
    end
  end

  defp build_mongo_url(cluster) do
    host = cluster.host

    if is_nil(host) or host == "" do
      {:error, "MongoDB host is not configured"}
    else
      db_name = cluster.database_name

      if is_nil(db_name) or db_name == "" do
        {:error, "MongoDB database name is not configured"}
      else
        url = "mongodb://"

        url =
          if cluster.username && cluster.password do
            "#{url}#{cluster.username}:#{cluster.password}@"
          else
            url
          end

        port = cluster.port || 27017
        url = "#{url}#{host}:#{port}/#{db_name}"

        url =
          if cluster.auth_database && cluster.auth_database != "" do
            "#{url}?authSource=#{cluster.auth_database}"
          else
            url
          end

        {:ok, url}
      end
    end
  end

  defp normalize_joined_identifiers(value) do
    case value do
      nil -> nil
      true -> :full
      false -> nil
      "true" -> :full
      "false" -> nil
      "full" -> :full
      :full -> :full
      "partial" -> :partial
      :partial -> :partial
      "null" -> nil
      "" -> nil
      val -> val
    end
  end

  defp parse_expire_after(nil), do: nil
  defp parse_expire_after(""), do: nil

  defp parse_expire_after(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp parse_expire_after(val) when is_integer(val), do: val
  defp parse_expire_after(_), do: nil
end
