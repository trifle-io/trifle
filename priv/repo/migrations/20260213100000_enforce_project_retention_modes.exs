defmodule Trifle.Repo.Migrations.EnforceProjectRetentionModes do
  use Ecto.Migration

  @basic_retention_seconds 15_778_476
  @extended_retention_seconds 94_670_856

  def up do
    execute("""
    UPDATE projects
    SET expire_after =
      CASE
        WHEN expire_after = #{@extended_retention_seconds} THEN #{@extended_retention_seconds}
        WHEN expire_after > #{@basic_retention_seconds} THEN #{@extended_retention_seconds}
        ELSE #{@basic_retention_seconds}
      END
    """)

    alter table(:projects) do
      modify :expire_after, :integer, null: false
    end

    create constraint(:projects, :projects_expire_after_retention_check,
             check:
               "expire_after IN (#{@basic_retention_seconds}, #{@extended_retention_seconds})"
           )
  end

  def down do
    drop constraint(:projects, :projects_expire_after_retention_check)

    alter table(:projects) do
      modify :expire_after, :integer, null: true
    end
  end
end
