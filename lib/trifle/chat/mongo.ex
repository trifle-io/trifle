defmodule Trifle.Chat.Mongo do
  @moduledoc """
  Light wrapper around the MongoDB connection used for ChatLive session storage.

  The connection is optional – it will only be started when the configuration
  provides the necessary connection details. This allows local development and
  tests to disable chat persistence when MongoDB is unavailable.
  """

  @default_name __MODULE__

  def child_spec(_opts) do
    unless enabled?() do
      raise ArgumentError,
            "Trifle.Chat.Mongo attempted to start without :url configuration. " <>
              "Either configure the connection or disable it via enabled: false."
    end

    config = Keyword.put_new(config(), :name, @default_name)

    case Keyword.fetch(config, :url) do
      {:ok, url} when is_binary(url) and url != "" -> :ok
      _ -> raise ArgumentError, "Trifle.Chat.Mongo requires :url configuration"
    end

    Mongo.child_spec(config)
  end

  @doc """
  Returns true when the chat Mongo connection should be started.
  """
  def enabled? do
    config = config()
    Keyword.get(config, :enabled, true) and config[:url] not in [nil, ""]
  end

  @doc """
  Returns the connection name that should be used for Mongo queries.
  """
  def conn_name do
    config()
    |> Keyword.get(:name, @default_name)
  end

  @doc """
  Reads runtime configuration for the chat Mongo connection.
  """
  def config do
    Application.get_env(:trifle, __MODULE__, [])
  end
end
