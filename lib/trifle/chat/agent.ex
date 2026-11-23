defmodule Trifle.Chat.Agent do
  @moduledoc """
  Orchestrates the Baker Agent conversation loop with OpenAI and internal tools.
  """

  alias MapSet
  alias Trifle.Chat.Notifier
  alias Trifle.Chat.OpenAIClient
  alias Trifle.Chat.Progress
  alias Trifle.Chat.Session
  alias Trifle.Chat.SessionStore
  alias Trifle.Chat.Tools
  alias Trifle.Chat.Visualizations

  @max_tool_rounds 5

  @type context :: Tools.context()

  @doc """
  Handles a new user message, appending it to the session and driving the
  OpenAI tool-call loop until a final assistant reply is produced.
  """
  @spec handle_user_message(Session.t(), String.t(), context()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def handle_user_message(%Session{} = session, user_message, context)
      when is_binary(user_message) do
    user_entry = %{
      role: "user",
      content: String.trim(user_message)
    }

    timestamp = DateTime.utc_now()

    with {:ok, pending_session} <-
           SessionStore.append_messages_and_reset_progress(session, [user_entry], timestamp) do
      Notifier.notify(context, {:progress, :received})
      run_loop(pending_session, context, 1)
    end
  end

  @doc """
  Continues processing for a session that already includes the user's prompt.
  """
  @spec resume_pending(Session.t(), context()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def resume_pending(%Session{} = session, context) do
    Notifier.notify(context, {:progress, :resume})
    run_loop(session, context, 1)
  end

  @doc """
  Continues processing for a session that has already been prepared by the
  caller without emitting the interrupted-conversation progress state.
  """
  @spec continue_pending(Session.t(), context()) ::
          {:ok, Session.t(), map()} | {:error, term()}
  def continue_pending(%Session{} = session, context) do
    run_loop(session, context, 1)
  end

  defp run_loop(%Session{} = session, context, iteration) do
    Notifier.notify(context, {:progress, :thinking, thinking_payload(iteration)})
    messages = build_messages(session, context)
    tools_allowed? = iteration <= @max_tool_rounds
    opts = [model: OpenAIClient.model(), tools: Tools.definitions(context)]

    {messages, opts} =
      if tools_allowed? do
        {messages, opts}
      else
        instruction = %{
          "role" => "system",
          "content" =>
            "Give the user a final answer now using the tool results already gathered. " <>
              "If any part of the request remains unverified, say which part and answer from the available evidence."
        }

        {messages ++ [instruction], Keyword.put(opts, :tool_choice, "none")}
      end

    client = Application.get_env(:trifle, :chat_completion_client, OpenAIClient)

    case client.chat_completion(messages, opts) do
      {:ok, %{"choices" => [%{"message" => message} | _]}} when is_map(message) ->
        case message["tool_calls"] do
          [_ | _] when tools_allowed? ->
            handle_tool_calls(session, context, message, iteration)

          [_ | _] ->
            incomplete_response(session)

          _ ->
            store_assistant_message(session, message, context)
        end

      {:ok, _other} ->
        incomplete_response(session)

      {:error, reason} ->
        {:error, normalize_openai_error(reason, session)}
    end
  end

  defp thinking_payload(iteration) do
    %{
      iteration: iteration,
      label: Progress.random_thinking_label()
    }
  end

  defp handle_tool_calls(session, context, message, iteration) do
    assistant_entry = %{
      role: "assistant",
      tool_calls: message["tool_calls"],
      content: message["content"]
    }

    with {:ok, session_with_assistant} <- SessionStore.append_message(session, assistant_entry),
         {:ok, session_after_tools} <-
           execute_tool_calls(session_with_assistant, message["tool_calls"], context) do
      Notifier.notify(context, {:progress, :processing_results})
      run_loop(session_after_tools, context, iteration + 1)
    else
      {:error, reason} ->
        clear_pending_session(session)
        {:error, reason}
    end
  end

  defp store_assistant_message(session, message, context) do
    visualizations = Visualizations.pending_from_messages(session.messages)
    content = coerce_content(message["content"])

    if String.trim(content) == "" and visualizations == [] do
      incomplete_response(session)
    else
      entry = %{role: "assistant", content: content, visualizations: visualizations}

      Notifier.notify(context, {:progress, :responding})

      case SessionStore.append_message_and_clear_pending(session, entry) do
        {:ok, updated_session} ->
          {:ok, updated_session, entry}

        error ->
          clear_pending_session(session)
          error
      end
    end
  end

  defp incomplete_response(session) do
    clear_pending_session(session)

    {:error,
     %{
       status: :incomplete_response,
       message: "Baker stopped before returning an answer. Try again."
     }}
  end

  defp execute_tool_calls(session, tool_calls, context) when is_list(tool_calls) do
    tool_calls
    |> Enum.reduce_while({:ok, session}, fn tool_call, {:ok, acc_session} ->
      name = get_in(tool_call, ["function", "name"])
      arguments = get_in(tool_call, ["function", "arguments"]) || "{}"
      tool_call_id = tool_call["id"] || Ecto.UUID.generate()

      case Tools.execute(name, arguments, context) do
        {:ok, result} ->
          payload = %{
            role: "tool",
            content: Jason.encode!(result),
            tool_call_id: tool_call_id,
            name: name
          }

          case SessionStore.append_message(acc_session, payload) do
            {:ok, session_with_tool} ->
              {:cont, {:ok, session_with_tool}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:error, error_payload} ->
          payload = %{
            role: "tool",
            content: Jason.encode!(error_payload),
            tool_call_id: tool_call_id,
            name: name
          }

          case SessionStore.append_message(acc_session, payload) do
            {:ok, session_with_tool} ->
              {:cont, {:ok, session_with_tool}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp build_messages(%Session{} = session, context) do
    system_message = %{
      "role" => "system",
      "content" => Tools.system_prompt(context)
    }

    trimmed_messages =
      session.messages
      |> Enum.map(&encode_message_for_openai/1)
      |> maybe_trim_history()

    [system_message | trimmed_messages]
  end

  defp encode_message_for_openai(message) do
    role = Map.get(message, :role, Map.get(message, "role"))
    name = Map.get(message, :name, Map.get(message, "name"))
    content = Map.get(message, :content, Map.get(message, "content"))

    encoded_content =
      case role do
        "tool" -> Tools.compact_tool_content_for_model(name, content)
        _ -> content
      end

    %{}
    |> maybe_put("role", role)
    |> maybe_put("content", encoded_content)
    |> maybe_put("tool_calls", Map.get(message, :tool_calls, Map.get(message, "tool_calls")))
    |> maybe_put(
      "tool_call_id",
      Map.get(message, :tool_call_id, Map.get(message, "tool_call_id"))
    )
    |> maybe_put("name", name)
  end

  defp maybe_trim_history(messages) do
    max_messages = Application.get_env(:trifle, __MODULE__, []) |> Keyword.get(:history_limit, 20)

    trimmed =
      if length(messages) > max_messages do
        Enum.take(messages, -max_messages)
      else
        messages
      end

    ensure_tool_sequence(trimmed)
  end

  defp ensure_tool_sequence(messages) do
    do_ensure_tool_sequence(messages, [])
  end

  defp do_ensure_tool_sequence([], acc), do: Enum.reverse(acc)

  defp do_ensure_tool_sequence([%{"role" => "assistant"} = message | rest], acc) do
    tool_calls =
      message
      |> Map.get("tool_calls")
      |> normalize_tool_calls()

    case tool_calls do
      [] ->
        do_ensure_tool_sequence(rest, [message | acc])

      ids ->
        {tool_messages, remainder, satisfied?} = consume_tool_messages(rest, MapSet.new(ids), [])

        if satisfied? do
          sequence = [message | Enum.reverse(tool_messages)]
          new_acc = Enum.reduce(sequence, acc, fn item, acc -> [item | acc] end)
          do_ensure_tool_sequence(remainder, new_acc)
        else
          do_ensure_tool_sequence(remainder, acc)
        end
    end
  end

  defp do_ensure_tool_sequence([message | rest], acc) do
    case Map.get(message, "role") do
      "tool" ->
        do_ensure_tool_sequence(rest, acc)

      _ ->
        do_ensure_tool_sequence(rest, [message | acc])
    end
  end

  defp normalize_tool_calls(nil), do: []
  defp normalize_tool_calls([]), do: []

  defp normalize_tool_calls(tool_calls) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(fn
      %{"id" => id} -> id
      %{id: id} -> id
      id when is_binary(id) -> id
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tool_calls(tool_calls) when is_map(tool_calls) do
    tool_calls
    |> Map.values()
    |> normalize_tool_calls()
  end

  defp consume_tool_messages(rest, pending_ids, acc) do
    cond do
      MapSet.size(pending_ids) == 0 ->
        {acc, rest, true}

      rest == [] ->
        {acc, rest, false}

      true ->
        [next | tail] = rest

        case Map.get(next, "role") do
          "tool" ->
            tool_call_id = Map.get(next, "tool_call_id")

            cond do
              MapSet.member?(pending_ids, tool_call_id) ->
                consume_tool_messages(
                  tail,
                  MapSet.delete(pending_ids, tool_call_id),
                  [next | acc]
                )

              true ->
                {acc, rest, false}
            end

          _ ->
            {acc, rest, false}
        end
    end
  end

  defp coerce_content(nil), do: ""
  defp coerce_content(content) when is_binary(content), do: content

  defp coerce_content(chunks) when is_list(chunks) do
    chunks
    |> Enum.map(fn
      %{"text" => text} -> text
      other when is_binary(other) -> other
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp coerce_content(other), do: inspect(other)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  if Mix.env() == :test do
    @doc false
    def __build_messages_for_test__(session, context) do
      build_messages(session, context)
    end
  end

  defp normalize_openai_error(error, session)

  defp normalize_openai_error({:http_error, status, _body}, session) do
    clear_pending_session(session)

    %{
      status: :http_error,
      http_status: status,
      message: "The model request failed with HTTP status #{status}. Try again."
    }
  end

  defp normalize_openai_error(%Mint.TransportError{reason: reason}, session) do
    clear_pending_session(session)

    %{
      status: :transport_error,
      message: "Connection to OpenAI failed: #{inspect(reason)}"
    }
  end

  defp normalize_openai_error(%Mint.HTTPError{reason: reason}, session) do
    clear_pending_session(session)

    %{
      status: :http_error,
      message: "HTTP error talking to OpenAI: #{inspect(reason)}"
    }
  end

  defp normalize_openai_error(:missing_api_key, session) do
    clear_pending_session(session)

    %{
      status: :missing_api_key,
      message: "Missing OpenAI API key configuration."
    }
  end

  defp normalize_openai_error(_other, session) do
    clear_pending_session(session)

    %{
      status: :unknown_error,
      message: "The model request failed. Try again."
    }
  end

  defp clear_pending_session(nil), do: nil

  defp clear_pending_session(%Session{} = session) do
    case SessionStore.clear_pending(session) do
      {:ok, updated_session} -> updated_session
      {:error, _} -> session
    end
  end
end
