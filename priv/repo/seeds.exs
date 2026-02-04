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

admin_user =
  case Accounts.get_user_by_email(admin_email) do
    nil ->
      {:ok, admin_user} =
        Accounts.register_user(%{
          email: admin_email,
          password: admin_password
        })

      changeset = Ecto.Changeset.change(admin_user, is_admin: true)
      {:ok, admin_user} = Trifle.Repo.update(changeset)

      IO.puts("✅ Created admin user: #{admin_email}")
      admin_user

    existing_user ->
      admin_user =
        if existing_user.is_admin do
          IO.puts("⚠️  Admin user already exists: #{admin_email}")
          existing_user
        else
          changeset = Ecto.Changeset.change(existing_user, is_admin: true)
          {:ok, updated_user} = Trifle.Repo.update(changeset)
          IO.puts("✅ Updated existing user to admin: #{admin_email}")
          updated_user
        end

      admin_user
  end

# Ensure a default organization exists and the admin owns it
organization_attrs = %{name: "Trifle Demo", slug: "trifle-demo"}

organization =
  case Organizations.get_organization_by_slug(organization_attrs.slug) do
    nil ->
      {:ok, organization} = Organizations.create_organization(organization_attrs)
      IO.puts("✅ Created default organization: #{organization.name}")
      organization

    organization ->
      IO.puts("⚠️  Organization already exists: #{organization.name}")
      organization
  end

_membership =
  case Organizations.get_membership_for_org(organization, admin_user) do
    nil ->
      {:ok, membership} = Organizations.create_membership(organization, admin_user, "owner")
      IO.puts("✅ Linked admin to organization as owner")
      membership

    membership ->
      IO.puts("⚠️  Admin already linked to organization as #{membership.role}")
      membership
  end

# Project cluster configuration
project_cluster_attrs = %{
  name: "Dev Cluster",
  code: "dev",
  driver: "mongo",
  status: "active",
  visibility: "public",
  is_default: true,
  region: "local",
  host: "mongo",
  port: 27017,
  database_name: "trifle",
  config: %{"collection_name" => "trifle_stats", "joined_identifiers" => "partial"}
}

case Organizations.list_project_clusters()
     |> Enum.find(&(&1.code == project_cluster_attrs.code)) do
  nil ->
    {:ok, _cluster} = Organizations.create_project_cluster(project_cluster_attrs)
    IO.puts("✅ Created project cluster: #{project_cluster_attrs.name}")

  _cluster ->
    IO.puts("⚠️  Project cluster already exists: #{project_cluster_attrs.name}")
end

# Database configurations
database_configs = [
  %{
    display_name: "Redis",
    driver: "redis",
    host: "redis",
    port: 6379,
    config: %{"prefix" => "trifle_stats"}
  },
  %{
    display_name: "Mongo Joined",
    driver: "mongo",
    host: "mongo",
    port: 27017,
    database_name: "trifle_stats_joined",
    config: %{"collection_name" => "trifle_stats_joined", "joined_identifiers" => "full"}
  },
  %{
    display_name: "Mongo Separated",
    driver: "mongo",
    host: "mongo",
    port: 27017,
    database_name: "trifle_stats_separated",
    config: %{"collection_name" => "trifle_stats_separated", "joined_identifiers" => "null"}
  },
  %{
    display_name: "Postgres Joined",
    driver: "postgres",
    host: "postgres",
    port: 5432,
    database_name: "trifle_dev",
    username: "postgres",
    password: "password",
    config: %{"table_name" => "trifle_stats_joined", "joined_identifiers" => "full"}
  },
  %{
    display_name: "Postgres Separated",
    driver: "postgres",
    host: "postgres",
    port: 5432,
    database_name: "trifle_dev",
    username: "postgres",
    password: "password",
    config: %{"table_name" => "trifle_stats_separated", "joined_identifiers" => "null"}
  },
  %{
    display_name: "SQLite Joined",
    driver: "sqlite",
    file_path: "trifle_stats_joined.sqlite",
    config: %{"table_name" => "trifle_stats_joined", "joined_identifiers" => "full"}
  },
  %{
    display_name: "SQLite Separated",
    driver: "sqlite",
    file_path: "trifle_stats_separated.sqlite",
    config: %{"table_name" => "trifle_stats_separated", "joined_identifiers" => "null"}
  }
]

# Create database records
Enum.each(database_configs, fn config ->
  case Organizations.list_databases_for_org(organization)
       |> Enum.find(&(&1.display_name == config.display_name)) do
    nil ->
      {:ok, _database} = Organizations.create_database_for_org(organization, config)
      IO.puts("✅ Created database: #{config.display_name}")

    _existing_database ->
      IO.puts("⚠️  Database already exists: #{config.display_name}")
  end
end)

IO.puts("🎉 Seeding completed!")
