defmodule Trifle.Monitors.Monitor do
  @moduledoc """
  Represents a monitor definition that can be configured to emit report or alert events.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Trifle.Accounts.User
  alias Trifle.Monitors.{Alert, Execution}
  alias Trifle.Organizations.{Dashboard, DashboardSegments, Organization}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type_values [:report, :alert]
  @status_values [:active, :paused]
  @trigger_status_values [:idle, :warning, :recovering, :alerting]
  @delivery_media_values [:pdf, :png_light, :png_dark, :file_csv, :file_json]

  schema "monitors" do
    field :name, :string
    field :description, :string
    field :type, Ecto.Enum, values: @type_values
    field :status, Ecto.Enum, values: @status_values, default: :active
    field :target, :map, default: %{}
    field :segment_values, :map, default: %{}
    field :trigger_status, Ecto.Enum, values: @trigger_status_values, default: :idle
    field :source_type, Ecto.Enum, values: [:database, :project]
    field :source_id, :binary_id
    field :alert_metric_key, :string
    field :alert_metric_path, :string
    field :alert_timeframe, :string
    field :alert_granularity, :string
    field :alert_notify_every, :integer, default: 1
    field :locked, :boolean, default: false

    embeds_one :report_settings, ReportSettings, on_replace: :update do
      field :frequency, Ecto.Enum,
        values: [:hourly, :daily, :weekly, :monthly],
        default: :daily

      field :timeframe, :string
      field :granularity, :string
    end

    embeds_many :delivery_channels, DeliveryChannel, on_replace: :delete do
      field :channel, Ecto.Enum,
        values: [:email, :slack_webhook, :webhook, :custom],
        default: :email

      field :label, :string
      field :target, :string
      field :config, :map, default: %{}
    end

    embeds_many :delivery_media, DeliveryMedium, on_replace: :delete do
      field :medium, Ecto.Enum,
        values: [:pdf, :png_light, :png_dark, :file_csv, :file_json],
        default: :pdf
    end

    belongs_to :organization, Organization
    belongs_to :dashboard, Dashboard
    belongs_to :user, User
    belongs_to :created_by, User, foreign_key: :created_by_id

    has_many :alerts, Alert, on_delete: :delete_all
    has_many :executions, Execution

    timestamps()
  end

  @doc """
  Returns a base changeset for monitors.
  """
  def changeset(monitor, attrs) do
    monitor
    |> cast(attrs, [
      :organization_id,
      :created_by_id,
      :user_id,
      :dashboard_id,
      :name,
      :description,
      :type,
      :status,
      :locked,
      :target,
      :segment_values,
      :trigger_status,
      :source_type,
      :source_id,
      :alert_metric_key,
      :alert_metric_path,
      :alert_timeframe,
      :alert_granularity,
      :alert_notify_every
    ])
    |> cast_embed(:report_settings, with: &report_settings_changeset/2, required: false)
    |> cast_embed(:delivery_channels, with: &delivery_channel_changeset/2, required: false)
    |> cast_embed(:delivery_media, with: &delivery_media_changeset/2, required: false)
    |> sanitize_target()
    |> sanitize_segment_values()
    |> validate_required([
      :organization_id,
      :user_id,
      :name,
      :type,
      :status,
      :source_type,
      :source_id
    ])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:alert_notify_every,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 100
    )
    |> maybe_require_dashboard()
    |> maybe_require_alert_target()
    |> maybe_sync_dashboard_reference()
    |> ensure_source_persistence()
  end

  defp report_settings_changeset(settings, attrs) do
    settings
    |> cast(attrs, [:frequency, :timeframe, :granularity])
    |> validate_required([:frequency])
    |> validate_length(:timeframe, max: 64)
    |> validate_length(:granularity, max: 32)
  end

  defp delivery_channel_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:channel, :label, :target, :config])
    |> validate_required([:channel, :target])
    |> validate_length(:label, max: 120)
    |> validate_length(:target, max: 255)
    |> update_change(:config, &normalize_map(&1 || %{}, %{}))
  end

  defp delivery_media_changeset(media, attrs) do
    media
    |> cast(attrs, [:medium])
    |> validate_required([:medium])
    |> validate_inclusion(:medium, @delivery_media_values)
  end

  defp sanitize_target(%Ecto.Changeset{} = changeset) do
    case fetch_change(changeset, :target) do
      :error ->
        changeset

      {:ok, nil} ->
        put_change(changeset, :target, %{})

      {:ok, target} when is_map(target) ->
        put_change(changeset, :target, normalize_map(target, %{}))

      {:ok, target} when is_binary(target) ->
        normalize_target_from_string(changeset, target)

      {:ok, _} ->
        add_error(changeset, :target, "must be a map or JSON object")
    end
  end

  defp sanitize_segment_values(%Ecto.Changeset{} = changeset) do
    value =
      case fetch_change(changeset, :segment_values) do
        {:ok, value} -> value
        :error -> get_field(changeset, :segment_values)
      end

    cond do
      is_nil(value) ->
        put_change(changeset, :segment_values, %{})

      is_map(value) ->
        normalized = DashboardSegments.normalize_value_map(value)
        put_change(changeset, :segment_values, normalized)

      is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          put_change(changeset, :segment_values, %{})
        else
          case Jason.decode(trimmed) do
            {:ok, %{} = decoded} ->
              normalized = DashboardSegments.normalize_value_map(decoded)
              put_change(changeset, :segment_values, normalized)

            {:ok, _other} ->
              add_error(changeset, :segment_values, "must be a JSON object")

            {:error, %Jason.DecodeError{} = error} ->
              add_error(changeset, :segment_values, "invalid JSON: #{Exception.message(error)}")

            {:error, reason} ->
              add_error(
                changeset,
                :segment_values,
                "invalid segment selection: #{inspect(reason)}"
              )
          end
        end

      is_list(value) ->
        try do
          map = Enum.into(value, %{})
          normalized = DashboardSegments.normalize_value_map(map)
          put_change(changeset, :segment_values, normalized)
        rescue
          _ ->
            add_error(changeset, :segment_values, "must be a map or JSON object")
        end

      true ->
        add_error(changeset, :segment_values, "must be a map or JSON object")
    end
  end

  defp normalize_target_from_string(changeset, target) do
    case Jason.decode(target) do
      {:ok, parsed} when is_map(parsed) ->
        put_change(changeset, :target, normalize_map(parsed, %{}))

      {:ok, _other} ->
        add_error(changeset, :target, "must be a JSON object")

      {:error, %Jason.DecodeError{} = error} ->
        add_error(changeset, :target, "invalid JSON: #{Exception.message(error)}")

      {:error, error} ->
        add_error(changeset, :target, "invalid target: #{inspect(error)}")
    end
  end

  defp normalize_map(map, _default) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_map(value) ->
        Map.put(acc, normalize_key(key), normalize_map(value, %{}))

      {key, value}, acc ->
        Map.put(acc, normalize_key(key), value)
    end)
  end

  defp normalize_map(_map, default), do: default

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp maybe_require_dashboard(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :type) do
      :report ->
        validate_required(changeset, [:dashboard_id])

      _ ->
        changeset
    end
  end

  defp maybe_require_alert_target(%Ecto.Changeset{} = changeset) do
    case get_field(changeset, :type) do
      :alert ->
        changeset
        |> validate_required([:alert_metric_key, :alert_metric_path])
        |> validate_length(:alert_metric_key, max: 255)
        |> validate_length(:alert_metric_path, max: 255)

      _ ->
        changeset
    end
  end

  defp maybe_sync_dashboard_reference(%Ecto.Changeset{} = changeset) do
    if get_field(changeset, :type) == :report do
      dashboard_id = get_field(changeset, :dashboard_id)
      target = get_field(changeset, :target) || %{}

      cond do
        dashboard_id ->
          put_change(changeset, :target, Map.put(target, "dashboard_id", dashboard_id))

        Map.has_key?(target, "dashboard_id") ->
          put_change(changeset, :dashboard_id, Map.get(target, "dashboard_id"))

        Map.has_key?(target, :dashboard_id) ->
          put_change(changeset, :dashboard_id, Map.get(target, :dashboard_id))

        true ->
          changeset
      end
    else
      changeset
    end
  end

  defp ensure_source_persistence(%Ecto.Changeset{} = changeset) do
    source_type = get_field(changeset, :source_type) || changeset.data.source_type
    source_id = get_field(changeset, :source_id) || changeset.data.source_id

    cond do
      is_nil(source_type) or is_nil(source_id) ->
        add_error(changeset, :source_id, "must reference a source")

      true ->
        changeset
    end
  end

  @doc """
  Returns the Tailwind background class for representing monitor state.
  """
  def icon_color_class(%__MODULE__{status: :paused}), do: "bg-slate-500"

  def icon_color_class(%__MODULE__{type: :report, status: :active}), do: "bg-emerald-600"

  def icon_color_class(%__MODULE__{type: :alert, status: :active, trigger_status: trigger_status}) do
    case trigger_status do
      :idle -> "bg-emerald-600"
      :warning -> "bg-amber-500"
      :recovering -> "bg-amber-500"
      :alerting -> "bg-red-600"
      _ -> "bg-emerald-600"
    end
  end

  def icon_color_class(%__MODULE__{}), do: "bg-slate-500"
  def icon_color_class(_), do: "bg-slate-500"
end
