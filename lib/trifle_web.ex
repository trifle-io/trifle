defmodule TrifleWeb do
  @moduledoc """
  Skeleton Phoenix wrapper that delegates web concerns to sub-apps.
  """

  @doc """
  Delegates static asset paths to the main TrifleApp.
  """
  @spec static_paths() :: [String.t()]
  def static_paths, do: TrifleApp.static_paths()
end
