defmodule Trifle.Organizations.ConnectorJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ["pending", "running", "ok", "error"]
  @types ["ping", "tcp_check", "database_tcp_check"]

  schema "connector_jobs" do
    field :type, :string
    field :status, :string, default: "pending"
    field :payload, :map, default: %{}
    field :result, :map
    field :error, :string
    field :logs, {:array, :string}, default: []
    field :completed_at, :utc_datetime

    belongs_to :organization_connector, Trifle.Organizations.OrganizationConnector

    timestamps()
  end

  def statuses, do: @statuses
  def types, do: @types

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :type,
      :status,
      :payload,
      :result,
      :error,
      :logs,
      :completed_at,
      :organization_connector_id
    ])
    |> validate_required([:type, :status, :organization_connector_id])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:status, @statuses)
    |> normalize_payload()
    |> normalize_logs()
    |> assoc_constraint(:organization_connector)
  end

  defp normalize_payload(changeset) do
    case get_field(changeset, :payload) do
      nil -> put_change(changeset, :payload, %{})
      value when is_map(value) -> changeset
      _ -> add_error(changeset, :payload, "must be an object")
    end
  end

  defp normalize_logs(changeset) do
    case get_field(changeset, :logs) do
      nil ->
        put_change(changeset, :logs, [])

      values when is_list(values) ->
        values =
          values
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        put_change(changeset, :logs, values)

      _ ->
        add_error(changeset, :logs, "must be a list")
    end
  end
end
