defmodule Trifle.Repo.Migrations.AddTraceBucketNames do
  use Ecto.Migration

  # Older installations have integer bucket_id values. Keep them for inspection;
  # the original bucket list is required to translate them safely into names.
  # Fresh library-created tables may already have bucket_name, or not exist yet.
  def up do
    for table <- ~w(trifle_traces trifle_internal_traces) do
      execute("ALTER TABLE IF EXISTS #{table} ADD COLUMN IF NOT EXISTS bucket_name TEXT")
    end
  end

  def down do
    raise Ecto.MigrationError,
      message: "Bucket names cannot safely be converted back to positional bucket IDs"
  end
end
