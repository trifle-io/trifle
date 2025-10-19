defmodule TrifleApp.Integrations.SlackController do
  use TrifleApp, :controller

  alias Trifle.Integrations
  alias Trifle.Organizations

  def callback(conn, %{"error" => "access_denied"}) do
    conn
    |> put_flash(:info, "Slack authorization was cancelled.")
    |> redirect(to: ~p"/organization/delivery")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    current_user = conn.assigns[:current_user]

    with {:ok, %{user_id: user_id, organization_id: organization_id}} <-
           Integrations.verify_slack_state(state),
         true <- current_user && current_user.id == user_id,
         %Organizations.OrganizationMembership{organization_id: ^organization_id} = membership <-
           Organizations.get_membership_for_user(current_user),
         {:ok, payload} <- Integrations.exchange_slack_code(code),
         {:ok, installation} <-
           Integrations.create_or_update_slack_installation(organization_id, current_user.id, payload) do
      case Integrations.sync_slack_channels(installation) do
        {:ok, synced_installation} ->
          channel_count = length(synced_installation.channels || [])

          conn
          |> put_flash(
            :info,
            "Slack workspace #{installation.team_name} connected. Synced #{channel_count} channel#{if channel_count == 1, do: "", else: "s"}."
          )
          |> redirect(to: ~p"/organization/delivery")

        {:error, reason} ->
          conn
          |> put_flash(:info, "Slack workspace #{installation.team_name} connected.")
          |> put_flash(:error, "Channel sync failed: #{format_reason(reason)}.")
          |> redirect(to: ~p"/organization/delivery")
      end
    else
      false ->
        conn
        |> put_flash(:error, "Slack authorization failed: session mismatch.")
        |> redirect(to: ~p"/organization/delivery")

      nil ->
        conn
        |> put_flash(:error, "Slack authorization failed: organization membership not found.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, {:invalid_payload, reason}} ->
        conn
        |> put_flash(:error, "Slack returned an unexpected payload (#{format_reason(reason)}).")
        |> redirect(to: ~p"/organization/delivery")

      {:error, {:slack_error, error}} ->
        conn
        |> put_flash(:error, "Slack API returned #{error}.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, :http_error, %{status: status}} ->
        conn
        |> put_flash(:error, "Slack API returned HTTP #{status}.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, %Ecto.Changeset{} = changeset} ->
        message = humanize_changeset_errors(changeset)

        conn
        |> put_flash(:error, "Unable to store Slack installation: #{message}.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, {:missing_config, field}} ->
        conn
        |> put_flash(:error, "Slack configuration is missing #{field}.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "Slack authorization expired. Please try again.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "Slack authorization token is invalid.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Slack authorization failed: #{format_reason(reason)}.")
        |> redirect(to: ~p"/organization/delivery")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Slack authorization failed. Missing parameters.")
    |> redirect(to: ~p"/organization/delivery")
  end

  defp humanize_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp format_reason({:missing_key, key}), do: "missing #{key}"
  defp format_reason({:slack_error, error}), do: error
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
