defmodule Trifle.Monitors.Alert do
  @moduledoc """
  Represents a single alert definition attached to a monitor.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Trifle.Monitors.Monitor
  alias __MODULE__.Settings

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @strategy_values [:threshold, :range, :hampel, :cusum]

  defmodule Settings do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :threshold_direction, Ecto.Enum,
        values: [:above, :below],
        default: :above

      field :threshold_value, :float
      field :range_min_value, :float
      field :range_max_value, :float
      field :hampel_window_size, :integer
      field :hampel_k, :float
      field :hampel_mad_floor, :float
      field :treat_nil_as_zero, :boolean, default: false
      field :cusum_k, :float
      field :cusum_h, :float
    end
  end

  @settings_fields [
    :threshold_direction,
    :threshold_value,
    :range_min_value,
    :range_max_value,
    :hampel_window_size,
    :hampel_k,
    :hampel_mad_floor,
    :treat_nil_as_zero,
    :cusum_k,
    :cusum_h
  ]

  schema "monitor_alerts" do
    field :analysis_strategy, Ecto.Enum,
      values: @strategy_values,
      default: :threshold

    embeds_one :settings, Settings, on_replace: :update

    belongs_to :monitor, Monitor

    timestamps()
  end

  @doc false
  def changeset(alert, attrs) do
    attrs = attrs || %{}
    strategy = resolve_strategy(alert, attrs)

    alert
    |> ensure_settings_struct(strategy)
    |> cast(attrs, [:analysis_strategy, :monitor_id])
    |> validate_required([:analysis_strategy, :monitor_id])
    |> cast_embed(:settings,
      with: &settings_changeset(&1, &2, strategy),
      required: false
    )
  end

  defp resolve_strategy(%__MODULE__{} = alert, attrs) do
    attrs_strategy =
      case Map.fetch(attrs, "analysis_strategy") do
        {:ok, value} -> value
        :error -> Map.get(attrs, :analysis_strategy)
      end

    attrs_strategy =
      case attrs_strategy do
        value when is_atom(value) -> value
        value when is_binary(value) -> safe_to_existing_atom(value)
        _ -> nil
      end

    cond do
      attrs_strategy in @strategy_values ->
        attrs_strategy

      alert.analysis_strategy in @strategy_values ->
        alert.analysis_strategy

      true ->
        :threshold
    end
  end

  defp ensure_settings_struct(%__MODULE__{analysis_strategy: current} = alert, strategy) do
    settings =
      cond do
        current != nil and current != strategy ->
          default_settings_struct(strategy)

        is_nil(alert.settings) ->
          default_settings_struct(strategy)

        true ->
          alert.settings
      end

    %{alert | settings: settings}
  end

  defp default_settings_struct(strategy) do
    base = %Settings{}

    case strategy do
      :threshold ->
        %{base | threshold_direction: base.threshold_direction, threshold_value: nil}

      :range ->
        %{base | range_min_value: nil, range_max_value: nil}

      :hampel ->
        %{
          base
          | hampel_window_size: nil,
            hampel_k: nil,
            hampel_mad_floor: nil,
            treat_nil_as_zero: false
        }

      :cusum ->
        %{base | cusum_k: nil, cusum_h: nil}

      _ ->
        base
    end
  end

  defp settings_changeset(%Settings{} = settings, attrs, strategy) do
    attrs = attrs || %{}

    settings
    |> cast(attrs, @settings_fields, empty_values: [""])
    |> apply_strategy_validations(strategy)
  end

  defp apply_strategy_validations(changeset, :threshold) do
    changeset
    |> validate_required([:threshold_value])
    |> validate_number(:threshold_value, message: "must be a number")
  end

  defp apply_strategy_validations(changeset, :range) do
    changeset
    |> validate_required([:range_min_value, :range_max_value])
    |> validate_number(:range_min_value, message: "must be a number")
    |> validate_number(:range_max_value, message: "must be a number")
    |> validate_change(:range_max_value, fn :range_max_value, max_value ->
      min_value = get_field(changeset, :range_min_value)

      if is_number(min_value) and is_number(max_value) and max_value <= min_value do
        [range_max_value: "must be greater than minimum value"]
      else
        []
      end
    end)
  end

  defp apply_strategy_validations(changeset, :hampel) do
    changeset
    |> validate_required([:hampel_window_size, :hampel_k, :hampel_mad_floor])
    |> validate_number(:hampel_window_size,
      message: "must be a positive integer",
      greater_than: 0
    )
    |> validate_number(:hampel_k,
      message: "must be a positive number",
      greater_than: 0
    )
    |> validate_number(:hampel_mad_floor,
      message: "must be zero or greater",
      greater_than_or_equal_to: 0
    )
    |> validate_inclusion(:treat_nil_as_zero, [true, false])
  end

  defp apply_strategy_validations(changeset, :cusum) do
    changeset
    |> validate_required([:cusum_k, :cusum_h])
    |> validate_number(:cusum_k,
      message: "must be zero or greater",
      greater_than_or_equal_to: 0
    )
    |> validate_number(:cusum_h,
      message: "must be a positive number",
      greater_than: 0
    )
  end

  defp apply_strategy_validations(changeset, _), do: changeset

  defp safe_to_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp safe_to_existing_atom(_), do: nil
end
