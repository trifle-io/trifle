defmodule Trifle.Integrations.Discord.State do
  @moduledoc false

  @salt "discord-oauth-state"

  def sign(user_id, organization_id, metadata \\ %{}) do
    payload =
      metadata
      |> Map.new()
      |> Map.put("user_id", user_id)
      |> Map.put("organization_id", organization_id)
      |> Map.put_new("nonce", nonce())

    Phoenix.Token.sign(TrifleWeb.Endpoint, @salt, payload)
  end

  def verify(token, opts \\ []) do
    max_age = Keyword.get(opts, :max_age, 600)

    case Phoenix.Token.verify(TrifleWeb.Endpoint, @salt, token, max_age: max_age) do
      {:ok, %{"user_id" => user_id, "organization_id" => organization_id} = data} ->
        {:ok,
         %{
           user_id: user_id,
           organization_id: organization_id,
           metadata: Map.drop(data, ["user_id", "organization_id"])
         }}

      {:ok, other} ->
        {:error, {:invalid_state, other}}

      error ->
        error
    end
  end

  defp nonce do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
