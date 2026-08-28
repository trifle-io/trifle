defmodule Trifle.Organizations.Dashboards do
  @moduledoc """
  Dashboards and dashboard groups: permissions, membership-scoped queries,
  group trees and reordering, visits, public share tokens, and CRUD.
  """

  import Ecto.Query, warn: false

  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.Attrs
  alias Trifle.Organizations.Dashboard
  alias Trifle.Organizations.DashboardGroup
  alias Trifle.Organizations.DashboardTemplateRef
  alias Trifle.Organizations.DashboardTemplates
  alias Trifle.Organizations.DashboardVisit
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Repo
  alias Trifle.Stats.Source, as: StatsSource

  def can_manage_dashboard?(%Dashboard{} = dashboard, %OrganizationMembership{} = membership) do
    Organizations.membership_owner?(membership) || Organizations.membership_admin?(membership) ||
      dashboard.user_id == membership.user_id
  end

  def can_view_dashboard?(%Dashboard{} = dashboard, %OrganizationMembership{} = membership) do
    cond do
      Organizations.membership_owner?(membership) -> true
      membership.role == "admin" -> true
      dashboard.user_id == membership.user_id -> true
      dashboard.visibility -> true
      true -> false
    end
  end

  def can_edit_dashboard?(%Dashboard{} = dashboard, %OrganizationMembership{} = membership) do
    cond do
      dashboard.organization_id != membership.organization_id -> false
      Organizations.membership_owner?(membership) -> true
      Organizations.membership_admin?(membership) -> true
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
        case Organizations.get_membership(target_membership_id) do
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

  defp ensure_dashboard_source(attrs, %OrganizationMembership{} = membership, default \\ nil) do
    with {:ok, {type, id}} <- resolve_dashboard_source(attrs, default),
         {:ok, updated_attrs} <- coerce_dashboard_source(attrs, membership, type, id) do
      {:ok, updated_attrs}
    end
  end

  defp maybe_ensure_dashboard_source(attrs, %OrganizationMembership{} = membership, default) do
    if valid_source_tuple?(default) or dashboard_source_params_present?(attrs) do
      ensure_dashboard_source(attrs, membership, default)
    else
      {:ok, attrs}
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
      database = Organizations.get_database_for_org!(membership.organization_id, id)

      with :ok <- Organizations.ensure_source_active(:database, database) do
        {:ok,
         attrs
         |> drop_source_param()
         |> put_attr("database_id", id)
         |> put_attr("source_type", "database")
         |> put_attr("source_id", id)}
      else
        {:source_inactive, reason} ->
          {:error, Organizations.inactive_source_message("Database", reason)}
      end
    rescue
      Ecto.NoResultsError ->
        {:error, "Database is not part of this organization"}
    end
  end

  defp coerce_dashboard_source(attrs, membership, "project", id) do
    try do
      project = Organizations.get_project_for_org!(membership.organization_id, id)

      with :ok <- Organizations.ensure_source_active(:project, project) do
        {:ok,
         attrs
         |> drop_source_param()
         |> put_attr("database_id", nil)
         |> put_attr("source_type", "project")
         |> put_attr("source_id", project.id)}
      else
        {:source_inactive, reason} ->
          {:error, Organizations.inactive_source_message("Project", reason)}
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

  defp dashboard_source_params_present?(attrs) when is_map(attrs) do
    Enum.any?(
      [
        :source,
        "source",
        :source_type,
        "source_type",
        :source_id,
        "source_id",
        :database_id,
        "database_id"
      ],
      &Map.has_key?(attrs, &1)
    )
  end

  defp dashboard_source_params_present?(_attrs), do: false

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

  defp sanitize_dashboard_update_attrs(attrs, allow_protected?, opts) when is_map(attrs) do
    sanitized =
      attrs
      |> Map.delete(:user_id)
      |> Map.delete("user_id")
      |> maybe_drop_template_payload_attrs(opts)

    cond do
      allow_protected? ->
        {:ok, sanitized}

      Enum.any?([:locked, "locked", :visibility, "visibility"], &Map.has_key?(attrs, &1)) ->
        {:error, :forbidden}

      true ->
        {:ok, sanitized}
    end
  end

  defp sanitize_dashboard_update_attrs(attrs, _allow_protected?, _opts), do: {:ok, attrs}

  defp maybe_drop_template_payload_attrs(attrs, opts) do
    if Keyword.get(opts, :allow_template_payload?, true) do
      attrs
    else
      attrs
      |> drop_attr("payload")
      |> drop_attr("template_version")
      |> drop_attr("dashboard_version")
    end
  end

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

  @doc """
  Query for all dashboards bound to a source; used by source deletion to
  detach dashboards.
  """
  def for_source_query(:database, source_id) do
    from(d in Dashboard,
      where:
        (d.source_type == "database" and d.source_id == ^source_id) or d.database_id == ^source_id
    )
  end

  def for_source_query(type, source_id) do
    type = Attrs.source_type_string(type)

    from(d in Dashboard,
      where: d.source_type == ^type and d.source_id == ^source_id
    )
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

    query
    |> Repo.all()
    |> resolve_dashboards_preserving_unresolved()
  end

  def list_all_dashboards_for_membership(
        %User{} = user,
        %OrganizationMembership{} = membership,
        opts \\ []
      ) do
    dashboards_base_query(user, membership)
    |> maybe_limit_query(Keyword.get(opts, :limit))
    |> Repo.all()
    |> resolve_dashboards_preserving_unresolved()
  end

  def dashboard_group_name_lookup_for_membership(
        %OrganizationMembership{} = membership,
        dashboards
      )
      when is_list(dashboards) do
    group_ids =
      dashboards
      |> Enum.flat_map(fn
        %Dashboard{group_id: group_id} when is_binary(group_id) -> [group_id]
        _ -> []
      end)
      |> Enum.uniq()

    if group_ids == [] do
      %{}
    else
      groups_by_id =
        DashboardGroup
        |> where([g], g.organization_id == ^membership.organization_id)
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      Map.new(group_ids, fn group_id ->
        names =
          group_id
          |> dashboard_group_chain_from_lookup(groups_by_id)
          |> Enum.reverse()
          |> Enum.map(& &1.name)

        {group_id, names}
      end)
    end
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

  defp maybe_limit_query(query, value) when is_integer(value) and value > 0 do
    limit(query, ^value)
  end

  defp maybe_limit_query(query, _value), do: query

  defp resolve_dashboards_preserving_unresolved(dashboards) do
    DashboardTemplates.resolve_dashboards_preserving_unresolved(dashboards)
  end

  defp resolve_dashboard_preserving_unresolved(%Dashboard{} = dashboard) do
    case DashboardTemplates.resolve_dashboard(dashboard) do
      {:ok, resolved} -> resolved
      {:error, _reason} -> dashboard
    end
  end

  defp dashboard_group_chain_from_lookup(group_id, groups_by_id) do
    do_dashboard_group_chain_from_lookup(group_id, groups_by_id, MapSet.new())
  end

  defp do_dashboard_group_chain_from_lookup(nil, _groups_by_id, _visited), do: []

  defp do_dashboard_group_chain_from_lookup(group_id, groups_by_id, visited) do
    cond do
      MapSet.member?(visited, group_id) ->
        []

      group = Map.get(groups_by_id, group_id) ->
        [
          group
          | do_dashboard_group_chain_from_lookup(
              group.parent_group_id,
              groups_by_id,
              MapSet.put(visited, group_id)
            )
        ]

      true ->
        []
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
      resolve_dashboard_preserving_unresolved(dashboard)
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
        |> Attrs.assign_org_id(membership.organization_id)
        |> ensure_dashboard_lock_default()
        |> Attrs.atomize_keys()

      create_dashboard_with_template(attrs, membership)
    else
      {:error, message} ->
        changeset =
          %Dashboard{}
          |> Dashboard.changeset(%{})
          |> Ecto.Changeset.add_error(:source_id, message)

        {:error, changeset}
    end
  end

  defp create_dashboard_with_template(attrs, membership) do
    template_id = DashboardTemplateRef.normalize(fetch_attr(attrs, "template_id"))

    attrs =
      attrs
      |> Map.put(:template_id, template_id)
      |> Map.delete("template_id")

    Repo.transaction(fn ->
      with :ok <- validate_dashboard_template_for_create(template_id, membership),
           {:ok, dashboard} <- insert_dashboard_with_effective_payload(attrs, template_id),
           {:ok, resolved} <- DashboardTemplates.resolve_dashboard(dashboard) do
        resolved
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, dashboard} -> {:ok, dashboard}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_dashboard_template_for_create(nil, _membership), do: :ok

  defp validate_dashboard_template_for_create(template_id, membership) do
    case DashboardTemplates.validate_reference(template_id, membership, lock: true) do
      {:ok, _template} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_dashboard_with_effective_payload(attrs, nil) do
    %Dashboard{}
    |> Dashboard.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_dashboard_with_effective_payload(attrs, _template_id) do
    %Dashboard{}
    |> Dashboard.changeset(
      attrs
      |> Map.put(:payload, %{})
      |> Map.delete("payload")
    )
    |> Repo.insert()
  end

  def create_dashboard_group_for_membership(%OrganizationMembership{} = membership, attrs \\ %{}) do
    attrs =
      attrs
      |> ensure_parent_group_within_org(membership)
      |> Attrs.assign_org_id(membership.organization_id)
      |> Attrs.atomize_keys()

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
        attrs,
        opts \\ []
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

        with {:ok, attrs} <- maybe_ensure_dashboard_source(attrs, membership, default_source),
             {:ok, sanitized_attrs} <- sanitize_dashboard_update_attrs(attrs, can_manage?, opts),
             {:ok, updated_dashboard} <-
               update_dashboard_and_template_payload(
                 dashboard,
                 membership,
                 sanitized_attrs
               ) do
          {:ok, updated_dashboard}
        else
          {:error, :forbidden} ->
            {:error, :forbidden}

          {:error, reason}
          when reason in [
                 :invalid_template_id,
                 :stale_dashboard,
                 :stale_template,
                 :dashboard_version_required,
                 :template_link_requires_context,
                 :template_not_found,
                 :template_read_only,
                 :template_version_required
               ] ->
            {:error, reason}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}

          {:error, message} when is_binary(message) ->
            changeset =
              dashboard
              |> Dashboard.changeset(%{})
              |> Ecto.Changeset.add_error(:source_id, message)

            {:error, changeset}
        end
    end
  end

  defp update_dashboard_and_template_payload(dashboard, membership, attrs) do
    if attr_present?(attrs, "template_id") do
      {:error, :template_link_requires_context}
    else
      {payload_provided?, payload} = attr_value(attrs, "payload")
      {version_provided?, expected_version_value} = attr_value(attrs, "template_version")

      {dashboard_version_provided?, expected_dashboard_version_value} =
        attr_value(attrs, "dashboard_version")

      local_attrs =
        attrs
        |> drop_attr("payload")
        |> drop_attr("template_version")
        |> drop_attr("dashboard_version")
        |> Attrs.assign_org_id(membership.organization_id)
        |> Attrs.atomize_keys()

      case DashboardTemplateRef.parse(dashboard.template_id) do
        :none when payload_provided? ->
          with {:ok, expected_version} <-
                 validate_dashboard_version(
                   dashboard_version_provided?,
                   expected_dashboard_version_value
                 ),
               {:ok, normalized_payload} <- normalize_dashboard_payload(dashboard, payload) do
            update_local_dashboard_payload(
              dashboard,
              membership,
              local_attrs,
              normalized_payload,
              expected_version
            )
          end

        :none ->
          update_local_dashboard(dashboard, local_attrs)

        {:ok, {:system, _key}} when payload_provided? ->
          {:error, :template_read_only}

        {:ok, {:system, _key}} ->
          update_local_dashboard(dashboard, local_attrs)

        {:ok, {:user, template_id}} when payload_provided? ->
          with {:ok, expected_version} <-
                 validate_template_version(version_provided?, expected_version_value),
               {:ok, normalized_payload} <- normalize_dashboard_payload(dashboard, payload) do
            update_user_template_and_dashboard(
              dashboard,
              local_attrs,
              template_id,
              membership,
              normalized_payload,
              expected_version
            )
          end

        {:ok, {:user, _template_id}} ->
          update_local_dashboard(dashboard, local_attrs)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp update_user_template_and_dashboard(
         dashboard,
         local_attrs,
         template_id,
         membership,
         payload,
         expected_version
       ) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:template, fn _repo, _changes ->
      DashboardTemplates.update_user_payload(
        template_id,
        membership,
        payload,
        expected_version
      )
    end)
    |> Ecto.Multi.update(:dashboard, Dashboard.changeset(dashboard, local_attrs))
    |> Repo.transaction()
    |> case do
      {:ok, %{dashboard: updated_dashboard}} ->
        DashboardTemplates.resolve_dashboard(updated_dashboard)

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  defp update_local_dashboard(dashboard, attrs) do
    dashboard
    |> Dashboard.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_dashboard} -> DashboardTemplates.resolve_dashboard(updated_dashboard)
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_local_dashboard_payload(
         dashboard,
         membership,
         local_attrs,
         payload,
         expected_version
       ) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:dashboard, fn repo, _changes ->
      query =
        from(d in Dashboard,
          where: d.id == ^dashboard.id and d.organization_id == ^membership.organization_id,
          lock: "FOR UPDATE"
        )

      case repo.one(query) do
        nil ->
          {:error, :unauthorized}

        %Dashboard{template_id: template_id} when not is_nil(template_id) ->
          {:error, :stale_dashboard}

        %Dashboard{lock_version: version} when version != expected_version ->
          {:error, :stale_dashboard}

        locked_dashboard ->
          if can_edit_dashboard?(locked_dashboard, membership) do
            locked_dashboard
            |> Dashboard.payload_changeset(Map.put(local_attrs, :payload, payload))
            |> repo.update()
          else
            {:error, :forbidden}
          end
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{dashboard: updated_dashboard}} ->
        DashboardTemplates.resolve_dashboard(updated_dashboard)

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  defp normalize_dashboard_payload(dashboard, payload) do
    changeset = Dashboard.changeset(dashboard, %{payload: payload})

    if changeset.valid? do
      {:ok, Ecto.Changeset.get_field(changeset, :payload)}
    else
      {:error, changeset}
    end
  end

  defp attr_present?(attrs, key) do
    Map.has_key?(attrs, key) || Map.has_key?(attrs, String.to_atom(key))
  end

  defp attr_value(attrs, key) do
    atom_key = String.to_atom(key)

    cond do
      Map.has_key?(attrs, key) -> {true, Map.get(attrs, key)}
      Map.has_key?(attrs, atom_key) -> {true, Map.get(attrs, atom_key)}
      true -> {false, nil}
    end
  end

  defp drop_attr(attrs, key) do
    attrs
    |> Map.delete(key)
    |> Map.delete(String.to_atom(key))
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp validate_template_version(true, value) do
    case parse_integer(value) do
      version when is_integer(version) -> {:ok, version}
      _ -> {:error, :template_version_required}
    end
  end

  defp validate_template_version(false, _value), do: {:error, :template_version_required}

  defp validate_dashboard_version(true, value) do
    case parse_integer(value) do
      version when is_integer(version) -> {:ok, version}
      _ -> {:error, :dashboard_version_required}
    end
  end

  defp validate_dashboard_version(false, _value), do: {:error, :dashboard_version_required}

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
    |> resolve_dashboards_preserving_unresolved()
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
    |> resolve_dashboards_preserving_unresolved()
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

    query
    |> Repo.all()
    |> resolve_dashboards_preserving_unresolved()
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
    |> resolve_dashboard_preserving_unresolved()
  end

  def resolve_dashboard_source(%Dashboard{} = dashboard) do
    cond do
      dashboard.source_type in [nil, ""] or dashboard.source_id in [nil, ""] ->
        {:error, :source_not_configured}

      dashboard.source_type == "project" ->
        try do
          project =
            Organizations.get_project_for_org!(dashboard.organization_id, dashboard.source_id)

          with :ok <- Organizations.ensure_source_active(:project, project) do
            {:ok, StatsSource.from_project(project)}
          else
            {:source_inactive, reason} -> {:error, :source_inactive, reason}
          end
        rescue
          Ecto.NoResultsError -> {:error, :source_not_found}
        end

      dashboard.source_type == "database" and match?(%Database{}, dashboard.database) ->
        with :ok <- Organizations.ensure_source_active(:database, dashboard.database) do
          {:ok, StatsSource.from_database(dashboard.database)}
        else
          {:source_inactive, reason} -> {:error, :source_inactive, reason}
        end

      dashboard.source_type == "database" ->
        try do
          database =
            Organizations.get_database_for_org!(dashboard.organization_id, dashboard.source_id)

          with :ok <- Organizations.ensure_source_active(:database, database) do
            {:ok, StatsSource.from_database(database)}
          else
            {:source_inactive, reason} -> {:error, :source_inactive, reason}
          end
        rescue
          Ecto.NoResultsError -> {:error, :source_not_found}
        end

      true ->
        {:error, :source_not_configured}
    end
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
    changeset =
      if attr_present?(attrs, "payload") do
        Dashboard.payload_changeset(dashboard, attrs)
      else
        Dashboard.changeset(dashboard, attrs)
      end

    Repo.update(changeset, stale_error_field: :lock_version)
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
        dashboard =
          dashboard
          |> Repo.preload([:user, :database])
          |> resolve_dashboard_preserving_unresolved()

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
