defmodule Trifle.Organizations.Dashboard do
  use Ecto.Schema
  import Ecto.Changeset
  alias Ecto.UUID

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dashboards" do
    field(:name, :string)
    # Now means Personal (false) / Everyone (true)
    field(:visibility, :boolean, default: false)
    # For public URL access, nullable
    field(:access_token, :string)
    field(:payload, :map, default: %{})
    field(:segments, {:array, :map}, default: [])
    field(:key, :string)
    field(:default_timeframe, :string)
    field(:default_granularity, :string)
    field(:position, :integer, default: 0)

    belongs_to(:organization, Trifle.Organizations.Organization)
    belongs_to(:database, Trifle.Organizations.Database)
    belongs_to(:user, Trifle.Accounts.User)
    belongs_to(:group, Trifle.Organizations.DashboardGroup)

    timestamps()
  end

  def changeset(dashboard, attrs) do
    # Handle payload separately to avoid Ecto's automatic casting
    # Check if payload was provided in attrs - if not, don't modify it
    payload_provided = Map.has_key?(attrs, "payload") || Map.has_key?(attrs, :payload)
    segments_provided = Map.has_key?(attrs, "segments") || Map.has_key?(attrs, :segments)

    {payload_raw, attrs_without_payload} =
      if Map.has_key?(attrs, "payload") do
        Map.pop(attrs, "payload")
      else
        Map.pop(attrs, :payload)
      end

    {segments_raw, cleaned_attrs} =
      if Map.has_key?(attrs_without_payload, "segments") do
        Map.pop(attrs_without_payload, "segments")
      else
        Map.pop(attrs_without_payload, :segments)
      end

    dashboard
    |> cast(cleaned_attrs, [
      :database_id,
      :user_id,
      :name,
      :visibility,
      :access_token,
      :key,
      :default_timeframe,
      :default_granularity,
      :position,
      :group_id,
      :organization_id
    ])
    |> validate_required([:database_id, :user_id, :name, :key, :organization_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:key, min: 1)
    |> handle_payload_field(payload_raw, payload_provided)
    |> handle_segments_field(segments_raw, segments_provided)
    |> unique_constraint(:access_token)
  end

  defp handle_payload_field(changeset, payload_raw, payload_provided) do
    case {payload_provided, payload_raw} do
      # If no payload was provided in attrs, don't modify the existing payload
      {false, _} ->
        changeset

      # Empty or nil payload from forms - reset to empty map  
      {true, nil} ->
        put_change(changeset, :payload, %{})

      {true, ""} ->
        put_change(changeset, :payload, %{})

      # String payload from forms - parse as JSON
      {true, payload} when is_binary(payload) ->
        # Trim whitespace
        trimmed_payload = String.trim(payload)

        if trimmed_payload == "" do
          put_change(changeset, :payload, %{})
        else
          case Jason.decode(trimmed_payload) do
            {:ok, parsed} when is_map(parsed) ->
              put_change(changeset, :payload, parsed)

            {:ok, _parsed} ->
              add_error(changeset, :payload, "must be a valid JSON object")

            {:error, %Jason.DecodeError{position: pos, data: data} = error} ->
              # More detailed error message with position
              context = String.slice(data, max(0, pos - 20), 40)

              add_error(
                changeset,
                :payload,
                "invalid JSON at position #{pos}: #{Exception.message(error)}. Context: '#{context}'"
              )

            {:error, error} ->
              add_error(changeset, :payload, "invalid JSON: #{inspect(error)}")
          end
        end

      # Map payload from API calls - keep as is
      {true, %{} = payload} ->
        put_change(changeset, :payload, payload)

      # Invalid payload type
      {true, _other} ->
        add_error(changeset, :payload, "must be a JSON object or map")
    end
  end

  defp handle_segments_field(changeset, segments_raw, segments_provided) do
    case {segments_provided, segments_raw} do
      {false, _} ->
        changeset

      {true, nil} ->
        put_change(changeset, :segments, [])

      {true, ""} ->
        put_change(changeset, :segments, [])

      {true, segments} when is_binary(segments) ->
        trimmed = String.trim(segments)

        cond do
          trimmed == "" ->
            put_change(changeset, :segments, [])

          true ->
            case Jason.decode(trimmed) do
              {:ok, decoded} ->
                persist_normalized_segments(changeset, decoded)

              {:error, %Jason.DecodeError{position: pos, data: data} = error} ->
                context = String.slice(data, max(0, pos - 20), 40)

                add_error(
                  changeset,
                  :segments,
                  "invalid JSON at position #{pos}: #{Exception.message(error)}. Context: '#{context}'"
                )

              {:error, error} ->
                add_error(changeset, :segments, "invalid JSON: #{inspect(error)}")
            end
        end

      {true, segments} ->
        persist_normalized_segments(changeset, segments)
    end
  end

  defp persist_normalized_segments(changeset, segments) do
    case normalize_segments_input(segments) do
      {:ok, normalized} -> put_change(changeset, :segments, normalized)
      {:error, message} -> add_error(changeset, :segments, message)
    end
  end

  defp normalize_segments_input(nil), do: {:ok, []}

  defp normalize_segments_input(segments) when is_list(segments) do
    segments
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, acc} ->
      case normalize_segment(segment) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      other -> other
    end
  end

  defp normalize_segments_input(_other),
    do: {:error, "must be a list of segments"}

  defp normalize_segment(segment) when is_map(segment) do
    segment_map = stringify_keys(segment)

    type =
      segment_map
      |> Map.get("type", "select")
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> case do
        "text" -> "text"
        "select" -> "select"
        "dropdown" -> "select"
        other when other != "" -> other
        _ -> "select"
      end

    name =
      segment_map
      |> Map.get("name")
      |> case do
        nil -> nil
        value -> value |> to_string() |> String.trim()
      end

    if name in [nil, ""] do
      {:error, "each segment must have a name"}
    else
      id =
        segment_map
        |> Map.get("id")
        |> case do
          nil -> UUID.generate()
          value -> value |> to_string() |> String.trim()
        end

      label =
        segment_map
        |> Map.get("label")
        |> case do
          nil -> name
          value -> value |> to_string() |> String.trim()
        end

      placeholder = normalize_placeholder(Map.get(segment_map, "placeholder"))

      default_value =
        segment_map
        |> Map.get("default_value")
        |> case do
          nil -> nil
          value -> value |> to_string() |> String.trim()
        end

      case type do
        "text" ->
          sanitized = %{
            "id" => id,
            "name" => name,
            "label" => label,
            "type" => "text",
            "placeholder" => placeholder,
            "default_value" => default_value,
            "groups" => []
          }

          {:ok, sanitized}

        _ ->
          groups = Map.get(segment_map, "groups", [])

          with {:ok, normalized_groups, resolved_default} <-
                 normalize_groups(groups, default_value) do
            sanitized = %{
              "id" => id,
              "name" => name,
              "label" => label,
              "type" => "select",
              "placeholder" => placeholder,
              "default_value" => resolved_default,
              "groups" => normalized_groups
            }

            {:ok, sanitized}
          else
            {:error, _} = error -> error
          end
      end
    end
  end

  defp normalize_segment(_other), do: {:error, "each segment must be a map"}

  defp normalize_groups(groups, default_value) when is_list(groups) do
    groups
    |> Enum.reduce_while({:ok, [], default_value, nil}, fn group,
                                                           {:ok, acc, provided_default,
                                                            first_value} ->
      case normalize_group(group) do
        {:ok, normalized, group_first_value} ->
          first_value = first_value || group_first_value
          {:cont, {:ok, [normalized | acc], provided_default, first_value}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, groups_acc, provided_default, first_value} ->
        resolved_default =
          case provided_default do
            nil -> first_value
            "" -> first_value
            value -> value
          end

        normalized_groups =
          groups_acc
          |> Enum.reverse()
          |> Enum.map(&mark_group_defaults(&1, resolved_default))

        {:ok, normalized_groups, resolved_default}

      {:error, _} = error ->
        error
    end
  end

  defp normalize_groups(_other, _default), do: {:error, "groups must be a list"}

  defp mark_group_defaults(group, default_value) do
    items =
      group["items"]
      |> Enum.map(fn item ->
        Map.put(item, "default", !is_nil(default_value) and item["value"] == default_value)
      end)

    Map.put(group, "items", items)
  end

  defp normalize_group(group) when is_map(group) do
    group_map = stringify_keys(group)
    items = Map.get(group_map, "items", [])

    with {:ok, normalized_items, first_value} <- normalize_items(items) do
      id =
        group_map
        |> Map.get("id")
        |> case do
          nil -> UUID.generate()
          value -> value |> to_string() |> String.trim()
        end

      label =
        group_map
        |> Map.get("label")
        |> case do
          nil -> nil
          value -> value |> to_string() |> String.trim()
        end

      sanitized = %{
        "id" => id,
        "label" => label,
        "items" => normalized_items
      }

      {:ok, sanitized, first_value}
    else
      {:error, _} = error -> error
    end
  end

  defp normalize_group(_other), do: {:error, "each group must be a map"}

  defp normalize_items(items) when is_list(items) do
    items
    |> Enum.reduce_while({:ok, [], nil}, fn item, {:ok, acc, first_value} ->
      case normalize_item(item) do
        {:ok, normalized} ->
          first_value = first_value || normalized["value"]
          {:cont, {:ok, [normalized | acc], first_value}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, list, first_value} -> {:ok, Enum.reverse(list), first_value}
      {:error, _} = error -> error
    end
  end

  defp normalize_items(_other), do: {:error, "items must be a list"}

  defp normalize_item(item) when is_map(item) do
    item_map = stringify_keys(item)

    value =
      item_map
      |> Map.get("value")
      |> case do
        nil -> ""
        v -> v |> to_string() |> String.trim()
      end

    label =
      item_map
      |> Map.get("label")
      |> case do
        nil -> value
        v -> v |> to_string() |> String.trim()
      end

    id =
      item_map
      |> Map.get("id")
      |> case do
        nil -> UUID.generate()
        v -> v |> to_string() |> String.trim()
      end

    sanitized = %{
      "id" => id,
      "label" => label,
      "value" => value
    }

    {:ok, sanitized}
  end

  defp normalize_item(_other), do: {:error, "each item must be a map"}

  defp stringify_keys(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc -> Map.put(acc, to_string(key), value) end)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp normalize_placeholder(nil), do: nil

  defp normalize_placeholder(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_placeholder(value), do: value

  @doc """
  Generates a new public access token for the dashboard
  """
  def generate_public_token(dashboard) do
    token = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
    changeset(dashboard, %{access_token: token})
  end

  @doc """
  Removes the public access token from the dashboard
  """
  def remove_public_token(dashboard) do
    changeset(dashboard, %{access_token: nil})
  end

  def visibility_display(true), do: "Everyone"
  def visibility_display(false), do: "Personal"
end
