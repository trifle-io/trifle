defmodule Trifle.Repo.Migrations.UpdateProjectsFields do
  use Ecto.Migration

  @default_granularities ~w(1s 1m 1h 1d 1w 1mo 1q 1y)

  def change do
    alter table(:projects) do
      remove :slug
      add :granularities, {:array, :string}, default: @default_granularities, null: false
      add :expire_after, :integer
      add :default_timeframe, :string
      add :default_granularity, :string
    end

    execute(
      "UPDATE projects SET granularities = ARRAY['1s','1m','1h','1d','1w','1mo','1q','1y'] WHERE granularities IS NULL OR array_length(granularities, 1) IS NULL"
    )

    execute(
      "UPDATE projects SET default_granularity = granularities[1] WHERE default_granularity IS NULL AND array_length(granularities, 1) > 0"
    )
  end
end
