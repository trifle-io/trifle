defmodule Trifle.Chat.Bus do
  @moduledoc """
  PubSub helpers for synchronizing chat sessions across LiveViews and tabs.
  """

  alias Trifle.Chat.Session

  @pubsub Trifle.PubSub

  @spec session_topic(String.t()) :: String.t()
  def session_topic(session_id) when is_binary(session_id) do
    "chat:session:" <> session_id
  end

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(session_id) when is_binary(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, session_topic(session_id))
  end

  @spec broadcast_session_updated(Session.t()) :: :ok
  def broadcast_session_updated(%Session{id: session_id} = session) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      session_topic(session_id),
      {:chat_session_updated, session_id, session}
    )
  end
end
