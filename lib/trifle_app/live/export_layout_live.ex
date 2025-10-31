defmodule TrifleApp.ExportLayoutLive do
  use Phoenix.LiveView, layout: false

  alias TrifleApp.Exports.{Layout, LayoutSession}

  require Logger

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    case LayoutSession.fetch(token) do
      {:ok, layout} ->
        theme = Map.get(params, "theme") |> normalize_theme(layout.theme)
        layout = %Layout{layout | theme: theme}

        {:ok,
         socket
         |> assign(:export_layout, layout)
         |> assign(:token, token)
         |> assign(:theme, theme)
         |> assign(:error, nil)}

      {:error, reason} ->
        Logger.warning("ExportLayoutLive invalid token: #{inspect(reason)}")
        {:ok, assign(socket, :error, :invalid_token)}
    end
  end

  @impl true
  def render(%{error: :invalid_token} = assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-slate-900 text-white">
      <div class="text-center">
        <p class="text-lg font-semibold">Export token expired or invalid.</p>
        <p class="text-sm opacity-70 mt-2">Please regenerate the export and try again.</p>
      </div>
    </div>
    """
  end

  def render(%{export_layout: %Layout{} = layout} = assigns) do
    ~H"""
    <div
      id="export-layout-root"
      class={[
        "export-layout-root min-h-screen text-slate-900",
        theme_root_class(@theme)
      ]}
      style="background: transparent;"
    >
      {theme_script(@theme)}
      <div class="export-layout-canvas">
        {layout_content(%{layout: layout})}
      </div>
    </div>
    """
  end

  attr :layout, Layout, required: true

  defp layout_content(%{layout: %Layout{render: %{module: module}} = layout}) do
    function = layout.render.function || :render

    render_assigns =
      layout.render.assigns
      |> Map.put_new(:current_user, nil)
      |> Map.put_new(:__changed__, %{})
      |> Map.put_new(:__slot__, %{})

    apply(module, function, [render_assigns])
  end

  defp layout_content(_assigns), do: Phoenix.HTML.raw("<!-- Missing render spec -->")

  defp theme_root_class(:dark), do: "dark text-slate-100"
  defp theme_root_class(_), do: "text-slate-900"

  defp theme_script(:dark) do
    Phoenix.HTML.raw("""
    <script>
      try {
        document.documentElement.classList.add('dark');
        if (document.body) {
          document.body.classList.add('dark');
          document.body.style.background = 'transparent';
        }
        document.documentElement.style.background = 'transparent';
      } catch (_) {}
    </script>
    """)
  end

  defp theme_script(_) do
    Phoenix.HTML.raw("""
    <script>
      try {
        document.documentElement.classList.remove('dark');
        if (document.body) {
          document.body.classList.remove('dark');
          document.body.style.background = 'transparent';
        }
        document.documentElement.style.background = 'transparent';
      } catch (_) {}
    </script>
    """)
  end

  defp normalize_theme(nil, fallback), do: fallback

  defp normalize_theme(theme, fallback) when is_binary(theme) do
    case String.downcase(String.trim(theme)) do
      "dark" -> :dark
      "light" -> :light
      _ -> fallback
    end
  end

  defp normalize_theme(theme, _fallback) when theme in [:dark, :light], do: theme
  defp normalize_theme(_theme, fallback), do: fallback

  @impl true
  def terminate(_reason, %{assigns: %{token: token}}) when is_binary(token) do
    _ = LayoutSession.consume(token)
    :ok
  end

  def terminate(_reason, _socket), do: :ok
end
