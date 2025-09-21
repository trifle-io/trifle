defmodule Trifle.Organizations.Project do
  use Ecto.Schema
  import Ecto.Changeset
  import Slugy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :beginning_of_week, :integer
    field :name, :string
    field :slug, :string
    field :time_zone, :string
    belongs_to :user, Trifle.Accounts.User
    has_many :project_tokens, Trifle.Organizations.ProjectToken

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :slug, :time_zone, :beginning_of_week])
    |> put_assoc(:user, attrs["user"])
    |> slugify(:name)
    |> validate_required([:user, :name, :slug, :time_zone, :beginning_of_week])
  end

  def stats_config(project) do
    # Use a shared connection pool instead of creating new connections
    connection = get_mongo_connection()

    Trifle.Stats.Configuration.configure(
      Trifle.Stats.Driver.MongoProject.new(connection, "proj_#{project.id}"),
      time_zone: project.time_zone,
      time_zone_database: Tzdata.TimeZoneDatabase,
      beginning_of_week: Trifle.Organizations.Project.beginning_of_week_for(project),
      track_granularities: ["1s", "1m", "1h", "1d", "1w", "1mo", "1q", "1y"]
    )
  end

  defp get_mongo_connection do
    case Process.whereis(:trifle_mongo) do
      nil ->
        {:ok, conn} =
          Mongo.start_link(url: "mongodb://localhost:27017/trifle", name: :trifle_mongo)

        conn

      pid ->
        pid
    end
  end

  def beginning_of_week_for(project) do
    inverted = Map.new(Trifle.Stats.Nocturnal.days_into_week(), fn {key, val} -> {val, key} end)

    inverted[project.beginning_of_week]
  end
end
