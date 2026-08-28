defmodule Trifle.Organizations.DashboardTemplates do
  @moduledoc """
  Organization-scoped dashboard template lifecycle and effective-layout resolution.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.Dashboard
  alias Trifle.Organizations.DashboardTemplate
  alias Trifle.Organizations.DashboardTemplateRef
  alias Trifle.Organizations.Dashboards
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Organizations.SystemDashboardTemplates
  alias Trifle.Repo

  defmodule Descriptor do
    @enforce_keys [:template_id, :type, :id, :name, :group, :version, :read_only]
    defstruct [:template_id, :type, :id, :name, :group, :version, :read_only]
  end

  defmodule ResolutionError do
    defexception [:reason, :message]

    @impl true
    def exception(opts) do
      reason = Keyword.fetch!(opts, :reason)

      %__MODULE__{
        reason: reason,
        message: "failed to resolve dashboard template: #{inspect(reason)}"
      }
    end
  end

  def list_available_for_membership(%OrganizationMembership{} = membership) do
    system = Enum.map(SystemDashboardTemplates.list(), &system_descriptor/1)

    user =
      membership
      |> list_user_for_membership()
      |> Enum.map(&user_descriptor/1)

    [
      %{label: "System templates", type: :system, templates: system},
      %{label: "Organization templates", type: :user, templates: user}
    ]
  end

  def list_user_for_membership(%OrganizationMembership{} = membership) do
    from(t in DashboardTemplate,
      where: t.organization_id == ^membership.organization_id,
      order_by: [asc: fragment("lower(?)", t.name), asc: t.id]
    )
    |> Repo.all()
  end

  def list_all_user do
    from(t in DashboardTemplate, order_by: [asc: t.inserted_at, asc: t.id])
    |> Repo.all()
  end

  def count_all_user, do: Repo.aggregate(DashboardTemplate, :count, :id)

  def get_user!(id), do: Repo.get!(DashboardTemplate, id)

  def get_user_for_membership!(%OrganizationMembership{} = membership, id) do
    Repo.get_by!(DashboardTemplate, id: id, organization_id: membership.organization_id)
  end

  def create_user(%User{} = user, %OrganizationMembership{} = membership, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("organization_id", membership.organization_id)
      |> Map.put("created_by_id", user.id)

    %DashboardTemplate{}
    |> DashboardTemplate.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(
        %DashboardTemplate{} = template,
        %User{} = user,
        %OrganizationMembership{} = membership,
        attrs
      ) do
    cond do
      template.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      not can_manage?(template, user, membership) ->
        {:error, :forbidden}

      true ->
        attrs = stringify_keys(attrs)
        expected_version = fetch_integer(attrs, "template_version")
        payload = Map.get(attrs, "payload")

        metadata_attrs =
          Map.drop(attrs, [
            "payload",
            "template_version",
            "lock_version",
            "organization_id",
            "created_by_id",
            "creator_id"
          ])

        Multi.new()
        |> maybe_update_payload(template, payload, expected_version)
        |> Multi.run(:template, fn repo, changes ->
          current = Map.get(changes, :payload_template, template)

          current
          |> DashboardTemplate.changeset(metadata_attrs)
          |> repo.update()
        end)
        |> Repo.transaction()
        |> transaction_result(:template)
    end
  end

  def delete_user(
        %DashboardTemplate{} = template,
        %User{} = user,
        %OrganizationMembership{} = membership
      ) do
    cond do
      template.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      not can_manage?(template, user, membership) ->
        {:error, :forbidden}

      true ->
        Repo.transaction(fn ->
          locked =
            from(t in DashboardTemplate,
              where: t.id == ^template.id and t.organization_id == ^membership.organization_id,
              lock: "FOR UPDATE"
            )
            |> Repo.one!()

          if template_usage_count(locked) > 0 do
            Repo.rollback(:template_in_use)
          else
            Repo.delete!(locked)
          end
        end)
        |> case do
          {:ok, deleted} -> {:ok, deleted}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def convert_dashboard(
        %User{} = user,
        %OrganizationMembership{} = membership,
        %Dashboard{} = dashboard,
        attrs
      ) do
    cond do
      dashboard.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      not Dashboards.can_edit_dashboard?(dashboard, membership) ->
        {:error, :forbidden}

      not is_nil(dashboard.template_id) ->
        {:error, :already_template_backed}

      true ->
        template_changeset =
          DashboardTemplate.changeset(%DashboardTemplate{}, %{
            organization_id: membership.organization_id,
            created_by_id: user.id,
            name: template_name(attrs, dashboard),
            payload: dashboard.payload || %{}
          })

        Multi.new()
        |> Multi.insert(:template, template_changeset)
        |> Multi.run(:dashboard, fn repo, %{template: template} ->
          dashboard
          |> Dashboard.changeset(%{
            template_id: DashboardTemplateRef.encode(:user, template.id),
            payload: %{}
          })
          |> repo.update()
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{template: template, dashboard: updated_dashboard}} ->
            with {:ok, effective_dashboard} <- resolve_dashboard(updated_dashboard) do
              {:ok, %{template: template, dashboard: effective_dashboard}}
            end

          {:error, _operation, reason, _changes} ->
            {:error, reason}
        end
    end
  end

  def link_dashboard(
        %Dashboard{} = dashboard,
        %OrganizationMembership{} = membership,
        template_id
      ) do
    cond do
      dashboard.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      not Dashboards.can_edit_dashboard?(dashboard, membership) ->
        {:error, :forbidden}

      true ->
        Repo.transaction(fn ->
          case validate_reference(template_id, membership, lock: true) do
            {:ok, _template} ->
              dashboard
              |> Dashboard.changeset(%{template_id: template_id, payload: %{}})
              |> Repo.update!()

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, updated} -> resolve_dashboard(updated)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def update_dashboard_configuration(
        %Dashboard{} = dashboard,
        %OrganizationMembership{} = membership,
        attrs,
        template_id
      ) do
    template_id = normalize_template_selection(template_id)

    cond do
      template_id == dashboard.template_id ->
        Dashboards.update_dashboard_for_membership(dashboard, membership, attrs)

      is_nil(template_id) and is_nil(dashboard.template_id) ->
        Dashboards.update_dashboard_for_membership(dashboard, membership, attrs)

      is_nil(template_id) ->
        {:error, :template_detach_requires_context}

      true ->
        Repo.transaction(fn ->
          with {:ok, _template} <- validate_reference(template_id, membership, lock: true),
               {:ok, updated_dashboard} <-
                 Dashboards.update_dashboard_for_membership(dashboard, membership, attrs) do
            updated_dashboard
            |> Dashboard.changeset(%{template_id: template_id, payload: %{}})
            |> Repo.update!()
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, updated_dashboard} -> resolve_dashboard(updated_dashboard)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def detach_dashboard(%Dashboard{} = dashboard, %OrganizationMembership{} = membership) do
    cond do
      dashboard.organization_id != membership.organization_id ->
        {:error, :unauthorized}

      not Dashboards.can_edit_dashboard?(dashboard, membership) ->
        {:error, :forbidden}

      is_nil(dashboard.template_id) ->
        {:ok, dashboard}

      true ->
        Repo.transaction(fn ->
          with {:ok, effective} <- resolve_dashboard(dashboard, lock: true) do
            effective
            |> Dashboard.changeset(%{template_id: nil, payload: effective.payload || %{}})
            |> Ecto.Changeset.force_change(:payload, effective.payload || %{})
            |> Repo.update!()
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, updated} -> {:ok, clear_template_metadata(updated)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def resolve_dashboard(%Dashboard{} = dashboard, opts \\ []) do
    case DashboardTemplateRef.parse(dashboard.template_id) do
      :none -> {:ok, clear_template_metadata(dashboard)}
      {:ok, {:system, key}} -> resolve_system(dashboard, key)
      {:ok, {:user, id}} -> resolve_user(dashboard, id, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  def resolve_dashboard!(%Dashboard{} = dashboard) do
    case resolve_dashboard(dashboard) do
      {:ok, resolved} -> resolved
      {:error, reason} -> raise_template_resolution_error(reason)
    end
  end

  def resolve_dashboards(dashboards) when is_list(dashboards) do
    user_ids =
      dashboards
      |> Enum.flat_map(fn dashboard ->
        case DashboardTemplateRef.parse(dashboard.template_id) do
          {:ok, {:user, id}} -> [id]
          _ -> []
        end
      end)
      |> Enum.uniq()

    templates_by_id =
      from(t in DashboardTemplate, where: t.id in ^user_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    Enum.reduce_while(dashboards, {:ok, []}, fn dashboard, {:ok, acc} ->
      result =
        case DashboardTemplateRef.parse(dashboard.template_id) do
          :none -> {:ok, clear_template_metadata(dashboard)}
          {:ok, {:system, key}} -> resolve_system(dashboard, key)
          {:ok, {:user, id}} -> resolve_user_from_map(dashboard, id, templates_by_id)
          {:error, reason} -> {:error, reason}
        end

      case result do
        {:ok, resolved} -> {:cont, {:ok, [resolved | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  def resolve_dashboards!(dashboards) when is_list(dashboards) do
    case resolve_dashboards(dashboards) do
      {:ok, resolved} -> resolved
      {:error, reason} -> raise_template_resolution_error(reason)
    end
  end

  def validate_reference(template_id, %OrganizationMembership{} = membership, opts \\ []) do
    case DashboardTemplateRef.parse(template_id) do
      {:ok, {:system, key}} ->
        SystemDashboardTemplates.fetch(key)

      {:ok, {:user, id}} ->
        query =
          from(t in DashboardTemplate,
            where: t.id == ^id and t.organization_id == ^membership.organization_id
          )

        query = if Keyword.get(opts, :lock, false), do: lock(query, "FOR UPDATE"), else: query

        case Repo.one(query) do
          nil -> {:error, :template_not_found}
          template -> {:ok, template}
        end

      :none ->
        {:error, :invalid_template_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_user_payload(template_id, organization_id, payload, expected_version)
      when is_map(payload) and is_integer(expected_version) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    query =
      from(t in DashboardTemplate,
        where:
          t.id == ^template_id and t.organization_id == ^organization_id and
            t.lock_version == ^expected_version
      )

    case Repo.update_all(query,
           set: [payload: payload, updated_at: now],
           inc: [lock_version: 1]
         ) do
      {1, _} -> {:ok, Repo.get!(DashboardTemplate, template_id)}
      {0, _} -> {:error, :stale_template}
    end
  end

  def update_user_payload(_template_id, _organization_id, _payload, _expected_version),
    do: {:error, :template_version_required}

  def template_usage_count(%DashboardTemplate{} = template) do
    reference = DashboardTemplateRef.encode(:user, template.id)
    Repo.aggregate(from(d in Dashboard, where: d.template_id == ^reference), :count, :id)
  end

  def template_usage_counts(templates) when is_list(templates) do
    empty_counts = Map.new(templates, &{&1.id, 0})

    references =
      Map.new(templates, fn template ->
        {DashboardTemplateRef.encode(:user, template.id), template.id}
      end)

    from(d in Dashboard,
      where: d.template_id in ^Map.keys(references),
      group_by: d.template_id,
      select: {d.template_id, count(d.id)}
    )
    |> Repo.all()
    |> Map.new(fn {reference, count} -> {Map.fetch!(references, reference), count} end)
    |> then(&Map.merge(empty_counts, &1))
  end

  def can_manage?(%DashboardTemplate{} = template, %User{} = user, membership) do
    template.created_by_id == user.id || Organizations.membership_owner?(membership) ||
      Organizations.membership_admin?(membership)
  end

  defp resolve_system(dashboard, key) do
    with {:ok, template} <- SystemDashboardTemplates.fetch(key) do
      {:ok,
       %{
         dashboard
         | payload: template.payload,
           template_type: :system,
           template_name: template.name,
           template_version: template.version,
           template_read_only: true
       }}
    end
  end

  defp resolve_user(dashboard, id, opts) do
    query =
      from(t in DashboardTemplate,
        where: t.id == ^id and t.organization_id == ^dashboard.organization_id
      )

    query = if Keyword.get(opts, :lock, false), do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil -> {:error, :template_not_found}
      template -> {:ok, apply_user_template(dashboard, template)}
    end
  end

  defp resolve_user_from_map(dashboard, id, templates_by_id) do
    case Map.get(templates_by_id, id) do
      %DashboardTemplate{organization_id: organization_id} = template
      when organization_id == dashboard.organization_id ->
        {:ok, apply_user_template(dashboard, template)}

      _ ->
        {:error, :template_not_found}
    end
  end

  defp apply_user_template(dashboard, template) do
    %{
      dashboard
      | payload: template.payload,
        template_type: :user,
        template_name: template.name,
        template_version: template.lock_version,
        template_read_only: false
    }
  end

  defp clear_template_metadata(dashboard) do
    %{
      dashboard
      | template_type: nil,
        template_name: nil,
        template_version: nil,
        template_read_only: false
    }
  end

  defp system_descriptor(template) do
    %Descriptor{
      template_id: SystemDashboardTemplates.reference(template),
      type: :system,
      id: template.key,
      name: template.name,
      group: template.group,
      version: template.version,
      read_only: true
    }
  end

  defp user_descriptor(template) do
    %Descriptor{
      template_id: DashboardTemplateRef.encode(:user, template.id),
      type: :user,
      id: template.id,
      name: template.name,
      group: "Organization templates",
      version: template.lock_version,
      read_only: false
    }
  end

  defp maybe_update_payload(multi, _template, nil, _expected_version), do: multi

  defp maybe_update_payload(multi, template, payload, expected_version) when is_map(payload) do
    Multi.run(multi, :payload_template, fn _repo, _changes ->
      update_user_payload(template.id, template.organization_id, payload, expected_version)
    end)
  end

  defp maybe_update_payload(multi, _template, _payload, _expected_version) do
    Multi.error(multi, :payload_template, :invalid_payload)
  end

  defp transaction_result({:ok, changes}, key), do: {:ok, Map.fetch!(changes, key)}
  defp transaction_result({:error, _operation, reason, _changes}, _key), do: {:error, reason}

  defp raise_template_resolution_error(:template_not_found) do
    raise Ecto.NoResultsError, queryable: DashboardTemplate
  end

  defp raise_template_resolution_error(reason) do
    raise ResolutionError, reason: reason
  end

  defp template_name(attrs, dashboard) do
    attrs = stringify_keys(attrs)

    case Map.get(attrs, "name") do
      value when is_binary(value) and value != "" -> value
      _ -> dashboard.name || "Dashboard template"
    end
  end

  defp normalize_template_selection(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_template_selection(_value), do: nil

  defp fetch_integer(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} -> parsed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn
      {key, val} when is_atom(key) -> {Atom.to_string(key), val}
      pair -> pair
    end)
  end
end
