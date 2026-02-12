defmodule TrifleApp.Plugs.RequireBillingActive do
  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    cond do
      Trifle.Config.self_hosted_mode?() ->
        conn

      allowlisted_path?(conn.request_path) ->
        conn

      :erlang.==(conn.assigns[:current_user], nil) ->
        conn

      billing_ok?(conn) ->
        conn

      true ->
        Plug.Conn.halt(
          Phoenix.Controller.redirect(
            Phoenix.Controller.put_flash(conn, :error, "Billing action required to continue."),
            to: "/organization/billing"
          )
        )
    end
  end

  defp billing_ok?(conn) do
    case conn.assigns[:current_membership] do
      %{organization_id: organization_id} when :erlang.is_binary(organization_id) ->
        :erlang.not(Trifle.Billing.billing_locked_for_org?(organization_id))

      _ ->
        true
    end
  end

  defp allowlisted_path?(path) when :erlang.is_binary(path) do
    Enum.any?(
      [
        "/organization/billing",
        "/organization/billing/success",
        "/organization/billing/checkout",
        "/organization/profile",
        "/users/settings",
        "/users/log_out",
        "/integrations/slack/oauth/callback",
        "/integrations/discord/oauth/callback"
      ],
      fn capture -> String.starts_with?(path, capture) end
    )
  end
end
