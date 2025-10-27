defmodule TrifleApp.Exports.Layout do
  @moduledoc """
  Normalised representation of a renderable layout for visual exports.

  A layout packages the metadata needed to render a GridStack surface (or a
  single widget) alongside the themed viewport information and the component
  that should do the actual rendering.
  """

  @type theme :: :light | :dark

  @type render_spec :: %{
          module: module(),
          function: atom(),
          assigns: map()
        }

  @enforce_keys [:id, :kind]
  defstruct id: nil,
            kind: nil,
            title: nil,
            theme: :light,
            viewport: %{width: 1366, height: 900},
            meta: %{},
            assigns: %{},
            render: nil

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom(),
          title: String.t() | nil,
          theme: theme(),
          viewport: %{width: pos_integer(), height: pos_integer()},
          meta: map(),
          assigns: map(),
          render: render_spec() | nil
        }

  @doc """
  Builds a new layout struct.
  """
  @spec new(Keyword.t() | map()) :: t()
  def new(attrs \\ []) do
    attrs = Enum.into(attrs, %{})

    defaults = %{
      theme: :light,
      viewport: %{width: 1366, height: 900},
      meta: %{},
      assigns: %{}
    }

    struct!(__MODULE__, Map.merge(defaults, attrs))
  end

  @doc """
  Sets the render specification (component/function/assigns) for the layout.
  """
  @spec with_render(t(), module(), atom(), map()) :: t()
  def with_render(%__MODULE__{} = layout, module, function \\ :render, assigns \\ %{}) do
    render = %{module: module, function: function, assigns: assigns}
    %__MODULE__{layout | render: render}
  end

  @doc """
  Adds or replaces a metadata entry on the layout.
  """
  @spec put_meta(t(), term(), term()) :: t()
  def put_meta(%__MODULE__{} = layout, key, value) do
    %__MODULE__{layout | meta: Map.put(layout.meta, key, value)}
  end

  @doc """
  Adds or replaces a top-level assign on the layout.
  """
  @spec put_assign(t(), term(), term()) :: t()
  def put_assign(%__MODULE__{} = layout, key, value) do
    %__MODULE__{layout | assigns: Map.put(layout.assigns, key, value)}
  end
end
