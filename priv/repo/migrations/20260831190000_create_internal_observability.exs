defmodule Trifle.Repo.Migrations.CreateInternalObservability do
  use Ecto.Migration

  def up do
    create table(:trifle_internal_stats, primary_key: false) do
      add :key, :string, primary_key: true
      add :data, :map, null: false, default: fragment("'{}'::jsonb")
    end

    create table(:trifle_internal_stats_ping, primary_key: false) do
      add :key, :string, primary_key: true
      add :at, :utc_datetime_usec, null: false
      add :data, :map, null: false, default: fragment("'{}'::jsonb")
    end

    create table(:trifle_traces, primary_key: false) do
      add :reference, :text, primary_key: true
      add :key, :text, null: false
      add :segments, :map, null: false, default: fragment("'[]'::jsonb")
      add :state, :string, size: 32, null: false
      add :tags, :map, null: false, default: fragment("'[]'::jsonb")
      add :meta, :map
      add :context, :map, null: false, default: fragment("'{}'::jsonb")
      add :duration, :bigint, null: false, default: 0
      add :counters, :map, null: false, default: fragment("'{}'::jsonb")
      add :length, :bigint, null: false, default: 0
      add :parts, :integer, null: false, default: 0
      add :first_at, :utc_datetime_usec, null: false
      add :last_at, :utc_datetime_usec, null: false
      add :retention, :integer, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :bucket_id, :integer, null: false, default: 0
    end

    execute(
      "CREATE INDEX trifle_traces_segments_gin ON trifle_traces USING GIN (segments)",
      "DROP INDEX trifle_traces_segments_gin"
    )

    execute(
      "CREATE INDEX trifle_traces_tags_gin ON trifle_traces USING GIN (tags)",
      "DROP INDEX trifle_traces_tags_gin"
    )

    execute(
      "CREATE INDEX trifle_traces_state_started " <>
        "ON trifle_traces (state, first_at DESC, reference DESC)",
      "DROP INDEX trifle_traces_state_started"
    )

    execute(
      "CREATE INDEX trifle_traces_started " <>
        "ON trifle_traces (first_at DESC, reference DESC)",
      "DROP INDEX trifle_traces_started"
    )

    execute(
      "CREATE INDEX trifle_traces_duration_started " <>
        "ON trifle_traces (duration, first_at DESC, reference DESC)",
      "DROP INDEX trifle_traces_duration_started"
    )

    create index(:trifle_traces, [:expires_at], name: :trifle_traces_expires_at)
  end

  def down do
    drop table(:trifle_traces)
    drop table(:trifle_internal_stats_ping)
    drop table(:trifle_internal_stats)
  end
end
