defmodule Trifle.Billing do
  defp usage_period(%Trifle.Billing.Subscription{} = subscription) do
    period_start =
      case subscription.current_period_start do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
          beginning_of_month(now())

        x ->
          x
      end

    period_end =
      case subscription.current_period_end do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
          end_of_month(period_start)

        x ->
          x
      end

    {period_start, period_end}
  end

  defp upsert_subscription(nil, attrs) do
    Trifle.Repo.insert(
      Trifle.Billing.Subscription.changeset(
        %Trifle.Billing.Subscription{
          __meta__: %{
            __struct__: Ecto.Schema.Metadata,
            context: nil,
            prefix: nil,
            schema: Trifle.Billing.Subscription,
            source: "billing_subscriptions",
            state: :built
          },
          cancel_at_period_end: false,
          current_period_end: nil,
          current_period_start: nil,
          founder_price: false,
          grace_until: nil,
          id: nil,
          inserted_at: nil,
          interval: nil,
          metadata: %{},
          organization: %{
            __cardinality__: :one,
            __field__: :organization,
            __owner__: Trifle.Billing.Subscription,
            __struct__: Ecto.Association.NotLoaded
          },
          organization_id: nil,
          scope_id: nil,
          scope_type: nil,
          status: nil,
          stripe_customer_id: nil,
          stripe_price_id: nil,
          stripe_subscription_id: nil,
          updated_at: nil
        },
        attrs
      )
    )
  end

  defp upsert_subscription(%Trifle.Billing.Subscription{} = subscription, attrs) do
    Trifle.Repo.update(
      Trifle.Billing.Subscription.changeset(
        subscription,
        attrs
      )
    )
  end

  defp upsert_entitlement(attrs) do
    case Trifle.Repo.get_by(Trifle.Billing.Entitlement, organization_id: attrs.organization_id) do
      nil ->
        Trifle.Repo.insert(
          Trifle.Billing.Entitlement.changeset(
            %Trifle.Billing.Entitlement{
              __meta__: %{
                __struct__: Ecto.Schema.Metadata,
                context: nil,
                prefix: nil,
                schema: Trifle.Billing.Entitlement,
                source: "billing_entitlements",
                state: :built
              },
              app_tier: nil,
              billing_locked: false,
              effective_at: nil,
              founder_offer_locked: false,
              id: nil,
              inserted_at: nil,
              lock_reason: nil,
              metadata: %{},
              organization: %{
                __cardinality__: :one,
                __field__: :organization,
                __owner__: Trifle.Billing.Entitlement,
                __struct__: Ecto.Association.NotLoaded
              },
              organization_id: nil,
              projects_enabled: false,
              seat_limit: nil,
              updated_at: nil
            },
            attrs
          )
        )

      %Trifle.Billing.Entitlement{} = entitlement ->
        Trifle.Repo.update(
          Trifle.Billing.Entitlement.changeset(
            entitlement,
            attrs
          )
        )
    end
  end

  defp update_existing_app_subscription(
         organization,
         subscription,
         price_id,
         tier,
         interval,
         founder?,
         opts
       ) do
    params =
      app_subscription_update_params(
        organization,
        nil,
        price_id,
        tier,
        interval,
        founder?,
        opts
      )

    with {:ok, subscription_item_id} <- resolve_subscription_item_id(subscription),
         params = put_in(params, ["items", Access.at(0), "id"], subscription_item_id),
         {:ok, payload} <-
           stripe_client_request(
             stripe_client(),
             :update_subscription,
             [subscription.stripe_subscription_id, params],
             idempotency_key:
               stripe_idempotency_key([
                 "app_subscription_update",
                 organization.id,
                 subscription.stripe_subscription_id,
                 price_id
               ])
           ),
         {:ok, organization_id} <-
           sync_subscription_from_stripe(payload, "customer.subscription.updated"),
         {:ok, _} <- refresh_entitlements!(organization_id) do
      {:ok, %{mode: :updated}}
    end
  end

  def update_billing_plan(%Trifle.Billing.Plan{} = plan, attrs) when :erlang.is_map(attrs) do
    Trifle.Repo.update(
      Trifle.Billing.Plan.changeset(
        plan,
        attrs
      )
    )
  end

  defp update_app_subscription?(%Trifle.Billing.Subscription{status: status})
       when :erlang.orelse(:erlang."=:="(status, "active"), :erlang."=:="(status, "trialing")) do
    true
  end

  defp update_app_subscription?(%Trifle.Billing.Subscription{status: status} = subscription)
       when :erlang.orelse(:erlang."=:="(status, "past_due"), :erlang."=:="(status, "unpaid")) do
    Trifle.Billing.Subscription.in_grace?(subscription)
  end

  defp update_app_subscription?(_) do
    false
  end

  defp unix_to_datetime(nil) do
    nil
  end

  defp unix_to_datetime(value) when :erlang.is_integer(value) do
    DateTime.truncate(
      DateTime.from_unix!(value),
      :second
    )
  end

  defp unix_to_datetime(value) when :erlang.is_binary(value) do
    case parse_int(value) do
      int when :erlang.andalso(:erlang.is_integer(int), :erlang.>(int, 0)) ->
        unix_to_datetime(int)

      _ ->
        nil
    end
  end

  defp unix_to_datetime(_) do
    nil
  end

  defp truthy?(value)
       when :erlang.orelse(
              :erlang.orelse(
                :erlang.orelse(
                  :erlang.orelse(
                    :erlang.orelse(
                      :erlang.orelse(:erlang."=:="(value, true), :erlang."=:="(value, 1)),
                      :erlang."=:="(value, "1")
                    ),
                    :erlang."=:="(value, "true")
                  ),
                  :erlang."=:="(value, "TRUE")
                ),
                :erlang."=:="(value, "yes")
              ),
              :erlang."=:="(value, "on")
            ) do
    true
  end

  defp truthy?(_) do
    false
  end

  defp sync_subscription_from_stripe(payload, event_type) do
    with {:ok, stripe_subscription_id} <- fetch_required_string(payload, "id"),
         {:ok, organization_id} <- resolve_organization_id_from_subscription(payload),
         {:ok, scope_type} <- resolve_scope_type(payload),
         {:ok, scope_id} <- resolve_scope_id(payload, scope_type) do
      subscription_by_stripe_id =
        Trifle.Repo.get_by(Trifle.Billing.Subscription,
          stripe_subscription_id: stripe_subscription_id
        )

      scope_subscription =
        maybe_scope_subscription_for_upsert(
          organization_id,
          scope_type,
          scope_id,
          event_type,
          Map.get(payload, "status")
        )

      subscription =
        case subscription_by_stripe_id do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
            scope_subscription

          x ->
            x
        end

      cond do
        (case :erlang.==(event_type, "customer.subscription.deleted") do
           false -> false
           true -> :erlang.==(subscription, nil)
         end) ->
          {:ok, organization_id}

        (case (case :erlang.==(event_type, "customer.subscription.updated") do
                 false -> false
                 true -> :erlang.==(subscription, nil)
               end) do
           false -> false
           true -> :erlang.not(should_upsert_by_scope?(event_type, Map.get(payload, "status")))
         end) ->
          {:ok, organization_id}

        stale_scope_subscription_event?(
          subscription_by_stripe_id,
          scope_subscription,
          payload,
          stripe_subscription_id
        ) ->
          {:ok, organization_id}

        true ->
          with {:ok, attrs} <-
                 build_subscription_attrs(
                   payload,
                   organization_id,
                   stripe_subscription_id,
                   scope_type,
                   scope_id,
                   subscription
                 ),
               {:ok, _record} <- upsert_subscription(subscription, attrs) do
            {:ok, organization_id}
          end
      end
    end
  end

  defp sync_project_billing_states(organization_id) do
    locked_org = billing_locked_for_org?(organization_id)
    projects = Trifle.Organizations.list_projects_for_org(organization_id)

    Enum.each(projects, fn project ->
      state =
        cond do
          locked_org ->
            "locked"

          true ->
            case get_scope_subscription(organization_id, "project", project.id) do
              nil ->
                "pending_checkout"

              %Trifle.Billing.Subscription{} = subscription ->
                project_state_from_subscription(project, subscription)
            end
        end

      case :erlang."/="(state, project.billing_state) do
        false ->
          nil

        true ->
          Trifle.Repo.update_all(
            %{
              offset: nil,
              select: nil,
              sources: nil,
              prefix: nil,
              windows: [],
              aliases: %{},
              lock: nil,
              limit: nil,
              __struct__: Ecto.Query,
              from: %Ecto.Query.FromExpr{
                source:
                  {Trifle.Organizations.Project.__schema__(:source), Trifle.Organizations.Project},
                params: [],
                as: nil,
                prefix: Trifle.Organizations.Project.__schema__(:prefix),
                hints: [],
                file: "/workspaces/trifle/lib/trifle/billing.ex",
                line: 1315
              },
              joins: [],
              combinations: [],
              distinct: nil,
              with_ctes: nil,
              wheres: [
                %Ecto.Query.BooleanExpr{
                  expr: {:==, [], [{{:., [], [{:&, [], [0]}, :id]}, [], []}, {:^, [], [0]}]},
                  op: :and,
                  params: [{Ecto.Query.Builder.not_nil!(project.id, "p.id"), {0, :id}}],
                  subqueries: [],
                  file: "/workspaces/trifle/lib/trifle/billing.ex",
                  line: 1315
                }
              ],
              updates: [],
              assocs: [],
              preloads: [],
              order_bys: [],
              havings: [],
              group_bys: []
            },
            set: [billing_state: state]
          )
      end
    end)
  end

  defp subscription_lock_state(%Trifle.Billing.Subscription{} = subscription) do
    cond do
      :lists.member(subscription.status, ["active", "trialing"]) ->
        {false, nil}

      (case :lists.member(subscription.status, ["past_due", "unpaid"]) do
         false -> false
         true -> Trifle.Billing.Subscription.in_grace?(subscription)
         other -> :erlang.error({:badbool, :and, other})
       end) ->
        {false, nil}

      :lists.member(subscription.status, ["past_due", "unpaid"]) ->
        {true, "payment_grace_expired"}

      (
        var = subscription.status

        :erlang.orelse(
          :erlang.orelse(
            :erlang.orelse(:erlang."=:="(var, "canceled"), :erlang."=:="(var, "incomplete")),
            :erlang."=:="(var, "incomplete_expired")
          ),
          :erlang."=:="(var, "paused")
        )
      ) ->
        {true, "subscription_inactive"}

      true ->
        {true, "subscription_inactive"}
    end
  end

  defp stripe_client() do
    Keyword.get(
      Application.get_env(:trifle, Trifle.Billing, []),
      :stripe_client,
      Trifle.Billing.StripeClient.HTTP
    )
  end

  defp stripe_client_request(module, function, args, opts) do
    args_with_opts = args ++ [opts]

    if function_exported?(module, function, length(args_with_opts)) do
      apply(module, function, args_with_opts)
    else
      apply(module, function, args)
    end
  end

  defp stripe_idempotency_key(parts) when is_list(parts) do
    digest =
      parts
      |> Enum.map(&to_string/1)
      |> Enum.join(":")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "trifle:#{digest}"
  end

  defp stale_scope_subscription_event?(
         %Trifle.Billing.Subscription{},
         _scope_subscription,
         _payload,
         _incoming_subscription_id
       ) do
    false
  end

  defp stale_scope_subscription_event?(
         nil,
         %Trifle.Billing.Subscription{} = scope_subscription,
         payload,
         incoming_subscription_id
       ) do
    incoming_period_start = unix_to_datetime(Map.get(payload, "current_period_start"))

    case (case (case :erlang."/="(
                       scope_subscription.stripe_subscription_id,
                       incoming_subscription_id
                     ) do
                  false ->
                    false

                  true ->
                    case DateTime do
                      name when :erlang.is_atom(name) ->
                        case incoming_period_start do
                          %{__struct__: ^name} -> true
                          _ -> false
                        end

                      _ ->
                        :erlang.error(ArgumentError.exception([]), :none,
                          error_info: %{module: Exception}
                        )
                    end
                end) do
            false ->
              false

            true ->
              case DateTime do
                name when :erlang.is_atom(name) ->
                  case scope_subscription.current_period_start do
                    %{__struct__: ^name} -> true
                    _ -> false
                  end

                _ ->
                  :erlang.error(ArgumentError.exception([]), :none,
                    error_info: %{module: Exception}
                  )
              end

            other ->
              :erlang.error({:badbool, :and, other})
          end) do
      false ->
        false

      true ->
        :erlang.==(
          DateTime.compare(incoming_period_start, scope_subscription.current_period_start),
          :lt
        )

      other ->
        :erlang.error({:badbool, :and, other})
    end
  end

  defp stale_scope_subscription_event?(_, _, _, _) do
    false
  end

  def source_access_allowed?(:project, %Trifle.Organizations.Project{} = project) do
    ingest_allowed?(project)
  end

  def source_access_allowed?(:database, %{organization_id: organization_id})
      when :erlang.is_binary(organization_id) do
    app_access_allowed_for_org_id(organization_id)
  end

  def source_access_allowed?(_, _) do
    :ok
  end

  defp should_upsert_by_scope?("customer.subscription.created", _status) do
    true
  end

  defp should_upsert_by_scope?("customer.subscription.updated", status)
       when :erlang.orelse(
              :erlang.orelse(
                :erlang.orelse(
                  :erlang.orelse(
                    :erlang.orelse(
                      :erlang."=:="(status, "active"),
                      :erlang."=:="(status, "trialing")
                    ),
                    :erlang."=:="(status, "past_due")
                  ),
                  :erlang."=:="(status, "unpaid")
                ),
                :erlang."=:="(status, "incomplete")
              ),
              :erlang."=:="(status, "paused")
            ) do
    true
  end

  defp should_upsert_by_scope?(_, _) do
    false
  end

  def set_billing_plan_active(%Trifle.Billing.Plan{} = plan, active?)
      when :erlang.is_boolean(active?) do
    update_billing_plan(plan, %{active: active?})
  end

  defp seat_limit_for_subscription(%Trifle.Billing.Subscription{} = subscription) do
    metadata_limit =
      case Map.get(
             case subscription.metadata do
               x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
               x -> x
             end,
             "seat_limit"
           ) do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
          Map.get(
            case subscription.metadata do
              x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
              x -> x
            end,
            :seat_limit
          )

        x ->
          x
      end

    cond do
      (case :erlang.is_integer(metadata_limit) do
         false -> false
         true -> :erlang.>(metadata_limit, 0)
       end) ->
        metadata_limit

      :erlang.is_binary(metadata_limit) ->
        parse_int(metadata_limit)

      true ->
        app_seat_limit_from_price_id(subscription.stripe_price_id)
    end
  end

  defp resolved_project_base_plans(organization_id) do
    resolved_plans_for_scope("project", organization_id, false, false)
  end

  defp resolved_plans_for_scope(scope_type, organization_id, retention_add_on, founder_offer) do
    query = %{
      offset: nil,
      select: nil,
      sources: nil,
      prefix: nil,
      windows: [],
      aliases: %{},
      lock: nil,
      limit: nil,
      __struct__: Ecto.Query,
      from: %Ecto.Query.FromExpr{
        source: {Trifle.Billing.Plan.__schema__(:source), Trifle.Billing.Plan},
        params: [],
        as: nil,
        prefix: Trifle.Billing.Plan.__schema__(:prefix),
        hints: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 1666
      },
      joins: [],
      combinations: [],
      distinct: nil,
      with_ctes: nil,
      wheres: [
        %Ecto.Query.BooleanExpr{
          expr:
            {:and, [],
             [
               {:and, [],
                [
                  {:and, [],
                   [
                     {{:., [], [{:&, [], [0]}, :active]}, [], []},
                     {:==, [], [{{:., [], [{:&, [], [0]}, :scope_type]}, [], []}, {:^, [], [0]}]}
                   ]},
                  {:==, [],
                   [{{:., [], [{:&, [], [0]}, :retention_add_on]}, [], []}, {:^, [], [1]}]}
                ]},
               {:==, [], [{{:., [], [{:&, [], [0]}, :founder_offer]}, [], []}, {:^, [], [2]}]}
             ]},
          op: :and,
          params: [
            {Ecto.Query.Builder.not_nil!(
               scope_type,
               "p.scope_type"
             ), {0, :scope_type}},
            {Ecto.Query.Builder.not_nil!(
               retention_add_on,
               "p.retention_add_on"
             ), {0, :retention_add_on}},
            {Ecto.Query.Builder.not_nil!(
               founder_offer,
               "p.founder_offer"
             ), {0, :founder_offer}}
          ],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 1666
        }
      ],
      updates: [],
      assocs: [],
      preloads: [],
      order_bys: [],
      havings: [],
      group_bys: []
    }

    query =
      case organization_id do
        value when :erlang.is_binary(value) ->
          query = Ecto.Query.Builder.From.apply(query, 1, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr:
              {:or, [],
               [
                 {:is_nil, [], [{{:., [], [{:&, [], [0]}, :organization_id]}, [], []}]},
                 {:==, [], [{{:., [], [{:&, [], [0]}, :organization_id]}, [], []}, {:^, [], [0]}]}
               ]},
            op: :and,
            params: [
              {Ecto.Query.Builder.not_nil!(value, "p.organization_id"), {0, :organization_id}}
            ],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 1677
          })

        _ ->
          query = Ecto.Query.Builder.From.apply(query, 1, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr: {:is_nil, [], [{{:., [], [{:&, [], [0]}, :organization_id]}, [], []}]},
            op: :and,
            params: [],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 1680
          })
      end

    resolve_plan_precedence(
      Trifle.Repo.all(query),
      organization_id
    )
  end

  defp resolved_app_subscription_plans(organization_id) do
    resolved_plans_for_scope("app", organization_id, false, false)
  end

  defp resolve_subscription_item_id(%Trifle.Billing.Subscription{} = subscription) do
    metadata =
      case subscription.metadata do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
        x -> x
      end

    item_id =
      case Map.get(metadata, "subscription_item_id") do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
          Map.get(metadata, :subscription_item_id)

        x ->
          x
      end

    case item_id do
      value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        {:ok, value}

      _ ->
        with {:ok, payload} <-
               stripe_client().get_subscription(subscription.stripe_subscription_id),
             value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) <-
               first_subscription_item_id(payload) do
          {:ok, value}
        else
          _ -> {:error, :subscription_item_not_found}
        end
    end
  end

  defp resolve_scope_type(payload) do
    metadata =
      case Map.get(payload, "metadata") do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
        x -> x
      end

    case (case Map.get(metadata, "scope_type") do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
              Map.get(metadata, :scope_type)

            x ->
              x
          end) do
      "project" -> {:ok, "project"}
      "app" -> {:ok, "app"}
      nil -> {:ok, "app"}
      _ -> {:error, :invalid_scope_type}
    end
  end

  defp resolve_scope_id(_payload, "app") do
    {:ok, nil}
  end

  defp resolve_scope_id(payload, "project") do
    metadata =
      case Map.get(payload, "metadata") do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
        x -> x
      end

    case (case Map.get(metadata, "scope_id") do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
              Map.get(metadata, :scope_id)

            x ->
              x
          end) do
      value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        {:ok, value}

      _ ->
        {:error, :scope_id_missing}
    end
  end

  defp resolve_plan_precedence(plans, organization_id) do
    :maps.values(
      Enum.reduce(plans, %{}, fn plan, acc ->
        key =
          {plan.scope_type, plan.tier_key, plan.interval, plan.retention_add_on,
           plan.founder_offer}

        existing = Map.get(acc, key)

        cond do
          :erlang.==(existing, nil) -> :maps.put(key, plan, acc)
          prefers_plan?(existing, plan, organization_id) -> :maps.put(key, plan, acc)
          true -> acc
        end
      end)
    )
  end

  defp resolve_organization_id_from_subscription(payload) do
    metadata =
      case Map.get(payload, "metadata") do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
        x -> x
      end

    org_id =
      case (case Map.get(metadata, "organization_id") do
              x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
                Map.get(metadata, :organization_id)

              x ->
                x
            end) do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
          organization_id_from_customer(Map.get(payload, "customer"))

        x ->
          x
      end

    case org_id do
      value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        {:ok, value}

      _ ->
        {:error, :organization_id_missing}
    end
  end

  defp reserve_founder_slot(organization_id) when :erlang.is_binary(organization_id) do
    case Trifle.Repo.transaction(fn ->
           case Trifle.Repo.get_by(Trifle.Billing.FounderClaim, organization_id: organization_id) do
             %Trifle.Billing.FounderClaim{} = claim ->
               claim

             nil ->
               Trifle.Repo.query!("LOCK TABLE billing_founder_claims IN EXCLUSIVE MODE")
               current_count = Trifle.Repo.aggregate(Trifle.Billing.FounderClaim, :count, :id)

               case :erlang.>=(current_count, 20) do
                 false ->
                   slot_number = :erlang.+(current_count, 1)

                   Trifle.Repo.insert!(
                     Trifle.Billing.FounderClaim.changeset(
                       %Trifle.Billing.FounderClaim{
                         __meta__: %{
                           __struct__: Ecto.Schema.Metadata,
                           context: nil,
                           prefix: nil,
                           schema: Trifle.Billing.FounderClaim,
                           source: "billing_founder_claims",
                           state: :built
                         },
                         claimed_at: nil,
                         id: nil,
                         inserted_at: nil,
                         organization: %{
                           __cardinality__: :one,
                           __field__: :organization,
                           __owner__: Trifle.Billing.FounderClaim,
                           __struct__: Ecto.Association.NotLoaded
                         },
                         organization_id: nil,
                         slot_number: nil,
                         updated_at: nil
                       },
                       %{
                         organization_id: organization_id,
                         slot_number: slot_number,
                         claimed_at: now()
                       }
                     )
                   )

                 true ->
                   Trifle.Repo.rollback(:sold_out)
               end
           end
         end) do
      {:ok, claim} -> {:ok, claim}
      {:error, :sold_out} -> {:error, :sold_out}
      {:error, reason} -> {:error, reason}
    end
  end

  def refresh_entitlements!(%Trifle.Organizations.Organization{} = organization) do
    refresh_entitlements!(organization.id)
  end

  def refresh_entitlements!(organization_id) when :erlang.is_binary(organization_id) do
    case enabled?() do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        {:ok, nil}

      _ ->
        app_subscription = get_scope_subscription(organization_id, "app", nil)
        founder_locked = founder_locked?(organization_id, app_subscription)

        attrs =
          case app_subscription do
            nil ->
              %{
                organization_id: organization_id,
                app_tier: nil,
                seat_limit: nil,
                projects_enabled: false,
                billing_locked: true,
                lock_reason: "missing_app_subscription",
                founder_offer_locked: founder_locked,
                effective_at: now(),
                metadata: %{}
              }

            %Trifle.Billing.Subscription{} = subscription ->
              tier = app_tier(subscription)
              seat_limit = seat_limit_for_subscription(subscription)
              {locked, reason} = subscription_lock_state(subscription)

              %{
                organization_id: organization_id,
                app_tier: tier,
                seat_limit: seat_limit,
                projects_enabled:
                  case :erlang.not(locked) do
                    false -> false
                    true -> :erlang.is_binary(tier)
                  end,
                billing_locked: locked,
                lock_reason: reason,
                founder_offer_locked: founder_locked,
                effective_at: now(),
                metadata: %{
                  "subscription_id" => subscription.stripe_subscription_id,
                  "stripe_price_id" => subscription.stripe_price_id,
                  "status" => subscription.status
                }
              }
          end

        upsert_entitlement(attrs)
        sync_project_billing_states(organization_id)
        {:ok, get_org_entitlement(organization_id)}
    end
  end

  def record_project_event_usage!(%Trifle.Organizations.Project{} = project, increment)
      when :erlang.andalso(:erlang.is_integer(increment), :erlang.>(increment, 0)) do
    case enabled?() do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        :ok

      _ ->
        case get_scope_subscription(project.organization_id, "project", project.id) do
          %Trifle.Billing.Subscription{} = subscription ->
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

            Trifle.Repo.insert(
              Trifle.Billing.ProjectUsage.changeset(
                %Trifle.Billing.ProjectUsage{
                  __meta__: %{
                    __struct__: Ecto.Schema.Metadata,
                    context: nil,
                    prefix: nil,
                    schema: Trifle.Billing.ProjectUsage,
                    source: "project_billing_usage",
                    state: :built
                  },
                  events_count: 0,
                  hard_limit: nil,
                  id: nil,
                  inserted_at: nil,
                  locked_at: nil,
                  period_end: nil,
                  period_start: nil,
                  project: %{
                    __cardinality__: :one,
                    __field__: :project,
                    __owner__: Trifle.Billing.ProjectUsage,
                    __struct__: Ecto.Association.NotLoaded
                  },
                  project_id: nil,
                  tier_key: nil,
                  updated_at: nil
                },
                attrs
              ),
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

            usage =
              Trifle.Repo.get_by!(Trifle.Billing.ProjectUsage,
                project_id: project.id,
                period_start: period_start
              )

            maybe_mark_usage_locked(usage)

          nil ->
            {:error, :project_subscription_required}
        end
    end
  end

  def record_project_event_usage!(x0) do
    record_project_event_usage!(x0, 1)
  end

  defp project_tier_order("100k") do
    1
  end

  defp project_tier_order("500k") do
    2
  end

  defp project_tier_order("1m") do
    3
  end

  defp project_tier_order("3m") do
    4
  end

  defp project_tier_order("6m") do
    5
  end

  defp project_tier_order("10m") do
    6
  end

  defp project_tier_order(_) do
    99
  end

  defp project_tier_key(%Trifle.Billing.Subscription{} = subscription) do
    case (case Map.get(
                 case subscription.metadata do
                   x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
                   x -> x
                 end,
                 "project_tier"
               ) do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
              Map.get(
                case subscription.metadata do
                  x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
                  x -> x
                end,
                :project_tier
              )

            x ->
              x
          end) do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        project_tier_from_price_id(subscription.stripe_price_id)

      x ->
        x
    end
  end

  defp project_tier_from_price_id(nil) do
    nil
  end

  defp project_tier_from_price_id(price_id) when :erlang.is_binary(price_id) do
    case plan_for_price_id(price_id) do
      %Trifle.Billing.Plan{} = plan -> project_tier_from_plan(plan)
      _ -> nil
    end
  end

  defp project_tier_from_plan(%Trifle.Billing.Plan{scope_type: "project", tier_key: tier_key}) do
    tier_key
  end

  defp project_tier_from_plan(_) do
    nil
  end

  defp project_state_from_subscription(
         %Trifle.Organizations.Project{} = project,
         %Trifle.Billing.Subscription{} = subscription
       ) do
    with :ok <- ensure_subscription_allows_access(subscription),
         :ok <- ensure_project_usage_below_limit(project, subscription) do
      "active"
    else
      {:error, :project_usage_limit_reached} -> "locked"
      {:error, _} -> "locked"
    end
  end

  defp project_hard_limit_from_price_id(price_id) do
    case plan_for_price_id(price_id) do
      %Trifle.Billing.Plan{} = plan -> project_hard_limit_from_plan(plan)
      _ -> nil
    end
  end

  defp project_hard_limit_from_plan(%Trifle.Billing.Plan{
         scope_type: "project",
         hard_limit: hard_limit
       }) do
    hard_limit
  end

  defp project_hard_limit_from_plan(_) do
    nil
  end

  defp project_hard_limit(%Trifle.Billing.Subscription{} = subscription) do
    metadata_limit =
      Map.get(
        case subscription.metadata do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
          x -> x
        end,
        "project_hard_limit"
      )

    cond do
      (case :erlang.is_integer(metadata_limit) do
         false -> false
         true -> :erlang.>(metadata_limit, 0)
       end) ->
        metadata_limit

      :erlang.is_binary(metadata_limit) ->
        parse_int(metadata_limit)

      true ->
        project_hard_limit_from_price_id(subscription.stripe_price_id)
    end
  end

  defp project_checkout_params(organization, customer, project, tier_key, retention_enabled, opts) do
    with {:ok, project_price_id, project_plan} <- fetch_project_price(organization.id, tier_key),
         {:ok, line_items} <-
           maybe_add_retention_line_item(
             [%{"price" => project_price_id, "quantity" => 1}],
             organization.id,
             tier_key,
             retention_enabled
           ) do
      metadata = %{
        "organization_id" => organization.id,
        "scope_type" => "project",
        "scope_id" => project.id,
        "project_tier" => tier_key,
        "project_hard_limit" => project_plan.hard_limit,
        "extended_retention" =>
          case retention_enabled do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> "false"
            _ -> "true"
          end
      }

      {:ok,
       %{
         "mode" => "subscription",
         "customer" => customer.stripe_customer_id,
         "client_reference_id" => organization.id,
         "success_url" => checkout_success_url(opts),
         "cancel_url" => checkout_cancel_url(opts),
         "line_items" => line_items,
         "subscription_data" => %{"metadata" => metadata}
       }}
    end
  end

  def process_webhook_event(webhook_event_id) when :erlang.is_binary(webhook_event_id) do
    case Trifle.Repo.get(Trifle.Billing.WebhookEvent, webhook_event_id) do
      nil -> {:error, :not_found}
      %Trifle.Billing.WebhookEvent{status: "processed"} = event -> {:ok, event}
      %Trifle.Billing.WebhookEvent{} = event -> process_and_mark_event(event)
    end
  end

  def process_stripe_event(payload) when :erlang.is_map(payload) do
    event_type = Map.get(payload, "type")

    data =
      case Kernel.get_in(payload, ["data", "object"]) do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
        x -> x
      end

    case event_type do
      type
      when :erlang.orelse(
             :erlang."=:="(type, "customer.subscription.created"),
             :erlang."=:="(type, "customer.subscription.updated")
           ) ->
        with {:ok, organization_id} <- sync_subscription_from_stripe(data, type),
             {:ok, _} <- refresh_entitlements!(organization_id) do
          :ok
        end

      "customer.subscription.deleted" ->
        with {:ok, organization_id} <-
               sync_subscription_from_stripe(data, "customer.subscription.deleted"),
             {:ok, _} <- refresh_entitlements!(organization_id) do
          :ok
        end

      "invoice.payment_failed" ->
        with {:ok, organization_id} <- handle_payment_failed(data),
             {:ok, _} <- refresh_entitlements!(organization_id) do
          :ok
        end

      "invoice.payment_succeeded" ->
        with {:ok, organization_id} <- handle_payment_succeeded(data),
             {:ok, _} <- refresh_entitlements!(organization_id) do
          :ok
        end

      "checkout.session.completed" ->
        maybe_refresh_org_from_checkout_session(data)

      _ ->
        :ok
    end
  end

  defp process_and_mark_event(%Trifle.Billing.WebhookEvent{} = event) do
    result = process_stripe_event(event.payload)

    case result do
      :ok ->
        Trifle.Repo.update(
          Trifle.Billing.WebhookEvent.changeset(
            event,
            %{status: "processed", processed_at: now(), error: nil}
          )
        )

      {:ok, _} ->
        Trifle.Repo.update(
          Trifle.Billing.WebhookEvent.changeset(
            event,
            %{status: "processed", processed_at: now(), error: nil}
          )
        )

      {:error, reason} ->
        Trifle.Repo.update(
          Trifle.Billing.WebhookEvent.changeset(
            event,
            %{status: "failed", processed_at: now(), error: Kernel.inspect(reason)}
          )
        )
    end
  end

  defp prefers_plan?(
         %Trifle.Billing.Plan{} = existing,
         %Trifle.Billing.Plan{} = candidate,
         organization_id
       )
       when :erlang.is_binary(organization_id) do
    case :erlang.==(existing.organization_id, nil) do
      false -> false
      true -> :erlang.==(candidate.organization_id, organization_id)
    end
  end

  defp prefers_plan?(_existing, _candidate, _organization_id) do
    false
  end

  defp portal_session_params(customer, opts) do
    params = %{
      "customer" => customer.stripe_customer_id,
      "return_url" => portal_return_url(opts),
      "locale" => "auto"
    }

    case portal_configuration_id() do
      value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        :maps.put("configuration", value, params)

      _ ->
        params
    end
  end

  defp portal_return_url(opts) do
    case (case Map.get(opts, :return_url) do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
              Map.get(opts, "return_url")

            x ->
              x
          end) do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        "https://app.trifle.io/organization/billing"

      x ->
        x
    end
  end

  defp portal_configuration_id() do
    System.get_env("STRIPE_PORTAL_CONFIGURATION_ID")
  end

  defp plan_for_price_id(nil) do
    nil
  end

  defp plan_for_price_id(price_id) when :erlang.is_binary(price_id) do
    Trifle.Repo.get_by(Trifle.Billing.Plan, stripe_price_id: price_id)
  end

  def plan_for_subscription(nil), do: nil

  def plan_for_subscription(%Trifle.Billing.Subscription{stripe_price_id: price_id}) do
    plan_for_price_id(price_id)
  end

  defp parse_int(value) when :erlang.is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_) do
    nil
  end

  defp organization_id_from_customer(stripe_customer_id)
       when :erlang.is_binary(stripe_customer_id) do
    case Trifle.Repo.get_by(Trifle.Billing.Customer, stripe_customer_id: stripe_customer_id) do
      %Trifle.Billing.Customer{organization_id: organization_id} -> organization_id
      nil -> nil
    end
  end

  defp organization_id_from_customer(_) do
    nil
  end

  defp organization_for_project(%Trifle.Organizations.Project{} = project) do
    case Trifle.Organizations.get_organization(project.organization_id) do
      %Trifle.Organizations.Organization{} = organization -> {:ok, %{organization: organization}}
      nil -> {:error, :organization_not_found}
    end
  end

  defp organization_contact_email(%Trifle.Organizations.Organization{} = organization) do
    with %Trifle.Organizations.OrganizationMembership{} = owner <-
           Trifle.Repo.one(%{
             offset: nil,
             select: nil,
             sources: nil,
             prefix: nil,
             windows: [],
             aliases: %{},
             lock: nil,
             limit: %Ecto.Query.LimitExpr{
               with_ties: false,
               expr: 1,
               params: [],
               file: "/workspaces/trifle/lib/trifle/billing.ex",
               line: 1852
             },
             __struct__: Ecto.Query,
             from: %Ecto.Query.FromExpr{
               source:
                 {Trifle.Organizations.OrganizationMembership.__schema__(:source),
                  Trifle.Organizations.OrganizationMembership},
               params: [],
               as: nil,
               prefix: Trifle.Organizations.OrganizationMembership.__schema__(:prefix),
               hints: [],
               file: "/workspaces/trifle/lib/trifle/billing.ex",
               line: 1852
             },
             joins: [],
             combinations: [],
             distinct: nil,
             with_ctes: nil,
             wheres: [
               %Ecto.Query.BooleanExpr{
                 expr:
                   {:and, [],
                    [
                      {:==, [],
                       [{{:., [], [{:&, [], [0]}, :organization_id]}, [], []}, {:^, [], [0]}]},
                      {:==, [],
                       [
                         {{:., [], [{:&, [], [0]}, :role]}, [], []},
                         %Ecto.Query.Tagged{tag: nil, value: "owner", type: {0, :role}}
                       ]}
                    ]},
                 op: :and,
                 params: [
                   {Ecto.Query.Builder.not_nil!(
                      organization.id,
                      "m.organization_id"
                    ), {0, :organization_id}}
                 ],
                 subqueries: [],
                 file: "/workspaces/trifle/lib/trifle/billing.ex",
                 line: 1852
               }
             ],
             updates: [],
             assocs: [],
             preloads: [:user],
             order_bys: [],
             havings: [],
             group_bys: []
           }),
         email when :erlang.is_binary(email) <-
           (case owner.user do
              x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> x
              _ -> owner.user.email
            end) do
      email
    else
      _ -> nil
    end
  end

  defp now() do
    DateTime.truncate(DateTime.utc_now(), :second)
  end

  defp normalize_scope(scope)
       when :erlang.orelse(
              :erlang.orelse(:erlang."=:="(scope, "all"), :erlang."=:="(scope, "app")),
              :erlang."=:="(scope, "project")
            ) do
    scope
  end

  defp normalize_scope(scope) when :erlang.is_binary(scope) do
    String.downcase(String.trim(scope))
  end

  defp normalize_scope(_) do
    "all"
  end

  defp normalize_project_tier(tier_key) when :erlang.is_binary(tier_key) do
    normalized = String.downcase(String.trim(tier_key))

    case :erlang."/="(normalized, "") do
      false -> {:error, :invalid_project_tier}
      true -> {:ok, normalized}
    end
  end

  defp normalize_project_tier(_) do
    {:error, :invalid_project_tier}
  end

  defp normalize_app_tier(tier) when :erlang.is_binary(tier) do
    tier = String.downcase(String.trim(tier))

    case :erlang."/="(tier, "") do
      false -> {:error, :invalid_app_tier}
      true -> {:ok, tier}
    end
  end

  defp normalize_app_tier(_) do
    {:error, :invalid_app_tier}
  end

  defp normalize_app_interval(interval) when :erlang.is_binary(interval) do
    normalized = String.downcase(String.trim(interval))

    case normalized do
      "month" -> {:ok, "month"}
      "monthly" -> {:ok, "month"}
      "year" -> {:ok, "year"}
      "yearly" -> {:ok, "year"}
      _ -> {:error, :invalid_app_interval}
    end
  end

  defp normalize_app_interval(_) do
    {:error, :invalid_app_interval}
  end

  defp maybe_scope_subscription_for_upsert(
         organization_id,
         scope_type,
         scope_id,
         event_type,
         payload_status
       ) do
    case should_upsert_by_scope?(event_type, payload_status) do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> nil
      _ -> get_scope_subscription(organization_id, scope_type, scope_id)
    end
  end

  defp maybe_refresh_org_from_checkout_session(payload) do
    with org_id when :erlang.andalso(:erlang.is_binary(org_id), :erlang."/="(org_id, "")) <-
           (case Map.get(payload, "client_reference_id") do
              x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
                Kernel.get_in(payload, ["metadata", "organization_id"])

              x ->
                x
            end),
         {:ok, _} <- refresh_entitlements!(org_id) do
      :ok
    else
      _ -> :ok
    end
  end

  defp maybe_put_string(map, _key, value)
       when :erlang.orelse(
              :erlang.not(:erlang.is_map(map)),
              :erlang.not(:erlang.is_binary(value))
            ) do
    map
  end

  defp maybe_put_string(map, _key, "") do
    map
  end

  defp maybe_put_string(map, key, value) do
    :maps.put(key, value, map)
  end

  defp maybe_put_founder_offer(
         entry,
         %Trifle.Billing.Plan{tier_key: "pro", interval: "month"},
         founder_offer
       )
       when :erlang.is_map(founder_offer) do
    :maps.put(:founder_offer, founder_offer, entry)
  end

  defp maybe_put_founder_offer(entry, _plan, _founder_offer) do
    entry
  end

  defp maybe_mark_usage_locked(%Trifle.Billing.ProjectUsage{} = usage) do
    cond do
      :erlang.==(usage.hard_limit, nil) ->
        {:ok, usage}

      :erlang.<(usage.events_count, usage.hard_limit) ->
        {:ok, usage}

      :erlang.not(:erlang.==(usage.locked_at, nil)) ->
        {:ok, usage}

      true ->
        Trifle.Repo.update(
          Trifle.Billing.ProjectUsage.changeset(
            usage,
            %{locked_at: now()}
          )
        )
    end
  end

  defp maybe_change_or_create_app_subscription(
         organization,
         customer,
         price_id,
         tier,
         interval,
         founder?,
         opts
       ) do
    case get_scope_subscription(organization.id, "app", nil) do
      %Trifle.Billing.Subscription{} = subscription ->
        case update_app_subscription?(subscription) do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
            create_new_app_subscription_checkout(
              organization,
              customer,
              price_id,
              tier,
              interval,
              founder?,
              opts
            )

          _ ->
            update_existing_app_subscription(
              organization,
              subscription,
              price_id,
              tier,
              interval,
              founder?,
              opts
            )
        end

      _ ->
        create_new_app_subscription_checkout(
          organization,
          customer,
          price_id,
          tier,
          interval,
          founder?,
          opts
        )
    end
  end

  defp maybe_add_retention_line_item(line_items, _organization_id, _tier_key, false) do
    {:ok, line_items}
  end

  defp maybe_add_retention_line_item(line_items, organization_id, tier_key, true) do
    case fetch_retention_price(organization_id, tier_key) do
      {:ok, retention_price_id} ->
        {:ok, :erlang.++(line_items, [%{"price" => retention_price_id, "quantity" => 1}])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_billing_plans_for_admin(search_query, scope) do
    Trifle.Repo.all(admin_plans_query(search_query, scope))
  end

  def list_billing_plans_for_admin(x0) do
    list_billing_plans_for_admin(x0, "all")
  end

  def list_billing_plans_for_admin() do
    list_billing_plans_for_admin("", "all")
  end

  defp insert_webhook_event(event_id, event_type, payload) do
    case Trifle.Repo.insert(
           Trifle.Billing.WebhookEvent.changeset(
             %Trifle.Billing.WebhookEvent{
               __meta__: %{
                 __struct__: Ecto.Schema.Metadata,
                 context: nil,
                 prefix: nil,
                 schema: Trifle.Billing.WebhookEvent,
                 source: "billing_webhook_events",
                 state: :built
               },
               error: nil,
               event_type: nil,
               id: nil,
               inserted_at: nil,
               payload: %{},
               processed_at: nil,
               status: "received",
               stripe_event_id: nil,
               updated_at: nil
             },
             %{
               stripe_event_id: event_id,
               event_type: event_type,
               payload: payload,
               status: "received"
             }
           )
         ) do
      {:ok, event} ->
        {:ok, event}

      {:error, %Ecto.Changeset{} = changeset} ->
        case duplicate_webhook_event?(changeset) do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
            {:error, changeset}

          _ ->
            {:error, :duplicate_event}
        end
    end
  end

  def ingest_allowed?(%Trifle.Organizations.Project{} = project) do
    case enabled?() do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        :ok

      _ ->
        with :ok <- app_access_allowed_for_org_id(project.organization_id),
             %Trifle.Billing.Subscription{} = subscription <-
               get_scope_subscription(project.organization_id, "project", project.id),
             :ok <- ensure_subscription_allows_access(subscription),
             :ok <- ensure_project_usage_below_limit(project, subscription) do
          :ok
        else
          nil -> {:error, :project_subscription_required}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp handle_payment_succeeded(invoice_payload) do
    with {:ok, subscription} <- find_subscription_for_invoice(invoice_payload),
         {:ok, updated} <-
           Trifle.Repo.update(
             Trifle.Billing.Subscription.changeset(
               subscription,
               %{grace_until: nil, status: "active"}
             )
           ) do
      {:ok, updated.organization_id}
    end
  end

  defp handle_payment_failed(invoice_payload) do
    with {:ok, subscription} <- find_subscription_for_invoice(invoice_payload),
         {:ok, updated} <-
           Trifle.Repo.update(
             Trifle.Billing.Subscription.changeset(
               subscription,
               %{grace_until: grace_deadline(), status: "past_due"}
             )
           ) do
      {:ok, updated.organization_id}
    end
  end

  defp grace_deadline() do
    DateTime.add(now(), :erlang.*(:erlang.*(:erlang.*(7, 24), 60), 60), :second)
  end

  def get_scope_subscription(organization_id, scope_type, scope_id)
      when :erlang.andalso(:erlang.is_binary(organization_id), :erlang.is_binary(scope_type)) do
    query = %{
      offset: nil,
      select: nil,
      sources: nil,
      prefix: nil,
      windows: [],
      aliases: %{},
      lock: nil,
      limit: %Ecto.Query.LimitExpr{
        with_ties: false,
        expr: 1,
        params: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 679
      },
      __struct__: Ecto.Query,
      from: %Ecto.Query.FromExpr{
        source: {Trifle.Billing.Subscription.__schema__(:source), Trifle.Billing.Subscription},
        params: [],
        as: nil,
        prefix: Trifle.Billing.Subscription.__schema__(:prefix),
        hints: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 679
      },
      joins: [],
      combinations: [],
      distinct: nil,
      with_ctes: nil,
      wheres: [
        %Ecto.Query.BooleanExpr{
          expr:
            {:and, [],
             [
               {:==, [], [{{:., [], [{:&, [], [0]}, :organization_id]}, [], []}, {:^, [], [0]}]},
               {:==, [], [{{:., [], [{:&, [], [0]}, :scope_type]}, [], []}, {:^, [], [1]}]}
             ]},
          op: :and,
          params: [
            {Ecto.Query.Builder.not_nil!(
               organization_id,
               "s.organization_id"
             ), {0, :organization_id}},
            {Ecto.Query.Builder.not_nil!(
               scope_type,
               "s.scope_type"
             ), {0, :scope_type}}
          ],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 679
        }
      ],
      updates: [],
      assocs: [],
      preloads: [],
      order_bys: [
        %Ecto.Query.ByExpr{
          expr: [
            desc: {{:., [], [{:&, [], [0]}, :updated_at]}, [], []},
            desc: {{:., [], [{:&, [], [0]}, :inserted_at]}, [], []}
          ],
          params: [],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 679
        }
      ],
      havings: [],
      group_bys: []
    }

    query =
      case scope_type do
        "app" ->
          query = Ecto.Query.Builder.From.apply(query, 1, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr: {:is_nil, [], [{{:., [], [{:&, [], [0]}, :scope_id]}, [], []}]},
            op: :and,
            params: [],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 687
          })

        _ ->
          query = Ecto.Query.Builder.From.apply(query, 1, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr: {:==, [], [{{:., [], [{:&, [], [0]}, :scope_id]}, [], []}, {:^, [], [0]}]},
            op: :and,
            params: [{Ecto.Query.Builder.not_nil!(scope_id, "s.scope_id"), {0, :scope_id}}],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 688
          })
      end

    Trifle.Repo.one(query)
  end

  def get_org_entitlement(organization_id) when :erlang.is_binary(organization_id) do
    Trifle.Repo.get_by(Trifle.Billing.Entitlement, organization_id: organization_id)
  end

  def get_billing_plan(id) when :erlang.is_binary(id) do
    Trifle.Repo.get(Trifle.Billing.Plan, id)
  end

  defp founder_status_for_org(organization_id) when :erlang.is_binary(organization_id) do
    cond do
      founder_claimed?(organization_id) -> "claimed"
      founder_offer_available?() -> "available"
      true -> "sold_out"
    end
  end

  defp founder_status_for_org(_organization_id) do
    case founder_offer_available?() do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> "sold_out"
      _ -> "available"
    end
  end

  def founder_slots() do
    20
  end

  defp founder_offer_for_org(organization_id) do
    case fetch_founder_plan(organization_id) do
      %Trifle.Billing.Plan{} = founder_plan ->
        %{
          amount: format_amount(founder_plan.amount_cents, founder_plan.currency),
          status: founder_status_for_org(organization_id),
          slots_total: 20
        }

      _ ->
        nil
    end
  end

  def founder_offer_available?() do
    :erlang.<(Trifle.Repo.aggregate(Trifle.Billing.FounderClaim, :count, :id), 20)
  end

  defp founder_locked?(organization_id, app_subscription) do
    case founder_claimed?(organization_id) do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        case app_subscription do
          %Trifle.Billing.Subscription{founder_price: true} -> true
          _ -> false
        end

      x ->
        x
    end
  end

  def founder_claimed?(organization_id) when :erlang.is_binary(organization_id) do
    Trifle.Repo.exists?(%{
      offset: nil,
      select: nil,
      sources: nil,
      prefix: nil,
      windows: [],
      aliases: %{},
      lock: nil,
      limit: nil,
      __struct__: Ecto.Query,
      from: %Ecto.Query.FromExpr{
        source: {Trifle.Billing.FounderClaim.__schema__(:source), Trifle.Billing.FounderClaim},
        params: [],
        as: nil,
        prefix: Trifle.Billing.FounderClaim.__schema__(:prefix),
        hints: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 669
      },
      joins: [],
      combinations: [],
      distinct: nil,
      with_ctes: nil,
      wheres: [
        %Ecto.Query.BooleanExpr{
          expr: {:==, [], [{{:., [], [{:&, [], [0]}, :organization_id]}, [], []}, {:^, [], [0]}]},
          op: :and,
          params: [
            {Ecto.Query.Builder.not_nil!(organization_id, "f.organization_id"),
             {0, :organization_id}}
          ],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 669
        }
      ],
      updates: [],
      assocs: [],
      preloads: [],
      order_bys: [],
      havings: [],
      group_bys: []
    })
  end

  def format_amount(nil, _currency) do
    "Custom"
  end

  def format_amount(amount_cents, currency) when :erlang.is_integer(amount_cents) do
    amount = Decimal.to_string(Decimal.div(Decimal.new(amount_cents), 100), :normal)

    currency =
      case currency do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> "usd"
        x -> x
      end

    case String.downcase(currency) do
      "usd" -> <<"$", amount::binary>>
      "eur" -> <<"EUR ", amount::binary>>
      "gbp" -> <<"GBP ", amount::binary>>
      _ -> <<amount::binary, " ", String.upcase(currency)::binary>>
    end
  end

  def format_amount(_amount_cents, _currency) do
    "Custom"
  end

  defp first_subscription_price(payload) do
    case Kernel.get_in(payload, ["items", "data"]) do
      [first | _] ->
        case Map.get(first, "price") do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> first["plan"]
          x -> x
        end

      _ ->
        nil
    end
  end

  defp first_subscription_item_id(payload) do
    case Kernel.get_in(payload, ["items", "data"]) do
      [%{"id" => id} | _] when :erlang.andalso(:erlang.is_binary(id), :erlang."/="(id, "")) -> id
      [first | _] when :erlang.is_map(first) -> Map.get(first, "id")
      _ -> nil
    end
  end

  defp find_subscription_for_invoice(payload) do
    stripe_subscription_id = Map.get(payload, "subscription")
    stripe_customer_id = Map.get(payload, "customer")

    subscription =
      cond do
        (case :erlang.is_binary(stripe_subscription_id) do
           false -> false
           true -> :erlang."/="(stripe_subscription_id, "")
         end) ->
          Trifle.Repo.get_by(Trifle.Billing.Subscription,
            stripe_subscription_id: stripe_subscription_id
          )

        (case :erlang.is_binary(stripe_customer_id) do
           false -> false
           true -> :erlang."/="(stripe_customer_id, "")
         end) ->
          Trifle.Repo.one(%{
            offset: nil,
            select: nil,
            sources: nil,
            prefix: nil,
            windows: [],
            aliases: %{},
            lock: nil,
            limit: %Ecto.Query.LimitExpr{
              with_ties: false,
              expr: 1,
              params: [],
              file: "/workspaces/trifle/lib/trifle/billing.ex",
              line: 1016
            },
            __struct__: Ecto.Query,
            from: %Ecto.Query.FromExpr{
              source:
                {Trifle.Billing.Subscription.__schema__(:source), Trifle.Billing.Subscription},
              params: [],
              as: nil,
              prefix: Trifle.Billing.Subscription.__schema__(:prefix),
              hints: [],
              file: "/workspaces/trifle/lib/trifle/billing.ex",
              line: 1016
            },
            joins: [],
            combinations: [],
            distinct: nil,
            with_ctes: nil,
            wheres: [
              %Ecto.Query.BooleanExpr{
                expr:
                  {:==, [],
                   [{{:., [], [{:&, [], [0]}, :stripe_customer_id]}, [], []}, {:^, [], [0]}]},
                op: :and,
                params: [
                  {Ecto.Query.Builder.not_nil!(
                     stripe_customer_id,
                     "s.stripe_customer_id"
                   ), {0, :stripe_customer_id}}
                ],
                subqueries: [],
                file: "/workspaces/trifle/lib/trifle/billing.ex",
                line: 1016
              }
            ],
            updates: [],
            assocs: [],
            preloads: [],
            order_bys: [
              %Ecto.Query.ByExpr{
                expr: [desc: {{:., [], [{:&, [], [0]}, :updated_at]}, [], []}],
                params: [],
                subqueries: [],
                file: "/workspaces/trifle/lib/trifle/billing.ex",
                line: 1016
              }
            ],
            havings: [],
            group_bys: []
          })

        true ->
          nil
      end

    case subscription do
      %Trifle.Billing.Subscription{} = subscription -> {:ok, subscription}
      nil -> {:error, :subscription_not_found}
    end
  end

  defp fetch_retention_price(organization_id, tier_key) do
    case fetch_retention_plan(organization_id, tier_key) do
      %Trifle.Billing.Plan{stripe_price_id: value}
      when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        {:ok, value}

      _ ->
        {:error, :missing_retention_price_id}
    end
  end

  defp fetch_retention_plan(organization_id, tier_key) do
    fetch_active_plan_by_lookup(organization_id, "project", tier_key, "month", true, false)
  end

  defp fetch_required_string(payload, key) do
    case Map.get(payload, key) do
      value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        {:ok, value}

      _ ->
        {:error, {:missing_key, key}}
    end
  end

  defp fetch_project_price(organization_id, tier_key) do
    case fetch_active_plan_by_lookup(organization_id, "project", tier_key, "month", false, false) do
      %Trifle.Billing.Plan{stripe_price_id: price_id} = plan
      when :erlang.andalso(:erlang.is_binary(price_id), :erlang."/="(price_id, "")) ->
        {:ok, price_id, plan}

      _ ->
        {:error, :missing_project_price_id}
    end
  end

  defp fetch_org_plan(nil, _scope_type, _tier_key, _interval, _retention_add_on, _founder_offer) do
    nil
  end

  defp fetch_org_plan(
         organization_id,
         scope_type,
         tier_key,
         interval,
         retention_add_on,
         founder_offer
       )
       when :erlang.is_binary(organization_id) do
    Trifle.Repo.one(%{
      offset: nil,
      select: nil,
      sources: nil,
      prefix: nil,
      windows: [],
      aliases: %{},
      lock: nil,
      limit: %Ecto.Query.LimitExpr{
        with_ties: false,
        expr: 1,
        params: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 1625
      },
      __struct__: Ecto.Query,
      from: %Ecto.Query.FromExpr{
        source: {Trifle.Billing.Plan.__schema__(:source), Trifle.Billing.Plan},
        params: [],
        as: nil,
        prefix: Trifle.Billing.Plan.__schema__(:prefix),
        hints: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 1625
      },
      joins: [],
      combinations: [],
      distinct: nil,
      with_ctes: nil,
      wheres: [
        %Ecto.Query.BooleanExpr{
          expr:
            {:and, [],
             [
               {:and, [],
                [
                  {:and, [],
                   [
                     {:and, [],
                      [
                        {:and, [],
                         [
                           {:and, [],
                            [
                              {{:., [], [{:&, [], [0]}, :active]}, [], []},
                              {:==, [],
                               [
                                 {{:., [], [{:&, [], [0]}, :organization_id]}, [], []},
                                 {:^, [], [0]}
                               ]}
                            ]},
                           {:==, [],
                            [{{:., [], [{:&, [], [0]}, :scope_type]}, [], []}, {:^, [], [1]}]}
                         ]},
                        {:==, [], [{{:., [], [{:&, [], [0]}, :tier_key]}, [], []}, {:^, [], [2]}]}
                      ]},
                     {:==, [], [{{:., [], [{:&, [], [0]}, :interval]}, [], []}, {:^, [], [3]}]}
                   ]},
                  {:==, [],
                   [{{:., [], [{:&, [], [0]}, :retention_add_on]}, [], []}, {:^, [], [4]}]}
                ]},
               {:==, [], [{{:., [], [{:&, [], [0]}, :founder_offer]}, [], []}, {:^, [], [5]}]}
             ]},
          op: :and,
          params: [
            {Ecto.Query.Builder.not_nil!(
               organization_id,
               "p.organization_id"
             ), {0, :organization_id}},
            {Ecto.Query.Builder.not_nil!(
               scope_type,
               "p.scope_type"
             ), {0, :scope_type}},
            {Ecto.Query.Builder.not_nil!(
               tier_key,
               "p.tier_key"
             ), {0, :tier_key}},
            {Ecto.Query.Builder.not_nil!(
               interval,
               "p.interval"
             ), {0, :interval}},
            {Ecto.Query.Builder.not_nil!(
               retention_add_on,
               "p.retention_add_on"
             ), {0, :retention_add_on}},
            {Ecto.Query.Builder.not_nil!(
               founder_offer,
               "p.founder_offer"
             ), {0, :founder_offer}}
          ],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 1625
        }
      ],
      updates: [],
      assocs: [],
      preloads: [],
      order_bys: [
        %Ecto.Query.ByExpr{
          expr: [
            desc: {{:., [], [{:&, [], [0]}, :updated_at]}, [], []},
            desc: {{:., [], [{:&, [], [0]}, :inserted_at]}, [], []}
          ],
          params: [],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 1625
        }
      ],
      havings: [],
      group_bys: []
    })
  end

  defp fetch_global_plan(scope_type, tier_key, interval, retention_add_on, founder_offer) do
    Trifle.Repo.one(%{
      offset: nil,
      select: nil,
      sources: nil,
      prefix: nil,
      windows: [],
      aliases: %{},
      lock: nil,
      limit: %Ecto.Query.LimitExpr{
        with_ties: false,
        expr: 1,
        params: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 1641
      },
      __struct__: Ecto.Query,
      from: %Ecto.Query.FromExpr{
        source: {Trifle.Billing.Plan.__schema__(:source), Trifle.Billing.Plan},
        params: [],
        as: nil,
        prefix: Trifle.Billing.Plan.__schema__(:prefix),
        hints: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 1641
      },
      joins: [],
      combinations: [],
      distinct: nil,
      with_ctes: nil,
      wheres: [
        %Ecto.Query.BooleanExpr{
          expr:
            {:and, [],
             [
               {:and, [],
                [
                  {:and, [],
                   [
                     {:and, [],
                      [
                        {:and, [],
                         [
                           {:and, [],
                            [
                              {{:., [], [{:&, [], [0]}, :active]}, [], []},
                              {:is_nil, [],
                               [{{:., [], [{:&, [], [0]}, :organization_id]}, [], []}]}
                            ]},
                           {:==, [],
                            [{{:., [], [{:&, [], [0]}, :scope_type]}, [], []}, {:^, [], [0]}]}
                         ]},
                        {:==, [], [{{:., [], [{:&, [], [0]}, :tier_key]}, [], []}, {:^, [], [1]}]}
                      ]},
                     {:==, [], [{{:., [], [{:&, [], [0]}, :interval]}, [], []}, {:^, [], [2]}]}
                   ]},
                  {:==, [],
                   [{{:., [], [{:&, [], [0]}, :retention_add_on]}, [], []}, {:^, [], [3]}]}
                ]},
               {:==, [], [{{:., [], [{:&, [], [0]}, :founder_offer]}, [], []}, {:^, [], [4]}]}
             ]},
          op: :and,
          params: [
            {Ecto.Query.Builder.not_nil!(
               scope_type,
               "p.scope_type"
             ), {0, :scope_type}},
            {Ecto.Query.Builder.not_nil!(
               tier_key,
               "p.tier_key"
             ), {0, :tier_key}},
            {Ecto.Query.Builder.not_nil!(
               interval,
               "p.interval"
             ), {0, :interval}},
            {Ecto.Query.Builder.not_nil!(
               retention_add_on,
               "p.retention_add_on"
             ), {0, :retention_add_on}},
            {Ecto.Query.Builder.not_nil!(
               founder_offer,
               "p.founder_offer"
             ), {0, :founder_offer}}
          ],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 1641
        }
      ],
      updates: [],
      assocs: [],
      preloads: [],
      order_bys: [
        %Ecto.Query.ByExpr{
          expr: [
            desc: {{:., [], [{:&, [], [0]}, :updated_at]}, [], []},
            desc: {{:., [], [{:&, [], [0]}, :inserted_at]}, [], []}
          ],
          params: [],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 1641
        }
      ],
      havings: [],
      group_bys: []
    })
  end

  defp fetch_founder_plan(organization_id) do
    fetch_active_plan_by_lookup(organization_id, "app", "pro", "month", false, true)
  end

  defp fetch_event_type(payload) do
    case Map.get(payload, "type") do
      value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        {:ok, value}

      _ ->
        {:error, :missing_event_type}
    end
  end

  defp fetch_event_id(payload) do
    case Map.get(payload, "id") do
      value when :erlang.andalso(:erlang.is_binary(value), :erlang."/="(value, "")) ->
        {:ok, value}

      _ ->
        {:error, :missing_event_id}
    end
  end

  defp fetch_app_price(organization_id, tier, interval) do
    case fetch_active_plan_by_lookup(organization_id, "app", tier, interval, false, false) do
      %Trifle.Billing.Plan{stripe_price_id: price_id}
      when :erlang.andalso(:erlang.is_binary(price_id), :erlang."/="(price_id, "")) ->
        {:ok, price_id, false}

      _ ->
        {:error, :missing_price_id}
    end
  end

  defp fetch_active_plan_by_lookup(
         organization_id,
         scope_type,
         tier_key,
         interval,
         retention_add_on,
         founder_offer
       ) do
    case fetch_org_plan(
           organization_id,
           scope_type,
           tier_key,
           interval,
           retention_add_on,
           founder_offer
         ) do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        fetch_global_plan(scope_type, tier_key, interval, retention_add_on, founder_offer)

      x ->
        x
    end
  end

  defp ensure_subscription_allows_access(%Trifle.Billing.Subscription{} = subscription) do
    cond do
      :lists.member(subscription.status, ["active", "trialing"]) ->
        :ok

      (case :lists.member(subscription.status, ["past_due", "unpaid"]) do
         false -> false
         true -> Trifle.Billing.Subscription.in_grace?(subscription)
         other -> :erlang.error({:badbool, :and, other})
       end) ->
        :ok

      :lists.member(subscription.status, ["past_due", "unpaid"]) ->
        {:error, :payment_grace_expired}

      true ->
        {:error, :subscription_inactive}
    end
  end

  defp ensure_seat_available(_organization_id, %Trifle.Billing.Entitlement{seat_limit: nil}) do
    :ok
  end

  defp ensure_seat_available(organization_id, %Trifle.Billing.Entitlement{seat_limit: seat_limit})
       when :erlang.andalso(:erlang.is_integer(seat_limit), :erlang.>(seat_limit, 0)) do
    current_member_count =
      Trifle.Repo.one(%{
        offset: nil,
        select: %Ecto.Query.SelectExpr{
          fields: nil,
          expr: {:count, [], [{{:., [], [{:&, [], [0]}, :id]}, [], []}]},
          params: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 1418,
          take: %{},
          subqueries: [],
          aliases: %{}
        },
        sources: nil,
        prefix: nil,
        windows: [],
        aliases: %{},
        lock: nil,
        limit: nil,
        __struct__: Ecto.Query,
        from: %Ecto.Query.FromExpr{
          source:
            {Trifle.Organizations.OrganizationMembership.__schema__(:source),
             Trifle.Organizations.OrganizationMembership},
          params: [],
          as: nil,
          prefix: Trifle.Organizations.OrganizationMembership.__schema__(:prefix),
          hints: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 1418
        },
        joins: [],
        combinations: [],
        distinct: nil,
        with_ctes: nil,
        wheres: [
          %Ecto.Query.BooleanExpr{
            expr:
              {:==, [], [{{:., [], [{:&, [], [0]}, :organization_id]}, [], []}, {:^, [], [0]}]},
            op: :and,
            params: [
              {Ecto.Query.Builder.not_nil!(
                 organization_id,
                 "m.organization_id"
               ), {0, :organization_id}}
            ],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 1418
          }
        ],
        updates: [],
        assocs: [],
        preloads: [],
        order_bys: [],
        havings: [],
        group_bys: []
      })

    case :erlang.<(current_member_count, seat_limit) do
      false -> {:error, :seat_limit_reached}
      true -> :ok
    end
  end

  defp ensure_seat_available(_, _) do
    :ok
  end

  defp ensure_project_usage_below_limit(
         %Trifle.Organizations.Project{} = project,
         %Trifle.Billing.Subscription{} = subscription
       ) do
    hard_limit = project_hard_limit(subscription)

    case hard_limit do
      nil ->
        :ok

      hard_limit when :erlang.andalso(:erlang.is_integer(hard_limit), :erlang.>(hard_limit, 0)) ->
        usage = current_usage(project, subscription)

        case :erlang.>=(usage.events_count, hard_limit) do
          false -> :ok
          true -> {:error, :project_usage_limit_reached}
        end
    end
  end

  def ensure_customer_for_org(%Trifle.Organizations.Organization{} = organization) do
    case enabled?() do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        {:error, :billing_disabled}

      _ ->
        case Trifle.Repo.get_by(Trifle.Billing.Customer, organization_id: organization.id) do
          %Trifle.Billing.Customer{} = customer ->
            {:ok, customer}

          nil ->
            params = %{
              "name" => organization.name,
              "email" => organization_contact_email(organization),
              "metadata" => %{"organization_id" => organization.id}
            }

            with {:ok, payload} <-
                   stripe_client_request(
                     stripe_client(),
                     :create_customer,
                     [params],
                     idempotency_key: stripe_idempotency_key(["customer", organization.id])
                   ),
                 %{"id" => stripe_customer_id} <- payload,
                 {:ok, customer} <-
                   Trifle.Repo.insert(
                     Trifle.Billing.Customer.changeset(
                       %Trifle.Billing.Customer{
                         __meta__: %{
                           __struct__: Ecto.Schema.Metadata,
                           context: nil,
                           prefix: nil,
                           schema: Trifle.Billing.Customer,
                           source: "billing_customers",
                           state: :built
                         },
                         default_payment_method_brand: nil,
                         default_payment_method_last4: nil,
                         email: nil,
                         id: nil,
                         inserted_at: nil,
                         metadata: %{},
                         name: nil,
                         organization: %{
                           __cardinality__: :one,
                           __field__: :organization,
                           __owner__: Trifle.Billing.Customer,
                           __struct__: Ecto.Association.NotLoaded
                         },
                         organization_id: nil,
                         stripe_customer_id: nil,
                         updated_at: nil
                       },
                       %{
                         organization_id: organization.id,
                         stripe_customer_id: stripe_customer_id,
                         email: Map.get(payload, "email"),
                         name: Map.get(payload, "name"),
                         metadata: payload
                       }
                     )
                   ) do
              {:ok, customer}
            else
              {:error, reason} -> {:error, reason}
              _ -> {:error, :invalid_customer_payload}
            end
        end
    end
  end

  defp enqueue_webhook_processing(%Trifle.Billing.WebhookEvent{} = event) do
    args = %{"webhook_event_id" => event.id}
    Oban.insert(Trifle.Billing.Jobs.ProcessStripeEvent.new(args, queue: :billing))
  end

  defp end_of_month(%DateTime{} = period_start) do
    next_month =
      Date.add(
        Date.end_of_month(DateTime.to_date(period_start)),
        1
      )

    {:ok, naive} =
      NaiveDateTime.new(next_month, %Time{
        calendar: Calendar.ISO,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
      })

    DateTime.from_naive!(naive, "Etc/UTC")
  end

  def enabled?() do
    Trifle.Config.saas_mode?()
  end

  defp duplicate_webhook_event?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn {field, {_message, opts}} ->
      case :erlang.==(field, :stripe_event_id) do
        false -> false
        true -> :erlang.==(opts[:constraint], :unique)
      end
    end)
  end

  defp current_usage(%Trifle.Organizations.Project{} = _project, nil) do
    %{events_count: 0, hard_limit: nil, tier_key: nil, period_start: nil, period_end: nil}
  end

  defp current_usage(
         %Trifle.Organizations.Project{} = project,
         %Trifle.Billing.Subscription{} = subscription
       ) do
    {period_start, period_end} = usage_period(subscription)

    usage =
      Trifle.Repo.get_by(Trifle.Billing.ProjectUsage,
        project_id: project.id,
        period_start: period_start
      )

    case usage do
      %Trifle.Billing.ProjectUsage{} = usage ->
        usage

      nil ->
        %Trifle.Billing.ProjectUsage{
          __meta__: %{
            __struct__: Ecto.Schema.Metadata,
            context: nil,
            prefix: nil,
            schema: Trifle.Billing.ProjectUsage,
            source: "project_billing_usage",
            state: :built
          },
          id: nil,
          inserted_at: nil,
          locked_at: nil,
          project: %{
            __cardinality__: :one,
            __field__: :project,
            __owner__: Trifle.Billing.ProjectUsage,
            __struct__: Ecto.Association.NotLoaded
          },
          updated_at: nil,
          project_id: project.id,
          period_start: period_start,
          period_end: period_end,
          events_count: 0,
          tier_key: project_tier_key(subscription),
          hard_limit: project_hard_limit(subscription)
        }
    end
  end

  def create_webhook_event(payload) when :erlang.is_map(payload) do
    with {:ok, event_id} <- fetch_event_id(payload),
         {:ok, event_type} <- fetch_event_type(payload),
         {:ok, event} <- insert_webhook_event(event_id, event_type, payload),
         {:ok, _job} <- enqueue_webhook_processing(event) do
      {:ok, event}
    else
      {:error, :duplicate_event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def create_project_checkout_session(
        %Trifle.Organizations.Project{} = project,
        tier_key,
        retention_enabled,
        opts
      ) do
    with true <- enabled?(),
         {:ok, %{organization: %Trifle.Organizations.Organization{} = organization}} <-
           organization_for_project(project),
         {:ok, customer} <- ensure_customer_for_org(organization),
         {:ok, tier} <- normalize_project_tier(tier_key),
         {:ok, params} <-
           project_checkout_params(
             organization,
             customer,
             project,
             tier,
             truthy?(retention_enabled),
             opts
           ),
         {:ok, payload} <-
           stripe_client_request(
             stripe_client(),
             :create_checkout_session,
             [params],
             idempotency_key:
               stripe_idempotency_key([
                 "project_checkout",
                 organization.id,
                 project.id,
                 tier,
                 truthy?(retention_enabled)
               ])
           ) do
      case payload do
        %{"id" => id, "url" => url}
        when :erlang.andalso(:erlang.is_binary(url), :erlang."/="(url, "")) ->
          {:ok, %{id: id, url: url}}

        _ ->
          {:error, :invalid_checkout_payload}
      end
    else
      false -> {:error, :billing_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_project_checkout_session(x0, x1, x2) do
    create_project_checkout_session(x0, x1, x2, %{})
  end

  def create_portal_session(%Trifle.Organizations.Organization{} = organization, opts) do
    with true <- enabled?(),
         {:ok, customer} <- ensure_customer_for_org(organization),
         {:ok, payload} <-
           stripe_client_request(
             stripe_client(),
             :create_portal_session,
             [portal_session_params(customer, opts)],
             idempotency_key: stripe_idempotency_key(["portal_session", organization.id])
           ),
         %{"url" => url} when :erlang.andalso(:erlang.is_binary(url), :erlang."/="(url, "")) <-
           payload do
      {:ok, %{url: url}}
    else
      false -> {:error, :billing_disabled}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_portal_payload}
    end
  end

  def create_portal_session(x0) do
    create_portal_session(x0, %{})
  end

  defp create_new_app_subscription_checkout(
         organization,
         customer,
         price_id,
         tier,
         interval,
         founder?,
         opts
       ) do
    with {:ok, payload} <-
           stripe_client_request(
             stripe_client(),
             :create_checkout_session,
             [
               app_checkout_params(
                 organization,
                 customer,
                 price_id,
                 tier,
                 interval,
                 founder?,
                 opts
               )
             ],
             idempotency_key:
               stripe_idempotency_key([
                 "app_checkout",
                 organization.id,
                 tier,
                 interval,
                 founder?
               ])
           ) do
      case payload do
        %{"id" => id, "url" => url}
        when :erlang.andalso(:erlang.is_binary(url), :erlang."/="(url, "")) ->
          {:ok, %{mode: :checkout, id: id, url: url}}

        _ ->
          {:error, :invalid_checkout_payload}
      end
    end
  end

  def create_billing_plan(attrs) when :erlang.is_map(attrs) do
    Trifle.Repo.insert(
      Trifle.Billing.Plan.changeset(
        %Trifle.Billing.Plan{
          __meta__: %{
            __struct__: Ecto.Schema.Metadata,
            context: nil,
            prefix: nil,
            schema: Trifle.Billing.Plan,
            source: "billing_plans",
            state: :built
          },
          active: true,
          amount_cents: nil,
          currency: "usd",
          founder_offer: false,
          hard_limit: nil,
          id: nil,
          inserted_at: nil,
          interval: nil,
          metadata: %{},
          name: nil,
          organization: %{
            __cardinality__: :one,
            __field__: :organization,
            __owner__: Trifle.Billing.Plan,
            __struct__: Ecto.Association.NotLoaded
          },
          organization_id: nil,
          retention_add_on: false,
          scope_type: nil,
          seat_limit: nil,
          stripe_price_id: nil,
          tier_key: nil,
          updated_at: nil
        },
        attrs
      )
    )
  end

  def create_app_checkout_session(
        %Trifle.Organizations.Organization{} = organization,
        tier,
        interval,
        opts
      ) do
    with true <- enabled?(),
         {:ok, normalized_tier} <- normalize_app_tier(tier),
         {:ok, normalized_interval} <- normalize_app_interval(interval),
         {:ok, customer} <- ensure_customer_for_org(organization),
         {:ok, price_id, founder?} <-
           app_checkout_price(organization, normalized_tier, normalized_interval) do
      maybe_change_or_create_app_subscription(
        organization,
        customer,
        price_id,
        normalized_tier,
        normalized_interval,
        founder?,
        opts
      )
    else
      false -> {:error, :billing_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_app_checkout_session(x0, x1, x2) do
    create_app_checkout_session(x0, x1, x2, %{})
  end

  defp checkout_success_url(opts) do
    case (case Map.get(opts, :success_url) do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
              Map.get(opts, "success_url")

            x ->
              x
          end) do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        "https://app.trifle.io/organization/billing"

      x ->
        x
    end
  end

  defp checkout_cancel_url(opts) do
    case (case Map.get(opts, :cancel_url) do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
              Map.get(opts, "cancel_url")

            x ->
              x
          end) do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        "https://app.trifle.io/organization/billing"

      x ->
        x
    end
  end

  def change_billing_plan(%Trifle.Billing.Plan{} = plan, attrs) do
    Trifle.Billing.Plan.changeset(plan, attrs)
  end

  def change_billing_plan(x0) do
    change_billing_plan(x0, %{})
  end

  defp build_subscription_attrs(
         payload,
         organization_id,
         stripe_subscription_id,
         scope_type,
         scope_id,
         existing_subscription
       ) do
    price = first_subscription_price(payload)

    price_id =
      case price do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> x
        _ -> Map.get(price, "id")
      end

    interval =
      Kernel.get_in(
        case price do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
          x -> x
        end,
        ["recurring", "interval"]
      )

    metadata =
      case Map.get(payload, "metadata") do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
        x -> x
      end

    payload_status = Map.get(payload, "status")
    matched_plan = plan_for_price_id(price_id)
    subscription_item_id = first_subscription_item_id(payload)

    founder_price =
      case matched_plan do
        %Trifle.Billing.Plan{founder_offer: true} -> true
        _ -> false
      end

    grace_until =
      case :lists.member(payload_status, ["past_due", "unpaid"]) do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
          nil

        _ ->
          case existing_subscription do
            %Trifle.Billing.Subscription{grace_until: grace_until} ->
              case grace_until do
                x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
                  grace_deadline()

                x ->
                  x
              end

            _ ->
              grace_deadline()
          end
      end

    tier_metadata =
      maybe_put_string(
        %{
          "app_tier" => app_tier_from_plan(matched_plan),
          "seat_limit" => app_seat_limit_from_plan(matched_plan),
          "project_tier" => project_tier_from_plan(matched_plan),
          "project_hard_limit" => project_hard_limit_from_plan(matched_plan)
        },
        "subscription_item_id",
        subscription_item_id
      )

    {:ok,
     %{
       organization_id: organization_id,
       scope_type: scope_type,
       scope_id: scope_id,
       stripe_subscription_id: stripe_subscription_id,
       stripe_customer_id: Map.get(payload, "customer"),
       stripe_price_id: price_id,
       status: payload_status,
       interval: interval,
       current_period_start: unix_to_datetime(Map.get(payload, "current_period_start")),
       current_period_end: unix_to_datetime(Map.get(payload, "current_period_end")),
       cancel_at_period_end: truthy?(Map.get(payload, "cancel_at_period_end")),
       grace_until: grace_until,
       founder_price: founder_price,
       metadata: :maps.merge(metadata, tier_metadata)
     }}
  end

  def billing_snapshot_for_membership(%Trifle.Organizations.OrganizationMembership{} = membership) do
    organization = Trifle.Organizations.get_organization(membership.organization_id)
    members = Trifle.Organizations.list_memberships_for_org_id(membership.organization_id)
    projects = Trifle.Organizations.list_projects_for_org(membership.organization_id)
    entitlement = get_org_entitlement(membership.organization_id)
    app_subscription = get_scope_subscription(membership.organization_id, "app", nil)

    projects_with_billing =
      Enum.map(projects, fn project ->
        subscription = get_scope_subscription(membership.organization_id, "project", project.id)
        usage = current_usage(project, subscription)

        %{
          project: project,
          subscription: subscription,
          usage: usage,
          state: project.billing_state,
          plan: plan_for_subscription(subscription)
        }
      end)

    %{
      organization: organization,
      entitlement: entitlement,
      app_subscription: app_subscription,
      app_plan: plan_for_subscription(app_subscription),
      seats_used: :erlang.length(members),
      founder_claim:
        Trifle.Repo.get_by(Trifle.Billing.FounderClaim,
          organization_id: membership.organization_id
        ),
      projects: projects_with_billing,
      available_app_tiers: available_app_tiers(membership.organization_id),
      available_project_tiers: available_project_tiers(membership.organization_id)
    }
  end

  def billing_locked_for_org?(organization_id) when :erlang.is_binary(organization_id) do
    case get_org_entitlement(organization_id) do
      %Trifle.Billing.Entitlement{billing_locked: locked} -> locked
      _ -> enabled?()
    end
  end

  defp beginning_of_month(%DateTime{} = datetime) do
    {:ok, date} = Date.new(datetime.year, datetime.month, 1)

    {:ok, naive} =
      NaiveDateTime.new(date, %Time{
        calendar: Calendar.ISO,
        hour: 0,
        minute: 0,
        second: 0,
        microsecond: {0, 0}
      })

    DateTime.from_naive!(naive, "Etc/UTC")
  end

  def available_project_tiers(organization_id) do
    Enum.sort_by(
      Enum.map(
        resolved_project_base_plans(organization_id),
        fn plan ->
          retention_plan = fetch_retention_plan(organization_id, plan.tier_key)

          %{
            tier_key: plan.tier_key,
            hard_limit: plan.hard_limit,
            amount: format_amount(plan.amount_cents, plan.currency),
            retention_available:
              case Trifle.Billing.Plan do
                name when :erlang.is_atom(name) ->
                  case retention_plan do
                    %{__struct__: ^name} -> true
                    _ -> false
                  end

                _ ->
                  :erlang.error(ArgumentError.exception([]), :none,
                    error_info: %{module: Exception}
                  )
              end,
            retention_amount:
              case retention_plan do
                %Trifle.Billing.Plan{} = value ->
                  format_amount(value.amount_cents, value.currency)

                _ ->
                  nil
              end
          }
        end
      ),
      fn entry -> {project_tier_order(entry.tier_key), entry.tier_key} end
    )
  end

  def available_project_tiers() do
    available_project_tiers(nil)
  end

  def available_app_tiers(organization_id) do
    founder_offer = founder_offer_for_org(organization_id)

    Enum.sort_by(
      Enum.map(
        resolved_app_subscription_plans(organization_id),
        fn plan ->
          maybe_put_founder_offer(
            %{
              tier: plan.tier_key,
              interval: plan.interval,
              amount: format_amount(plan.amount_cents, plan.currency),
              seat_limit: plan.seat_limit
            },
            plan,
            founder_offer
          )
        end
      ),
      fn entry -> {app_tier_order(entry.tier), app_interval_order(entry.interval)} end
    )
  end

  def available_app_tiers() do
    available_app_tiers(nil)
  end

  defp app_tier_order("starter") do
    1
  end

  defp app_tier_order("team") do
    2
  end

  defp app_tier_order("pro") do
    3
  end

  defp app_tier_order(_) do
    99
  end

  defp app_tier_from_price_id(nil) do
    nil
  end

  defp app_tier_from_price_id(price_id) when :erlang.is_binary(price_id) do
    case plan_for_price_id(price_id) do
      %Trifle.Billing.Plan{} = plan -> app_tier_from_plan(plan)
      _ -> nil
    end
  end

  defp app_tier_from_plan(%Trifle.Billing.Plan{scope_type: "app", tier_key: tier_key}) do
    tier_key
  end

  defp app_tier_from_plan(_) do
    nil
  end

  defp app_tier(%Trifle.Billing.Subscription{} = subscription) do
    metadata_tier =
      case Map.get(
             case subscription.metadata do
               x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
               x -> x
             end,
             "app_tier"
           ) do
        x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
          Map.get(
            case subscription.metadata do
              x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> %{}
              x -> x
            end,
            :app_tier
          )

        x ->
          x
      end

    case metadata_tier do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        app_tier_from_price_id(subscription.stripe_price_id)

      x ->
        x
    end
  end

  defp app_subscription_update_params(
         organization,
         subscription_item_id,
         price_id,
         tier,
         interval,
         founder?,
         opts
       ) do
    metadata = %{
      "organization_id" => organization.id,
      "scope_type" => "app",
      "app_tier" => tier,
      "billing_interval" => interval,
      "founder_price" =>
        case founder? do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> "false"
          _ -> "true"
        end
    }

    %{
      "items" => [%{"id" => subscription_item_id, "price" => price_id}],
      "metadata" => metadata,
      "cancel_at_period_end" => false,
      "payment_behavior" => "allow_incomplete",
      "proration_behavior" =>
        case (case Map.get(opts, :proration_behavior) do
                x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
                  Map.get(opts, "proration_behavior")

                x ->
                  x
              end) do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
            "create_prorations"

          x ->
            x
        end
    }
  end

  defp app_seat_limit_from_price_id(price_id) when :erlang.is_binary(price_id) do
    case plan_for_price_id(price_id) do
      %Trifle.Billing.Plan{} = plan -> app_seat_limit_from_plan(plan)
      _ -> nil
    end
  end

  defp app_seat_limit_from_price_id(_) do
    nil
  end

  defp app_seat_limit_from_plan(%Trifle.Billing.Plan{scope_type: "app", seat_limit: seat_limit}) do
    seat_limit
  end

  defp app_seat_limit_from_plan(_) do
    nil
  end

  defp app_interval_order("month") do
    1
  end

  defp app_interval_order("year") do
    2
  end

  defp app_interval_order(_) do
    99
  end

  defp app_checkout_price(%Trifle.Organizations.Organization{} = organization, "pro", "month") do
    founder_plan = fetch_founder_plan(organization.id)

    cond do
      :erlang.==(founder_plan, nil) ->
        fetch_app_price(organization.id, "pro", "month")

      founder_claimed?(organization.id) ->
        {:ok, founder_plan.stripe_price_id, true}

      true ->
        case reserve_founder_slot(organization.id) do
          {:ok, _claim} -> {:ok, founder_plan.stripe_price_id, true}
          {:error, :sold_out} -> fetch_app_price(organization.id, "pro", "month")
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp app_checkout_price(%Trifle.Organizations.Organization{} = organization, tier, interval) do
    fetch_app_price(organization.id, tier, interval)
  end

  defp app_checkout_params(
         organization,
         customer,
         price_id,
         tier,
         interval,
         founder?,
         opts
       ) do
    metadata = %{
      "organization_id" => organization.id,
      "scope_type" => "app",
      "app_tier" => tier,
      "billing_interval" => interval,
      "founder_price" =>
        case founder? do
          x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> "false"
          _ -> "true"
        end
    }

    %{
      "mode" => "subscription",
      "customer" => customer.stripe_customer_id,
      "client_reference_id" => organization.id,
      "success_url" => checkout_success_url(opts),
      "cancel_url" => checkout_cancel_url(opts),
      "line_items" => [%{"price" => price_id, "quantity" => 1}],
      "subscription_data" => %{"metadata" => metadata}
    }
  end

  def app_access_allowed_for_org_id(organization_id) when :erlang.is_binary(organization_id) do
    case enabled?() do
      x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) ->
        :ok

      _ ->
        case get_org_entitlement(organization_id) do
          %Trifle.Billing.Entitlement{billing_locked: true, lock_reason: reason}
          when :erlang.is_binary(reason) ->
            {:error, :erlang.binary_to_atom(reason)}

          %Trifle.Billing.Entitlement{billing_locked: true} ->
            {:error, :billing_locked}

          %Trifle.Billing.Entitlement{app_tier: tier}
          when :erlang.andalso(:erlang.is_binary(tier), :erlang."/="(tier, "")) ->
            :ok

          _ ->
            {:error, :missing_app_subscription}
        end
    end
  end

  def allowed_to_create_project?(%Trifle.Organizations.Organization{} = organization) do
    app_access_allowed_for_org_id(organization.id)
  end

  def allowed_to_add_member?(%Trifle.Organizations.Organization{} = organization) do
    with :ok <- app_access_allowed_for_org_id(organization.id),
         %Trifle.Billing.Entitlement{} = entitlement <- get_org_entitlement(organization.id),
         :ok <- ensure_seat_available(organization.id, entitlement) do
      :ok
    else
      nil -> {:error, :billing_required}
      {:error, reason} -> {:error, reason}
    end
  end

  def admin_subscriptions_query(search_query, scope) do
    search_query =
      String.trim(
        String.Chars.to_string(
          case search_query do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> ""
            x -> x
          end
        )
      )

    scope = normalize_scope(scope)

    query = %{
      offset: nil,
      select: nil,
      sources: nil,
      prefix: nil,
      windows: [],
      aliases: %{},
      lock: nil,
      limit: nil,
      __struct__: Ecto.Query,
      from: %Ecto.Query.FromExpr{
        source: {Trifle.Billing.Subscription.__schema__(:source), Trifle.Billing.Subscription},
        params: [],
        as: nil,
        prefix: Trifle.Billing.Subscription.__schema__(:prefix),
        hints: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 699
      },
      joins: [
        (
          nil

          %Ecto.Query.JoinExpr{
            ix: nil,
            as: nil,
            assoc: nil,
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 699,
            params: [],
            prefix: nil,
            qual: :inner,
            source: {nil, Trifle.Organizations.Organization},
            hints: [],
            on: %Ecto.Query.QueryExpr{
              expr:
                {:==, [],
                 [
                   {{:., [], [{:&, [], [1]}, :id]}, [], []},
                   {{:., [], [{:&, [], [0]}, :organization_id]}, [], []}
                 ]},
              params: [],
              line: 699,
              file: "/workspaces/trifle/lib/trifle/billing.ex"
            }
          }
        )
      ],
      combinations: [],
      distinct: nil,
      with_ctes: nil,
      wheres: [],
      updates: [],
      assocs: [organization: {1, []}],
      preloads: [],
      order_bys: [
        %Ecto.Query.ByExpr{
          expr: [
            desc: {{:., [], [{:&, [], [0]}, :updated_at]}, [], []},
            desc: {{:., [], [{:&, [], [0]}, :inserted_at]}, [], []}
          ],
          params: [],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 699
        }
      ],
      havings: [],
      group_bys: []
    }

    query =
      case scope do
        "all" ->
          query

        "app" ->
          query = Ecto.Query.Builder.From.apply(query, 2, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr:
              {:==, [],
               [
                 {{:., [], [{:&, [], [0]}, :scope_type]}, [], []},
                 %Ecto.Query.Tagged{tag: nil, value: "app", type: {0, :scope_type}}
               ]},
            op: :and,
            params: [],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 709
          })

        "project" ->
          query = Ecto.Query.Builder.From.apply(query, 2, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr:
              {:==, [],
               [
                 {{:., [], [{:&, [], [0]}, :scope_type]}, [], []},
                 %Ecto.Query.Tagged{tag: nil, value: "project", type: {0, :scope_type}}
               ]},
            op: :and,
            params: [],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 710
          })

        _ ->
          query
      end

    case :erlang.==(search_query, "") do
      false ->
        pattern = <<"%", String.Chars.to_string(search_query)::binary, "%">>

        (
          query = Ecto.Query.Builder.From.apply(query, 2, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr:
              {:or, [],
               [
                 {:or, [],
                  [
                    {:or, [],
                     [
                       {:or, [],
                        [
                          {:or, [],
                           [
                             {:ilike, [],
                              [{{:., [], [{:&, [], [1]}, :name]}, [], []}, {:^, [], [0]}]},
                             {:ilike, [],
                              [{{:., [], [{:&, [], [1]}, :slug]}, [], []}, {:^, [], [1]}]}
                           ]},
                          {:ilike, [],
                           [
                             {{:., [], [{:&, [], [0]}, :stripe_subscription_id]}, [], []},
                             {:^, [], [2]}
                           ]}
                        ]},
                       {:ilike, [],
                        [{{:., [], [{:&, [], [0]}, :stripe_customer_id]}, [], []}, {:^, [], [3]}]}
                     ]},
                    {:ilike, [],
                     [{{:., [], [{:&, [], [0]}, :stripe_price_id]}, [], []}, {:^, [], [4]}]}
                  ]},
                 {:ilike, [], [{{:., [], [{:&, [], [0]}, :status]}, [], []}, {:^, [], [5]}]}
               ]},
            op: :and,
            params: [
              {pattern, :string},
              {pattern, :string},
              {pattern, :string},
              {pattern, :string},
              {pattern, :string},
              {pattern, :string}
            ],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 719
          })
        )

      true ->
        query
    end
  end

  def admin_subscriptions_query(x0) do
    admin_subscriptions_query(x0, "all")
  end

  def admin_subscriptions_query() do
    admin_subscriptions_query("", "all")
  end

  def admin_plans_query(search_query, scope) do
    search_query =
      String.trim(
        String.Chars.to_string(
          case search_query do
            x when :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil)) -> ""
            x -> x
          end
        )
      )

    scope = normalize_scope(scope)

    query = %{
      offset: nil,
      select: nil,
      sources: nil,
      prefix: nil,
      windows: [],
      aliases: %{},
      lock: nil,
      limit: nil,
      __struct__: Ecto.Query,
      from: %Ecto.Query.FromExpr{
        source: {Trifle.Billing.Plan.__schema__(:source), Trifle.Billing.Plan},
        params: [],
        as: nil,
        prefix: Trifle.Billing.Plan.__schema__(:prefix),
        hints: [],
        file: "/workspaces/trifle/lib/trifle/billing.ex",
        line: 622
      },
      joins: [
        (
          nil

          %Ecto.Query.JoinExpr{
            ix: nil,
            as: nil,
            assoc: nil,
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 622,
            params: [],
            prefix: nil,
            qual: :left,
            source: {nil, Trifle.Organizations.Organization},
            hints: [],
            on: %Ecto.Query.QueryExpr{
              expr:
                {:==, [],
                 [
                   {{:., [], [{:&, [], [1]}, :id]}, [], []},
                   {{:., [], [{:&, [], [0]}, :organization_id]}, [], []}
                 ]},
              params: [],
              line: 622,
              file: "/workspaces/trifle/lib/trifle/billing.ex"
            }
          }
        )
      ],
      combinations: [],
      distinct: nil,
      with_ctes: nil,
      wheres: [],
      updates: [],
      assocs: [organization: {1, []}],
      preloads: [],
      order_bys: [
        %Ecto.Query.ByExpr{
          expr: [
            desc: {{:., [], [{:&, [], [0]}, :active]}, [], []},
            asc_nulls_first: {{:., [], [{:&, [], [1]}, :name]}, [], []},
            asc: {{:., [], [{:&, [], [0]}, :scope_type]}, [], []},
            asc: {{:., [], [{:&, [], [0]}, :tier_key]}, [], []},
            asc: {{:., [], [{:&, [], [0]}, :interval]}, [], []},
            asc: {{:., [], [{:&, [], [0]}, :retention_add_on]}, [], []},
            asc: {{:., [], [{:&, [], [0]}, :founder_offer]}, [], []},
            asc: {{:., [], [{:&, [], [0]}, :inserted_at]}, [], []}
          ],
          params: [],
          subqueries: [],
          file: "/workspaces/trifle/lib/trifle/billing.ex",
          line: 622
        }
      ],
      havings: [],
      group_bys: []
    }

    query =
      case scope do
        "all" ->
          query

        "app" ->
          query = Ecto.Query.Builder.From.apply(query, 2, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr:
              {:==, [],
               [
                 {{:., [], [{:&, [], [0]}, :scope_type]}, [], []},
                 %Ecto.Query.Tagged{tag: nil, value: "app", type: {0, :scope_type}}
               ]},
            op: :and,
            params: [],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 641
          })

        "project" ->
          query = Ecto.Query.Builder.From.apply(query, 2, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr:
              {:==, [],
               [
                 {{:., [], [{:&, [], [0]}, :scope_type]}, [], []},
                 %Ecto.Query.Tagged{tag: nil, value: "project", type: {0, :scope_type}}
               ]},
            op: :and,
            params: [],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 642
          })

        _ ->
          query
      end

    case :erlang.==(search_query, "") do
      false ->
        pattern = <<"%", String.Chars.to_string(search_query)::binary, "%">>

        (
          query = Ecto.Query.Builder.From.apply(query, 2, nil, nil, [])

          Ecto.Query.Builder.Filter.apply(query, :where, %Ecto.Query.BooleanExpr{
            expr:
              {:or, [],
               [
                 {:or, [],
                  [
                    {:or, [],
                     [
                       {:or, [],
                        [
                          {:or, [],
                           [
                             {:or, [],
                              [
                                {:ilike, [],
                                 [{{:., [], [{:&, [], [0]}, :name]}, [], []}, {:^, [], [0]}]},
                                {:ilike, [],
                                 [{{:., [], [{:&, [], [0]}, :scope_type]}, [], []}, {:^, [], [1]}]}
                              ]},
                             {:ilike, [],
                              [{{:., [], [{:&, [], [0]}, :tier_key]}, [], []}, {:^, [], [2]}]}
                           ]},
                          {:ilike, [],
                           [{{:., [], [{:&, [], [0]}, :interval]}, [], []}, {:^, [], [3]}]}
                        ]},
                       {:ilike, [],
                        [{{:., [], [{:&, [], [0]}, :stripe_price_id]}, [], []}, {:^, [], [4]}]}
                     ]},
                    {:ilike, [], [{{:., [], [{:&, [], [1]}, :name]}, [], []}, {:^, [], [5]}]}
                  ]},
                 {:ilike, [], [{{:., [], [{:&, [], [1]}, :slug]}, [], []}, {:^, [], [6]}]}
               ]},
            op: :and,
            params: [
              {pattern, :string},
              {pattern, :string},
              {pattern, :string},
              {pattern, :string},
              {pattern, :string},
              {pattern, :string},
              {pattern, :string}
            ],
            subqueries: [],
            file: "/workspaces/trifle/lib/trifle/billing.ex",
            line: 651
          })
        )

      true ->
        query
    end
  end

  def admin_plans_query(x0) do
    admin_plans_query(x0, "all")
  end

  def admin_plans_query() do
    admin_plans_query("", "all")
  end
end
