defmodule TrifleApp.Components.DashboardWidgets.WidgetType do
  @moduledoc false

  alias Trifle.Stats.Series

  @callback type() :: String.t()
  @callback editor_module() :: module()
  @callback dataset(Series.t() | nil, map()) :: any()
  @callback client_payload(String.t(), map()) :: map() | nil
  @callback normalize_widget(map()) :: map()

  @optional_callbacks normalize_widget: 1
end
