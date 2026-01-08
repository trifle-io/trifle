defmodule Trifle.Organizations.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Timeframe

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @default_granularities ["1s", "1m", "1h", "1d", "1w", "1mo", "1q", "1y"]

  schema "projects" do
    field :beginning_of_week, :integer
    field :name, :string
    field :time_zone, :string
    field :granularities, {:array, :string}, default: @default_granularities
    field :expire_after, :integer
    field :default_timeframe, :string
    field :default_granularity, :string

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
    "default_granularity" => :default_granularity
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
      :default_granularity
    ])
    |> maybe_put_user(user)
    |> ensure_granularities()
    |> validate_timeframe_field(:default_timeframe)
    |> ensure_default_granularity()
    |> validate_required([:name, :time_zone, :beginning_of_week, :granularities])
    |> validate_number(:expire_after, greater_than: 0)
  end

  def stats_config(project) do
    connection = get_mongo_connection()

    granularities =
      case project.granularities do
        list when is_list(list) and list != [] -> list
        _ -> @default_granularities
      end

    driver =
      Trifle.Stats.Driver.MongoProject.new(
        connection,
        "proj_#{project.id}",
        "trifle_stats",
        "::",
        1,
        :partial,
        project.expire_after,
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

  defp get_mongo_connection do
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
    case Map.get(attrs, :expire_after) do
      value when value in [nil, ""] ->
        Map.put(attrs, :expire_after, nil)

      value when is_binary(value) ->
        trimmed = String.trim(value)

        case Integer.parse(trimmed) do
          {int, _rest} -> Map.put(attrs, :expire_after, int)
          :error -> Map.put(attrs, :expire_after, nil)
        end

      value ->
        Map.put(attrs, :expire_after, value)
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

  defp maybe_put_user(changeset, nil), do: changeset
  defp maybe_put_user(changeset, user), do: put_assoc(changeset, :user, user)
end
