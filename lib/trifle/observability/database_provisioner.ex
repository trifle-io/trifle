defmodule Trifle.Observability.DatabaseProvisioner do
  @moduledoc "Creates the editable database source representing Trifle's own observability data."

  import Ecto.Query, warn: false
  require Logger

  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Organization}
  alias Trifle.Repo

  @managed_key "internal_trifle_observability"

  def managed_key, do: @managed_key

  @spec ensure_internal_database(Organization.t() | nil) ::
          {:ok, Database.t() | nil} | {:error, term()}
  def ensure_internal_database(organization \\ nil) do
    cond do
      not Trifle.Config.self_hosted_mode?() ->
        {:ok, nil}

      existing = Repo.get_by(Database, managed_key: @managed_key) ->
        {:ok, existing}

      true ->
        with %Organization{} = first <- first_organization(),
             :ok <- ensure_first_organization(first, organization),
             {:ok, attrs} <- Trifle.Observability.database_attrs(),
             {:ok, database} <-
               Organizations.create_managed_database_for_org(first, @managed_key, attrs) do
          finish_setup(database)
        else
          nil -> {:error, :organization_not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  rescue
    error in Ecto.ConstraintError ->
      case Repo.get_by(Database, managed_key: @managed_key) do
        %Database{} = database -> {:ok, database}
        nil -> {:error, error}
      end
  end

  def maybe_provision(%Organization{} = organization) do
    case ensure_internal_database(organization) do
      {:ok, _database} ->
        :ok

      {:error, :not_first_organization} ->
        :ok

      {:error, :observability_disabled} ->
        :ok

      {:error, reason} ->
        Logger.warning("Internal observability database was not provisioned: #{inspect(reason)}")
        {:warning, reason}
    end
  end

  defp first_organization do
    from(o in Organization, order_by: [asc: o.inserted_at, asc: o.id], limit: 1)
    |> Repo.one()
  end

  defp ensure_first_organization(_first, nil), do: :ok
  defp ensure_first_organization(%Organization{id: id}, %Organization{id: id}), do: :ok
  defp ensure_first_organization(_first, _requested), do: {:error, :not_first_organization}

  defp finish_setup(database) do
    case Organizations.setup_database(database) do
      {:ok, _message} ->
        case Organizations.check_database_status(database) do
          {:ok, checked, _exists?} -> {:ok, checked}
          {:error, checked, _reason} -> {:ok, checked}
        end

      {:error, reason} ->
        {:ok, failed} = Database.mark_check_failed(database, reason)
        Logger.warning("Internal observability database setup failed: #{reason}")
        {:ok, failed}
    end
  end
end
