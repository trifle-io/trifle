defmodule Trifle.Organizations.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Timeframe
  alias Trifle.Organizations
  alias Trifle.Organizations.ProjectCluster

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @default_granularities ["1s", "1m", "1h", "1d", "1w", "1mo", "1q", "1y"]
  @billing_states ["pending_checkout", "active", "locked"]
  @basic_retention_seconds 15_778_476
  @extended_retention_seconds 94_670_856
  @retention_seconds [@basic_retention_seconds, @extended_retention_seconds]
  @retention_options [
    {"Basic (6m)", @basic_retention_seconds},
    {"Extended (3y)", @extended_retention_seconds}
  ]

  schema "projects" do
    field :beginning_of_week, :integer
    field :name, :string
    field :time_zone, :string
    field :granularities, {:array, :string}, default: @default_granularities
    field :expire_after, :integer
    field :default_timeframe, :string
    field :default_granularity, :string
    field :billing_required, :boolean, default: true
    field :billing_state, :string, default: "pending_checkout"

    belongs_to :organization, Trifle.Organizations.Organization
    belongs_to :project_cluster, Trifle.Organizations.ProjectCluster
    belongs_to :user, Trifle.Accounts.User
    has_many :project_tokens, Trifle.Organizations.ProjectToken

    timestamps()
  end

  @string_to_atom %{
    "name" => :name,
    "time_zone" => :time_zone,
    "beginning_of_week" => :beginning_of_week,
    "granularities" => :granularities,
    "expire_after" => :expire_after,
    "default_timeframe" => :default_timeframe,
    "default_granularity" => :default_granularity,
    "billing_required" => :billing_required,
    "billing_state" => :billing_state,
    "organization_id" => :organization_id,
    "project_cluster_id" => :project_cluster_id
  }

  @doc false
  def changeset(project, attrs) do
    user = Map.get(attrs, "user") || Map.get(attrs, :user)

    attrs =
      attrs
      |> Map.delete(:user)
      |> Map.delete("user")
      |> normalize_attrs()
      |> normalize_granularities()
      |> normalize_expire_after()

    project
    |> cast(attrs, [
      :name,
      :time_zone,
      :beginning_of_week,
      :granularities,
      :expire_after,
      :default_timeframe,
      :default_granularity,
      :billing_required,
      :billing_state,
      :organization_id,
      :project_cluster_id
    ])
    |> maybe_put_user(user)
    |> ensure_granularities()
    |> validate_timeframe_field(:default_timeframe)
    |> ensure_default_granularity()
    |> validate_required([
      :name,
      :time_zone,
      :beginning_of_week,
      :granularities,
      :expire_after,
      :organization_id
    ])
    |> validate_inclusion(:expire_after, @retention_seconds)
    |> validate_retention_immutable(project)
    |> validate_inclusion(:billing_state, @billing_states)
    |> check_constraint(:billing_state, name: :projects_billing_state_check)
    |> check_constraint(:expire_after, name: :projects_expire_after_retention_check)
  end

  @doc false
  def billing_changeset(project, attrs) do
    project
    |> cast(attrs, [:billing_required, :billing_state])
    |> validate_required([:billing_required, :billing_state])
    |> validate_inclusion(:billing_state, @billing_states)
    |> check_constraint(:billing_state, name: :projects_billing_state_check)
  end

  def stats_config(project) do
    {connection, cluster_config} = resolve_cluster_connection(project)

    granularities =
      case project.granularities do
        list when is_list(list) and list != [] -> list
        _ -> @default_granularities
      end

    expire_after = project_expire_after(project)

    driver =
      Trifle.Stats.Driver.MongoProject.new(
        connection,
        "proj_#{project.id}",
        cluster_config["collection_name"] || "trifle_stats",
        "::",
        1,
        cluster_config["joined_identifiers"] || :partial,
        expire_after,
        true
      )

    Trifle.Stats.Configuration.configure(
      driver,
      time_zone: project.time_zone || "UTC",
      time_zone_database: Tzdata.TimeZoneDatabase,
      beginning_of_week: Trifle.Organizations.Project.beginning_of_week_for(project) || :monday,
      track_granularities: granularities,
      buffer_enabled: false
    )
  end

  defp resolve_cluster_connection(%__MODULE__{} = project) do
    case fetch_project_cluster(project) do
      {:ok, %ProjectCluster{driver: "mongo"} = cluster} ->
        {:ok, connection_name} =
          Trifle.DatabasePools.MongoProjectClusterPoolSupervisor.start_mongo_pool(cluster)

        {connection_name, cluster.config || %{}}

      {:ok, %ProjectCluster{driver: driver}} ->
        raise ArgumentError, "unsupported project cluster driver: #{inspect(driver)}"

      :error ->
        {get_legacy_mongo_connection(), %{}}
    end
  end

  defp fetch_project_cluster(%__MODULE__{} = project) do
    cond do
      Ecto.assoc_loaded?(project.project_cluster) && project.project_cluster ->
        {:ok, project.project_cluster}

      is_binary(project.project_cluster_id) ->
        case Organizations.get_project_cluster(project.project_cluster_id) do
          nil -> :error
          cluster -> {:ok, cluster}
        end

      true ->
        case Organizations.get_default_project_cluster() do
          nil -> :error
          cluster -> {:ok, cluster}
        end
    end
  end

  defp get_legacy_mongo_connection do
    case Process.whereis(:trifle_mongo) do
      nil ->
        url = System.get_env("MONGODB_URL") || "mongodb://localhost:27017/trifle"

        {:ok, conn} =
          Mongo.start_link(url: url, name: :trifle_mongo)

        conn

      pid ->
        pid
    end
  end

  def beginning_of_week_for(project) do
    inverted = Map.new(Trifle.Stats.Nocturnal.days_into_week(), fn {key, val} -> {val, key} end)

    inverted[project.beginning_of_week]
  end

  def default_granularities, do: @default_granularities
  def retention_options, do: @retention_options
  def basic_retention_seconds, do: @basic_retention_seconds
  def extended_retention_seconds, do: @extended_retention_seconds

  def retention_mode(%__MODULE__{expire_after: @extended_retention_seconds}), do: :extended
  def retention_mode(%__MODULE__{expire_after: @basic_retention_seconds}), do: :basic
  def retention_mode(%__MODULE__{}), do: :basic

  def retention_label(%__MODULE__{} = project), do: retention_label(project.expire_after)
  def retention_label(@extended_retention_seconds), do: "Extended (3y)"
  def retention_label(@basic_retention_seconds), do: "Basic (6m)"
  def retention_label(_), do: "Basic (6m)"

  defp normalize_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)

      {key, value}, acc when is_binary(key) ->
        case Map.get(@string_to_atom, key) do
          nil -> acc
          atom_key -> Map.put(acc, atom_key, value)
        end

      {_key, _value}, acc ->
        acc
    end)
  end

  defp normalize_attrs(attrs), do: attrs

  defp normalize_granularities(attrs) do
    granularities = Map.get(attrs, :granularities)
    parsed = parse_granularities(granularities)

    case parsed do
      nil -> attrs
      list -> Map.put(attrs, :granularities, list)
    end
  end

  defp normalize_expire_after(attrs) do
    if Map.has_key?(attrs, :expire_after) do
      case Map.get(attrs, :expire_after) do
        value when value in [nil, ""] ->
          Map.put(attrs, :expire_after, nil)

        value when is_binary(value) ->
          case value |> String.trim() |> String.downcase() do
            "basic" ->
              Map.put(attrs, :expire_after, @basic_retention_seconds)

            "extended" ->
              Map.put(attrs, :expire_after, @extended_retention_seconds)

            trimmed ->
              case Integer.parse(trimmed) do
                {int, _rest} -> Map.put(attrs, :expire_after, int)
                :error -> Map.put(attrs, :expire_after, nil)
              end
          end

        value ->
          Map.put(attrs, :expire_after, value)
      end
    else
      attrs
    end
  end

  defp parse_granularities(nil), do: nil

  defp parse_granularities(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp parse_granularities(value) when is_list(value) do
    value
    |> Enum.map(fn
      v when is_binary(v) -> String.trim(v)
      v -> to_string(v)
    end)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp parse_granularities(_), do: nil

  defp ensure_granularities(changeset) do
    granularities =
      changeset
      |> get_field(:granularities)
      |> case do
        nil ->
          @default_granularities

        list when is_list(list) ->
          list
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> case do
            [] -> @default_granularities
            cleaned -> Enum.uniq(cleaned)
          end
      end

    put_change(changeset, :granularities, granularities)
  end

  defp ensure_default_granularity(changeset) do
    granularities = get_field(changeset, :granularities) || @default_granularities
    default = get_field(changeset, :default_granularity)

    cond do
      is_nil(default) or String.trim(to_string(default)) == "" ->
        put_change(changeset, :default_granularity, List.first(granularities))

      default in granularities ->
        changeset

      true ->
        add_error(changeset, :default_granularity, "must be one of the configured granularities")
    end
  end

  defp validate_timeframe_field(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Timeframe.validate(value) do
        :ok -> []
        {:ok, _parser} -> []
        {:error, message} -> [{field, message}]
      end
    end)
  end

  defp validate_retention_immutable(changeset, %__MODULE__{id: nil}), do: changeset

  defp validate_retention_immutable(changeset, %__MODULE__{}) do
    case get_change(changeset, :expire_after) do
      nil -> changeset
      _ -> add_error(changeset, :expire_after, "cannot be changed after project creation")
    end
  end

  defp project_expire_after(%__MODULE__{expire_after: expire_after})
       when expire_after in @retention_seconds,
       do: expire_after

  defp project_expire_after(%__MODULE__{}), do: @basic_retention_seconds

  defp maybe_put_user(changeset, nil), do: changeset
  defp maybe_put_user(changeset, user), do: put_assoc(changeset, :user, user)
end
