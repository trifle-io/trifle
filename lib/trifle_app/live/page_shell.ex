defmodule TrifleApp.Live.PageShell do
  @moduledoc """
  Shared plumbing for data pages (dashboard, explore, monitor), attached via
  `on_mount`: the export dropdown, the transponder-error modal, async
  loading-progress messages, and chat page-context requests.

  Views mounting this hook must implement `chat_page_context/1`, returning
  the page-context map sent back to the chat shell.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias TrifleApp.ChatPageContext

  @callback chat_page_context(Phoenix.LiveView.Socket.t()) :: map()

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(:page_shell_events, :handle_event, &handle_event/3)
     |> attach_hook(:page_shell_info, :handle_info, &handle_info/2)}
  end

  defp handle_event("toggle_export_dropdown", _params, socket) do
    current = socket.assigns[:show_export_dropdown] || false
    {:halt, assign(socket, :show_export_dropdown, !current)}
  end

  defp handle_event("hide_export_dropdown", _params, socket) do
    {:halt, assign(socket, :show_export_dropdown, false)}
  end

  defp handle_event("show_transponder_errors", _params, socket) do
    {:halt, assign(socket, :show_error_modal, true)}
  end

  defp handle_event("hide_transponder_errors", _params, socket) do
    {:halt, assign(socket, :show_error_modal, false)}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp handle_info({:loading_progress, progress_map}, socket) do
    {:halt, assign(socket, :loading_progress, progress_map)}
  end

  defp handle_info({:transponding, state}, socket) do
    {:halt, assign(socket, :transponding, state)}
  end

  defp handle_info({:chat_context_request, request_id, requester}, socket) do
    send(requester, {:chat_context_response, request_id, socket.view.chat_page_context(socket)})
    {:halt, socket}
  end

  defp handle_info({:chat_context_request, request_id, requester, expected_path}, socket) do
    context = socket.view.chat_page_context(socket)

    if ChatPageContext.matches_path?(context, expected_path) do
      send(requester, {:chat_context_response, request_id, context})
    end

    {:halt, socket}
  end

  defp handle_info(_msg, socket), do: {:cont, socket}
end
