defmodule Trifle.Repo.Migrations.AddAlertSeriesToMonitors do
  use Ecto.Migration

  def up do
    alter table(:monitors) do
      add :alert_series, {:array, :map}, default: [], null: false
    end

    execute("""
    UPDATE monitors
    SET alert_series = CASE
      WHEN COALESCE(BTRIM(alert_metric_path), '') = '' THEN ARRAY[]::jsonb[]
      ELSE ARRAY[
        jsonb_build_object(
          'kind', 'path',
          'path', alert_metric_path,
          'expression', '',
          'label', '',
          'visible', true,
          'color_selector', 'default.*'
        )
      ]
    END
    """)
  end

  def down do
    alter table(:monitors) do
      remove :alert_series
    end
  end
end
