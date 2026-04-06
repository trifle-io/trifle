defmodule TrifleApp.ChatBus do
  @moduledoc """
  Per-tab PubSub helpers for chat shell and page context coordination.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1]

  @pubsub Trifle.PubSub

  @spec page_topic(String.t(), String.t()) :: String.t()
  def page_topic(user_id, tab_id) when is_binary(user_id) and is_binary(tab_id) do
    "chat:page:" <> user_id <> ":" <> tab_id
  end

  @spec current_tab_id(Phoenix.LiveView.Socket.t()) :: String.t() | nil
  def current_tab_id(socket) do
    socket.assigns[:chat_tab_id] ||
      if connected?(socket) do
        get_connect_params(socket)["tab_id"]
      end
  rescue
    RuntimeError -> nil
  end

  @spec maybe_subscribe_page_channel(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def maybe_subscribe_page_channel(socket) do
    socket = maybe_assign_tab_id(socket)

    with true <- connected?(socket),
         user_id when is_binary(user_id) <- current_user_id(socket),
         tab_id when is_binary(tab_id) <- socket.assigns[:chat_tab_id] do
      topic = page_topic(user_id, tab_id)

      if socket.assigns[:chat_page_topic] == topic do
        socket
      else
        Phoenix.PubSub.subscribe(@pubsub, topic)
        assign(socket, :chat_page_topic, topic)
      end
    else
      _ -> socket
    end
  end

  @spec publish_page_context(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def publish_page_context(socket, %{} = context) do
    case socket.assigns[:chat_page_topic] do
      topic when is_binary(topic) ->
        Phoenix.PubSub.broadcast_from(@pubsub, self(), topic, {:chat_context_updated, context})
        socket

      _ ->
        socket
    end
  end

  @spec request_page_context(String.t(), String.t(), String.t(), pid()) :: :ok
  def request_page_context(user_id, tab_id, request_id, requester)
      when is_binary(user_id) and is_binary(tab_id) and is_binary(request_id) and
             is_pid(requester) do
    Phoenix.PubSub.broadcast_from(
      @pubsub,
      self(),
      page_topic(user_id, tab_id),
      {:chat_context_request, request_id, requester}
    )
  end

  @spec send_page_action(String.t(), String.t(), String.t(), pid(), map()) :: :ok
  def send_page_action(user_id, tab_id, request_id, requester, %{} = action)
      when is_binary(user_id) and is_binary(tab_id) and is_binary(request_id) and
             is_pid(requester) do
    Phoenix.PubSub.broadcast_from(
      @pubsub,
      self(),
      page_topic(user_id, tab_id),
      {:chat_page_action, request_id, requester, action}
    )
  end

  defp maybe_assign_tab_id(socket) do
    case current_tab_id(socket) do
      tab_id when is_binary(tab_id) -> assign(socket, :chat_tab_id, tab_id)
      _ -> socket
    end
  end

  defp current_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: id} when not is_nil(id) -> to_string(id)
      _ -> nil
    end
  end
end
