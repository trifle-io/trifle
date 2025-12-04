defmodule TrifleApp.Integrations.DiscordController do
  use TrifleApp, :controller

  alias Trifle.Integrations
  alias Trifle.Organizations

  def callback(conn, %{"error" => "access_denied"}) do
    conn
    |> put_flash(:info, "Discord authorization was cancelled.")
    |> redirect(to: ~p"/organization/delivery")
  end

  def callback(conn, %{"code" => code, "state" => state} = params) do
    current_user = conn.assigns[:current_user]

    with {:ok, %{user_id: user_id, organization_id: organization_id}} <-
           Integrations.verify_discord_state(state),
         true <- current_user && current_user.id == user_id,
         %Organizations.OrganizationMembership{organization_id: ^organization_id} =
           Organizations.get_membership_for_user(current_user),
         {:ok, payload} <- Integrations.exchange_discord_code(code),
         {:ok, guild_id} <- fetch_param(params, "guild_id"),
         {:ok, guild} <- Integrations.fetch_discord_guild(guild_id),
         {:ok, installation} <-
           Integrations.create_or_update_discord_installation(
             organization_id,
             current_user.id,
             build_installation_payload(params, payload, guild)
           ) do
      case Integrations.sync_discord_channels(installation) do
        {:ok, synced_installation} ->
          channel_count = length(synced_installation.channels || [])

          conn
          |> put_flash(
            :info,
            "Discord server #{installation.guild_name} connected. Synced #{channel_count} channel#{if channel_count == 1, do: "", else: "s"}."
          )
          |> redirect(to: ~p"/organization/delivery")

        {:error, reason} ->
          conn
          |> put_flash(:info, "Discord server #{installation.guild_name} connected.")
          |> put_flash(:error, "Channel sync failed: #{format_reason(reason)}.")
          |> redirect(to: ~p"/organization/delivery")
      end
    else
      false ->
        conn
        |> put_flash(:error, "Discord authorization failed: session mismatch.")
        |> redirect(to: ~p"/organization/delivery")

      nil ->
        conn
        |> put_flash(:error, "Discord authorization failed: organization membership not found.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, {:invalid_payload, reason}} ->
        conn
        |> put_flash(:error, "Discord returned an unexpected payload (#{format_reason(reason)}).")
        |> redirect(to: ~p"/organization/delivery")

      {:error, {:discord_error, error, _details}} ->
        conn
        |> put_flash(:error, "Discord API returned #{error}.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, :http_error, %{status: status}} ->
        conn
        |> put_flash(:error, "Discord API returned HTTP #{status}.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, {:missing_config, field}} ->
        conn
        |> put_flash(:error, "Discord configuration is missing #{field}.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, %Ecto.Changeset{} = changeset} ->
        message = humanize_changeset_errors(changeset)

        conn
        |> put_flash(:error, "Unable to store Discord installation: #{message}.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "Discord authorization expired. Please try again.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "Discord authorization token is invalid.")
        |> redirect(to: ~p"/organization/delivery")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Discord authorization failed: #{format_reason(reason)}.")
        |> redirect(to: ~p"/organization/delivery")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Discord authorization failed. Missing parameters.")
    |> redirect(to: ~p"/organization/delivery")
  end

  defp build_installation_payload(params, payload, guild) do
    %{
      "guild" => guild,
      "guild_id" => Map.get(params, "guild_id"),
      "guild_name" => Map.get(guild, "name") || Map.get(params, "guild_name"),
      "guild_icon" => Map.get(guild, "icon"),
      "permissions" => Map.get(params, "permissions"),
      "scope" => Map.get(payload, "scope"),
      "token_type" => Map.get(payload, "token_type")
    }
  end

  defp fetch_param(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed != "" do
          {:ok, trimmed}
        else
          {:error, {:missing_key, key}}
        end

      _ ->
        {:error, {:missing_key, key}}
    end
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
  defp format_reason({:discord_error, error, _payload}), do: error
  defp format_reason({:discord_error, error, _code, _payload}), do: error
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
