defmodule Trifle.Organizations.Project do
  use Ecto.Schema
  import Ecto.Changeset
  import Slugy

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
    |> put_assoc(:user,  attrs["user"])
    |> slugify(:name)
    |> validate_required([:user, :name, :slug, :time_zone, :beginning_of_week])
  end

  def stats_config(project) do
    {:ok, connection} = Mongo.start_link(url: "mongodb://mongo:27017/trifle")

    Trifle.Stats.Configuration.configure(
      Trifle.Stats.Driver.MongoProject.new(connection, "proj_#{project.id}"),
      project.time_zone,
      Tzdata.TimeZoneDatabase,
      Trifle.Organizations.Project.beginning_of_week_for(project)
    )
  end

  def beginning_of_week_for(project) do
    inverted = Map.new(Trifle.Stats.Nocturnal.days_into_week(), fn {key, val} -> {val, key} end)

    inverted[project.beginning_of_week]
  end
end
