defmodule TrifleApp.BillingController do
  use TrifleApp, :controller

  import TrifleApp.UserAuth, only: [require_authenticated_user: 2]

  alias Trifle.Billing
  alias Trifle.Organizations

  plug :ensure_saas_mode
  plug :require_authenticated_user

  def success(conn, _params) do
    conn
    |> put_flash(:info, "Billing updated.")
    |> redirect(to: ~p"/organization/billing")
  end

  def portal(conn, _params) do
    with {:ok, membership} <- fetch_membership(conn),
         {:ok, organization} <- fetch_organization(membership),
         {:ok, %{url: url}} <-
           Billing.create_portal_session(organization, %{return_url: billing_return_url(conn)}) do
      redirect(conn, external: url)
    else
      {:error, :membership_required} ->
        membership_required(conn)

      {:error, :billing_disabled} ->
        not_found(conn)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not open billing portal: #{format_reason(reason)}")
        |> redirect(to: ~p"/organization/billing")
    end
  end

  def checkout_project(conn, %{"project_id" => project_id} = params) do
    with {:ok, membership} <- fetch_membership(conn),
         {:ok, project} <- fetch_project(membership.organization_id, project_id),
         tier when is_binary(tier) <- param(params, "tier"),
         retention <- param(params, "retention", "false"),
         {:ok, %{url: url}} <-
           Billing.create_project_checkout_session(project, tier, retention, checkout_urls(conn)) do
      redirect(conn, external: url)
    else
      {:error, :membership_required} ->
        membership_required(conn)

      {:error, :project_not_found} ->
        conn
        |> put_flash(:error, "Project not found.")
        |> redirect(to: ~p"/organization/billing")

      {:error, :missing_project_price_id} ->
        conn
        |> put_flash(:error, "Billing is not configured for this project tier.")
        |> redirect(to: ~p"/organization/billing")

      {:error, :missing_retention_price_id} ->
        conn
        |> put_flash(:error, "Extended retention is not configured for this project tier.")
        |> redirect(to: ~p"/organization/billing")

      {:error, :billing_disabled} ->
        not_found(conn)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not create checkout: #{format_reason(reason)}")
        |> redirect(to: ~p"/organization/billing")

      _ ->
        conn
        |> put_flash(:error, "Invalid billing request.")
        |> redirect(to: ~p"/organization/billing")
    end
  end

  def checkout_app(conn, params) do
    with {:ok, membership} <- fetch_membership(conn),
         {:ok, organization} <- fetch_organization(membership),
         tier when is_binary(tier) <- param(params, "tier"),
         interval when is_binary(interval) <- param(params, "interval"),
         {:ok, result} <-
           Billing.create_app_checkout_session(organization, tier, interval, checkout_urls(conn)) do
      case result do
        %{url: url} when is_binary(url) and url != "" ->
          redirect(conn, external: url)

        %{mode: :updated} ->
          conn
          |> put_flash(
            :info,
            "Subscription updated. Stripe will apply prorated billing adjustments."
          )
          |> redirect(to: ~p"/organization/billing")

        _ ->
          conn
          |> put_flash(:error, "Could not start billing flow.")
          |> redirect(to: ~p"/organization/billing")
      end
    else
      {:error, :membership_required} ->
        membership_required(conn)

      {:error, :missing_price_id} ->
        conn
        |> put_flash(:error, "Billing is not configured for this plan.")
        |> redirect(to: ~p"/organization/billing")

      {:error, :billing_disabled} ->
        not_found(conn)

      {:error, :subscription_item_not_found} ->
        conn
        |> put_flash(
          :error,
          "Could not change the current subscription item. Open Billing Portal to change plan."
        )
        |> redirect(to: ~p"/organization/billing")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not start billing flow: #{format_reason(reason)}")
        |> redirect(to: ~p"/organization/billing")

      _ ->
        conn
        |> put_flash(:error, "Invalid billing request.")
        |> redirect(to: ~p"/organization/billing")
    end
  end

  defp fetch_membership(conn) do
    case conn.assigns[:current_membership] ||
           Organizations.get_membership_for_user(conn.assigns.current_user) do
      nil -> {:error, :membership_required}
      membership -> {:ok, membership}
    end
  end

  defp fetch_organization(%{organization: %Organizations.Organization{} = organization}),
    do: {:ok, organization}

  defp fetch_organization(%{organization_id: organization_id}) when is_binary(organization_id) do
    case Organizations.get_organization(organization_id) do
      nil -> {:error, :membership_required}
      organization -> {:ok, organization}
    end
  end

  defp fetch_project(organization_id, project_id) do
    {:ok, Organizations.get_project_for_org!(organization_id, project_id)}
  rescue
    Ecto.NoResultsError -> {:error, :project_not_found}
  end

  defp membership_required(conn) do
    conn
    |> put_flash(:error, "Organization membership is required.")
    |> redirect(to: ~p"/organization/billing")
  end

  defp param(params, key, default \\ nil), do: Map.get(params, key, default)

  defp checkout_urls(conn) do
    %{
      success_url: app_base_url(conn) <> "/organization/billing/success",
      cancel_url: billing_return_url(conn)
    }
  end

  defp billing_return_url(conn), do: app_base_url(conn) <> "/organization/billing"

  defp app_base_url(_conn), do: TrifleWeb.Endpoint.url()

  defp format_reason(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp format_reason(reason), do: inspect(reason)

  defp ensure_saas_mode(conn, _opts) do
    if Trifle.Config.saas_mode?() do
      conn
    else
      not_found(conn)
      |> halt()
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(json: TrifleApi.ErrorJSON)
    |> render("404.json")
  end
end
