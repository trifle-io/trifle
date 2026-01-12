defmodule Trifle.Organizations do
  @moduledoc """
  The Organizations context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Trifle.Repo

  alias Trifle.Accounts.User

  alias Trifle.Organizations.{
    Project,
    ProjectToken,
    DatabaseToken,
    Organization,
    OrganizationMembership,
    OrganizationInvitation,
    OrganizationSSOProvider,
    OrganizationSSODomain,
    Database,
    Dashboard,
    DashboardVisit,
    Transponder,
    DashboardGroup
  }

  alias Trifle.Organizations.InvitationNotifier

  ## Organizations

  def list_organizations do
    from(o in Organization, order_by: [asc: o.name])
    |> Repo.all()
  end

  def count_organizations do
    Repo.aggregate(Organization, :count, :id)
  end

  def count_memberships_by_role do
    from(m in OrganizationMembership,
      group_by: m.role,
      select: {m.role, count(m.id)}
    )
    |> Repo.all()
    |> Enum.into(%{})
  end

  def list_user_organizations(%User{} = user) do
    from(m in OrganizationMembership,
      where: m.user_id == ^user.id,
      join: o in assoc(m, :organization),
      preload: [organization: o],
      order_by: [asc: o.name]
    )
    |> Repo.all()
    |> Enum.map(& &1.organization)
  end

  def get_organization!(id) when is_binary(id), do: Repo.get!(Organization, id)
  def get_organization(id) when is_binary(id), do: Repo.get(Organization, id)

  def get_organization_by_slug!(slug) when is_binary(slug),
    do: Repo.get_by!(Organization, slug: slug)

  def get_organization_by_slug(slug) when is_binary(slug),
    do: Repo.get_by(Organization, slug: slug)

  def create_organization(attrs \\ %{}) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  def create_organization_with_owner(attrs, %User{} = user) do
    if get_membership_for_user(user) do
      {:error, :already_member}
    else
      Repo.transaction(fn ->
        with {:ok, organization} <- create_organization(attrs),
             {:ok, membership} <- create_membership(organization, user, "owner") do
          %{organization: organization, membership: membership}
        else
          {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback({:error, changeset})
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, %{organization: organization, membership: membership}} ->
          {:ok, organization, membership}

        {:error, {:error, %Ecto.Changeset{} = changeset}} ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  def change_organization(%Organization{} = organization, attrs \\ %{}) do
    Organization.changeset(organization, attrs)
  end

  ## Organization memberships

  def membership_roles, do: OrganizationMembership.roles()

  def get_membership!(id) when is_binary(id) do
    OrganizationMembership
    |> Repo.get!(id)
    |> Repo.preload([:organization, :user, :invited_by])
  end

  def get_membership(id) when is_binary(id) do
    OrganizationMembership
    |> Repo.get(id)
    |> case do
      nil -> nil
      membership -> Repo.preload(membership, [:organization, :user, :invited_by])
    end
  end

  def get_membership_for_user(%User{} = user) do
    from(m in OrganizationMembership,
      where: m.user_id == ^user.id,
      preload: [:organization, :user, :invited_by]
    )
    |> Repo.one()
  end

  def fetch_active_membership!(%User{} = user) do
    from(m in OrganizationMembership,
      where: m.user_id == ^user.id,
      preload: [:organization, :user, :invited_by]
    )
    |> Repo.one!()
  end

  def get_active_organization(%User{} = user) do
    case get_membership_for_user(user) do
      nil -> nil
      membership -> membership.organization
    end
  end

  def get_membership_for_org(%Organization{} = organization, %User{} = user) do
    from(m in OrganizationMembership,
      where: m.organization_id == ^organization.id and m.user_id == ^user.id,
      preload: [:organization, :user, :invited_by]
    )
    |> Repo.one()
  end

  def list_memberships_for_org_id(organization_id) when is_binary(organization_id) do
    from(m in OrganizationMembership,
      where: m.organization_id == ^organization_id,
      join: u in assoc(m, :user),
      order_by: [asc: u.email],
      preload: [user: u]
    )
    |> Repo.all()
  end

  def list_members(%Organization{} = organization) do
    from(m in OrganizationMembership,
      where: m.organization_id == ^organization.id,
      join: u in assoc(m, :user),
      left_join: inviter in assoc(m, :invited_by),
      preload: [:organization, user: u, invited_by: inviter],
      order_by: [asc: u.email]
    )
    |> Repo.all()
  end

  def list_memberships_for_users(user_ids) when is_list(user_ids) do
    ids = user_ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    case ids do
      [] ->
        []

      _ ->
        from(m in OrganizationMembership,
          where: m.user_id in ^ids,
          join: o in assoc(m, :organization),
          preload: [organization: o]
        )
        |> Repo.all()
    end
  end

  def create_membership(
        %Organization{} = organization,
        %User{} = user,
        role \\ "member",
        invited_by \\ nil
      ) do
    attrs = %{
      organization_id: organization.id,
      user_id: user.id,
      role: role,
      invited_by_user_id: invited_by && invited_by.id
    }

    %OrganizationMembership{}
    |> OrganizationMembership.changeset(attrs)
    |> Repo.insert()
  end

  def update_membership(%OrganizationMembership{} = membership, attrs) do
    membership
    |> OrganizationMembership.changeset(attrs)
    |> Repo.update()
  end

  def update_membership_role(%OrganizationMembership{} = membership, role) do
    update_membership(membership, %{role: role})
  end

  def remove_member(%OrganizationMembership{} = membership) do
    Repo.delete(membership)
  end

  def remove_member(%Organization{} = organization, %User{} = user) do
    with %OrganizationMembership{} = membership <- get_membership_for_org(organization, user) do
      remove_member(membership)
    else
      nil -> {:error, :not_found}
    end
  end

  def touch_membership_last_active(%OrganizationMembership{} = membership) do
    membership
    |> OrganizationMembership.changeset(%{last_active_at: DateTime.utc_now()})
    |> Repo.update()
    |> case do
      {:ok, updated_membership} ->
        {:ok, Repo.preload(updated_membership, [:organization, :user, :invited_by])}

      error ->
        error
    end
  end

  def membership_owner?(%OrganizationMembership{} = membership) do
    membership.role == "owner"
  end

  def membership_admin?(%OrganizationMembership{} = membership) do
    membership.role in ["owner", "admin"]
  end

  def can_manage_dashboard?(%Dashboard{} = dashboard, %OrganizationMembership{} = membership) do
    membership_owner?(membership) || membership_admin?(membership) ||
      dashboard.user_id == membership.user_id
  end

  def can_view_dashboard?(%Dashboard{} = dashboard, %OrganizationMembership{} = membership) do
    cond do
      membership_owner?(membership) -> true
      membership.role == "admin" -> true
      dashboard.user_id == membership.user_id -> true
      dashboard.visibility -> true
      true -> false
    end
  end

  def can_edit_dashboard?(%Dashboard{} = dashboard, %OrganizationMembership{} = membership) do
    cond do
      dashboard.organization_id != membership.organization_id -> false
      membership_owner?(membership) -> true
      membership_admin?(membership) -> true
      dashboard.user_id == membership.user_id -> true
      dashboard.locked -> false
      dashboard.visibility -> true
      true -> false
    end
  end

  def can_clone_dashboard?(%Dashboard{} = dashboard, %OrganizationMembership{} = membership) do
    can_view_dashboard?(dashboard, membership)
  end

  def transfer_dashboard_ownership(
        %Dashboard{} = dashboard,
        %OrganizationMembership{} = membership,
        target_membership_id
      )
      when is_binary(target_membership_id) do
    cond do
      dashboard.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      not can_manage_dashboard?(dashboard, membership) ->
        {:error, :forbidden}

      true ->
        case get_membership(target_membership_id) do
          nil ->
            {:error, :not_found}

          %OrganizationMembership{organization_id: org_id}
          when org_id != dashboard.organization_id ->
            {:error, :invalid_target}

          %OrganizationMembership{} = new_owner ->
            if new_owner.user_id == dashboard.user_id do
              {:error, :same_owner}
            else
              dashboard
              |> Dashboard.changeset(%{user_id: new_owner.user_id})
              |> Repo.update()
            end
        end
    end
  end

  ## Organization invitations

  def list_invitations(%Organization{} = organization) do
    now = DateTime.utc_now()

    from(i in OrganizationInvitation,
      where: i.organization_id == ^organization.id,
      left_join: inviter in assoc(i, :invited_by),
      left_join: accepted in assoc(i, :accepted_user),
      preload: [:organization, invited_by: inviter, accepted_user: accepted],
      order_by: [desc: i.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(&maybe_mark_invitation_expired(&1, now))
  end

  def get_invitation!(id) when is_binary(id) do
    OrganizationInvitation
    |> Repo.get!(id)
    |> Repo.preload([:organization, :invited_by, :accepted_user])
    |> maybe_mark_invitation_expired()
  end

  def get_invitation(id) when is_binary(id) do
    OrganizationInvitation
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      invitation ->
        invitation
        |> Repo.preload([:organization, :invited_by, :accepted_user])
        |> maybe_mark_invitation_expired()
    end
  end

  def get_invitation_by_token(token) when is_binary(token) do
    OrganizationInvitation
    |> Repo.get_by(token: token)
    |> case do
      nil ->
        nil

      invitation ->
        invitation
        |> Repo.preload([:organization, :invited_by, :accepted_user])
        |> maybe_mark_invitation_expired()
    end
  end

  def get_invitation_by_token!(token) when is_binary(token) do
    OrganizationInvitation
    |> Repo.get_by!(token: token)
    |> Repo.preload([:organization, :invited_by, :accepted_user])
    |> maybe_mark_invitation_expired()
  end

  @doc """
  Retrieves an active invitation by token.

  Returns `{:ok, invitation}` when the invitation exists, is pending, and
  has not expired. Otherwise returns `{:error, reason}` where reason is one of
  `:not_found`, `:expired`, `:already_accepted`, `:cancelled`, or `:invalid`.
  """
  def get_active_invitation_by_token(token) when is_binary(token) do
    case get_invitation_by_token(token) do
      %OrganizationInvitation{status: "pending"} = invitation ->
        if invitation_expired?(invitation) do
          {:error, :expired}
        else
          {:ok, invitation}
        end

      %OrganizationInvitation{status: "accepted"} ->
        {:error, :already_accepted}

      %OrganizationInvitation{status: "cancelled"} ->
        {:error, :cancelled}

      %OrganizationInvitation{status: "expired"} ->
        {:error, :expired}

      nil ->
        {:error, :not_found}

      _ ->
        {:error, :invalid}
    end
  end

  def create_invitation(%Organization{} = organization, attrs \\ %{}, invited_by \\ nil) do
    attrs =
      attrs
      |> Map.new(fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        other -> other
      end)
      |> Map.put("organization_id", organization.id)
      |> Map.put("invited_by_user_id", invited_by && invited_by.id)

    %OrganizationInvitation{}
    |> OrganizationInvitation.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, invitation} -> InvitationNotifier.deliver_invitation(invitation)
      _ -> :ok
    end)
  end

  def refresh_invitation(%OrganizationInvitation{status: status} = invitation)
      when status in ["pending", "expired"] do
    invitation
    |> OrganizationInvitation.changeset(%{token: nil, expires_at: nil, status: "pending"})
    |> Repo.update()
    |> tap(fn
      {:ok, updated_invitation} -> InvitationNotifier.deliver_invitation(updated_invitation)
      _ -> :ok
    end)
  end

  def refresh_invitation(%OrganizationInvitation{}), do: {:error, :invalid_status}

  def cancel_invitation(%OrganizationInvitation{} = invitation) do
    invitation
    |> OrganizationInvitation.changeset(%{status: "cancelled"})
    |> Repo.update()
  end

  def invitation_expired?(%OrganizationInvitation{expires_at: expires_at, status: "pending"}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end

  def invitation_expired?(%OrganizationInvitation{status: status})
      when status in ["expired", "accepted", "cancelled"],
      do: status == "expired"

  def invitation_expired?(_), do: false

  ## Organization SSO providers

  def list_sso_providers(%Organization{} = organization) do
    organization
    |> Repo.preload(sso_providers: [:domains])
    |> Map.get(:sso_providers, [])
  end

  def get_sso_provider_for_org(%Organization{} = organization, provider) do
    if provider in OrganizationSSOProvider.providers() do
      from(p in OrganizationSSOProvider,
        where: p.organization_id == ^organization.id and p.provider == ^provider,
        preload: [:domains]
      )
      |> Repo.one()
    else
      nil
    end
  end

  def google_sso_enabled?(%Organization{} = organization) do
    case get_sso_provider_for_org(organization, :google) do
      %OrganizationSSOProvider{enabled: true, domains: [_ | _]} -> true
      _ -> false
    end
  end

  def upsert_google_sso_provider(%Organization{} = organization, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        other -> other
      end)

    Repo.transaction(fn ->
      provider =
        organization
        |> get_sso_provider_for_org(:google)
        |> case do
          nil ->
            %OrganizationSSOProvider{}
            |> OrganizationSSOProvider.changeset(%{
              "organization_id" => organization.id,
              "provider" => :google,
              "enabled" => Map.get(attrs, "enabled", true),
              "auto_provision_members" => Map.get(attrs, "auto_provision_members", true)
            })
            |> Repo.insert()

          %OrganizationSSOProvider{} = provider ->
            provider
            |> OrganizationSSOProvider.changeset(%{
              "enabled" => Map.get(attrs, "enabled", provider.enabled),
              "auto_provision_members" =>
                Map.get(attrs, "auto_provision_members", provider.auto_provision_members)
            })
            |> Repo.update()
        end
        |> case do
          {:ok, provider} -> provider
          {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback({:changeset, changeset})
          {:error, reason} -> Repo.rollback(reason)
        end

      domains = normalize_domains(Map.get(attrs, "domains", []))

      with :ok <- replace_provider_domains(provider, domains) do
        Repo.preload(provider, :domains)
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback({:changeset, changeset})
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def find_google_sso_provider_for_domain(domain) when domain in [nil, ""] do
    nil
  end

  def find_google_sso_provider_for_domain(domain) when is_binary(domain) do
    normalized = normalize_domain(domain)

    from(p in OrganizationSSOProvider,
      join: d in OrganizationSSODomain,
      on: d.organization_sso_provider_id == p.id,
      where:
        p.provider == :google and p.enabled == true and
          fragment("lower(?) = ?", d.domain, ^normalized),
      preload: [:organization]
    )
    |> Repo.one()
  end

  def ensure_membership_for_sso(%User{} = user, :google, email) when is_binary(email) do
    case get_membership_for_user(user) do
      %OrganizationMembership{} = membership ->
        {:ok, membership}

      nil ->
        domain =
          email
          |> String.split("@")
          |> List.last()
          |> normalize_domain()

        with {:domain, domain} when is_binary(domain) <- {:domain, domain},
             %OrganizationSSOProvider{} = provider <- find_google_sso_provider_for_domain(domain),
             true <- provider.auto_provision_members do
          case create_membership(provider.organization, user) do
            {:ok, membership} -> {:ok, membership}
            {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
          end
        else
          {:domain, _} -> {:error, :invalid_email_domain}
          false -> {:error, :auto_provision_disabled}
          nil -> {:error, :domain_not_allowed}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def ensure_membership_for_sso(_, _, _), do: {:error, :unsupported_provider}

  defp replace_provider_domains(%OrganizationSSOProvider{} = provider, []) do
    Repo.delete_all(
      from d in OrganizationSSODomain,
        where: d.organization_sso_provider_id == ^provider.id
    )

    :ok
  end

  defp replace_provider_domains(%OrganizationSSOProvider{} = provider, domains) do
    Repo.delete_all(
      from d in OrganizationSSODomain,
        where: d.organization_sso_provider_id == ^provider.id
    )

    Enum.reduce_while(domains, :ok, fn domain, :ok ->
      %OrganizationSSODomain{}
      |> OrganizationSSODomain.changeset(%{
        organization_sso_provider_id: provider.id,
        domain: domain
      })
      |> Repo.insert()
      |> case do
        {:ok, _record} -> {:cont, :ok}
        {:error, %Ecto.Changeset{} = changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp normalize_domains(domains) when is_list(domains) do
    domains
    |> Enum.map(&normalize_domain/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp normalize_domains(value) when is_binary(value) do
    value
    |> String.split(~r/[,;\s]+/, trim: true)
    |> normalize_domains()
  end

  defp normalize_domains(_), do: []

  defp normalize_domain(nil), do: nil

  defp normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
  end

  def accept_invitation(%OrganizationInvitation{} = invitation, %User{} = user) do
    invitation = Repo.preload(invitation, [:organization, :invited_by])

    with {:ok, existing_membership} <- ensure_invitation_acceptance_allowed(invitation, user) do
      multi =
        Multi.new()
        |> Multi.run(:membership, fn _repo, _changes ->
          case existing_membership do
            nil ->
              create_membership(
                invitation.organization,
                user,
                invitation.role,
                invitation.invited_by
              )

            %OrganizationMembership{} = membership ->
              {:ok, membership}
          end
        end)
        |> Multi.update(
          :invitation,
          OrganizationInvitation.changeset(invitation, %{
            status: "accepted",
            accepted_user_id: user.id
          })
        )

      case Repo.transaction(multi) do
        {:ok, %{membership: membership}} -> {:ok, membership}
        {:error, :membership, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  defp ensure_invitation_acceptance_allowed(
         %OrganizationInvitation{} = invitation,
         %User{} = user
       ) do
    cond do
      invitation.status != "pending" ->
        {:error, :invalid_status}

      invitation_expired?(invitation) ->
        {:error, :expired}

      true ->
        case get_membership_for_user(user) do
          nil ->
            {:ok, nil}

          %OrganizationMembership{organization_id: org_id} = membership
          when org_id == invitation.organization_id ->
            {:ok, membership}

          _ ->
            {:error, :belongs_to_another_organization}
        end
    end
  end

  defp maybe_mark_invitation_expired(
         %OrganizationInvitation{} = invitation,
         now \\ DateTime.utc_now()
       ) do
    if invitation.status == "pending" and DateTime.compare(invitation.expires_at, now) == :lt do
      {:ok, updated} =
        invitation
        |> OrganizationInvitation.changeset(%{status: "expired"})
        |> Repo.update()

      updated
    else
      invitation
    end
  end

  defp assign_org_id(attrs, %Organization{} = organization) do
    assign_org_id(attrs, organization.id)
  end

  defp assign_org_id(attrs, organization_id) when is_binary(organization_id) do
    attrs
    |> Map.put("organization_id", organization_id)
    |> Map.delete(:organization_id)
  end

  defp ensure_transponder_org(attrs) do
    case Map.get(attrs, :organization_id) || Map.get(attrs, "organization_id") do
      nil ->
        case Map.get(attrs, :database_id) || Map.get(attrs, "database_id") do
          nil ->
            attrs

          database_id ->
            case Repo.get(Database, database_id) do
              nil -> attrs
              %Database{} = database -> assign_org_id(attrs, database.organization_id)
            end
        end

      _ ->
        attrs
    end
  end

  defp ensure_dashboard_source(attrs, %OrganizationMembership{} = membership, default \\ nil) do
    with {:ok, {type, id}} <- resolve_dashboard_source(attrs, default),
         {:ok, updated_attrs} <- coerce_dashboard_source(attrs, membership, type, id) do
      {:ok, updated_attrs}
    end
  end

  defp resolve_dashboard_source(attrs, default) do
    case fetch_attr(attrs, "source") do
      %{} = source_map ->
        type = fetch_attr(source_map, "type")
        id = fetch_attr(source_map, "id")
        normalize_source_tuple(type, id)

      _ ->
        cond do
          type = fetch_attr(attrs, "source_type") ->
            id = fetch_attr(attrs, "source_id")
            normalize_source_tuple(type, id)

          id = fetch_attr(attrs, "database_id") ->
            normalize_source_tuple("database", id)

          valid_source_tuple?(default) ->
            {:ok, default}

          true ->
            {:error, "Source selection is required"}
        end
    end
  end

  defp normalize_source_tuple(type, id) do
    type = type && type |> to_string() |> String.trim() |> String.downcase()
    id = id && to_string(id) |> String.trim()

    cond do
      type in ["database", "project"] and id not in [nil, ""] ->
        {:ok, {type, id}}

      true ->
        {:error, "Invalid source selection"}
    end
  end

  defp valid_source_tuple?({type, id})
       when type in ["database", "project"] and id not in [nil, ""] do
    true
  end

  defp valid_source_tuple?(_), do: false

  defp coerce_dashboard_source(attrs, membership, "database", id) do
    try do
      _ = get_database_for_org!(membership.organization_id, id)

      {:ok,
       attrs
       |> drop_source_param()
       |> put_attr("database_id", id)
       |> put_attr("source_type", "database")
       |> put_attr("source_id", id)}
    rescue
      Ecto.NoResultsError ->
        {:error, "Database is not part of this organization"}
    end
  end

  defp coerce_dashboard_source(attrs, membership, "project", id) do
    try do
      project = get_project!(id)

      if project.user_id == membership.user_id do
        {:ok,
         attrs
         |> drop_source_param()
         |> put_attr("database_id", nil)
         |> put_attr("source_type", "project")
         |> put_attr("source_id", project.id)}
      else
        {:error, "Project is not available to this user"}
      end
    rescue
      Ecto.NoResultsError ->
        {:error, "Project not found"}
    end
  end

  defp coerce_dashboard_source(_attrs, _membership, _type, _id) do
    {:error, "Invalid source selection"}
  end

  defp drop_source_param(attrs) do
    attrs
    |> Map.delete("source")
    |> Map.delete(:source)
  end

  defp fetch_attr(attrs, key) when is_binary(key) do
    Map.get(attrs, key) || Map.get(attrs, String.to_atom(key))
  end

  defp put_attr(attrs, key, value) when is_binary(key) do
    attrs
    |> Map.put(key, value)
    |> Map.delete(String.to_atom(key))
  end

  defp ensure_dashboard_source_defaults(attrs) do
    cond do
      fetch_attr(attrs, "source_type") && fetch_attr(attrs, "source_id") ->
        attrs

      source = fetch_attr(attrs, "source") ->
        type = fetch_attr(source, "type")
        id = fetch_attr(source, "id")

        attrs
        |> drop_source_param()
        |> put_attr("source_type", type)
        |> put_attr("source_id", id)

      database_id = fetch_attr(attrs, "database_id") ->
        attrs
        |> put_attr("source_type", "database")
        |> put_attr("source_id", database_id)

      true ->
        attrs
    end
  end

  defp ensure_dashboard_lock_default(attrs) when is_map(attrs) do
    if Map.has_key?(attrs, :locked) || Map.has_key?(attrs, "locked") do
      attrs
    else
      Map.put(attrs, "locked", false)
    end
  end

  defp ensure_dashboard_lock_default(attrs), do: attrs

  defp sanitize_dashboard_update_attrs(attrs, allow_protected?) when is_map(attrs) do
    sanitized =
      attrs
      |> Map.delete(:user_id)
      |> Map.delete("user_id")

    cond do
      allow_protected? ->
        {:ok, sanitized}

      Enum.any?([:locked, "locked", :visibility, "visibility"], &Map.has_key?(attrs, &1)) ->
        {:error, :forbidden}

      true ->
        {:ok, sanitized}
    end
  end

  defp sanitize_dashboard_update_attrs(attrs, _allow_protected?), do: {:ok, attrs}

  defp ensure_parent_group_within_org(attrs, %OrganizationMembership{} = membership) do
    value = Map.get(attrs, "parent_group_id") || Map.get(attrs, :parent_group_id)

    cond do
      value in [nil, ""] ->
        attrs
        |> Map.delete(:parent_group_id)
        |> Map.delete("parent_group_id")

      match?(%DashboardGroup{}, value) ->
        id = value.id
        ensure_parent_group_exists(id, membership)

        attrs
        |> Map.put("parent_group_id", id)
        |> Map.delete(:parent_group_id)

      is_binary(value) ->
        ensure_parent_group_exists(value, membership)

        attrs
        |> Map.put("parent_group_id", value)
        |> Map.delete(:parent_group_id)

      true ->
        parent_id = to_string(value)
        ensure_parent_group_exists(parent_id, membership)

        attrs
        |> Map.put("parent_group_id", parent_id)
        |> Map.delete(:parent_group_id)
    end
  end

  defp ensure_parent_group_exists(parent_id, %OrganizationMembership{} = membership) do
    case Repo.get_by(DashboardGroup, id: parent_id, organization_id: membership.organization_id) do
      nil ->
        raise Ecto.NoResultsError, queryable: DashboardGroup, message: "Dashboard group not found"

      _group ->
        :ok
    end
  end

  defp ensure_dashboard_group_within_org(attrs, %OrganizationMembership{} = membership) do
    value = Map.get(attrs, "group_id") || Map.get(attrs, :group_id)

    cond do
      value in [nil, ""] ->
        attrs
        |> Map.delete(:group_id)
        |> Map.delete("group_id")

      match?(%DashboardGroup{}, value) ->
        id = value.id
        _ = get_dashboard_group_for_membership!(membership, id)

        attrs
        |> Map.put("group_id", id)
        |> Map.delete(:group_id)

      is_binary(value) ->
        _ = get_dashboard_group_for_membership!(membership, value)

        attrs
        |> Map.put("group_id", value)
        |> Map.delete(:group_id)

      true ->
        group_id = to_string(value)
        _ = get_dashboard_group_for_membership!(membership, group_id)

        attrs
        |> Map.put("group_id", group_id)
        |> Map.delete(:group_id)
    end
  end

  defp atomize_keys(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      cond do
        is_atom(key) ->
          Map.put(acc, key, value)

        is_binary(key) ->
          atom_key =
            try do
              String.to_existing_atom(key)
            rescue
              ArgumentError -> nil
            end

          if atom_key do
            Map.put(acc, atom_key, value)
          else
            Map.put(acc, key, value)
          end

        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  @doc """
  Returns the list of projects.

  ## Examples

      iex> list_projects()
      [%Project{}, ...]

  """
  def list_projects do
    Repo.all(Project)
  end

  def list_projects_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    case ids do
      [] ->
        []

      _ ->
        from(p in Project,
          where: p.id in ^ids,
          select: struct(p, [:id, :name])
        )
        |> Repo.all()
    end
  end

  def count_projects do
    Repo.aggregate(Project, :count, :id)
  end

  def list_users_projects(%Trifle.Accounts.User{} = user) do
    query =
      from(
        p in Project,
        where: p.user_id == ^user.id
      )

    Repo.all(query)
  end

  @doc """
  Gets a single project.

  Raises `Ecto.NoResultsError` if the Project does not exist.

  ## Examples

      iex> get_project!(123)
      %Project{}

      iex> get_project!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Creates a project.

  ## Examples

      iex> create_project(%{field: value})
      {:ok, %Project{}}

      iex> create_project(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def create_users_project(attrs \\ %{}, %Trifle.Accounts.User{} = user) do
    attrs = Map.put(attrs, "user", user)

    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.

  ## Examples

      iex> update_project(project, %{field: new_value})
      {:ok, %Project{}}

      iex> update_project(project, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.

  ## Examples

      iex> delete_project(project)
      {:ok, %Project{}}

      iex> delete_project(project)
      {:error, %Ecto.Changeset{}}

  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.

  ## Examples

      iex> change_project(project)
      %Ecto.Changeset{data: %Project{}}

  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  @doc """
  Returns the list of project_tokens.

  ## Examples

      iex> list_project_tokens()
      [%ProjectToken{}, ...]

  """
  def list_project_tokens do
    Repo.all(ProjectToken)
  end

  def list_projects_project_tokens(%Project{} = project) do
    query =
      from(
        pt in ProjectToken,
        where: pt.project_id == ^project.id
      )

    Repo.all(query)
  end

  @doc """
  Gets a single project_token.

  Raises `Ecto.NoResultsError` if the Project token does not exist.

  ## Examples

      iex> get_project_token!(123)
      %ProjectToken{}

      iex> get_project_token!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project_token!(id), do: Repo.get!(ProjectToken, id)

  def get_project_by_token(token) when is_binary(token) do
    with %ProjectToken{} = record <- Repo.get_by(ProjectToken, token: token),
         record <- Repo.preload(record, :project),
         {:ok, _id} <-
           Phoenix.Token.verify(TrifleWeb.Endpoint, "project auth", record.token,
             max_age: 86400 * 365
           ),
         %Project{} = project <- record.project do
      {:ok, project, record}
    else
      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Creates a project_token.

  ## Examples

      iex> create_project_token(%{field: value})
      {:ok, %ProjectToken{}}

      iex> create_project_token(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_project_token(attrs \\ %{}) do
    %ProjectToken{}
    |> ProjectToken.changeset(attrs)
    |> Repo.insert()
  end

  def create_projects_project_token(attrs \\ %{}, %Project{} = project) do
    attrs = Map.put(attrs, "project", project)

    %ProjectToken{}
    |> ProjectToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project_token.

  ## Examples

      iex> update_project_token(project_token, %{field: new_value})
      {:ok, %ProjectToken{}}

      iex> update_project_token(project_token, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_project_token(%ProjectToken{} = project_token, attrs) do
    project_token
    |> ProjectToken.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project_token.

  ## Examples

      iex> delete_project_token(project_token)
      {:ok, %ProjectToken{}}

      iex> delete_project_token(project_token)
      {:error, %Ecto.Changeset{}}

  """
  def delete_project_token(%ProjectToken{} = project_token) do
    Repo.delete(project_token)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project_token changes.

  ## Examples

      iex> change_project_token(project_token)
      %Ecto.Changeset{data: %ProjectToken{}}

  """
  def change_project_token(%ProjectToken{} = project_token, attrs \\ %{}) do
    ProjectToken.changeset(project_token, attrs)
  end

  ## Database tokens

  @doc """
  Returns the list of database_tokens.

  ## Examples

      iex> list_database_tokens()
      [%DatabaseToken{}, ...]

  """
  def list_database_tokens do
    Repo.all(DatabaseToken)
  end

  def list_databases_database_tokens(%Database{} = database) do
    query =
      from(
        dt in DatabaseToken,
        where: dt.database_id == ^database.id
      )

    Repo.all(query)
  end

  @doc """
  Gets a single database_token.

  Raises `Ecto.NoResultsError` if the Database token does not exist.

  ## Examples

      iex> get_database_token!(123)
      %DatabaseToken{}

      iex> get_database_token!(456)
      ** (Ecto.NoResultsError)

  """
  def get_database_token!(id), do: Repo.get!(DatabaseToken, id)

  def get_database_by_token(token) when is_binary(token) do
    with %DatabaseToken{} = record <- Repo.get_by(DatabaseToken, token: token),
         record <- Repo.preload(record, :database),
         {:ok, _id} <-
           Phoenix.Token.verify(TrifleWeb.Endpoint, "database auth", record.token,
             max_age: 86400 * 365
           ),
         %Database{} = database <- record.database do
      {:ok, database, record}
    else
      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Creates a database_token.

  ## Examples

      iex> create_database_token(%{field: value})
      {:ok, %DatabaseToken{}}

      iex> create_database_token(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_database_token(attrs \\ %{}) do
    %DatabaseToken{}
    |> DatabaseToken.changeset(attrs)
    |> Repo.insert()
  end

  def create_databases_database_token(attrs \\ %{}, %Database{} = database) do
    attrs = Map.put(attrs, "database", database)

    %DatabaseToken{}
    |> DatabaseToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a database_token.

  ## Examples

      iex> update_database_token(database_token, %{field: new_value})
      {:ok, %DatabaseToken{}}

      iex> update_database_token(database_token, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_database_token(%DatabaseToken{} = database_token, attrs) do
    database_token
    |> DatabaseToken.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a database_token.

  ## Examples

      iex> delete_database_token(database_token)
      {:ok, %DatabaseToken{}}

      iex> delete_database_token(database_token)
      {:error, %Ecto.Changeset{}}

  """
  def delete_database_token(%DatabaseToken{} = database_token) do
    Repo.delete(database_token)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking database_token changes.

  ## Examples

      iex> change_database_token(database_token)
      %Ecto.Changeset{data: %DatabaseToken{}}

  """
  def change_database_token(%DatabaseToken{} = database_token, attrs \\ %{}) do
    DatabaseToken.changeset(database_token, attrs)
  end

  ## Database functions

  @doc """
  Returns the list of databases for an organization.
  """
  def list_databases_for_org(%Organization{} = organization) do
    list_databases_for_org(organization.id)
  end

  def list_databases_for_org(organization_id) when is_binary(organization_id) do
    from(d in Database,
      where: d.organization_id == ^organization_id,
      order_by: [asc: d.inserted_at, asc: d.id]
    )
    |> Repo.all()
  end

  def list_databases_for_user(%User{} = user) do
    case get_membership_for_user(user) do
      nil -> []
      %OrganizationMembership{} = membership -> list_databases_for_org(membership.organization_id)
    end
  end

  def list_all_databases do
    from(d in Database, order_by: [asc: d.inserted_at, asc: d.id], preload: [:organization])
    |> Repo.all()
  end

  def list_databases_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.uniq() |> Enum.reject(&is_nil/1)

    case ids do
      [] ->
        []

      _ ->
        from(d in Database,
          where: d.id in ^ids,
          select: struct(d, [:id, :display_name])
        )
        |> Repo.all()
    end
  end

  def count_databases do
    Repo.aggregate(Database, :count, :id)
  end

  @deprecated "Use list_databases_for_org/1 or list_databases_for_user/1"
  def list_databases do
    list_all_databases()
  end

  @doc """
  Gets a single database for an organization.

  Raises `Ecto.NoResultsError` if the Database does not exist.
  """
  def get_database_for_org!(%Organization{} = organization, id) when is_binary(id) do
    Repo.get_by!(Database, id: id, organization_id: organization.id)
  end

  def get_database_for_org!(organization_id, id)
      when is_binary(organization_id) and is_binary(id) do
    Repo.get_by!(Database, id: id, organization_id: organization_id)
  end

  def get_database_for_user!(%User{} = user, id) when is_binary(id) do
    membership = fetch_active_membership!(user)
    get_database_for_org!(membership.organization_id, id)
  end

  def get_database!(id) do
    Repo.get!(Database, id)
  end

  @doc """
  Creates a database within an organization.
  """
  def create_database_for_org(%Organization{} = organization, attrs \\ %{}) do
    attrs =
      attrs
      |> assign_org_id(organization)
      |> atomize_keys()

    %Database{}
    |> Database.changeset(attrs)
    |> Repo.insert()
  end

  def create_database(attrs \\ %{}) do
    %Database{}
    |> Database.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a database.
  """
  def update_database(%Database{} = database, attrs) do
    database
    |> Database.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a database.
  """
  def delete_database(%Database{} = database) do
    Repo.delete(database)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking database changes.
  """
  def change_database(%Database{} = database, attrs \\ %{}) do
    Database.changeset(database, attrs)
  end

  @doc """
  Checks if the database is already set up.
  """
  def database_setup?(%Database{} = database) do
    Database.is_setup?(database)
  end

  @doc """
  Checks the database status and updates the tracking fields.
  """
  def check_database_status(%Database{} = database) do
    Database.check_status(database)
  end

  @doc """
  Sets up the database for Trifle::Stats.
  """
  def setup_database(%Database{} = database) do
    Database.setup(database)
  end

  @doc """
  Nukes all data from the database.
  """
  def nuke_database(%Database{} = database) do
    Database.nuke(database)
  end

  ## Transponder functions

  alias Trifle.Organizations.Transponder

  @doc """
  Returns the list of transponders for a database.
  """
  def list_transponders_for_database(%Database{} = database) do
    list_transponders_for_source(:database, database.id, database.organization_id)
  end

  @doc """
  Returns the list of transponders for a project.
  """
  def list_transponders_for_project(%Project{} = project) do
    list_transponders_for_source(:project, project.id, nil)
  end

  @doc """
  Gets a single transponder.
  """
  def get_transponder_for_org!(%Organization{} = organization, id) when is_binary(id) do
    Repo.get_by!(Transponder, id: id, organization_id: organization.id)
  end

  def get_transponder_for_org!(organization_id, id)
      when is_binary(organization_id) and is_binary(id) do
    Repo.get_by!(Transponder, id: id, organization_id: organization_id)
  end

  def get_transponder!(id), do: Repo.get!(Transponder, id)

  def get_transponder_for_source!(%Database{} = database, id) when is_binary(id) do
    Repo.get_by!(Transponder,
      id: id,
      source_type: source_type_string(:database),
      source_id: database.id,
      organization_id: database.organization_id
    )
  end

  def get_transponder_for_source!(%Project{} = project, id) when is_binary(id) do
    Repo.get_by!(Transponder,
      id: id,
      source_type: source_type_string(:project),
      source_id: project.id
    )
  end

  @doc """
  Creates a transponder bound to a database.
  """
  def create_transponder_for_database(%Database{} = database, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put("database_id", database.id)
      |> Map.delete(:database_id)
      |> assign_org_id(database.organization_id)
      |> assign_source(:database, database.id)
      |> atomize_keys()

    create_transponder(attrs)
  end

  @doc """
  Creates a transponder bound to a project.
  """
  def create_transponder_for_project(%Project{} = project, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.delete(:database_id)
      |> Map.delete("database_id")
      |> assign_source(:project, project.id)
      |> atomize_keys()

    create_transponder(attrs)
  end

  @doc """
  Creates a transponder.
  """
  def create_transponder(attrs \\ %{}) do
    attrs =
      attrs
      |> ensure_transponder_org()
      |> ensure_transponder_source()
      |> atomize_keys()

    %Transponder{}
    |> Transponder.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a transponder.
  """
  def update_transponder(%Transponder{} = transponder, attrs) do
    attrs = ensure_transponder_source(attrs)

    transponder
    |> Transponder.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a transponder.
  """
  def delete_transponder(%Transponder{} = transponder) do
    Repo.delete(transponder)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking transponder changes.
  """
  def change_transponder(%Transponder{} = transponder, attrs \\ %{}) do
    attrs = ensure_transponder_source(attrs)

    Transponder.changeset(transponder, attrs)
  end

  @doc """
  Updates the order of transponders for a database.
  """
  def update_transponder_order(%Database{} = database, transponder_ids) do
    update_transponder_order_for_source(:database, database.id, transponder_ids)
  end

  def update_transponder_order(%Project{} = project, transponder_ids) do
    update_transponder_order_for_source(:project, project.id, transponder_ids)
  end

  @doc """
  Sets the next available order for a new transponder.
  """
  def get_next_transponder_order(%Database{} = database) do
    get_next_transponder_order_for_source(:database, database.id)
  end

  def get_next_transponder_order(%Project{} = project) do
    get_next_transponder_order_for_source(:project, project.id)
  end

  @doc """
  Returns the next position index for dashboards within a group (global).
  Pass nil for top-level (ungrouped).
  """
  def get_next_dashboard_position_for_group(group_id) do
    base = from(d in Dashboard, select: max(d.position))

    query =
      case group_id do
        nil -> from(d in base, where: is_nil(d.group_id))
        id when is_binary(id) -> from(d in base, where: d.group_id == ^id)
      end

    case Repo.one(query) do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  def get_next_dashboard_position_for_membership(%OrganizationMembership{} = membership, group_id) do
    base =
      from(d in Dashboard,
        where: d.organization_id == ^membership.organization_id,
        select: max(d.position)
      )

    query =
      case group_id do
        nil -> from(d in base, where: is_nil(d.group_id))
        id when is_binary(id) -> from(d in base, where: d.group_id == ^id)
      end

    case Repo.one(query) do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  defp list_transponders_for_source(type, source_id, organization_id) do
    type_string = source_type_string(type)

    base_query =
      from t in Transponder,
        where:
          t.source_type == ^type_string and t.source_id == ^source_id and
            t.type == ^Transponder.expression_type(),
        order_by: [asc: t.order, asc: t.key]

    query =
      case organization_id do
        nil -> base_query
        org_id -> from t in base_query, where: t.organization_id == ^org_id
      end

    Repo.all(query)
  end

  defp update_transponder_order_for_source(type, source_id, transponder_ids) do
    type_string = source_type_string(type)

    Repo.transaction(fn ->
      transponder_ids
      |> Enum.with_index()
      |> Enum.each(fn {transponder_id, index} ->
        from(t in Transponder,
          where:
            t.id == ^transponder_id and t.source_type == ^type_string and
              t.source_id == ^source_id
        )
        |> Repo.update_all(set: [order: index])
      end)
    end)
  end

  defp get_next_transponder_order_for_source(type, source_id) do
    type_string = source_type_string(type)

    query =
      from(t in Transponder,
        where:
          t.source_type == ^type_string and t.source_id == ^source_id and
            t.type == ^Transponder.expression_type(),
        select: max(t.order)
      )

    case Repo.one(query) do
      nil -> 0
      max_order -> max_order + 1
    end
  end

  defp assign_source(attrs, type, source_id) do
    attrs
    |> Map.put("source_type", source_type_string(type))
    |> Map.put("source_id", source_id)
    |> Map.delete(:source_type)
    |> Map.delete(:source_id)
  end

  defp ensure_transponder_source(nil), do: %{}

  defp ensure_transponder_source(attrs) when is_map(attrs) do
    source_type = Map.get(attrs, :source_type) || Map.get(attrs, "source_type")
    source_id = Map.get(attrs, :source_id) || Map.get(attrs, "source_id")
    database_id = Map.get(attrs, :database_id) || Map.get(attrs, "database_id")

    cond do
      source_type && source_id ->
        attrs
        |> Map.put("source_type", normalize_source_type(source_type))
        |> Map.delete(:source_type)
        |> Map.put("source_id", source_id)
        |> Map.delete(:source_id)

      database_id ->
        attrs
        |> Map.put("source_type", source_type_string(:database))
        |> Map.put("source_id", database_id)

      true ->
        attrs
    end
  end

  defp ensure_transponder_source(attrs), do: attrs

  defp normalize_source_type(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_source_type()
  end

  defp normalize_source_type(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_source_type(_), do: nil

  defp source_type_string(type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> String.downcase()
  end

  defp source_type_string(type) when is_binary(type) do
    type
    |> String.trim()
    |> String.downcase()
  end

  defp dashboards_base_query(
         %User{} = user,
         %OrganizationMembership{} = membership
       ) do
    base =
      from(d in Dashboard,
        where: d.organization_id == ^membership.organization_id,
        order_by: [asc: d.position, asc: d.inserted_at],
        preload: [:user, :database]
      )

    case membership.role do
      "owner" -> base
      "admin" -> base
      _ -> from(d in base, where: d.user_id == ^user.id or d.visibility == true)
    end
  end

  def list_dashboards_for_membership(
        %User{} = user,
        %OrganizationMembership{} = membership,
        group_id \\ nil
      ) do
    base = dashboards_base_query(user, membership)

    query =
      case group_id do
        nil -> from(d in base, where: is_nil(d.group_id))
        id when is_binary(id) -> from(d in base, where: d.group_id == ^id)
      end

    Repo.all(query)
  end

  def list_all_dashboards_for_membership(
        %User{} = user,
        %OrganizationMembership{} = membership
      ) do
    dashboards_base_query(user, membership)
    |> Repo.all()
  end

  def list_recent_dashboard_visits_for_membership(user, membership, limit \\ 5)
  def list_recent_dashboard_visits_for_membership(_, nil, _limit), do: []
  def list_recent_dashboard_visits_for_membership(nil, _membership, _limit), do: []

  def list_recent_dashboard_visits_for_membership(
        %User{} = user,
        %OrganizationMembership{} = membership,
        limit
      ) do
    limit = max(limit || 0, 0)

    dashboard_scope =
      dashboards_base_query(user, membership)
      |> Ecto.Query.exclude(:preload)

    from(v in DashboardVisit,
      join: d in subquery(dashboard_scope),
      on: d.id == v.dashboard_id,
      where:
        v.user_id == ^user.id and
          v.organization_id == ^membership.organization_id,
      order_by: [desc: v.last_viewed_at, desc: v.updated_at, desc: v.inserted_at],
      limit: ^limit,
      preload: [dashboard: d]
    )
    |> Repo.all()
  end

  def record_dashboard_visit(_, nil, _), do: {:error, :unauthorized}
  def record_dashboard_visit(nil, _membership, _), do: {:error, :unauthorized}

  def record_dashboard_visit(
        %User{} = user,
        %OrganizationMembership{} = membership,
        %Dashboard{} = dashboard
      ) do
    cond do
      membership.user_id != user.id ->
        {:error, :unauthorized}

      dashboard.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      true ->
        now = DateTime.utc_now()

        attrs = %{
          user_id: user.id,
          organization_id: membership.organization_id,
          dashboard_id: dashboard.id,
          last_viewed_at: now,
          view_count: 1
        }

        case Repo.insert(
               DashboardVisit.changeset(%DashboardVisit{}, attrs),
               conflict_target: [:user_id, :dashboard_id],
               on_conflict: [
                 inc: [view_count: 1],
                 set: [
                   last_viewed_at: now,
                   organization_id: membership.organization_id,
                   updated_at: now
                 ]
               ]
             ) do
          {:ok, _visit} -> :ok
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  def count_dashboards_for_membership(%User{} = user, %OrganizationMembership{} = membership) do
    base =
      from(d in Dashboard,
        where: d.organization_id == ^membership.organization_id
      )

    base =
      case membership.role do
        "owner" -> base
        "admin" -> base
        _ -> from(d in base, where: d.user_id == ^user.id or d.visibility == true)
      end

    Repo.one(from(d in base, select: count(d.id)))
  end

  def count_dashboard_groups_for_membership(%OrganizationMembership{} = membership) do
    Repo.one(
      from(g in DashboardGroup,
        where: g.organization_id == ^membership.organization_id,
        select: count(g.id)
      )
    )
  end

  def list_dashboard_groups_for_membership(
        %OrganizationMembership{} = membership,
        parent_group_id \\ nil
      ) do
    base =
      from(g in DashboardGroup,
        where: g.organization_id == ^membership.organization_id,
        order_by: [asc: g.position]
      )

    query =
      case parent_group_id do
        nil -> from(g in base, where: is_nil(g.parent_group_id))
        id when is_binary(id) -> from(g in base, where: g.parent_group_id == ^id)
      end

    Repo.all(query)
  end

  def list_dashboard_tree_for_membership(%User{} = user, %OrganizationMembership{} = membership) do
    top_groups = list_dashboard_groups_for_membership(membership, nil)

    Enum.map(top_groups, fn group ->
      build_group_tree_for_membership(user, membership, group)
    end)
  end

  defp build_group_tree_for_membership(
         %User{} = user,
         %OrganizationMembership{} = membership,
         %DashboardGroup{} = group
       ) do
    children = list_dashboard_groups_for_membership(membership, group.id)

    %{
      group: group,
      children: Enum.map(children, &build_group_tree_for_membership(user, membership, &1)),
      dashboards: list_dashboards_for_membership(user, membership, group.id)
    }
  end

  def get_dashboard_for_membership!(%OrganizationMembership{} = membership, id)
      when is_binary(id) do
    dashboard =
      Dashboard
      |> Repo.get_by!(id: id, organization_id: membership.organization_id)
      |> Repo.preload([:user, :database, :group])

    if can_view_dashboard?(dashboard, membership) do
      dashboard
    else
      raise Ecto.NoResultsError, queryable: Dashboard
    end
  end

  def create_dashboard_for_membership(
        %User{} = user,
        %OrganizationMembership{} = membership,
        attrs \\ %{}
      ) do
    attrs =
      attrs
      |> Map.put("user_id", user.id)
      |> Map.delete(:user_id)
      |> ensure_dashboard_group_within_org(membership)

    with {:ok, attrs} <- ensure_dashboard_source(attrs, membership) do
      attrs =
        attrs
        |> assign_org_id(membership.organization_id)
        |> ensure_dashboard_lock_default()
        |> atomize_keys()

      %Dashboard{}
      |> Dashboard.changeset(attrs)
      |> Repo.insert()
    else
      {:error, message} ->
        changeset =
          %Dashboard{}
          |> Dashboard.changeset(%{})
          |> Ecto.Changeset.add_error(:source_id, message)

        {:error, changeset}
    end
  end

  def create_dashboard_group_for_membership(%OrganizationMembership{} = membership, attrs \\ %{}) do
    attrs =
      attrs
      |> ensure_parent_group_within_org(membership)
      |> assign_org_id(membership.organization_id)
      |> atomize_keys()

    %DashboardGroup{}
    |> DashboardGroup.changeset(attrs)
    |> Repo.insert()
  end

  def get_dashboard_group_for_membership!(%OrganizationMembership{} = membership, id)
      when is_binary(id) do
    Repo.get_by!(DashboardGroup, id: id, organization_id: membership.organization_id)
  end

  def update_dashboard_for_membership(
        %Dashboard{} = dashboard,
        %OrganizationMembership{} = membership,
        attrs
      ) do
    cond do
      dashboard.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      not can_edit_dashboard?(dashboard, membership) ->
        {:error, :forbidden}

      true ->
        can_manage? = can_manage_dashboard?(dashboard, membership)

        attrs =
          attrs
          |> ensure_dashboard_group_within_org(membership)

        default_source = {dashboard.source_type, dashboard.source_id}

        with {:ok, attrs} <- ensure_dashboard_source(attrs, membership, default_source),
             {:ok, sanitized_attrs} <- sanitize_dashboard_update_attrs(attrs, can_manage?) do
          dashboard
          |> Dashboard.changeset(
            assign_org_id(sanitized_attrs, membership.organization_id)
            |> atomize_keys()
          )
          |> Repo.update()
        else
          {:error, :forbidden} ->
            {:error, :forbidden}

          {:error, message} ->
            changeset =
              dashboard
              |> Dashboard.changeset(%{})
              |> Ecto.Changeset.add_error(:source_id, message)

            {:error, changeset}
        end
    end
  end

  def delete_dashboard_for_membership(
        %Dashboard{} = dashboard,
        %OrganizationMembership{} = membership
      ) do
    cond do
      dashboard.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      not can_edit_dashboard?(dashboard, membership) ->
        {:error, :forbidden}

      true ->
        delete_dashboard(dashboard)
    end
  end

  def reorder_nodes_for_membership(
        %OrganizationMembership{} = membership,
        parent_group_id,
        items,
        from_parent_id,
        from_items,
        moved_id,
        moved_type
      )
      when is_list(items) do
    if (moved_type == "group" and parent_group_id) &&
         group_descendant_for_membership?(membership, moved_id, parent_group_id) do
      {:error, :invalid_parent}
    else
      Repo.transaction(fn ->
        Enum.with_index(items)
        |> Enum.each(fn {%{"id" => id, "type" => type}, idx} ->
          case type do
            "dashboard" ->
              dashboard =
                Repo.get_by!(Dashboard, id: id, organization_id: membership.organization_id)

              unless can_edit_dashboard?(dashboard, membership) do
                Repo.rollback({:error, :forbidden})
              end

              from(d in Dashboard, where: d.id == ^id)
              |> Repo.update_all(set: [group_id: parent_group_id, position: idx])

            "group" ->
              from(g in DashboardGroup,
                where: g.id == ^id and g.organization_id == ^membership.organization_id
              )
              |> Repo.update_all(set: [parent_group_id: parent_group_id, position: idx])

            _ ->
              :ok
          end
        end)

        if is_list(from_items) and from_parent_id != parent_group_id do
          Enum.with_index(from_items)
          |> Enum.each(fn {%{"id" => id, "type" => type}, idx} ->
            case type do
              "dashboard" ->
                dashboard =
                  Repo.get_by!(Dashboard, id: id, organization_id: membership.organization_id)

                unless can_edit_dashboard?(dashboard, membership) do
                  Repo.rollback({:error, :forbidden})
                end

                from(d in Dashboard, where: d.id == ^id)
                |> Repo.update_all(set: [position: idx])

              "group" ->
                from(g in DashboardGroup,
                  where: g.id == ^id and g.organization_id == ^membership.organization_id
                )
                |> Repo.update_all(set: [position: idx])

              _ ->
                :ok
            end
          end)
        end
      end)
    end
  end

  @doc """
  Returns the list of dashboards for a database.
  """
  def list_dashboards_for_database(%Database{} = database) do
    from(d in Dashboard,
      where: d.database_id == ^database.id,
      order_by: [asc: d.position, asc: d.inserted_at],
      preload: :user
    )
    |> Repo.all()
  end

  @doc """
  Returns all dashboards across the organization (all databases).
  """
  def list_all_dashboards do
    from(d in Dashboard,
      order_by: [asc: d.inserted_at, asc: d.id],
      preload: [:user, :database, :organization]
    )
    |> Repo.all()
  end

  def count_dashboards do
    Repo.aggregate(Dashboard, :count, :id)
  end

  # Removed database-scoped dashboard group listing in favor of global groups

  @doc """
  Returns dashboard groups at the organization level, optionally under a parent group.
  """
  def list_dashboard_groups_global(nil) do
    from(g in DashboardGroup,
      where: is_nil(g.parent_group_id),
      order_by: [asc: g.position]
    )
    |> Repo.all()
  end

  def list_dashboard_groups_global(parent_group_id) when is_binary(parent_group_id) do
    from(g in DashboardGroup,
      where: g.parent_group_id == ^parent_group_id,
      order_by: [asc: g.position]
    )
    |> Repo.all()
  end

  # Removed database-scoped dashboard listing in favor of user-or-visible global queries

  @doc """
  Returns dashboards either created by the given user or visible to everyone, filtered by group.
  """
  def list_dashboards_for_user_or_visible(%Trifle.Accounts.User{} = user, group_id \\ nil) do
    base =
      from(d in Dashboard,
        where: d.user_id == ^user.id or d.visibility == true,
        order_by: [asc: d.position, asc: d.inserted_at],
        preload: [:user, :database]
      )

    query =
      case group_id do
        nil -> from(d in base, where: is_nil(d.group_id))
        id when is_binary(id) -> from(d in base, where: d.group_id == ^id)
      end

    Repo.all(query)
  end

  @doc """
  Counts dashboards either created by the given user or visible to everyone.
  """
  def count_dashboards_for_user_or_visible(%Trifle.Accounts.User{} = user) do
    query =
      from(d in Dashboard,
        where: d.user_id == ^user.id or d.visibility == true,
        select: count(d.id)
      )

    Repo.one(query)
  end

  @doc """
  Counts total dashboard groups in the organization.
  """
  def count_dashboard_groups_global do
    Repo.one(from(g in DashboardGroup, select: count(g.id)))
  end

  @doc """
  Builds a nested tree of groups and dashboards for the entire organization.
  Includes dashboards owned by user or visible to everyone.
  """
  def list_dashboard_tree_global(%Trifle.Accounts.User{} = user) do
    top_groups = list_dashboard_groups_global(nil)

    Enum.map(top_groups, fn g ->
      build_group_tree_global(user, g)
    end)
  end

  defp build_group_tree_global(%Trifle.Accounts.User{} = user, %DashboardGroup{} = group) do
    children = list_dashboard_groups_global(group.id)

    %{
      group: group,
      children: Enum.map(children, &build_group_tree_global(user, &1)),
      dashboards: list_dashboards_for_user_or_visible(user, group.id)
    }
  end

  @doc """
  Creates a dashboard group.
  """
  def create_dashboard_group(attrs \\ %{}) do
    %DashboardGroup{}
    |> DashboardGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a dashboard group.
  """
  def update_dashboard_group(%DashboardGroup{} = group, attrs) do
    group
    |> DashboardGroup.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a dashboard group, moving its children (groups and dashboards) to its parent.
  """
  def delete_dashboard_group(%DashboardGroup{} = group) do
    Repo.transaction(fn ->
      # Move dashboards to parent
      from(d in Dashboard, where: d.group_id == ^group.id)
      |> Repo.update_all(set: [group_id: group.parent_group_id])

      # Move child groups to parent
      from(g in DashboardGroup, where: g.parent_group_id == ^group.id)
      |> Repo.update_all(set: [parent_group_id: group.parent_group_id])

      Repo.delete!(group)
    end)
  end

  @doc """
  Gets a dashboard group by id.
  """
  def get_dashboard_group!(id), do: Repo.get!(DashboardGroup, id)

  @doc """
  Returns the next position index for dashboard groups under a parent group (global).
  """
  def get_next_dashboard_group_position(parent_group_id) do
    base = from(g in DashboardGroup, select: max(g.position))

    query =
      case parent_group_id do
        nil -> from(g in base, where: is_nil(g.parent_group_id))
        id when is_binary(id) -> from(g in base, where: g.parent_group_id == ^id)
      end

    case Repo.one(query) do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  def get_next_dashboard_group_position_for_membership(
        %OrganizationMembership{} = membership,
        parent_group_id
      ) do
    base =
      from(g in DashboardGroup,
        where: g.organization_id == ^membership.organization_id,
        select: max(g.position)
      )

    query =
      case parent_group_id do
        nil -> from(g in base, where: is_nil(g.parent_group_id))
        id when is_binary(id) -> from(g in base, where: g.parent_group_id == ^id)
      end

    case Repo.one(query) do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  @doc """
  Reorders mixed nodes (groups and dashboards) within a container (global).
  items: list of maps %{"id" => id, "type" => "group" | "dashboard"}
  from_items: same for the source container after the move
  """
  def reorder_nodes(parent_group_id, items, from_parent_id, from_items, moved_id, moved_type)
      when is_list(items) do
    # Cycle protection for groups
    if (moved_type == "group" and parent_group_id) && group_descendant?(moved_id, parent_group_id) do
      {:error, :invalid_parent}
    else
      Repo.transaction(fn ->
        # Update target container in order
        Enum.with_index(items)
        |> Enum.each(fn {%{"id" => id, "type" => type}, idx} ->
          case type do
            "dashboard" ->
              from(d in Dashboard, where: d.id == ^id)
              |> Repo.update_all(set: [group_id: parent_group_id, position: idx])

            "group" ->
              from(g in DashboardGroup, where: g.id == ^id)
              |> Repo.update_all(set: [parent_group_id: parent_group_id, position: idx])

            _ ->
              :ok
          end
        end)

        # Normalize source container positions if different container
        if is_list(from_items) and from_parent_id != parent_group_id do
          Enum.with_index(from_items)
          |> Enum.each(fn {%{"id" => id, "type" => type}, idx} ->
            case type do
              "dashboard" ->
                from(d in Dashboard, where: d.id == ^id)
                |> Repo.update_all(set: [position: idx])

              "group" ->
                from(g in DashboardGroup, where: g.id == ^id)
                |> Repo.update_all(set: [position: idx])

              _ ->
                :ok
            end
          end)
        end
      end)
    end
  end

  defp group_descendant_for_membership?(
         %OrganizationMembership{} = membership,
         group_id,
         possible_parent_id
       ) do
    case Repo.get_by(DashboardGroup,
           id: possible_parent_id,
           organization_id: membership.organization_id
         ) do
      nil ->
        false

      %DashboardGroup{parent_group_id: nil} ->
        group_id == possible_parent_id

      %DashboardGroup{parent_group_id: parent_id} = group ->
        group_id == group.id or group_descendant_for_membership?(membership, group_id, parent_id)
    end
  end

  # Returns true if possible_parent_id is a descendant of group_id
  defp group_descendant?(group_id, possible_parent_id) do
    case Repo.get(DashboardGroup, possible_parent_id) do
      nil ->
        false

      %DashboardGroup{parent_group_id: nil} ->
        group_id == possible_parent_id

      %DashboardGroup{parent_group_id: parent_id} = g ->
        group_id == g.id || group_descendant?(group_id, parent_id)
    end
  end

  @doc """
  Gets a single dashboard.
  """
  def get_dashboard!(id) do
    Dashboard
    |> Repo.get!(id)
    |> Repo.preload([:user, :database])
  end

  @doc """
  Creates a dashboard.
  """
  def create_dashboard(attrs \\ %{}) do
    attrs =
      attrs
      |> ensure_dashboard_source_defaults()
      |> ensure_dashboard_lock_default()

    %Dashboard{}
    |> Dashboard.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a dashboard.
  """
  def update_dashboard(%Dashboard{} = dashboard, attrs) do
    dashboard
    |> Dashboard.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a dashboard.
  """
  def delete_dashboard(%Dashboard{} = dashboard) do
    Repo.delete(dashboard)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking dashboard changes.
  """
  def change_dashboard(%Dashboard{} = dashboard, attrs \\ %{}) do
    Dashboard.changeset(dashboard, attrs)
  end

  @doc """
  Generates a public access token for a dashboard.
  """
  def generate_dashboard_public_token(%Dashboard{} = dashboard) do
    dashboard
    |> Dashboard.generate_public_token()
    |> Repo.update()
  end

  @doc """
  Removes the public access token from a dashboard.
  """
  def remove_dashboard_public_token(%Dashboard{} = dashboard) do
    dashboard
    |> Dashboard.remove_public_token()
    |> Repo.update()
  end

  @doc """
  Gets a dashboard by public access token for unauthenticated access.
  """
  def get_dashboard_by_token(_dashboard_id, token) when token in [nil, ""] do
    {:error, :invalid_token}
  end

  def get_dashboard_by_token(dashboard_id, token)
      when is_binary(dashboard_id) and is_binary(token) do
    case Repo.get(Dashboard, dashboard_id) do
      %Dashboard{access_token: ^token} = dashboard when not is_nil(token) ->
        dashboard = Repo.preload(dashboard, [:user, :database])
        {:ok, dashboard}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns the list of DashboardGroup structs from top-level down to the given group_id.
  If `group_id` is nil, returns an empty list.
  """
  def get_dashboard_group_chain(nil), do: []

  def get_dashboard_group_chain(group_id) when is_binary(group_id) do
    chain = do_group_chain(group_id, [])
    Enum.reverse(chain)
  end

  defp do_group_chain(nil, acc), do: acc

  defp do_group_chain(group_id, acc) do
    case Repo.get(DashboardGroup, group_id) do
      nil -> acc
      %DashboardGroup{parent_group_id: parent} = g -> do_group_chain(parent, [g | acc])
    end
  end
end
