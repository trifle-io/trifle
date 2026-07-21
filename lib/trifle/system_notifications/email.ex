defmodule Trifle.SystemNotifications.Email do
  @moduledoc false

  alias Trifle.Mailer.Template

  @spec render(String.t(), map()) ::
          {:ok, %{subject: String.t(), html: String.t(), text: String.t()}}
          | {:error, :unsupported_event}
  def render(event, payload) when is_binary(event) and is_map(payload) do
    with {:ok, title, lines, path} <- content(event, payload) do
      body =
        Template.action_email(
          headline: title,
          greeting: "Hi,",
          intro_lines: Enum.reject(lines, &blank?/1),
          action_label: if(path, do: "Open in admin", else: nil),
          action_url: if(path, do: admin_url(path), else: nil),
          footer_lines: ["This is an internal Trifle system notification."]
        )

      {:ok,
       %{
         subject: "[Trifle System] #{title}",
         html: body.html,
         text: body.text
       }}
    end
  end

  defp content("user_created", payload) do
    title = "User created: #{value(payload, "email", "unknown")}"

    {:ok, title,
     [
       line("Name", payload["name"]),
       line("Email", payload["email"]),
       line("User ID", payload["user_id"]),
       line("Created at", payload["occurred_at"])
     ], "/admin/users/#{payload["user_id"]}/show"}
  end

  defp content("user_invited", payload) do
    title = "User invited: #{value(payload, "email", "unknown")}"

    {:ok, title,
     [
       line("Organization", payload["organization_name"]),
       line("Invitee", payload["email"]),
       line("Role", payload["role"]),
       line("Invited by", payload["invited_by_email"]),
       line("Expires at", payload["expires_at"]),
       line("Created at", payload["occurred_at"])
     ], "/admin/organizations/#{payload["organization_id"]}/show"}
  end

  defp content("project_created", payload) do
    title = "Project created: #{value(payload, "project_name", "unknown")}"

    {:ok, title,
     [
       line("Organization", payload["organization_name"]),
       line("Project", payload["project_name"]),
       line("Project ID", payload["project_id"]),
       line("Owner", payload["owner_email"]),
       line("Created at", payload["occurred_at"])
     ], "/admin/projects/#{payload["project_id"]}/show"}
  end

  defp content("database_created", payload) do
    title = "Database created: #{value(payload, "database_name", "unknown")}"

    {:ok, title,
     [
       line("Organization", payload["organization_name"]),
       line("Database", payload["database_name"]),
       line("Database ID", payload["database_id"]),
       line("Driver", payload["driver"]),
       line("Connection method", payload["connection_method"]),
       line("Created at", payload["occurred_at"])
     ], "/admin/databases/#{payload["database_id"]}/show"}
  end

  defp content("database_checked", payload) do
    status = value(payload, "status", "unknown")
    title = "Database check #{status}: #{value(payload, "database_name", "unknown")}"

    {:ok, title,
     [
       line("Organization", payload["organization_name"]),
       line("Database", payload["database_name"]),
       line("Database ID", payload["database_id"]),
       line("Driver", payload["driver"]),
       line("Result", status),
       line("Error", payload["error"]),
       line("Checked at", payload["occurred_at"])
     ], "/admin/databases/#{payload["database_id"]}/show"}
  end

  defp content(event, payload)
       when event in [
              "subscription_created",
              "subscription_cancellation_scheduled",
              "subscription_cancelled"
            ] do
    action =
      case event do
        "subscription_created" -> "Subscription created"
        "subscription_cancellation_scheduled" -> "Subscription cancellation scheduled"
        "subscription_cancelled" -> "Subscription cancelled"
      end

    scope_label =
      if payload["scope_type"] == "project",
        do: value(payload, "project_name", "project"),
        else: value(payload, "organization_name", "organization")

    {:ok, "#{action}: #{scope_label}",
     [
       line("Scope", payload["scope_type"]),
       line("Organization", payload["organization_name"]),
       line("Project", payload["project_name"]),
       line("Status", payload["status"]),
       line("Price", payload["stripe_price_id"]),
       line("Interval", payload["interval"]),
       line("Current period ends", payload["current_period_end"]),
       line("Stripe subscription", payload["stripe_subscription_id"]),
       line("Occurred at", payload["occurred_at"])
     ], "/admin/billing/#{payload["subscription_id"]}/show"}
  end

  defp content(_event, _payload), do: {:error, :unsupported_event}

  defp admin_url(path) do
    base_url =
      cond do
        function_exported?(TrifleWeb.Endpoint, :url, 0) -> TrifleWeb.Endpoint.url()
        configured = Application.get_env(:trifle, :app_base_url) -> configured
        true -> "http://localhost:4000"
      end

    String.trim_trailing(base_url, "/") <> path
  end

  defp line(_label, value) when value in [nil, ""], do: nil
  defp line(label, value), do: "#{label}: #{value}"

  defp value(payload, key, fallback) do
    case payload[key] do
      value when value in [nil, ""] -> fallback
      value -> value
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
