defmodule Trifle.Integrations do
  @moduledoc """
  Context for managing outbound delivery integrations such as Slack.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Trifle.Integrations.Discord.Client, as: DiscordClient
  alias Trifle.Integrations.Discord.State, as: DiscordState
  alias Trifle.Integrations.{DiscordChannel, DiscordInstallation}
  alias Trifle.Integrations.Slack.Client, as: SlackClient
  alias Trifle.Integrations.Slack.State, as: SlackState
  alias Trifle.Integrations.{SlackChannel, SlackInstallation}
  alias Trifle.Repo

  @slack_default_scopes ~w(chat:write chat:write.public channels:read groups:read incoming-webhook)
  @discord_default_scopes ~w(bot applications.commands identify guilds)
  @discord_default_permissions 52_224

  ## Slack configuration helpers

  def slack_config do
    base =
      Application.get_env(:trifle, :slack, %{})
      |> to_map()

    env_overrides =
      %{
        client_id: System.get_env("SLACK_CLIENT_ID"),
        client_secret: System.get_env("SLACK_CLIENT_SECRET"),
        signing_secret: System.get_env("SLACK_SIGNING_SECRET"),
        redirect_uri: System.get_env("SLACK_REDIRECT_URI"),
        scopes: System.get_env("SLACK_SCOPES")
      }
      |> Enum.reduce(%{}, fn
        {:scopes, nil}, acc ->
          acc

        {:scopes, ""}, acc ->
          Map.put(acc, :scopes, [])

        {:scopes, scopes}, acc when is_binary(scopes) ->
          parsed =
            scopes
            |> String.split(~r/[, ]+/, trim: true)
            |> Enum.reject(&(&1 == ""))

          Map.put(acc, :scopes, parsed)

        {key, value}, acc when is_binary(value) ->
          if String.trim(value) == "" do
            acc
          else
            Map.put(acc, key, value)
          end

        _ignored, acc ->
          acc
      end)

    Map.merge(base, env_overrides)
  end

  def slack_scopes do
    case Map.get(slack_config(), :scopes) do
      nil -> @slack_default_scopes
      scopes when is_list(scopes) -> scopes
      scopes when is_binary(scopes) -> String.split(scopes, ~r/[, ]+/, trim: true)
      _ -> @slack_default_scopes
    end
  end

  def slack_default_scopes, do: @slack_default_scopes

  def slack_configured? do
    config = slack_config()

    [:client_id, :client_secret, :signing_secret]
    |> Enum.all?(fn key ->
      case Map.get(config, key) do
        value when is_binary(value) -> String.trim(value) != ""
        _ -> false
      end
    end)
  end

  def slack_redirect_uri(default \\ nil) do
    case Map.get(slack_config(), :redirect_uri) do
      nil -> default
      "" -> default
      value -> value
    end
  end

  def slack_settings(default_redirect \\ nil) do
    config = slack_config()

    %{
      client_id: Map.get(config, :client_id),
      client_secret: Map.get(config, :client_secret),
      signing_secret: Map.get(config, :signing_secret),
      redirect_uri: slack_redirect_uri(default_redirect),
      scopes: slack_scopes()
    }
  end

  def sign_slack_state(user_id, organization_id, metadata \\ %{}) do
    SlackState.sign(user_id, organization_id, metadata)
  end

  def verify_slack_state(token, opts \\ []) do
    SlackState.verify(token, opts)
  end

  ## Discord configuration helpers

  def discord_config do
    base =
      Application.get_env(:trifle, :discord, %{})
      |> to_map()

    env_overrides =
      %{
        client_id: System.get_env("DISCORD_CLIENT_ID"),
        client_secret: System.get_env("DISCORD_CLIENT_SECRET"),
        bot_token: System.get_env("DISCORD_BOT_TOKEN"),
        redirect_uri: System.get_env("DISCORD_REDIRECT_URI"),
        scopes: System.get_env("DISCORD_SCOPES"),
        permissions: System.get_env("DISCORD_BOT_PERMISSIONS")
      }
      |> Enum.reduce(%{}, fn
        {:scopes, nil}, acc ->
          acc

        {:scopes, ""}, acc ->
          Map.put(acc, :scopes, [])

        {:scopes, scopes}, acc when is_binary(scopes) ->
          parsed =
            scopes
            |> String.split(~r/[, ]+/, trim: true)
            |> Enum.reject(&(&1 == ""))

          Map.put(acc, :scopes, parsed)

        {:permissions, nil}, acc ->
          acc

        {:permissions, ""}, acc ->
          acc

        {:permissions, value}, acc when is_binary(value) ->
          parsed =
            case Integer.parse(value) do
              {int, _} -> int
              :error -> nil
            end

          if is_nil(parsed) do
            acc
          else
            Map.put(acc, :permissions, parsed)
          end

        {key, value}, acc when is_binary(value) ->
          if String.trim(value) == "" do
            acc
          else
            Map.put(acc, key, value)
          end

        _ignored, acc ->
          acc
      end)

    Map.merge(base, env_overrides)
  end

  def discord_scopes do
    case Map.get(discord_config(), :scopes) do
      nil -> @discord_default_scopes
      scopes when is_list(scopes) -> scopes
      scopes when is_binary(scopes) -> String.split(scopes, ~r/[, ]+/, trim: true)
      _ -> @discord_default_scopes
    end
  end

  def discord_permissions do
    case Map.get(discord_config(), :permissions) do
      nil ->
        @discord_default_permissions

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, _} -> int
          _ -> @discord_default_permissions
        end

      _ ->
        @discord_default_permissions
    end
  end

  def discord_default_scopes, do: @discord_default_scopes
  def discord_default_permissions, do: @discord_default_permissions

  def discord_configured? do
    config = discord_config()

    [:client_id, :client_secret, :bot_token]
    |> Enum.all?(fn key ->
      case Map.get(config, key) do
        value when is_binary(value) -> String.trim(value) != ""
        _ -> false
      end
    end)
  end

  def discord_bot_token do
    config = discord_config()

    case config do
      %{} -> Map.get(config, :bot_token) || Map.get(config, "bot_token")
      _ -> nil
    end
  end

  def discord_redirect_uri(default \\ nil) do
    case Map.get(discord_config(), :redirect_uri) do
      nil -> default
      "" -> default
      value -> value
    end
  end

  def discord_settings(default_redirect \\ nil) do
    config = discord_config()

    %{
      client_id: Map.get(config, :client_id),
      client_secret: Map.get(config, :client_secret),
      bot_token: discord_bot_token(),
      redirect_uri: discord_redirect_uri(default_redirect),
      scopes: discord_scopes(),
      permissions: discord_permissions()
    }
  end

  def sign_discord_state(user_id, organization_id, metadata \\ %{}) do
    DiscordState.sign(user_id, organization_id, metadata)
  end

  def verify_discord_state(token, opts \\ []) do
    DiscordState.verify(token, opts)
  end

  ## Slack installations

  def list_slack_installations_for_org(organization_id, opts \\ []) do
    query =
      from i in SlackInstallation,
        where: i.organization_id == ^organization_id,
        order_by: [asc: i.team_name]

    query =
      if Keyword.get(opts, :preload_channels, false) do
        channels_query = from(c in SlackChannel, order_by: [asc: c.name])
        preload(query, channels: ^channels_query)
      else
        query
      end

    Repo.all(query)
  end

  def get_slack_installation(organization_id, id, opts \\ []) do
    query =
      from i in SlackInstallation,
        where: i.organization_id == ^organization_id and i.id == ^id

    query =
      if Keyword.get(opts, :preload_channels, false) do
        channels_query = from(c in SlackChannel, order_by: [asc: c.name])
        preload(query, channels: ^channels_query)
      else
        query
      end

    Repo.one(query)
  end

  def get_slack_installation!(organization_id, id, opts \\ []) do
    query =
      from i in SlackInstallation,
        where: i.organization_id == ^organization_id and i.id == ^id

    query =
      if Keyword.get(opts, :preload_channels, false) do
        preload(query, [:channels])
      else
        query
      end

    Repo.one!(query)
  end

  def fetch_slack_installation_by_team(organization_id, team_id) do
    Repo.get_by(SlackInstallation,
      organization_id: organization_id,
      team_id: team_id
    )
  end

  def create_or_update_slack_installation(organization_id, user_id, payload) do
    with {:ok, attrs} <- normalize_slack_installation_attrs(payload, organization_id, user_id) do
      reference_name =
        Map.get(attrs, :team_name) ||
          Map.get(attrs, "team_name") ||
          Map.get(attrs, :team_domain) ||
          Map.get(attrs, "team_domain") ||
          Map.get(attrs, :team_id) ||
          Map.get(attrs, "team_id") ||
          slack_reference_name_from_payload(payload)

      team_id = fetch_attr(attrs, :team_id)

      case fetch_slack_installation_by_team(organization_id, team_id) do
        nil ->
          reference =
            generate_reference(
              SlackInstallation,
              "slack",
              organization_id,
              reference_name,
              team_id
            )

          params = Map.put(attrs, :reference, reference)

          %SlackInstallation{}
          |> SlackInstallation.changeset(params)
          |> Repo.insert()
          |> case do
            {:ok, installation} -> {:ok, ensure_slack_reference(installation)}
            other -> other
          end

        %SlackInstallation{} = installation ->
          reference =
            case installation.reference do
              nil ->
                generate_reference(
                  SlackInstallation,
                  "slack",
                  organization_id,
                  reference_name,
                  team_id,
                  installation.id
                )

              "" ->
                generate_reference(
                  SlackInstallation,
                  "slack",
                  organization_id,
                  reference_name,
                  team_id,
                  installation.id
                )

              "slack" ->
                generate_reference(
                  SlackInstallation,
                  "slack",
                  organization_id,
                  reference_name,
                  team_id,
                  installation.id
                )

              "slack_slack" ->
                generate_reference(
                  SlackInstallation,
                  "slack",
                  organization_id,
                  reference_name,
                  team_id,
                  installation.id
                )

              existing ->
                existing
            end

          params =
            attrs
            |> Map.put(:reference, reference)

          installation
          |> SlackInstallation.changeset(params)
          |> Repo.update()
          |> case do
            {:ok, updated} -> {:ok, updated}
            other -> other
          end
      end
    end
  end

  def delete_slack_installation(%SlackInstallation{} = installation) do
    Repo.delete(installation)
  end

  def update_slack_channel_enabled(organization_id, channel_id, enabled) do
    query =
      from c in SlackChannel,
        join: i in assoc(c, :installation),
        where: c.id == ^channel_id and i.organization_id == ^organization_id,
        preload: [installation: i]

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      %SlackChannel{} = channel ->
        channel
        |> SlackChannel.enable_changeset(%{enabled: enabled})
        |> Repo.update()
    end
  end

  def exchange_slack_code(code) do
    default_redirect = default_slack_redirect_uri()

    config =
      slack_settings(default_redirect)
      |> Map.put(:redirect_uri, slack_redirect_uri(default_redirect) || default_redirect)

    SlackClient.exchange_code(config, code)
  end

  def sync_slack_channels(%SlackInstallation{} = installation) do
    with {:ok, channels} <- SlackClient.list_channels(installation.bot_access_token) do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      filtered_channels =
        channels
        |> Enum.filter(fn channel -> present?(Map.get(channel, "id")) end)

      channel_ids = Enum.map(filtered_channels, &Map.get(&1, "id"))

      multi =
        Multi.new()
        |> Multi.update(
          :installation,
          Ecto.Changeset.change(installation, last_channel_sync_at: timestamp)
        )
        |> Multi.merge(fn _ ->
          Enum.reduce(filtered_channels, Multi.new(), fn channel, acc ->
            attrs = slack_channel_attrs(installation.id, channel)

            changeset = SlackChannel.changeset(%SlackChannel{}, attrs)

            multi_key = {:channel, attrs.channel_id}

            Multi.insert(acc, multi_key, changeset,
              on_conflict:
                {:replace, [:name, :channel_type, :is_private, :metadata, :updated_at]},
              conflict_target: [:slack_installation_id, :channel_id]
            )
          end)
        end)
        |> Multi.run(:prune_channels, fn repo, _changes ->
          prune_query =
            from c in SlackChannel,
              where:
                c.slack_installation_id == ^installation.id and c.channel_id not in ^channel_ids

          {deleted_count, _} = repo.delete_all(prune_query)
          {:ok, deleted_count}
        end)

      case Repo.transaction(multi) do
        {:ok, %{installation: updated}} ->
          {:ok, Repo.preload(updated, channels: from(c in SlackChannel, order_by: [asc: c.name]))}

        {:error, {:channel, _channel_id}, %Ecto.Changeset{} = changeset, _changes} ->
          {:error, changeset}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  def default_slack_redirect_uri do
    TrifleWeb.Endpoint.url() <> "/integrations/slack/oauth/callback"
  rescue
    _ -> "/integrations/slack/oauth/callback"
  end

  ## Discord installations

  def list_discord_installations_for_org(organization_id, opts \\ []) do
    query =
      from i in DiscordInstallation,
        where: i.organization_id == ^organization_id,
        order_by: [asc: i.guild_name]

    query =
      if Keyword.get(opts, :preload_channels, false) do
        channels_query = from(c in DiscordChannel, order_by: [asc: c.name])
        preload(query, channels: ^channels_query)
      else
        query
      end

    Repo.all(query)
  end

  def get_discord_installation(organization_id, id, opts \\ []) do
    query =
      from i in DiscordInstallation,
        where: i.organization_id == ^organization_id and i.id == ^id

    query =
      if Keyword.get(opts, :preload_channels, false) do
        channels_query = from(c in DiscordChannel, order_by: [asc: c.name])
        preload(query, channels: ^channels_query)
      else
        query
      end

    Repo.one(query)
  end

  def get_discord_installation!(organization_id, id, opts \\ []) do
    query =
      from i in DiscordInstallation,
        where: i.organization_id == ^organization_id and i.id == ^id

    query =
      if Keyword.get(opts, :preload_channels, false) do
        preload(query, [:channels])
      else
        query
      end

    Repo.one!(query)
  end

  def fetch_discord_installation_by_guild(organization_id, guild_id) do
    Repo.get_by(DiscordInstallation,
      organization_id: organization_id,
      guild_id: guild_id
    )
  end

  def create_or_update_discord_installation(organization_id, user_id, payload) do
    with {:ok, attrs} <- normalize_discord_installation_attrs(payload, organization_id, user_id) do
      reference_name =
        Map.get(attrs, :guild_name) ||
          Map.get(attrs, "guild_name") ||
          Map.get(attrs, :guild_id) ||
          Map.get(attrs, "guild_id") ||
          discord_reference_name_from_payload(payload)

      guild_id = fetch_attr(attrs, :guild_id)

      case fetch_discord_installation_by_guild(organization_id, guild_id) do
        nil ->
          reference =
            generate_reference(
              DiscordInstallation,
              "discord",
              organization_id,
              reference_name,
              guild_id,
              nil
            )

          params = Map.put(attrs, :reference, reference)

          %DiscordInstallation{}
          |> DiscordInstallation.changeset(params)
          |> Repo.insert()
          |> case do
            {:ok, installation} -> {:ok, ensure_discord_reference(installation)}
            other -> other
          end

        %DiscordInstallation{} = installation ->
          reference =
            case installation.reference do
              nil ->
                generate_reference(
                  DiscordInstallation,
                  "discord",
                  organization_id,
                  reference_name,
                  guild_id,
                  installation.id
                )

              "" ->
                generate_reference(
                  DiscordInstallation,
                  "discord",
                  organization_id,
                  reference_name,
                  guild_id,
                  installation.id
                )

              "discord" ->
                generate_reference(
                  DiscordInstallation,
                  "discord",
                  organization_id,
                  reference_name,
                  guild_id,
                  installation.id
                )

              "discord_discord" ->
                generate_reference(
                  DiscordInstallation,
                  "discord",
                  organization_id,
                  reference_name,
                  guild_id,
                  installation.id
                )

              existing ->
                existing
            end

          params =
            attrs
            |> Map.put(:reference, reference)

          installation
          |> DiscordInstallation.changeset(params)
          |> Repo.update()
          |> case do
            {:ok, updated} -> {:ok, updated}
            other -> other
          end
      end
    end
  end

  def delete_discord_installation(%DiscordInstallation{} = installation) do
    Repo.delete(installation)
  end

  def update_discord_channel_enabled(organization_id, channel_id, enabled) do
    query =
      from c in DiscordChannel,
        join: i in assoc(c, :installation),
        where: c.id == ^channel_id and i.organization_id == ^organization_id,
        preload: [installation: i]

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      %DiscordChannel{} = channel ->
        channel
        |> DiscordChannel.enable_changeset(%{enabled: enabled})
        |> Repo.update()
    end
  end

  def exchange_discord_code(code) do
    default_redirect = default_discord_redirect_uri()

    config =
      discord_settings(default_redirect)
      |> Map.put(:redirect_uri, discord_redirect_uri(default_redirect) || default_redirect)

    DiscordClient.exchange_code(config, code)
  end

  def fetch_discord_guild(guild_id, opts \\ []) do
    with {:ok, token} <- discord_bot_token_or_error(),
         {:ok, guild} <- DiscordClient.fetch_guild(token, guild_id, opts) do
      {:ok, guild}
    else
      {:error, _} = error -> error
      other -> other
    end
  end

  def sync_discord_channels(%DiscordInstallation{} = installation, opts \\ []) do
    installation = ensure_discord_reference(installation)

    with {:ok, token} <- discord_bot_token_or_error(),
         {:ok, channels} <- DiscordClient.list_channels(token, installation.guild_id, opts) do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      filtered_channels =
        channels
        |> Enum.filter(&allowed_discord_channel?/1)

      channel_ids = Enum.map(filtered_channels, &Map.get(&1, "id"))

      multi =
        Multi.new()
        |> Multi.update(
          :installation,
          Ecto.Changeset.change(installation, last_channel_sync_at: timestamp)
        )
        |> Multi.merge(fn _ ->
          Enum.reduce(filtered_channels, Multi.new(), fn channel, acc ->
            attrs = discord_channel_attrs(installation.id, channel)

            changeset = DiscordChannel.changeset(%DiscordChannel{}, attrs)

            multi_key = {:channel, attrs.channel_id}

            Multi.insert(acc, multi_key, changeset,
              on_conflict: {:replace, [:name, :channel_type, :is_thread, :metadata, :updated_at]},
              conflict_target: [:discord_installation_id, :channel_id]
            )
          end)
        end)
        |> Multi.run(:prune_channels, fn repo, _changes ->
          prune_query =
            from c in DiscordChannel,
              where:
                c.discord_installation_id == ^installation.id and c.channel_id not in ^channel_ids

          {deleted_count, _} = repo.delete_all(prune_query)
          {:ok, deleted_count}
        end)

      case Repo.transaction(multi) do
        {:ok, %{installation: updated}} ->
          {:ok,
           Repo.preload(updated, channels: from(c in DiscordChannel, order_by: [asc: c.name]))}

        {:error, {:channel, _channel_id}, %Ecto.Changeset{} = changeset, _changes} ->
          {:error, changeset}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  def default_discord_redirect_uri do
    TrifleWeb.Endpoint.url() <> "/integrations/discord/oauth/callback"
  rescue
    _ -> "/integrations/discord/oauth/callback"
  end

  ## Helpers

  defp normalize_slack_installation_attrs(payload, organization_id, user_id) do
    with {:ok, team} <- fetch_required(payload, "team"),
         {:ok, team_id} <- fetch_required(team, "id"),
         {:ok, team_name} <- fetch_required(team, "name"),
         {:ok, token} <- fetch_required(payload, "access_token") do
      attrs =
        %{
          organization_id: organization_id,
          installed_by_user_id: user_id,
          team_id: team_id,
          team_name: team_name,
          team_domain: Map.get(team, "domain"),
          bot_user_id: Map.get(payload, "bot_user_id"),
          bot_access_token: token,
          scope: Map.get(payload, "scope"),
          settings: build_slack_installation_settings(payload)
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      {:ok, attrs}
    else
      {:error, reason} ->
        {:error, {:invalid_payload, reason}}
    end
  end

  defp build_slack_installation_settings(payload) do
    %{}
    |> maybe_put("app_id", Map.get(payload, "app_id"))
    |> maybe_put("authed_user", Map.get(payload, "authed_user"))
    |> maybe_put("incoming_webhook", Map.get(payload, "incoming_webhook"))
    |> maybe_put("enterprise", Map.get(payload, "enterprise"))
  end

  defp normalize_discord_installation_attrs(payload, organization_id, user_id) do
    guild = Map.get(payload, "guild") || Map.get(payload, :guild) || %{}

    guild_id =
      Map.get(payload, "guild_id") ||
        Map.get(payload, :guild_id) ||
        Map.get(guild, "id") ||
        Map.get(guild, :id)

    guild_name =
      Map.get(payload, "guild_name") ||
        Map.get(payload, :guild_name) ||
        Map.get(guild, "name") ||
        Map.get(guild, :name)

    guild_icon =
      Map.get(payload, "guild_icon") ||
        Map.get(payload, :guild_icon) ||
        Map.get(guild, "icon") ||
        Map.get(guild, :icon)

    permissions = Map.get(payload, "permissions") || Map.get(payload, :permissions)
    scope = Map.get(payload, "scope") || Map.get(payload, :scope)

    with {:ok, guild_id} <- fetch_required(%{"guild_id" => guild_id}, "guild_id"),
         {:ok, guild_name} <- fetch_required(%{"guild_name" => guild_name}, "guild_name") do
      attrs =
        %{
          organization_id: organization_id,
          installed_by_user_id: user_id,
          guild_id: guild_id,
          guild_name: guild_name,
          guild_icon: guild_icon,
          permissions: permissions,
          scope: scope,
          settings: build_discord_installation_settings(payload)
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      {:ok, attrs}
    else
      {:error, reason} ->
        {:error, {:invalid_payload, reason}}
    end
  end

  defp build_discord_installation_settings(payload) do
    %{}
    |> maybe_put("token_type", Map.get(payload, "token_type") || Map.get(payload, :token_type))
    |> maybe_put("scope", Map.get(payload, "scope") || Map.get(payload, :scope))
    |> maybe_put("guild", Map.get(payload, "guild") || Map.get(payload, :guild))
    |> maybe_put("permissions", Map.get(payload, "permissions") || Map.get(payload, :permissions))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fetch_required(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed != "" do
          {:ok, trimmed}
        else
          {:error, {:missing_key, key}}
        end

      value when is_map(value) ->
        {:ok, value}

      _ ->
        {:error, {:missing_key, key}}
    end
  end

  defp generate_reference(schema, prefix, organization_id, name, external_id, exclude_id \\ nil) do
    slug =
      name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    base =
      ensure_alpha_prefix(prefix, slug, external_id)
      |> String.slice(0, 48)

    ensure_unique_reference(schema, organization_id, base, 0, exclude_id)
  end

  defp ensure_alpha_prefix(prefix, "", external_id),
    do: "#{prefix}_" <> String.slice(String.downcase(to_string(external_id)), 0, 8)

  defp ensure_alpha_prefix(prefix, <<"_", rest::binary>>, external_id),
    do: ensure_alpha_prefix(prefix, rest, external_id)

  defp ensure_alpha_prefix(prefix, <<digit, _::binary>> = value, _external_id)
       when digit >= ?0 and digit <= ?9,
       do: "#{prefix}_" <> value

  defp ensure_alpha_prefix(_prefix, value, _external_id), do: value

  defp ensure_unique_reference(schema, organization_id, base, attempt, exclude_id) do
    candidate =
      case attempt do
        0 -> base
        _ -> "#{base}_#{attempt}"
      end

    exists? =
      schema
      |> from(
        where: [organization_id: ^organization_id, reference: ^candidate],
        where: ^exclude_filter(exclude_id),
        select: 1,
        limit: 1
      )
      |> Repo.exists?()

    if exists? do
      ensure_unique_reference(schema, organization_id, base, attempt + 1, exclude_id)
    else
      candidate
    end
  end

  defp exclude_filter(nil), do: true
  defp exclude_filter(exclude_id), do: dynamic([r], r.id != ^exclude_id)

  defp slack_channel_attrs(installation_id, channel_payload) do
    channel_id = Map.get(channel_payload, "id")
    name = Map.get(channel_payload, "name") || Map.get(channel_payload, "real_name") || channel_id

    is_private =
      case Map.get(channel_payload, "is_private") do
        true -> true
        "true" -> true
        _ -> false
      end

    channel_type = derive_slack_channel_type(channel_payload, is_private)

    %{
      slack_installation_id: installation_id,
      channel_id: channel_id,
      name: name,
      channel_type: channel_type,
      is_private: is_private,
      metadata: channel_metadata(channel_payload)
    }
  end

  defp derive_slack_channel_type(_channel_payload, true), do: "private_channel"

  defp derive_slack_channel_type(channel_payload, false) do
    cond do
      Map.get(channel_payload, "is_channel") -> "public_channel"
      Map.get(channel_payload, "is_group") -> "group"
      Map.get(channel_payload, "is_im") -> "im"
      true -> "channel"
    end
  end

  defp channel_metadata(payload) do
    %{}
    |> maybe_put("topic", get_in(payload, ["topic", "value"]))
    |> maybe_put("purpose", get_in(payload, ["purpose", "value"]))
    |> maybe_put("num_members", Map.get(payload, "num_members"))
  end

  defp allowed_discord_channel?(payload) when is_map(payload) do
    type = Map.get(payload, "type")
    id = Map.get(payload, "id")

    present?(id) and type in [0, 5]
  end

  defp allowed_discord_channel?(_), do: false

  defp ensure_discord_reference(%DiscordInstallation{} = installation) do
    desired_name =
      installation.guild_name ||
        installation.guild_id ||
        "discord_" <> String.slice(to_string(installation.guild_id || "guild"), 0, 8)

    desired_reference =
      generate_reference(
        DiscordInstallation,
        "discord",
        installation.organization_id,
        desired_name,
        installation.guild_id,
        installation.id
      )

    if installation.reference == desired_reference do
      installation
    else
      case installation
           |> DiscordInstallation.changeset(%{reference: desired_reference})
           |> Repo.update() do
        {:ok, updated} -> updated
        _ -> installation
      end
    end
  end

  defp ensure_slack_reference(%SlackInstallation{} = installation) do
    desired_name =
      installation.team_name ||
        installation.team_domain ||
        installation.team_id ||
        "slack_" <> String.slice(to_string(installation.team_id || "team"), 0, 8)

    desired_reference =
      generate_reference(
        SlackInstallation,
        "slack",
        installation.organization_id,
        desired_name,
        installation.team_id,
        installation.id
      )

    if installation.reference == desired_reference do
      installation
    else
      case installation
           |> SlackInstallation.changeset(%{reference: desired_reference})
           |> Repo.update() do
        {:ok, updated} -> updated
        _ -> installation
      end
    end
  end

  defp discord_channel_attrs(installation_id, channel_payload) do
    channel_id = Map.get(channel_payload, "id")
    name = Map.get(channel_payload, "name") || channel_id
    channel_type = discord_channel_type(channel_payload)

    %{
      discord_installation_id: installation_id,
      channel_id: channel_id,
      name: name,
      channel_type: channel_type,
      is_thread: Map.get(channel_payload, "type") in [10, 11, 12],
      metadata: discord_channel_metadata(channel_payload)
    }
  end

  defp discord_channel_type(%{"type" => 0}), do: "text"
  defp discord_channel_type(%{"type" => 5}), do: "announcement"

  defp discord_channel_type(%{"type" => type}) when is_integer(type) do
    "type_#{type}"
  end

  defp discord_channel_type(%{"type" => type}) when is_binary(type), do: type
  defp discord_channel_type(_), do: "channel"

  defp discord_channel_metadata(payload) do
    %{}
    |> maybe_put("topic", Map.get(payload, "topic"))
    |> maybe_put("nsfw", Map.get(payload, "nsfw"))
    |> maybe_put("parent_id", Map.get(payload, "parent_id"))
    |> maybe_put("raw_type", Map.get(payload, "type"))
    |> maybe_put("position", Map.get(payload, "position"))
  end

  defp fetch_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp slack_reference_name_from_payload(payload) do
    get_in(payload, ["team", "name"]) ||
      get_in(payload, [:team, :name]) ||
      Map.get(payload, "team_name") ||
      Map.get(payload, :team_name) ||
      get_in(payload, ["team", "domain"]) ||
      get_in(payload, [:team, :domain]) ||
      Map.get(payload, "team_domain") ||
      Map.get(payload, :team_domain) ||
      get_in(payload, ["team", "id"]) ||
      get_in(payload, [:team, :id]) ||
      Map.get(payload, "team_id") ||
      Map.get(payload, :team_id)
  end

  defp discord_reference_name_from_payload(payload) do
    get_in(payload, ["guild", "name"]) ||
      get_in(payload, [:guild, :name]) ||
      Map.get(payload, "guild_name") ||
      Map.get(payload, :guild_name) ||
      get_in(payload, ["guild", "id"]) ||
      get_in(payload, [:guild, :id]) ||
      Map.get(payload, "guild_id") ||
      Map.get(payload, :guild_id)
  end

  defp discord_bot_token_or_error do
    token = discord_bot_token()

    if is_binary(token) and String.trim(token) != "" do
      {:ok, token}
    else
      {:error, {:missing_config, :bot_token}}
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp to_map(nil), do: %{}
  defp to_map(map) when is_map(map), do: map
  defp to_map(list) when is_list(list), do: Map.new(list)
  defp to_map(other), do: other
end
