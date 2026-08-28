defmodule Trifle.Organizations do
  @moduledoc """
  The Organizations context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Ecto.Multi
  alias Trifle.Billing
  alias Trifle.Billing.Subscription
  alias Trifle.Monitors.Monitor
  alias Trifle.Repo
  alias Trifle.SqliteUploads
  alias Trifle.SystemNotifications

  alias Trifle.Accounts.User

  alias Trifle.Organizations.{
    Project,
    ProjectCluster,
    ProjectClusterAccess,
    OrganizationConnector,
    Organization,
    OrganizationMembership,
    OrganizationInvitation,
    Database
  }

  alias Trifle.Organizations.Attrs
  alias Trifle.Organizations.Connectors
  alias Trifle.Organizations.Dashboards
  alias Trifle.Organizations.DashboardTemplates
  alias Trifle.Organizations.InvitationNotifier
  alias Trifle.Organizations.SSO
  alias Trifle.Organizations.Tokens
  alias Trifle.Organizations.Transponders

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

  defdelegate can_manage_dashboard?(dashboard, membership), to: Dashboards
  defdelegate can_view_dashboard?(dashboard, membership), to: Dashboards
  defdelegate can_edit_dashboard?(dashboard, membership), to: Dashboards
  defdelegate can_clone_dashboard?(dashboard, membership), to: Dashboards

  defdelegate list_available_dashboard_templates(membership),
    to: DashboardTemplates,
    as: :list_available_for_membership

  defdelegate list_user_dashboard_templates_for_membership(membership),
    to: DashboardTemplates,
    as: :list_user_for_membership

  defdelegate list_all_dashboard_templates(), to: DashboardTemplates, as: :list_all_user
  defdelegate count_all_dashboard_templates(), to: DashboardTemplates, as: :count_all_user
  defdelegate get_dashboard_template!(id), to: DashboardTemplates, as: :get_user!

  defdelegate get_dashboard_template_for_membership!(membership, id),
    to: DashboardTemplates,
    as: :get_user_for_membership!

  defdelegate create_dashboard_template(user, membership, attrs),
    to: DashboardTemplates,
    as: :create_user

  defdelegate update_dashboard_template(template, user, membership, attrs),
    to: DashboardTemplates,
    as: :update_user

  defdelegate delete_dashboard_template(template, user, membership),
    to: DashboardTemplates,
    as: :delete_user

  defdelegate convert_dashboard_to_template(user, membership, dashboard, attrs),
    to: DashboardTemplates,
    as: :convert_dashboard

  defdelegate link_dashboard_template(dashboard, membership, template_id),
    to: DashboardTemplates,
    as: :link_dashboard

  defdelegate update_dashboard_configuration(dashboard, membership, attrs, template_id),
    to: DashboardTemplates

  defdelegate detach_dashboard_template(dashboard, membership),
    to: DashboardTemplates,
    as: :detach_dashboard

  defdelegate resolve_dashboard_template(dashboard),
    to: DashboardTemplates,
    as: :resolve_dashboard

  defdelegate resolve_dashboard_templates(dashboards),
    to: DashboardTemplates,
    as: :resolve_dashboards

  defdelegate resolve_dashboard_template!(dashboard),
    to: DashboardTemplates,
    as: :resolve_dashboard!

  defdelegate resolve_dashboard_templates!(dashboards),
    to: DashboardTemplates,
    as: :resolve_dashboards!

  defdelegate dashboard_template_usage_count(template),
    to: DashboardTemplates,
    as: :template_usage_count

  defdelegate dashboard_template_usage_counts(templates),
    to: DashboardTemplates,
    as: :template_usage_counts

  defdelegate transfer_dashboard_ownership(dashboard, membership, target_membership_id),
    to: Dashboards

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
      {:ok, invitation} ->
        InvitationNotifier.deliver_invitation(invitation)
        notify_invitation_created(invitation)

      _ ->
        :ok
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

  defdelegate list_sso_providers(organization), to: SSO
  defdelegate get_sso_provider_for_org(organization, provider), to: SSO
  defdelegate google_sso_enabled?(organization), to: SSO
  defdelegate upsert_google_sso_provider(organization, attrs), to: SSO
  defdelegate find_google_sso_provider_for_domain(domain), to: SSO
  defdelegate ensure_membership_for_sso(user, provider, email), to: SSO

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

  defp assign_org_id(attrs, org_or_id), do: Attrs.assign_org_id(attrs, org_or_id)

  defp atomize_keys(attrs), do: Attrs.atomize_keys(attrs)

  defp maybe_cleanup_replaced_sqlite_file(
         %Database{driver: "sqlite", file_path: old_path, config: old_config},
         %Database{file_path: new_path, config: new_config}
       ) do
    old_storage = SqliteUploads.extract_storage_metadata(old_config || %{})
    new_storage = SqliteUploads.extract_storage_metadata(new_config || %{})

    cond do
      old_path in [nil, ""] ->
        :ok

      old_path == new_path and old_storage == new_storage ->
        :ok

      true ->
        maybe_delete_sqlite_file(old_path, old_config)
    end
  end

  defp maybe_cleanup_replaced_sqlite_file(_previous, _updated), do: :ok

  defp maybe_cleanup_deleted_sqlite_file(%Database{
         driver: "sqlite",
         file_path: path,
         config: config
       }) do
    maybe_delete_sqlite_file(path, config)
  end

  defp maybe_cleanup_deleted_sqlite_file(_database), do: :ok

  defp maybe_delete_sqlite_file(path, config) when is_binary(path) and path != "" do
    case SqliteUploads.delete_managed_upload(path, config || %{}) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to delete managed SQLite file #{path}: #{inspect(reason)}")
        :ok
    end
  end

  defp maybe_delete_sqlite_file(_path, _config), do: :ok

  ## Project clusters

  def list_project_clusters do
    from(c in ProjectCluster, order_by: [asc: c.name, asc: c.id])
    |> Repo.all()
  end

  def get_project_cluster!(id) when is_binary(id), do: Repo.get!(ProjectCluster, id)
  def get_project_cluster(id) when is_binary(id), do: Repo.get(ProjectCluster, id)

  def get_default_project_cluster do
    from(c in ProjectCluster, where: c.is_default == true, limit: 1)
    |> Repo.one()
  end

  def list_project_clusters_for_org(%Organization{} = organization) do
    list_project_clusters_for_org(organization.id)
  end

  def list_project_clusters_for_org(organization_id) when is_binary(organization_id) do
    clusters = list_project_clusters()
    access_ids = project_cluster_access_ids(organization_id)

    clusters
    |> Enum.filter(&project_cluster_visible_with_access_ids?(&1, access_ids))
    |> Enum.map(fn cluster ->
      selectable =
        cluster.status == "active" and
          project_cluster_accessible_with_access_ids?(cluster, access_ids)

      reason =
        cond do
          cluster.status != "active" -> :coming_soon
          selectable -> nil
          true -> :contact_sales
        end

      %{
        cluster: cluster,
        selectable: selectable,
        reason: reason
      }
    end)
  end

  def create_project_cluster(attrs \\ %{}) do
    changeset = ProjectCluster.changeset(%ProjectCluster{}, attrs)

    Multi.new()
    |> Multi.insert(:cluster, changeset)
    |> Multi.run(:clear_default, fn repo, %{cluster: cluster} ->
      if cluster.is_default do
        repo.update_all(
          from(c in ProjectCluster, where: c.id != ^cluster.id),
          set: [is_default: false]
        )
      end

      {:ok, cluster}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{cluster: cluster}} -> {:ok, cluster}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def update_project_cluster(%ProjectCluster{} = cluster, attrs) do
    changeset = ProjectCluster.changeset(cluster, attrs)

    Multi.new()
    |> Multi.update(:cluster, changeset)
    |> Multi.run(:clear_default, fn repo, %{cluster: updated} ->
      if updated.is_default do
        repo.update_all(
          from(c in ProjectCluster, where: c.id != ^updated.id),
          set: [is_default: false]
        )
      end

      {:ok, updated}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{cluster: updated}} -> {:ok, updated}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def change_project_cluster(%ProjectCluster{} = cluster, attrs \\ %{}) do
    ProjectCluster.changeset(cluster, attrs)
  end

  def project_cluster_setup?(%ProjectCluster{} = cluster) do
    ProjectCluster.is_setup?(cluster)
  end

  def check_project_cluster_status(%ProjectCluster{} = cluster) do
    ProjectCluster.check_status(cluster)
  end

  def setup_project_cluster(%ProjectCluster{} = cluster) do
    ProjectCluster.setup(cluster)
  end

  def list_project_cluster_accesses(%ProjectCluster{} = cluster) do
    from(a in ProjectClusterAccess,
      where: a.project_cluster_id == ^cluster.id,
      join: o in assoc(a, :organization),
      preload: [organization: o],
      order_by: [asc: o.name]
    )
    |> Repo.all()
  end

  def grant_project_cluster_access(%ProjectCluster{} = cluster, %Organization{} = organization) do
    %ProjectClusterAccess{}
    |> ProjectClusterAccess.changeset(%{
      project_cluster_id: cluster.id,
      organization_id: organization.id
    })
    |> Repo.insert()
  end

  def revoke_project_cluster_access(%ProjectClusterAccess{} = access) do
    Repo.delete(access)
  end

  def project_cluster_accessible?(%ProjectCluster{} = cluster, %Organization{} = organization) do
    project_cluster_accessible_with_access_ids?(
      cluster,
      project_cluster_access_ids(organization.id)
    )
  end

  defp project_cluster_accessible_with_access_ids?(
         %ProjectCluster{visibility: "public"},
         _access_ids
       ),
       do: true

  defp project_cluster_accessible_with_access_ids?(
         %ProjectCluster{visibility: visibility} = cluster,
         access_ids
       )
       when visibility in ["restricted", "private"] do
    MapSet.member?(access_ids, cluster.id)
  end

  defp project_cluster_visible_with_access_ids?(
         %ProjectCluster{visibility: "public"},
         _access_ids
       ),
       do: true

  defp project_cluster_visible_with_access_ids?(
         %ProjectCluster{visibility: "restricted"},
         _access_ids
       ),
       do: true

  defp project_cluster_visible_with_access_ids?(
         %ProjectCluster{visibility: "private"} = cluster,
         access_ids
       ) do
    MapSet.member?(access_ids, cluster.id)
  end

  defp project_cluster_access_ids(organization_id) when is_binary(organization_id) do
    from(a in ProjectClusterAccess,
      where: a.organization_id == ^organization_id,
      select: a.project_cluster_id
    )
    |> Repo.all()
    |> MapSet.new()
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

  def list_projects_for_org(%Organization{} = organization) do
    list_projects_for_org(organization.id)
  end

  def list_projects_for_org(organization_id) when is_binary(organization_id) do
    from(p in Project,
      where: p.organization_id == ^organization_id,
      order_by: [asc: p.name, asc: p.id]
    )
    |> Repo.all()
  end

  def list_projects_for_membership(%OrganizationMembership{} = membership) do
    list_projects_for_org(membership.organization_id)
  end

  def list_users_projects(%Trifle.Accounts.User{} = user) do
    case get_membership_for_user(user) do
      %OrganizationMembership{} = membership -> list_projects_for_membership(membership)
      _ -> []
    end
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

  def get_project_for_org!(%Organization{} = organization, id) when is_binary(id) do
    Repo.get_by!(Project, id: id, organization_id: organization.id)
  end

  def get_project_for_org!(organization_id, id)
      when is_binary(organization_id) and is_binary(id) do
    Repo.get_by!(Project, id: id, organization_id: organization_id)
  end

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
    |> Project.changeset(apply_project_billing_defaults(attrs))
    |> Repo.insert()
    |> notify_project_created()
  end

  def create_users_project(attrs \\ %{}, %Trifle.Accounts.User{} = user) do
    case get_membership_for_user(user) do
      %OrganizationMembership{} = membership ->
        create_project_for_membership(attrs, membership, user)

      _ ->
        {:error, :organization_required}
    end
  end

  def create_project_for_membership(attrs, %OrganizationMembership{} = membership, %User{} = user) do
    attrs =
      attrs
      |> Map.put("user", user)
      |> Map.put("organization_id", membership.organization_id)
      |> apply_project_billing_defaults()

    %Project{}
    |> Project.changeset(attrs)
    |> ensure_project_cluster(membership.organization_id)
    |> Repo.insert()
    |> notify_project_created()
  end

  defp apply_project_billing_defaults(attrs) when is_map(attrs) do
    if Trifle.Config.self_hosted_mode?() do
      attrs
      |> maybe_put_string_key("billing_required", false)
      |> maybe_put_string_key("billing_state", "active")
    else
      attrs
    end
  end

  defp apply_project_billing_defaults(attrs), do: attrs

  defp maybe_put_string_key(attrs, key, value) when is_map(attrs) and is_binary(key) do
    atom_key = String.to_atom(key)

    cond do
      Map.has_key?(attrs, key) -> attrs
      Map.has_key?(attrs, atom_key) -> attrs
      true -> Map.put(attrs, key, value)
    end
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
    case get_project_subscription(project) do
      %Subscription{} = subscription ->
        if project_subscription_inactive?(subscription) do
          delete_project_with_dependencies(project)
        else
          {:error, :active_subscription}
        end

      nil ->
        delete_project_with_dependencies(project)
    end
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

  def get_project_subscription(%Project{} = project) do
    Billing.get_scope_subscription(project.organization_id, "project", project.id)
  end

  def project_deletable?(%Project{} = project) do
    case get_project_subscription(project) do
      nil -> true
      %Subscription{} = subscription -> project_subscription_inactive?(subscription)
    end
  end

  def project_delete_block_reason(%Project{} = project) do
    case get_project_subscription(project) do
      nil ->
        nil

      %Subscription{} = subscription ->
        if project_subscription_inactive?(subscription) do
          nil
        else
          "Project can only be deleted when its subscription is inactive."
        end
    end
  end

  defp ensure_project_cluster(%Ecto.Changeset{} = changeset, organization_id) do
    cluster_id = Ecto.Changeset.get_field(changeset, :project_cluster_id)
    default_cluster = get_default_project_cluster()

    cluster =
      cond do
        is_binary(cluster_id) -> get_project_cluster(cluster_id)
        default_cluster -> default_cluster
        true -> nil
      end

    changeset =
      case cluster do
        %ProjectCluster{} = cluster ->
          selectable? =
            cluster.status == "active" and
              project_cluster_accessible_with_access_ids?(
                cluster,
                project_cluster_access_ids(organization_id)
              )

          if selectable? do
            Ecto.Changeset.put_change(changeset, :project_cluster_id, cluster.id)
          else
            Ecto.Changeset.add_error(changeset, :project_cluster_id, "is not available")
          end

        nil ->
          Ecto.Changeset.add_error(changeset, :project_cluster_id, "is required")
      end

    changeset
  end

  ## Organization API tokens

  defdelegate list_organization_api_tokens_for_org(org_or_id), to: Tokens
  defdelegate get_organization_api_token_for_org!(organization_id, token_id), to: Tokens
  defdelegate get_organization_api_token_for_org(organization_id, token_id), to: Tokens
  defdelegate create_organization_api_token(user, attrs \\ %{}), to: Tokens
  defdelegate update_organization_api_token(token, attrs), to: Tokens
  defdelegate bind_organization_api_token_to_organization(token, organization_id), to: Tokens
  defdelegate delete_organization_api_token(token), to: Tokens
  defdelegate change_organization_api_token(token, attrs \\ %{}), to: Tokens
  defdelegate get_api_token_auth(token), to: Tokens
  defdelegate touch_organization_api_token(token, attrs \\ %{}), to: Tokens

  defdelegate grant_organization_api_token_source_access(
                token,
                source_type,
                source_id,
                read,
                write
              ),
              to: Tokens

  defdelegate ensure_token_permission(token, source_type, source_id, mode), to: Tokens
  defdelegate token_has_permission?(permissions, source_type, source_id, mode), to: Tokens
  defdelegate source_permission(token, source_type, source_id), to: Tokens
  defdelegate source_key(source_type, source_id), to: Tokens

  def get_source_for_org(organization_id, source_id)
      when is_binary(organization_id) and is_binary(source_id) do
    with {:ok, source_id} <- Ecto.UUID.cast(source_id) do
      case Repo.get_by(Project, id: source_id, organization_id: organization_id) do
        %Project{} = project ->
          {:ok, :project, project}

        nil ->
          case Repo.get_by(Database, id: source_id, organization_id: organization_id) do
            %Database{} = database -> {:ok, :database, database}
            nil -> {:error, :not_found}
          end
      end
    else
      :error -> {:error, :bad_request}
    end
  end

  def get_source_for_org(_organization_id, _source_id), do: {:error, :bad_request}

  def get_operational_source_for_org(organization_id, source_id)
      when is_binary(organization_id) and is_binary(source_id) do
    with {:ok, source_type, record} <- get_source_for_org(organization_id, source_id),
         :ok <- ensure_source_active(source_type, record) do
      {:ok, source_type, record}
    else
      {:error, reason} -> {:error, reason}
      {:source_inactive, reason} -> {:error, :source_inactive, reason}
    end
  end

  def get_operational_source_for_org(_organization_id, _source_id), do: {:error, :bad_request}

  @doc false
  def ensure_source_active(source_type, record) do
    case Billing.source_access_status(source_type, record) do
      %{active?: true} -> :ok
      %{inactive_reason: reason} -> {:source_inactive, reason}
    end
  end

  @doc false
  def inactive_source_message(source_label, reason) when is_binary(source_label) do
    case Billing.source_access_status_reason(reason) do
      :pending_checkout ->
        "#{source_label} requires an active subscription before it can be used."

      :missing_app_subscription ->
        "#{source_label} requires an active organization subscription."

      :billing_locked ->
        "#{source_label} is unavailable until billing is reactivated."

      :subscription_inactive ->
        "#{source_label} subscription is inactive."

      :payment_grace_expired ->
        "#{source_label} is unavailable because payment grace has expired."

      :project_usage_limit_reached ->
        "#{source_label} is unavailable because its usage limit has been reached."

      _ ->
        "#{source_label} is inactive and cannot be used right now."
    end
  end

  defdelegate normalize_token_permissions(permissions), to: Tokens

  defdelegate list_project_tokens, to: Tokens
  defdelegate list_projects_project_tokens(project), to: Tokens
  defdelegate get_project_token!(id), to: Tokens
  defdelegate get_project_by_token(token), to: Tokens
  defdelegate create_project_token(attrs \\ %{}), to: Tokens
  defdelegate create_projects_project_token(attrs \\ %{}, project), to: Tokens
  defdelegate update_project_token(project_token, attrs), to: Tokens
  defdelegate delete_project_token(project_token), to: Tokens
  defdelegate change_project_token(project_token, attrs \\ %{}), to: Tokens

  ## Organization connectors

  defdelegate list_connectors_for_org(org_or_id), to: Connectors
  defdelegate get_connector_for_org!(org_or_id, id), to: Connectors
  defdelegate get_connector_for_org(organization_id, id), to: Connectors
  defdelegate create_connector_for_org(organization), to: Connectors
  defdelegate create_connector_for_org(organization, attrs), to: Connectors
  defdelegate change_connector(connector), to: Connectors
  defdelegate change_connector(connector, attrs), to: Connectors
  defdelegate delete_connector(connector), to: Connectors
  defdelegate get_connector_auth(token), to: Connectors
  defdelegate record_connector_heartbeat(connector), to: Connectors
  defdelegate record_connector_heartbeat(connector, attrs), to: Connectors
  defdelegate touch_connector_poll(connector), to: Connectors
  defdelegate enqueue_connector_job(connector, type), to: Connectors
  defdelegate enqueue_connector_job(connector, type, payload), to: Connectors
  defdelegate list_pending_connector_jobs(connector), to: Connectors
  defdelegate list_pending_connector_jobs(connector, limit), to: Connectors
  defdelegate complete_connector_job(connector, job_id, attrs), to: Connectors

  ## Database tokens

  defdelegate list_database_tokens, to: Tokens
  defdelegate list_databases_database_tokens(database), to: Tokens
  defdelegate get_database_token!(id), to: Tokens
  defdelegate get_database_by_token(token), to: Tokens
  defdelegate create_database_token(attrs \\ %{}), to: Tokens
  defdelegate create_databases_database_token(attrs \\ %{}, database), to: Tokens
  defdelegate update_database_token(database_token, attrs), to: Tokens
  defdelegate delete_database_token(database_token), to: Tokens
  defdelegate change_database_token(database_token, attrs \\ %{}), to: Tokens

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
    |> database_changeset(attrs)
    |> Repo.insert()
    |> notify_database_created()
  end

  def create_database(attrs \\ %{}) do
    %Database{}
    |> database_changeset(attrs)
    |> Repo.insert()
    |> notify_database_created()
  end

  @doc """
  Updates a database.
  """
  def update_database(%Database{} = database, attrs) do
    changeset = database_changeset(database, attrs)

    if pool_relevant_changes?(changeset) do
      Repo.transaction(fn ->
        case Repo.update(changeset) do
          {:ok, updated_database} ->
            {1, _} =
              from(d in Database, where: d.id == ^updated_database.id)
              |> Repo.update_all(inc: [pool_version: 1])

            Repo.get!(Database, updated_database.id)

          {:error, %Ecto.Changeset{} = failed_changeset} ->
            Repo.rollback({:changeset, failed_changeset})
        end
      end)
      |> case do
        {:ok, updated_database} ->
          maybe_cleanup_replaced_sqlite_file(database, updated_database)
          {:ok, updated_database}

        {:error, {:changeset, %Ecto.Changeset{} = failed_changeset}} ->
          {:error, failed_changeset}

        {:error, reason} ->
          {:error, reason}
      end
    else
      case Repo.update(changeset) do
        {:ok, updated_database} ->
          maybe_cleanup_replaced_sqlite_file(database, updated_database)
          {:ok, updated_database}

        error ->
          error
      end
    end
  end

  @doc """
  Deletes a database.
  """
  def delete_database(%Database{} = database) do
    Multi.new()
    |> Multi.update_all(:dashboards, Dashboards.for_source_query(:database, database.id),
      set: [source_type: nil, source_id: nil, database_id: nil]
    )
    |> Multi.update_all(:monitors, monitors_for_source_query(:database, database.id),
      set: [source_type: nil, source_id: nil]
    )
    |> Multi.delete_all(:transponders, Transponders.for_source_query(:database, database.id))
    |> Multi.delete(:database, database)
    |> Repo.transaction()
    |> case do
      {:ok, %{database: deleted_database}} ->
        _ = Trifle.DatabasePools.PoolManager.stop_all_pools_for_database(deleted_database.id)
        maybe_cleanup_deleted_sqlite_file(deleted_database)
        {:ok, deleted_database}

      {:error, :database, reason, _changes} ->
        {:error, reason}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking database changes.
  """
  def change_database(%Database{} = database, attrs \\ %{}) do
    database_changeset(database, attrs)
  end

  defp database_changeset(%Database{} = database, attrs) do
    database
    |> Database.changeset(attrs)
    |> validate_database_connector_scope()
  end

  defp validate_database_connector_scope(%Ecto.Changeset{} = changeset) do
    connection_method = Ecto.Changeset.get_field(changeset, :connection_method)
    organization_id = Ecto.Changeset.get_field(changeset, :organization_id)
    organization_connector_id = Ecto.Changeset.get_field(changeset, :organization_connector_id)

    cond do
      connection_method != "connector" ->
        changeset

      not is_binary(organization_connector_id) or not is_binary(organization_id) ->
        changeset

      connector_belongs_to_org?(organization_connector_id, organization_id) ->
        changeset

      true ->
        Ecto.Changeset.add_error(changeset, :organization_connector_id, "is not available")
    end
  end

  defp connector_belongs_to_org?(connector_id, organization_id) do
    from(a in OrganizationConnector,
      where: a.id == ^connector_id and a.organization_id == ^organization_id
    )
    |> Repo.exists?()
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
    database
    |> Database.check_status()
    |> notify_database_checked()
  end

  defp notify_invitation_created(%OrganizationInvitation{} = invitation) do
    invitation = Repo.preload(invitation, [:organization, :invited_by])

    SystemNotifications.enqueue(:user_invited, %{
      invitation_id: invitation.id,
      organization_id: invitation.organization_id,
      organization_name: invitation.organization && invitation.organization.name,
      email: invitation.email,
      role: invitation.role,
      invited_by_email: invitation.invited_by && invitation.invited_by.email,
      expires_at: invitation.expires_at,
      occurred_at: invitation.inserted_at
    })
  end

  defp notify_project_created({:ok, %Project{} = project} = result) do
    project = Repo.preload(project, [:organization, :user])

    SystemNotifications.enqueue(:project_created, %{
      project_id: project.id,
      project_name: project.name,
      organization_id: project.organization_id,
      organization_name: project.organization && project.organization.name,
      owner_email: project.user && project.user.email,
      occurred_at: project.inserted_at
    })

    result
  end

  defp notify_project_created(result), do: result

  defp notify_database_created({:ok, %Database{} = database} = result) do
    database = Repo.preload(database, :organization)

    SystemNotifications.enqueue(:database_created, %{
      database_id: database.id,
      database_name: database.display_name,
      organization_id: database.organization_id,
      organization_name: database.organization && database.organization.name,
      driver: database.driver,
      connection_method: database.connection_method,
      occurred_at: database.inserted_at
    })

    result
  end

  defp notify_database_created(result), do: result

  defp notify_database_checked({result, %Database{} = database, detail} = response)
       when result in [:ok, :error] do
    database = Repo.preload(database, :organization)

    SystemNotifications.enqueue(:database_checked, %{
      database_id: database.id,
      database_name: database.display_name,
      organization_id: database.organization_id,
      organization_name: database.organization && database.organization.name,
      driver: database.driver,
      connection_method: database.connection_method,
      status: database.last_check_status,
      error: if(result == :error, do: redact_database_error(detail), else: nil),
      occurred_at: database.last_check_at || DateTime.utc_now()
    })

    response
  end

  defp notify_database_checked(response), do: response

  defp redact_database_error(error) do
    error
    |> to_string()
    |> String.replace(~r/(?i)(password|passphrase|secret|token)=([^\s,;]+)/, "\\1=[REDACTED]")
    |> String.replace(~r{(://[^:/\s]+:)[^@\s]+@}, "\\1[REDACTED]@")
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

  defp pool_relevant_changes?(%Ecto.Changeset{} = changeset) do
    changed_fields = Map.keys(changeset.changes)

    Enum.any?(Database.pool_relevant_fields(), fn field ->
      field in changed_fields
    end)
  end

  ## Transponder functions

  defdelegate list_transponders_for_database(database), to: Transponders
  defdelegate list_transponders_for_project(project), to: Transponders
  defdelegate get_transponder_for_org!(org_or_id, id), to: Transponders
  defdelegate get_transponder!(id), to: Transponders
  defdelegate get_transponder_for_source!(source, id), to: Transponders
  defdelegate create_transponder_for_database(database), to: Transponders
  defdelegate create_transponder_for_database(database, attrs), to: Transponders
  defdelegate create_transponder_for_project(project), to: Transponders
  defdelegate create_transponder_for_project(project, attrs), to: Transponders
  defdelegate create_transponder, to: Transponders
  defdelegate create_transponder(attrs), to: Transponders
  defdelegate update_transponder(transponder, attrs), to: Transponders
  defdelegate delete_transponder(transponder), to: Transponders
  defdelegate change_transponder(transponder), to: Transponders
  defdelegate change_transponder(transponder, attrs), to: Transponders
  defdelegate update_transponder_order(source, transponder_ids), to: Transponders
  defdelegate get_next_transponder_order(source), to: Transponders

  defdelegate get_next_dashboard_position_for_group(group_id), to: Dashboards
  defdelegate get_next_dashboard_position_for_membership(membership, group_id), to: Dashboards

  defp project_subscription_query(%Project{} = project) do
    from(s in Subscription,
      where:
        s.organization_id == ^project.organization_id and
          s.scope_type == "project" and
          s.scope_id == ^project.id
    )
  end

  defp project_subscription_inactive?(%Subscription{status: status}) do
    status in [nil, "", "canceled", "incomplete", "incomplete_expired", "paused"]
  end

  defp delete_project_with_dependencies(%Project{} = project) do
    Multi.new()
    |> Multi.update_all(:dashboards, Dashboards.for_source_query(:project, project.id),
      set: [source_type: nil, source_id: nil, database_id: nil]
    )
    |> Multi.update_all(:monitors, monitors_for_source_query(:project, project.id),
      set: [source_type: nil, source_id: nil]
    )
    |> Multi.delete_all(:transponders, Transponders.for_source_query(:project, project.id))
    |> Multi.delete_all(:subscription, project_subscription_query(project))
    |> Multi.delete(:project, project)
    |> Repo.transaction()
    |> case do
      {:ok, %{project: deleted_project}} ->
        {:ok, deleted_project}

      {:error, :project, reason, _changes} ->
        {:error, reason}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp monitors_for_source_query(type, source_id) do
    type = monitor_source_type(type)

    from(m in Monitor,
      where: m.source_type == ^type and m.source_id == ^source_id
    )
  end

  defp monitor_source_type(:database), do: :database
  defp monitor_source_type(:project), do: :project
  defp monitor_source_type("database"), do: :database
  defp monitor_source_type("project"), do: :project

  ## Dashboards

  defdelegate list_dashboards_for_membership(user, membership, group_id \\ nil), to: Dashboards
  defdelegate list_all_dashboards_for_membership(user, membership, opts \\ []), to: Dashboards
  defdelegate dashboard_group_name_lookup_for_membership(membership, dashboards), to: Dashboards

  defdelegate list_recent_dashboard_visits_for_membership(user, membership, limit \\ 5),
    to: Dashboards

  defdelegate record_dashboard_visit(user, membership, dashboard), to: Dashboards
  defdelegate count_dashboards_for_membership(user, membership), to: Dashboards
  defdelegate count_dashboard_groups_for_membership(membership), to: Dashboards

  defdelegate list_dashboard_groups_for_membership(membership, parent_group_id \\ nil),
    to: Dashboards

  defdelegate list_dashboard_tree_for_membership(user, membership), to: Dashboards
  defdelegate get_dashboard_for_membership!(membership, id), to: Dashboards
  defdelegate create_dashboard_for_membership(user, membership, attrs \\ %{}), to: Dashboards
  defdelegate create_dashboard_group_for_membership(membership, attrs \\ %{}), to: Dashboards
  defdelegate get_dashboard_group_for_membership!(membership, id), to: Dashboards
  defdelegate update_dashboard_for_membership(dashboard, membership, attrs), to: Dashboards
  defdelegate delete_dashboard_for_membership(dashboard, membership), to: Dashboards

  defdelegate reorder_nodes_for_membership(
                membership,
                parent_group_id,
                items,
                from_parent_id,
                from_items,
                moved_id,
                moved_type
              ),
              to: Dashboards

  defdelegate list_dashboards_for_database(database), to: Dashboards
  defdelegate list_all_dashboards, to: Dashboards
  defdelegate count_dashboards, to: Dashboards
  defdelegate list_dashboard_groups_global(parent_group_id), to: Dashboards
  defdelegate list_dashboards_for_user_or_visible(user, group_id \\ nil), to: Dashboards
  defdelegate count_dashboards_for_user_or_visible(user), to: Dashboards
  defdelegate count_dashboard_groups_global, to: Dashboards
  defdelegate list_dashboard_tree_global(user), to: Dashboards
  defdelegate create_dashboard_group(attrs \\ %{}), to: Dashboards
  defdelegate update_dashboard_group(group, attrs), to: Dashboards
  defdelegate delete_dashboard_group(group), to: Dashboards
  defdelegate get_dashboard_group!(id), to: Dashboards
  defdelegate get_next_dashboard_group_position(parent_group_id), to: Dashboards

  defdelegate get_next_dashboard_group_position_for_membership(membership, parent_group_id),
    to: Dashboards

  defdelegate reorder_nodes(
                parent_group_id,
                items,
                from_parent_id,
                from_items,
                moved_id,
                moved_type
              ),
              to: Dashboards

  defdelegate get_dashboard!(id), to: Dashboards
  defdelegate resolve_dashboard_source(dashboard), to: Dashboards
  defdelegate create_dashboard(attrs \\ %{}), to: Dashboards
  defdelegate update_dashboard(dashboard, attrs), to: Dashboards
  defdelegate delete_dashboard(dashboard), to: Dashboards
  defdelegate change_dashboard(dashboard, attrs \\ %{}), to: Dashboards
  defdelegate generate_dashboard_public_token(dashboard), to: Dashboards
  defdelegate remove_dashboard_public_token(dashboard), to: Dashboards
  defdelegate get_dashboard_by_token(dashboard_id, token), to: Dashboards
  defdelegate get_dashboard_group_chain(group_id), to: Dashboards
end
