# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Trifle.Repo.insert!(%Trifle.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Trifle.Accounts
alias Trifle.Organizations

IO.puts("🌱 Seeding database...")

# Create admin user
admin_email = "admin@trifle.io"
admin_password = "password"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, admin_user} =
      Accounts.register_user(%{
        email: admin_email,
        password: admin_password
      })

    # Set admin status directly using Ecto changeset
    changeset = Ecto.Changeset.change(admin_user, is_admin: true)
    {:ok, _admin_user} = Trifle.Repo.update(changeset)

    IO.puts("✅ Created admin user: #{admin_email}")

  existing_user ->
    # Ensure existing user has admin status
    if not existing_user.is_admin do
      changeset = Ecto.Changeset.change(existing_user, is_admin: true)
      {:ok, _admin_user} = Trifle.Repo.update(changeset)
      IO.puts("✅ Updated existing user to admin: #{admin_email}")
    else
      IO.puts("⚠️  Admin user already exists: #{admin_email}")
    end
end

# Database configurations
database_configs = [
  %{
    display_name: "Redis",
    driver: "redis",
    host: "localhost",
    port: 6379,
    config: %{"prefix" => "trifle_stats"}
  },
  %{
    display_name: "Mongo Joined",
    driver: "mongo",
    host: "localhost",
    port: 27017,
    database_name: "trifle_stats_joined",
    config: %{"collection_name" => "trifle_stats_joined", "joined_identifiers" => true}
  },
  %{
    display_name: "Mongo Separated",
    driver: "mongo",
    host: "localhost",
    port: 27017,
    database_name: "trifle_stats_separated",
    config: %{"collection_name" => "trifle_stats_separated", "joined_identifiers" => false}
  },
  %{
    display_name: "Postgres Joined",
    driver: "postgres",
    host: "localhost",
    port: 5432,
    database_name: "trifle_dev",
    username: "postgres",
    password: "password",
    config: %{"table_name" => "trifle_stats_joined", "joined_identifiers" => true}
  },
  %{
    display_name: "Postgres Separated",
    driver: "postgres",
    host: "localhost",
    port: 5432,
    database_name: "trifle_dev",
    username: "postgres",
    password: "password",
    config: %{"table_name" => "trifle_stats_separated", "joined_identifiers" => false}
  },
  %{
    display_name: "SQLite Joined",
    driver: "sqlite",
    file_path: "trifle_stats_separated.sqlite",
    config: %{"table_name" => "trifle_stats_joined", "joined_identifiers" => true}
  },
  %{
    display_name: "SQLite Separated",
    driver: "sqlite",
    file_path: "trifle_stats_separated.sqlite",
    config: %{"table_name" => "trifle_stats_separated", "joined_identifiers" => false}
  }
]

# Create database records
Enum.each(database_configs, fn config ->
  case Organizations.list_databases()
       |> Enum.find(&(&1.display_name == config.display_name)) do
    nil ->
      {:ok, _database} = Organizations.create_database(config)
      IO.puts("✅ Created database: #{config.display_name}")

    _existing_database ->
      IO.puts("⚠️  Database already exists: #{config.display_name}")
  end
end)

IO.puts("🎉 Seeding completed!")
