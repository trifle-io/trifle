defmodule Trifle.Billing.Access do
  @moduledoc """
  Billing access control and usage enforcement: whether an organization or
  project may be used (app entitlement, subscription state, grace periods,
  seat limits) and per-project event usage recording against plan hard
  limits.

  Rewritten into idiomatic Elixir from the decompiled `Trifle.Billing`
  source; behavior is intentionally identical.
  """

  import Ecto.Query, warn: false

  alias Trifle.Billing
  alias Trifle.Billing.Entitlement
  alias Trifle.Billing.Plan
  alias Trifle.Billing.ProjectUsage
  alias Trifle.Billing.Subscription
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.Organization
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Organizations.Project
  alias Trifle.Repo

  ## Source access

  def source_access_allowed?(:project, %Project{} = project) do
    ingest_allowed?(project)
  end

  def source_access_allowed?(:database, %{organization_id: organization_id})
      when is_binary(organization_id) do
    app_access_allowed_for_org_id(organization_id)
  end

  def source_access_allowed?(_, _), do: :ok

  def source_access_status(%Project{} = project) do
    source_access_status(:project, project)
  end

  def source_access_status(%Database{} = database) do
    source_access_status(:database, database)
  end

  def source_access_status(source_type, record) do
    :telemetry.span(
      [:trifle, :billing, :source_access_status],
      %{source_type: source_type},
      fn ->
        result = do_source_access_status(source_type, record)
        {result, %{source_type: source_type, active: result.active?}}
      end
    )
  end

  defp do_source_access_status(:project, %Project{} = project) do
    case source_access_allowed?(:project, project) do
      :ok ->
        %{billing_state: "active", active?: true, inactive_reason: nil}

      {:error, reason} ->
        %{
          billing_state: project_billing_state_for_reason(project, reason),
          active?: false,
          inactive_reason: source_inactive_reason(reason)
        }
    end
  end

  defp do_source_access_status(:database, %{organization_id: organization_id})
       when is_binary(organization_id) do
    case source_access_allowed?(:database, %{organization_id: organization_id}) do
      :ok ->
        %{billing_state: "active", active?: true, inactive_reason: nil}

      {:error, reason} ->
        %{
          billing_state: "locked",
          active?: false,
          inactive_reason: source_inactive_reason(reason)
        }
    end
  end

  defp do_source_access_status(_, _) do
    %{billing_state: "active", active?: true, inactive_reason: nil}
  end

  def source_access_status_reason(reason) do
    source_inactive_reason(reason)
  end

  def ingest_allowed?(%Project{} = project) do
    if Billing.enabled?() do
      with :ok <- app_access_allowed_for_org_id(project.organization_id),
           %Subscription{} = subscription <-
             Billing.get_scope_subscription(project.organization_id, "project", project.id),
           :ok <- ensure_subscription_allows_access(subscription),
           :ok <- ensure_project_usage_below_limit(project, subscription) do
        :ok
      else
        nil -> {:error, :project_subscription_required}
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  def app_access_allowed_for_org_id(organization_id) when is_binary(organization_id) do
    if Billing.enabled?() do
      case Billing.get_org_entitlement(organization_id) do
        %Entitlement{billing_locked: true, lock_reason: reason} when is_binary(reason) ->
          {:error, String.to_atom(reason)}

        %Entitlement{billing_locked: true} ->
          {:error, :billing_locked}

        %Entitlement{app_tier: tier} when is_binary(tier) and tier != "" ->
          :ok

        _ ->
          {:error, :missing_app_subscription}
      end
    else
      :ok
    end
  end

  def allowed_to_create_project?(%Organization{} = organization) do
    app_access_allowed_for_org_id(organization.id)
  end

  def allowed_to_add_member?(%Organization{} = organization) do
    with :ok <- app_access_allowed_for_org_id(organization.id),
         %Entitlement{} = entitlement <- Billing.get_org_entitlement(organization.id),
         :ok <- ensure_seat_available(organization.id, entitlement) do
      :ok
    else
      nil -> {:error, :billing_required}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Usage recording and limits

  def record_project_event_usage!(project, increment \\ 1)

  def record_project_event_usage!(%Project{} = project, increment)
      when is_integer(increment) and increment > 0 do
    if Billing.enabled?() do
      case Billing.get_scope_subscription(project.organization_id, "project", project.id) do
        %Subscription{} = subscription ->
          {period_start, period_end} = usage_period(subscription)
          hard_limit = project_hard_limit(subscription)
          tier_key = project_tier_key(subscription)

          attrs = %{
            project_id: project.id,
            period_start: period_start,
            period_end: period_end,
            events_count: increment,
            tier_key: tier_key,
            hard_limit: hard_limit,
            locked_at: nil
          }

          Repo.insert(
            ProjectUsage.changeset(%ProjectUsage{}, attrs),
            on_conflict: [
              inc: [events_count: increment],
              set: [
                period_end: period_end,
                tier_key: tier_key,
                hard_limit: hard_limit,
                updated_at: DateTime.truncate(DateTime.utc_now(), :second)
              ]
            ],
            conflict_target: [:project_id, :period_start]
          )

          usage = Repo.get_by!(ProjectUsage, project_id: project.id, period_start: period_start)

          maybe_mark_usage_locked(usage)

        nil ->
          {:error, :project_subscription_required}
      end
    else
      :ok
    end
  end

  @doc """
  Billing state string ("active"/"locked") for a project under a given
  subscription. Used by `Trifle.Billing.sync_project_billing_states/1`.
  """
  def project_state_from_subscription(%Project{} = project, %Subscription{} = subscription) do
    with :ok <- ensure_subscription_allows_access(subscription),
         :ok <- ensure_project_usage_below_limit(project, subscription) do
      "active"
    else
      {:error, :project_usage_limit_reached} -> "locked"
      {:error, _} -> "locked"
    end
  end

  @doc """
  Current period usage for a project; returns a zeroed placeholder when the
  project has no subscription or no usage row yet.
  """
  def current_usage(%Project{} = _project, nil) do
    %{events_count: 0, hard_limit: nil, tier_key: nil, period_start: nil, period_end: nil}
  end

  def current_usage(%Project{} = project, %Subscription{} = subscription) do
    {period_start, period_end} = usage_period(subscription)

    case Repo.get_by(ProjectUsage, project_id: project.id, period_start: period_start) do
      %ProjectUsage{} = usage ->
        usage

      nil ->
        %ProjectUsage{
          project_id: project.id,
          period_start: period_start,
          period_end: period_end,
          events_count: 0,
          tier_key: project_tier_key(subscription),
          hard_limit: project_hard_limit(subscription)
        }
    end
  end

  ## Private

  defp ensure_subscription_allows_access(%Subscription{} = subscription) do
    cond do
      subscription.status in ["active", "trialing"] ->
        :ok

      subscription.status in ["past_due", "unpaid"] and Subscription.in_grace?(subscription) ->
        :ok

      subscription.status in ["past_due", "unpaid"] ->
        {:error, :payment_grace_expired}

      true ->
        {:error, :subscription_inactive}
    end
  end

  defp ensure_seat_available(_organization_id, %Entitlement{seat_limit: nil}), do: :ok

  defp ensure_seat_available(organization_id, %Entitlement{seat_limit: seat_limit})
       when is_integer(seat_limit) and seat_limit > 0 do
    current_member_count =
      Repo.one(
        from(m in OrganizationMembership,
          where: m.organization_id == ^organization_id,
          select: count(m.id)
        )
      )

    if current_member_count < seat_limit do
      :ok
    else
      {:error, :seat_limit_reached}
    end
  end

  defp ensure_seat_available(_, _), do: :ok

  defp ensure_project_usage_below_limit(%Project{} = project, %Subscription{} = subscription) do
    case project_hard_limit(subscription) do
      nil ->
        :ok

      hard_limit when is_integer(hard_limit) and hard_limit > 0 ->
        usage = current_usage(project, subscription)

        if usage.events_count >= hard_limit do
          {:error, :project_usage_limit_reached}
        else
          :ok
        end
    end
  end

  defp maybe_mark_usage_locked(%ProjectUsage{} = usage) do
    cond do
      usage.hard_limit == nil ->
        {:ok, usage}

      usage.events_count < usage.hard_limit ->
        {:ok, usage}

      usage.locked_at != nil ->
        {:ok, usage}

      true ->
        case Repo.update(ProjectUsage.changeset(usage, %{locked_at: now()})) do
          {:ok, updated_usage} ->
            case Repo.get(Project, usage.project_id) do
              %Project{} = project ->
                project
                |> Ecto.Changeset.change(billing_state: "locked")
                |> Repo.update()

              _ ->
                :ok
            end

            {:ok, updated_usage}

          error ->
            error
        end
    end
  end

  defp usage_period(%Subscription{} = subscription) do
    period_start = subscription.current_period_start || beginning_of_month(now())
    period_end = subscription.current_period_end || end_of_month(period_start)
    {period_start, period_end}
  end

  defp project_hard_limit(%Subscription{} = subscription) do
    metadata_limit = Map.get(subscription.metadata || %{}, "project_hard_limit")

    cond do
      is_integer(metadata_limit) and metadata_limit > 0 ->
        metadata_limit

      is_binary(metadata_limit) ->
        parse_int(metadata_limit)

      true ->
        project_hard_limit_from_price_id(subscription.stripe_price_id)
    end
  end

  defp project_hard_limit_from_price_id(price_id) do
    case plan_for_price_id(price_id) do
      %Plan{} = plan -> Plan.project_hard_limit(plan)
      _ -> nil
    end
  end

  defp project_tier_key(%Subscription{} = subscription) do
    metadata = subscription.metadata || %{}

    Map.get(metadata, "project_tier") ||
      Map.get(metadata, :project_tier) ||
      project_tier_from_price_id(subscription.stripe_price_id)
  end

  defp project_tier_from_price_id(nil), do: nil

  defp project_tier_from_price_id(price_id) when is_binary(price_id) do
    case plan_for_price_id(price_id) do
      %Plan{} = plan -> Plan.project_tier(plan)
      _ -> nil
    end
  end

  defp plan_for_price_id(nil), do: nil

  defp plan_for_price_id(price_id) when is_binary(price_id) do
    Repo.get_by(Plan, stripe_price_id: price_id)
  end

  defp project_billing_state_for_reason(%Project{} = _project, reason) do
    case source_inactive_reason(reason) do
      :pending_checkout -> "pending_checkout"
      _ -> "locked"
    end
  end

  defp source_inactive_reason(:project_subscription_required), do: :pending_checkout
  defp source_inactive_reason(:pending_checkout), do: :pending_checkout
  defp source_inactive_reason(:missing_app_subscription), do: :missing_app_subscription
  defp source_inactive_reason(:billing_locked), do: :billing_locked
  defp source_inactive_reason(:subscription_inactive), do: :subscription_inactive
  defp source_inactive_reason(:payment_grace_expired), do: :payment_grace_expired
  defp source_inactive_reason(:project_usage_limit_reached), do: :project_usage_limit_reached
  defp source_inactive_reason(reason) when is_atom(reason), do: reason
  defp source_inactive_reason(_), do: :source_inactive

  defp beginning_of_month(%DateTime{} = datetime) do
    {:ok, date} = Date.new(datetime.year, datetime.month, 1)
    {:ok, naive} = NaiveDateTime.new(date, ~T[00:00:00])
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp end_of_month(%DateTime{} = period_start) do
    next_month =
      period_start
      |> DateTime.to_date()
      |> Date.end_of_month()
      |> Date.add(1)

    {:ok, naive} = NaiveDateTime.new(next_month, ~T[00:00:00])
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
