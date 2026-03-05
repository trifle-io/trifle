defmodule TrifleApi.AuthContext do
  @moduledoc false

  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationApiToken
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Repo

  def resolve_membership(%{
        assigns: %{
          current_api_user: %User{} = user,
          current_api_token: %OrganizationApiToken{} = token
        }
      }) do
    with organization_id when is_binary(organization_id) <- token.organization_id,
         %OrganizationMembership{} = membership <- Organizations.get_membership_for_user(user),
         true <- membership.organization_id == organization_id do
      {:ok, %{user: user, membership: membership}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def resolve_membership(%{assigns: %{current_project: project}})
      when is_map(project) do
    user_id = Map.get(project, :user_id) || Map.get(project, "user_id")

    with %User{} = user <- Repo.get(User, user_id),
         %{organization_id: _org_id} = membership <- Organizations.get_membership_for_user(user) do
      {:ok, %{user: user, membership: membership}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def resolve_membership(%{assigns: %{current_database: database}})
      when is_map(database) do
    organization_id = Map.get(database, :organization_id) || Map.get(database, "organization_id")

    membership =
      organization_id
      |> Organizations.list_memberships_for_org_id()
      |> pick_service_membership()

    case membership do
      %{user: %User{} = user} ->
        {:ok, %{user: user, membership: membership}}

      _ ->
        {:error, :unauthorized}
    end
  end

  def resolve_membership(_conn), do: {:error, :unauthorized}

  defp pick_service_membership(memberships) when is_list(memberships) do
    Enum.find(memberships, &Organizations.membership_owner?/1) ||
      Enum.find(memberships, &Organizations.membership_admin?/1) ||
      List.first(memberships)
  end

  defp pick_service_membership(_), do: nil
end
