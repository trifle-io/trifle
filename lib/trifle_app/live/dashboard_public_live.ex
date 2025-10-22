defmodule TrifleApp.DashboardPublicLive do
  use TrifleApp, :live_view

  alias TrifleApp.DashboardLive
  alias TrifleApp.Components.DashboardPage

  def mount(params, session, socket) do
    DashboardLive.mount_public(params, session, socket)
  end

  def handle_params(params, url, socket) do
    DashboardLive.handle_public_params(params, url, socket)
  end

  def handle_event(event, params, socket) do
    DashboardLive.handle_event(event, params, socket)
  end

  def handle_info(message, socket) do
    DashboardLive.handle_info(message, socket)
  end

  def handle_async(tag, result, socket) do
    DashboardLive.handle_async(tag, result, socket)
  end

  def render(assigns) do
    DashboardPage.dashboard(assigns)
  end
end
