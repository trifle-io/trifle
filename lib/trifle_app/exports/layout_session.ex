defmodule TrifleApp.Exports.LayoutSession do
  @moduledoc """
  Generates and validates signed tokens that grant temporary access to export
  layouts.

  Tokens reference an entry in `TrifleApp.Exports.LayoutStore` and expire
  quickly to reduce exposure.
  """

  alias TrifleApp.Exports.Layout
  alias TrifleApp.Exports.LayoutStore

  @salt "export-layout-token"
  @default_max_age 120

  @doc """
  Stores the layout and returns a signed token that can be used to retrieve it.
  """
  @spec sign(Layout.t(), Keyword.t()) :: String.t()
  def sign(%Layout{} = layout, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, 60_000)
    id = LayoutStore.put(layout, ttl: ttl)
    Phoenix.Token.sign(TrifleWeb.Endpoint, @salt, %{"id" => id})
  end

  @doc """
  Verifies the token and fetches the stored layout without consuming it.
  """
  @spec fetch(String.t(), Keyword.t()) :: {:ok, Layout.t()} | {:error, term()}
  def fetch(token, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, @default_max_age)

    with {:ok, %{"id" => id}} <-
           Phoenix.Token.verify(TrifleWeb.Endpoint, @salt, token, max_age: max_age),
         {:ok, layout} <- LayoutStore.fetch(id) do
      {:ok, layout}
    end
  end

  @doc """
  Verifies the token and consumes the stored layout.
  """
  @spec consume(String.t(), Keyword.t()) :: {:ok, Layout.t()} | {:error, term()}
  def consume(token, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, @default_max_age)

    with {:ok, %{"id" => id}} <-
           Phoenix.Token.verify(TrifleWeb.Endpoint, @salt, token, max_age: max_age),
         {:ok, layout} <- LayoutStore.take(id) do
      {:ok, layout}
    end
  end
end
