defmodule Trifle.Integrations do
  @moduledoc """
  Context for managing outbound delivery integrations such as Slack.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Trifle.Integrations.Slack.Client
  alias Trifle.Integrations.Slack.State
  alias Trifle.Integrations.{SlackChannel, SlackInstallation}
  alias Trifle.Repo

  @slack_default_scopes ~w(chat:write chat:write.public channels:read groups:read incoming-webhook)

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
    State.sign(user_id, organization_id, metadata)
  end

  def verify_slack_state(token, opts \\ []) do
    State.verify(token, opts)
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
    with {:ok, attrs} <- normalize_installation_attrs(payload, organization_id, user_id) do
      case fetch_slack_installation_by_team(organization_id, attrs.team_id) do
        nil ->
          reference = generate_reference(organization_id, attrs.team_name, attrs.team_id)
          params = Map.put(attrs, :reference, reference)

          %SlackInstallation{}
          |> SlackInstallation.changeset(params)
          |> Repo.insert()

        %SlackInstallation{} = installation ->
          params =
            attrs
            |> Map.put(:reference, installation.reference)

          installation
          |> SlackInstallation.changeset(params)
          |> Repo.update()
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

    Client.exchange_code(config, code)
  end

  def sync_slack_channels(%SlackInstallation{} = installation) do
    with {:ok, channels} <- Client.list_channels(installation.bot_access_token) do
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
            attrs = channel_attrs(installation.id, channel)

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

  ## Helpers

  defp normalize_installation_attrs(payload, organization_id, user_id) do
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
          settings: build_installation_settings(payload)
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      {:ok, attrs}
    else
      {:error, reason} ->
        {:error, {:invalid_payload, reason}}
    end
  end

  defp build_installation_settings(payload) do
    %{}
    |> maybe_put("app_id", Map.get(payload, "app_id"))
    |> maybe_put("authed_user", Map.get(payload, "authed_user"))
    |> maybe_put("incoming_webhook", Map.get(payload, "incoming_webhook"))
    |> maybe_put("enterprise", Map.get(payload, "enterprise"))
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

  defp generate_reference(organization_id, team_name, team_id) do
    base =
      team_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> ensure_alpha_prefix(team_id)
      |> String.slice(0, 48)

    ensure_unique_reference(organization_id, base, 0)
  end

  defp ensure_alpha_prefix("", team_id),
    do: "slack_" <> String.slice(String.downcase(team_id), 0, 8)

  defp ensure_alpha_prefix(<<"_", rest::binary>>, team_id), do: ensure_alpha_prefix(rest, team_id)

  defp ensure_alpha_prefix(<<digit, _::binary>> = value, team_id)
       when digit >= ?0 and digit <= ?9,
       do: "slack_" <> value

  defp ensure_alpha_prefix(value, _team_id), do: value

  defp ensure_unique_reference(organization_id, base, attempt) do
    candidate =
      case attempt do
        0 -> base
        _ -> "#{base}_#{attempt}"
      end

    exists? =
      from(i in SlackInstallation,
        where: i.organization_id == ^organization_id and i.reference == ^candidate,
        select: 1,
        limit: 1
      )
      |> Repo.exists?()

    if exists? do
      ensure_unique_reference(organization_id, base, attempt + 1)
    else
      candidate
    end
  end

  defp channel_attrs(installation_id, channel_payload) do
    channel_id = Map.get(channel_payload, "id")
    name = Map.get(channel_payload, "name") || Map.get(channel_payload, "real_name") || channel_id

    is_private =
      case Map.get(channel_payload, "is_private") do
        true -> true
        "true" -> true
        _ -> false
      end

    channel_type = derive_channel_type(channel_payload, is_private)

    %{
      slack_installation_id: installation_id,
      channel_id: channel_id,
      name: name,
      channel_type: channel_type,
      is_private: is_private,
      metadata: channel_metadata(channel_payload)
    }
  end

  defp derive_channel_type(channel_payload, true), do: "private_channel"

  defp derive_channel_type(channel_payload, false) do
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

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp to_map(nil), do: %{}
  defp to_map(map) when is_map(map), do: map
  defp to_map(list) when is_list(list), do: Map.new(list)
  defp to_map(other), do: other
end
