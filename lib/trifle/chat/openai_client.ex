defmodule Trifle.Chat.OpenAIClient do
  @moduledoc """
  Minimal OpenAI HTTP client tailored for ChatLive.
  """

  require Logger

  @endpoint "https://api.openai.com/v1/chat/completions"

  @spec chat_completion(list(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def chat_completion(messages, opts \\ []) when is_list(messages) do
    with {:ok, api_key} <- fetch_api_key(opts),
         {:ok, body} <- build_body(messages, opts),
         {:ok, response} <- perform_request(body, api_key) do
      Jason.decode(response.body)
    end
  end

  defp build_body(messages, opts) do
    payload =
      %{
        "model" => opts[:model] || default_model(),
        "messages" => messages
      }
      |> maybe_put(:max_completion_tokens, opts[:max_completion_tokens])
      |> maybe_put(:response_format, opts[:response_format])
      |> maybe_put(:tools, opts[:tools])
      |> maybe_put(:tool_choice, opts[:tool_choice])

    Jason.encode(payload)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp perform_request(body, api_key) do
    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    request = Finch.build(:post, @endpoint, headers, body)

    config = config()

    opts = [
      receive_timeout: get_config_value(config, :receive_timeout, 60_000),
      pool_timeout: get_config_value(config, :pool_timeout, 10_000)
    ]

    case Finch.request(request, Trifle.Finch, opts) do
      {:ok, %Finch.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        Logger.error("OpenAI request failed with status #{status}: #{response_body}")
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        Logger.error("OpenAI request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_api_key(opts) do
    case Keyword.get(opts, :api_key) do
      key when is_binary(key) and byte_size(key) > 0 ->
        {:ok, key}

      key when is_nil(key) or key == "" ->
        fetch_configured_api_key()

      _ ->
        fetch_configured_api_key()
    end
  end

  defp fetch_configured_api_key do
    case api_key() do
      key when is_binary(key) and byte_size(key) > 0 -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp default_model do
    model()
  end

  def config do
    Application.get_env(:trifle, __MODULE__, %{})
  end

  def model do
    config()
    |> get_config_value(:model, "gpt-5")
  end

  def api_key do
    config()
    |> get_config_value(:api_key, nil)
  end

  defp get_config_value(config, key, default) when is_map(config) do
    Map.get(config, key, default)
  end

  defp get_config_value(config, key, default) when is_list(config) do
    if Keyword.keyword?(config) do
      Keyword.get(config, key, default)
    else
      default
    end
  end

  defp get_config_value(_config, _key, default), do: default
end
