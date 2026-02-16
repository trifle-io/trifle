defmodule TrifleApp.DesignSystem.DatabaseLabel do
  use Phoenix.Component

  @doc """
  Renders a consistent database type label with blue styling.

  ## Examples

      <.database_label driver="postgres" />
      <.database_label driver="redis" />
  """
  attr :driver, :string, required: true
  attr :class, :string, default: ""

  def driver_display_name("mysql"), do: "MySQL"
  def driver_display_name("postgres"), do: "Postgres"
  def driver_display_name("mongo"), do: "MongoDB"
  def driver_display_name("redis"), do: "Redis"
  def driver_display_name("sqlite"), do: "SQLite"
  def driver_display_name(driver) when is_binary(driver), do: String.capitalize(driver)
  def driver_display_name(_driver), do: "Unknown"

  def database_label(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-md bg-blue-50 dark:bg-blue-900/20 px-2 py-1 text-xs font-medium text-blue-700 dark:text-blue-300 ring-1 ring-inset ring-blue-600/20 dark:ring-blue-400/30",
      @class
    ]}>
      {driver_display_name(@driver)}
    </span>
    """
  end
end
