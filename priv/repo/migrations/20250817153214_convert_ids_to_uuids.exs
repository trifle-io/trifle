defmodule Trifle.Repo.Migrations.ConvertIdsToUuids do
  use Ecto.Migration

  def up do
    # Add UUID columns first
    alter table(:users) do
      add :uuid_id, :binary_id, null: true
    end

    alter table(:projects) do
      add :uuid_id, :binary_id, null: true
      add :uuid_user_id, :binary_id, null: true
    end

    alter table(:project_tokens) do
      add :uuid_id, :binary_id, null: true
      add :uuid_project_id, :binary_id, null: true
    end

    alter table(:users_tokens) do
      add :uuid_id, :binary_id, null: true
      add :uuid_user_id, :binary_id, null: true
    end

    # Generate UUIDs for all existing records
    flush()

    execute """
    UPDATE users SET uuid_id = gen_random_uuid();
    """

    execute """
    UPDATE projects 
    SET uuid_id = gen_random_uuid(),
        uuid_user_id = (SELECT u.uuid_id FROM users u WHERE u.id = projects.user_id);
    """

    execute """
    UPDATE project_tokens 
    SET uuid_id = gen_random_uuid(),
        uuid_project_id = (SELECT p.uuid_id FROM projects p WHERE p.id = project_tokens.project_id);
    """

    execute """
    UPDATE users_tokens 
    SET uuid_id = gen_random_uuid(),
        uuid_user_id = (SELECT u.uuid_id FROM users u WHERE u.id = users_tokens.user_id);
    """

    # Make UUID columns not null
    alter table(:users) do
      modify :uuid_id, :binary_id, null: false
    end

    alter table(:projects) do
      modify :uuid_id, :binary_id, null: false
      modify :uuid_user_id, :binary_id, null: false
    end

    alter table(:project_tokens) do
      modify :uuid_id, :binary_id, null: false
      modify :uuid_project_id, :binary_id, null: false
    end

    alter table(:users_tokens) do
      modify :uuid_id, :binary_id, null: false
      modify :uuid_user_id, :binary_id, null: false
    end

    # Drop old primary key constraints and foreign keys
    execute "ALTER TABLE project_tokens DROP CONSTRAINT project_tokens_project_id_fkey;"
    execute "ALTER TABLE users_tokens DROP CONSTRAINT users_tokens_user_id_fkey;"
    execute "ALTER TABLE projects DROP CONSTRAINT projects_user_id_fkey;"

    drop constraint(:users, "users_pkey")
    drop constraint(:projects, "projects_pkey")
    drop constraint(:project_tokens, "project_tokens_pkey")
    drop constraint(:users_tokens, "users_tokens_pkey")

    # Drop old columns
    alter table(:users) do
      remove :id
    end

    alter table(:projects) do
      remove :id
      remove :user_id
    end

    alter table(:project_tokens) do
      remove :id
      remove :project_id
    end

    alter table(:users_tokens) do
      remove :id
      remove :user_id
    end

    # Rename UUID columns to id
    rename table(:users), :uuid_id, to: :id
    rename table(:projects), :uuid_id, to: :id
    rename table(:projects), :uuid_user_id, to: :user_id
    rename table(:project_tokens), :uuid_id, to: :id
    rename table(:project_tokens), :uuid_project_id, to: :project_id
    rename table(:users_tokens), :uuid_id, to: :id
    rename table(:users_tokens), :uuid_user_id, to: :user_id

    # Add primary key constraints
    alter table(:users) do
      modify :id, :binary_id, primary_key: true
    end

    alter table(:projects) do
      modify :id, :binary_id, primary_key: true
    end

    alter table(:project_tokens) do
      modify :id, :binary_id, primary_key: true
    end

    alter table(:users_tokens) do
      modify :id, :binary_id, primary_key: true
    end

    # Add foreign key constraints
    alter table(:projects) do
      modify :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:project_tokens) do
      modify :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:users_tokens) do
      modify :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end
  end

  def down do
    # This would be complex to reverse, so we'll leave it empty for now
    # In production, you'd want to create a proper rollback strategy
    raise "Irreversible migration - UUID conversion cannot be automatically rolled back"
  end
end
