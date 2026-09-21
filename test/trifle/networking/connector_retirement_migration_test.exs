defmodule Trifle.Networking.ConnectorRetirementMigrationTest do
  use ExUnit.Case, async: false

  defmodule MigrationRepo do
    use Ecto.Repo, otp_app: :trifle, adapter: Ecto.Adapters.Postgres
  end

  test "retirement preserves source settings and blocks access without a silent direct fallback" do
    assert_retirement(false)
  end

  test "retirement accepts repaired legacy schemas without the connection method constraint" do
    assert_retirement(true)
  end

  defp assert_retirement(repaired?) do
    # Earlier synchronous UI tests can leave source pools supervised after their
    # sandbox rows disappear. Release those before allocating an isolated repo.
    supervisor = Trifle.DatabasePools.PostgresPoolSupervisor

    for {_, pid, _, _} <- DynamicSupervisor.which_children(supervisor),
        do: DynamicSupervisor.terminate_child(supervisor, pid)

    # Exercise the real irreversible migration against an isolated disposable
    # database. Never roll back or alter the shared test/development schema.
    config = Trifle.Repo.config() |> Keyword.delete(:pool) |> Keyword.put(:pool_size, 2)

    {:ok, admin} =
      Postgrex.start_link(
        Keyword.take(config, [:hostname, :port, :username, :password, :database])
      )

    database_name = "trifle_network_migration_" <> String.replace(Ecto.UUID.generate(), "-", "")
    Postgrex.query!(admin, "CREATE DATABASE #{database_name}", [])

    try do
      {:ok, repo} = MigrationRepo.start_link(Keyword.put(config, :database, database_name))

      try do
        for statement <- [
              "CREATE TABLE organizations (id uuid PRIMARY KEY)",
              "CREATE TABLE organization_connectors (id uuid PRIMARY KEY)",
              "CREATE TABLE connector_jobs (id uuid PRIMARY KEY)",
              """
              CREATE TABLE databases (
                id uuid PRIMARY KEY, organization_id uuid REFERENCES organizations(id),
                display_name text, host text, password bytea, config jsonb, trace_config jsonb,
                connection_method text, organization_connector_id uuid REFERENCES organization_connectors(id),
                pool_version integer, last_check_status text, last_error text,
                CONSTRAINT chk_databases_connection_method_allowed CHECK (connection_method IN ('direct', 'ssh_tunnel', 'connector')),
                CONSTRAINT chk_databases_connector_required CHECK ((connection_method = 'connector') = (organization_connector_id IS NOT NULL))
              )
              """,
              "INSERT INTO organizations VALUES ('00000000-0000-0000-0000-000000000001')",
              "INSERT INTO organization_connectors VALUES ('00000000-0000-0000-0000-000000000002')",
              """
              INSERT INTO databases VALUES (
                '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
                'Private metrics', '100.64.0.7', decode('1234abcd', 'hex'), '{"ssl":true}', '{"index_name":"traces"}',
                'connector', '00000000-0000-0000-0000-000000000002', 4, 'ok', NULL
              )
              """
            ],
            do: MigrationRepo.query!(statement)

        if repaired? do
          MigrationRepo.query!(
            "ALTER TABLE databases DROP CONSTRAINT chk_databases_connection_method_allowed"
          )
        end

        Code.require_file(
          "priv/repo/migrations/20260918150000_replace_connectors_with_network_connections.exs"
        )

        assert :ok =
                 Ecto.Migrator.up(
                   MigrationRepo,
                   20_260_918_150_000,
                   Trifle.Repo.Migrations.ReplaceConnectorsWithNetworkConnections,
                   log: false
                 )

        assert %{
                 rows: [
                   [
                     "Private metrics",
                     "100.64.0.7",
                     <<0x12, 0x34, 0xAB, 0xCD>>,
                     %{"ssl" => true},
                     %{"index_name" => "traces"},
                     "unconfigured",
                     5,
                     "error",
                     nil,
                     nil
                   ]
                 ]
               } =
                 MigrationRepo.query!(
                   "SELECT display_name, host, password, config, trace_config, connection_method, pool_version, last_check_status, network_connection_id, trace_network_connection_id FROM databases"
                 )

        assert %{rows: [[nil, nil]]} =
                 MigrationRepo.query!(
                   "SELECT to_regclass('connector_jobs'), to_regclass('organization_connectors')"
                 )
      after
        Supervisor.stop(repo)
      end
    after
      Postgrex.query!(admin, "DROP DATABASE #{database_name}", [])
      GenServer.stop(admin)
    end
  end
end
