defmodule Trifle.Repo.Migrations.AddMonitorExecutionsDispatchIndex do
  use Ecto.Migration

  # Built concurrently so a large executions table is not write-locked during deploy.
  @disable_ddl_transaction true
  @disable_migration_lock true

  @index_name :monitor_executions_monitor_kind_triggered_index

  # Serves the per-minute dispatcher lookup "latest execution of kind K for monitor M"
  # (Trifle.Monitors.Jobs.DispatchRunner.last_execution_map/3) with one index seek
  # per monitor instead of an aggregate over the whole table.
  def up do
    create_if_not_exists index(
                           :monitor_executions,
                           ["monitor_id", "(details->>'kind')", "triggered_at DESC"],
                           name: @index_name,
                           concurrently: true
                         )
  end

  def down do
    drop_if_exists index(:monitor_executions, [], name: @index_name, concurrently: true)
  end
end
