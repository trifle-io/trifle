defmodule Trifle.Repo.Migrations.AlignInternalTraceTimestamps do
  use Ecto.Migration

  # Ecto's :utc_datetime_usec creates timestamp WITHOUT time zone. The external
  # trace driver's schema uses timestamptz, which Postgrex decodes as DateTime.
  # Existing values represent UTC; never interpret them in the server's zone.
  def up do
    execute("""
    ALTER TABLE trifle_traces
      ALTER COLUMN first_at TYPE timestamptz USING first_at AT TIME ZONE 'UTC',
      ALTER COLUMN last_at TYPE timestamptz USING last_at AT TIME ZONE 'UTC',
      ALTER COLUMN expires_at TYPE timestamptz USING expires_at AT TIME ZONE 'UTC'
    """)
  end

  def down do
    execute("""
    ALTER TABLE trifle_traces
      ALTER COLUMN first_at TYPE timestamp(6) USING first_at AT TIME ZONE 'UTC',
      ALTER COLUMN last_at TYPE timestamp(6) USING last_at AT TIME ZONE 'UTC',
      ALTER COLUMN expires_at TYPE timestamp(6) USING expires_at AT TIME ZONE 'UTC'
    """)
  end
end
