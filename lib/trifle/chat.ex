defmodule Trifle.Chat do
  @moduledoc """
  Public-facing API for the ChatLive feature.
  """

  alias Trifle.Chat.Agent
  alias Trifle.Chat.Session
  alias Trifle.Chat.SessionStore
  alias Trifle.Stats.Source

  @type context :: Agent.context()

  @doc """
  Ensures a session exists for the given user, organization, and analytics source.
  """
  @spec ensure_session(struct(), struct(), Source.t()) ::
          {:ok, Session.t()} | {:error, term()}
  def ensure_session(user, membership, %Source{} = source) do
    user_id = user.id |> to_string()
    org_id = membership.organization_id |> to_string()

    SessionStore.fetch_or_create(user_id, org_id, source_ref(source))
  end

  @doc """
  Resets the conversation, clearing all messages while preserving the session.
  """
  @spec reset(Session.t()) :: {:ok, Session.t()} | {:error, term()}
  def reset(session), do: SessionStore.reset(session)

  @doc """
  Handles a user's message and returns the updated session alongside the
  assistant's latest reply entry.
  """
  @spec handle_user_message(Session.t(), String.t(), context()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def handle_user_message(session, message, context) do
    Agent.handle_user_message(session, message, context)
  end

  @doc """
  Continues a pending conversation without appending a new user message.
  """
  @spec resume_pending(Session.t(), context()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def resume_pending(session, context) do
    Agent.resume_pending(session, context)
  end

  @doc """
  Returns true when the session appears to have an in-flight assistant response.
  """
  @spec pending?(Session.t() | nil) :: boolean()
  def pending?(nil), do: false

  def pending?(%Session{pending_started_at: %DateTime{}}), do: true

  def pending?(%Session{messages: messages}) do
    case List.last(messages) do
      nil ->
        false

      message ->
        role = Map.get(message, :role) || Map.get(message, "role")
        tool_calls = Map.get(message, :tool_calls, Map.get(message, "tool_calls"))
        content = Map.get(message, :content, Map.get(message, "content", ""))

        cond do
          role in ["user", "tool"] ->
            true

          role == "assistant" and tool_calls not in [nil, []] ->
            true

          role == "assistant" and (is_binary(content) and String.trim(content) == "") ->
            true

          true ->
            false
        end
    end
  end

  @doc """
  Builds the tool context from the LiveView assigns.
  """
  @spec build_context(Source.t() | nil, [Source.t()], map()) :: context()
  def build_context(active_source, sources, assigns \\ %{}) do
    base = %{
      source: active_source,
      sources: sources,
      user: Map.get(assigns, :current_user),
      organization: Map.get(assigns, :current_organization)
    }

    case Map.get(assigns, :notify) do
      nil -> base
      notify -> Map.put(base, :notify, notify)
    end
  end

  @doc """
  Converts stored messages into a render-friendly format, excluding internal tool chatter.
  """
  @spec renderable_messages(Session.t() | nil) :: [map()]
  def renderable_messages(nil), do: []

  def renderable_messages(%Session{} = session) do
    session.messages
    |> Enum.filter(&(&1.role in ["user", "assistant"]))
    |> Enum.map(fn message ->
      role = Map.get(message, :role) || Map.get(message, "role")

      content =
        Map.get(message, :content) ||
          Map.get(message, "content") ||
          ""

      created_at =
        Map.get(message, :created_at) ||
          Map.get(message, "created_at")

      %{
        role: role,
        content: content,
        created_at: created_at
      }
    end)
    |> Enum.reject(&(&1.content in [nil, ""]))
  end

  defp source_ref(%Source{} = source) do
    %{
      type: source |> Source.type() |> Atom.to_string(),
      id: source |> Source.id() |> to_string()
    }
  end
end
