defmodule TrifleApp.MonitorAlertFormComponent do
  @moduledoc false
  use TrifleApp, :live_component

  alias Ecto.Changeset
  alias Ecto.UUID
  alias Phoenix.LiveView.JS
  alias Trifle.Monitors
  alias Trifle.Monitors.Alert

  @ai_default %{status: :idle, variant: nil, request_id: nil, message: nil}

  @impl true
  def update(%{ai_recommendation: result} = assigns, socket) do
    socket =
      socket
      |> maybe_assign_id(assigns)
      |> apply_ai_recommendation(result)

    {:ok, socket}
  end

  def update(%{ai_recommendation_error: error} = assigns, socket) do
    socket =
      socket
      |> maybe_assign_id(assigns)
      |> apply_ai_error(error)

    {:ok, socket}
  end

  def update(assigns, socket) do
    alert = assigns.alert || %Alert{monitor_id: assigns.monitor.id}
    changeset = assigns[:changeset] || Monitors.change_alert(alert, %{})
    ai_state = socket.assigns[:ai_state] || @ai_default

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:alert, alert)
     |> assign(:action, assigns[:action] || :new)
     |> assign(:ai_state, ai_state)
     |> put_changeset(changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.app_modal id="monitor-alert-modal" show size="sm" on_cancel={JS.push("close_alert_modal")}>
        <:title>
          {if @action == :new, do: "Add alert", else: "Edit alert"}
        </:title>
        <:body>
          <.form
            :let={f}
            for={@changeset}
            as={:alert}
            id="monitor-alert-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="save"
          >
            <div class="space-y-3">
              <.input
                field={f[:analysis_strategy]}
                type="select"
                label="Analysis strategy"
                options={[
                  {"Threshold", "threshold"},
                  {"Range", "range"},
                  {"Hampel (Robust Outlier)", "hampel"},
                  {"CUSUM (Level Shift)", "cusum"}
                ]}
                required
              />

              <.inputs_for :let={settings_form} field={f[:settings]}>
                <%= case @strategy do %>
                  <% :threshold -> %>
                    <div class="space-y-3">
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Threshold alerts fire when the metric crosses a single fixed boundary. Choose whether you want to be warned about surges or drops in the tracked value.
                      </p>
                      <.ai_controls ai_state={@ai_state} myself={@myself} />
                      <.input
                        field={settings_form[:threshold_direction]}
                        type="select"
                        label="Trigger when value is"
                        options={[
                          {"Above threshold", "above"},
                          {"Below threshold", "below"}
                        ]}
                      />
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Direction decides if the alert triggers on upward movement (above) or downward movement (below).
                      </p>
                      <.input
                        field={settings_form[:threshold_value]}
                        type="number"
                        step="any"
                        label="Threshold value"
                        placeholder="e.g. 120"
                        required
                      />
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Threshold value is the numeric boundary; the alert fires as soon as any point crosses it in the chosen direction.
                      </p>
                    </div>
                  <% :range -> %>
                    <div class="space-y-3">
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Range alerts track when the metric escapes a safe band between two limits. We notify you the moment values drift below the minimum or above the maximum.
                      </p>
                      <.ai_controls ai_state={@ai_state} myself={@myself} />
                      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <.input
                          field={settings_form[:range_min_value]}
                          type="number"
                          step="any"
                          label="Minimum"
                          placeholder="e.g. 25"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-2">
                          Minimum is the lower boundary; anything lower triggers an alert.
                        </p>
                        <.input
                          field={settings_form[:range_max_value]}
                          type="number"
                          step="any"
                          label="Maximum"
                          placeholder="e.g. 45"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-2">
                          Maximum is the upper boundary; readings above it also trigger alerts.
                        </p>
                      </div>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Keep the range tight for sensitive monitoring or widen it for tolerant alerting.
                      </p>
                    </div>
                  <% :hampel -> %>
                    <div class="space-y-3">
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Hampel alerts detect robust outliers by comparing each point to the rolling median and scaled median absolute deviation (MAD). It’s ideal for spotting spikes while ignoring gradual trends.
                      </p>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Tune the window, K multiplier, and MAD floor to control sensitivity in noisy data.
                      </p>
                      <.ai_controls ai_state={@ai_state} myself={@myself} />
                      <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
                        <.input
                          field={settings_form[:hampel_window_size]}
                          type="number"
                          step="1"
                          min="1"
                          label="Window size"
                          placeholder="e.g. 7"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-3">
                          Window size is the number of recent points used to compute the rolling median; larger windows smooth more volatility.
                        </p>
                        <.input
                          field={settings_form[:hampel_k]}
                          type="number"
                          step="0.1"
                          label="K threshold"
                          placeholder="e.g. 3.0"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-3">
                          K threshold scales the MAD; higher values make the detector less sensitive to moderate deviations.
                        </p>
                        <.input
                          field={settings_form[:hampel_mad_floor]}
                          type="number"
                          step="0.1"
                          min="0"
                          label="MAD floor"
                          placeholder="e.g. 0.1"
                          required
                        />
                      </div>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        MAD floor prevents the detector from collapsing when variance is near zero by enforcing a minimum spread.
                      </p>
                    </div>
                  <% :cusum -> %>
                    <div class="space-y-3">
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        CUSUM alerts accumulate small deviations over time and trigger when the shift indicates a sustained level change. It excels at catching subtle drifts that wouldn’t cross a single threshold.
                      </p>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        Balance the drift allowance and alarm threshold to set how quickly CUSUM reacts.
                      </p>
                      <.ai_controls ai_state={@ai_state} myself={@myself} />
                      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <.input
                          field={settings_form[:cusum_k]}
                          type="number"
                          step="0.1"
                          min="0"
                          label="K (drift allowance)"
                          placeholder="e.g. 0.5"
                          required
                        />
                        <p class="text-xs text-slate-500 dark:text-slate-400 sm:col-span-2">
                          K (drift allowance) defines the size of deviation ignored in each step; larger values tolerate gradual changes longer.
                        </p>
                        <.input
                          field={settings_form[:cusum_h]}
                          type="number"
                          step="0.1"
                          min="0.1"
                          label="H threshold"
                          placeholder="e.g. 5.0"
                          required
                        />
                      </div>
                      <p class="text-xs text-slate-500 dark:text-slate-400">
                        H threshold is the cumulative score that must be exceeded before an alert fires; lower values trigger sooner.
                      </p>
                    </div>
                  <% _ -> %>
                    <div class="text-xs text-slate-500 dark:text-slate-400">
                      Select an analysis strategy to configure its parameters.
                    </div>
                <% end %>
              </.inputs_for>

              <div class="flex items-center justify-end gap-2">
                <button
                  type="button"
                  class="inline-flex items-center rounded-md border border-slate-300 dark:border-slate-600 px-3 py-1.5 text-xs font-medium text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700/70"
                  phx-click="close_alert_modal"
                >
                  Cancel
                </button>
                <.button type="submit">
                  {if @action == :new, do: "Create alert", else: "Save alert"}
                </.button>
              </div>
            </div>
          </.form>

          <div :if={@action == :edit} class="mt-6 border-t border-red-200 pt-4 dark:border-red-800">
            <div class="mb-3">
              <span class="text-sm font-semibold text-red-700 dark:text-red-200">Danger zone</span>
              <p class="mt-1 text-xs text-red-600 dark:text-red-300">
                Deleting this alert cannot be undone.
              </p>
            </div>
            <button
              type="button"
              class="mt-3 w-full inline-flex items-center justify-center rounded-md bg-red-50 px-3 py-2 text-sm font-semibold text-red-700 ring-1 ring-inset ring-red-600/20 hover:bg-red-100 dark:bg-red-900 dark:text-red-200 dark:ring-red-500/30 dark:hover:bg-red-800"
              phx-click="delete"
              phx-target={@myself}
              data-confirm="Are you sure you want to delete this alert?"
            >
              <svg
                class="-ml-0.5 mr-1.5 h-4 w-4"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                />
              </svg>
              Delete alert
            </button>
          </div>
        </:body>
      </.app_modal>
    </div>
    """
  end

  def handle_event("ai_recommend", %{"variant" => variant_param}, socket) do
    case normalize_variant(variant_param) do
      nil ->
        {:noreply,
         assign(socket, :ai_state, Map.merge(@ai_default, %{status: :error, message: "Choose a valid AI option."}))}

      variant ->
        request_id = UUID.generate()
        strategy = socket.assigns.strategy || :threshold

        notify_parent(
          {:ai_recommendation_request,
           %{
             component_id: socket.assigns.id,
             request_id: request_id,
             variant: variant,
             strategy: strategy
           }}
        )

        {:noreply,
         assign(socket, :ai_state, %{
           status: :loading,
           variant: variant,
           request_id: request_id,
           message: nil
         })}
    end
  end

  @impl true
  def handle_event("validate", %{"alert" => params}, socket) do
    changeset =
      socket.assigns.alert
      |> Monitors.change_alert(params)
      |> Map.put(:action, :validate)

    {:noreply, put_changeset(socket, changeset)}
  end

  def handle_event("save", %{"alert" => params}, socket) do
    case socket.assigns.action do
      :new -> create_alert(socket, params)
      :edit -> update_alert(socket, params)
    end
  end

  def handle_event("delete", _params, socket) do
    case Monitors.delete_alert(socket.assigns.alert) do
      {:ok, alert} ->
        notify_parent({:deleted, alert})
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete alert: #{inspect(reason)}")}
    end
  end

  defp maybe_assign_id(socket, %{id: id}) when is_binary(id) do
    assign(socket, :id, id)
  end

  defp maybe_assign_id(socket, _), do: socket

  defp apply_ai_recommendation(socket, %{request_id: request_id} = result) do
    current_state = socket.assigns[:ai_state] || @ai_default

    cond do
      current_state.request_id && current_state.request_id != request_id ->
        socket

      strategy_conflict?(socket.assigns[:strategy], result.strategy) ->
        assign(socket, :ai_state, %{
          status: :stale,
          variant: current_state.variant,
          request_id: nil,
          message:
            "Recommendation used #{human_strategy(result.strategy)}, but the form now uses #{human_strategy(socket.assigns[:strategy])}. Request a fresh suggestion."
        })

      true ->
        variant =
          result.variant
          |> normalize_variant()
          |> case do
            nil -> current_state.variant
            value -> value
          end

        strategy =
          normalize_strategy_value(result.strategy) ||
            socket.assigns[:strategy] ||
            :threshold

        params = %{
          "analysis_strategy" => to_string(strategy),
          "settings" => result.settings || %{}
        }

        changeset =
          socket.assigns.alert
          |> Monitors.change_alert(params)
          |> Map.put(:action, :validate)

        socket
        |> assign(:ai_state, %{
          status: :success,
          variant: variant,
          request_id: request_id,
          message: safe_summary(result.summary, variant)
        })
        |> put_changeset(changeset)
    end
  end

  defp apply_ai_recommendation(socket, _result), do: socket

  defp apply_ai_error(socket, %{request_id: request_id, message: message}) do
    current_state = socket.assigns[:ai_state] || @ai_default

    cond do
      current_state.request_id && current_state.request_id != request_id ->
        socket

      true ->
        assign(socket, :ai_state, %{
          status: :error,
          variant: current_state.variant,
          request_id: nil,
          message: safe_error_message(message)
        })
    end
  end

  defp apply_ai_error(socket, _), do: socket

  defp strategy_conflict?(nil, _), do: false
  defp strategy_conflict?(_, nil), do: false
  defp strategy_conflict?(current, result), do: normalize_strategy_value(result) != normalize_strategy_value(current)

  defp normalize_strategy_value(value) when value in [:threshold, :range, :hampel, :cusum], do: value

  defp normalize_strategy_value(value) when is_binary(value) do
    case String.downcase(value) do
      "threshold" -> :threshold
      "range" -> :range
      "hampel" -> :hampel
      "cusum" -> :cusum
      _ -> nil
    end
  end

  defp normalize_strategy_value(_), do: nil

  defp normalize_variant(value) when value in [:conservative, :balanced, :sensitive], do: value

  defp normalize_variant(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "conservative" -> :conservative
      "balanced" -> :balanced
      "sensitive" -> :sensitive
      _ -> nil
    end
  end

  defp normalize_variant(_), do: nil

  defp safe_summary(summary, variant) do
    summary
    |> safe_trimmed_string()
    |> case do
      nil -> success_caption(variant)
      value -> String.slice(value, 0, 200)
    end
  end

  defp safe_error_message(message) do
    message
    |> safe_trimmed_string()
    |> case do
      nil -> "Could not fetch AI recommendation. Try again."
      value -> String.slice(value, 0, 200)
    end
  end

  defp safe_trimmed_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp safe_trimmed_string(_), do: nil

  defp success_caption(nil), do: "AI recommendation applied. Review the values before saving."

  defp success_caption(variant),
    do: "#{variant_label(variant)} recommendation applied. Review the values before saving."

  defp human_strategy(value) do
    case normalize_strategy_value(value) do
      :threshold -> "Threshold"
      :range -> "Range"
      :hampel -> "Hampel"
      :cusum -> "CUSUM"
      _ -> "this strategy"
    end
  end

  defp human_variant(nil), do: "Balanced"
  defp human_variant(variant), do: variant_label(variant)

  defp create_alert(socket, params) do
    case Monitors.create_alert(socket.assigns.monitor, params) do
      {:ok, alert} ->
        notify_parent({:saved, alert, :new})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_changeset(socket, changeset)}
    end
  end

  defp update_alert(socket, params) do
    case Monitors.update_alert(socket.assigns.alert, params) do
      {:ok, alert} ->
        notify_parent({:saved, alert, :edit})
        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_changeset(socket, changeset)}
    end
  end

  defp notify_parent(message), do: send(self(), {__MODULE__, message})

  defp ai_controls(assigns) do
    assigns =
      assigns
      |> assign_new(:ai_state, fn -> @ai_default end)
      |> assign_new(:myself, fn -> nil end)

    ~H"""
    <div class="space-y-2">
      <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-300">
        AI Recommendation
      </h4>

      <div class="flex flex-row gap-2">
        <button
          type="button"
          class={variant_button_classes(:conservative, @ai_state)}
          phx-click="ai_recommend"
          phx-target={@myself}
          phx-value-variant="conservative"
          disabled={@ai_state.status == :loading}
        >
          <.icon
            :if={variant_loading?(@ai_state, :conservative)}
            name="hero-arrow-path"
            class="h-4 w-4 animate-spin"
          />
          <.icon
            :if={variant_success?(@ai_state, :conservative)}
            name="hero-check-mini"
            class="h-4 w-4"
          />
          <span>{variant_label(:conservative)}</span>
        </button>

        <button
          type="button"
          class={variant_button_classes(:balanced, @ai_state)}
          phx-click="ai_recommend"
          phx-target={@myself}
          phx-value-variant="balanced"
          disabled={@ai_state.status == :loading}
        >
          <.icon
            :if={variant_loading?(@ai_state, :balanced)}
            name="hero-arrow-path"
            class="h-4 w-4 animate-spin"
          />
          <.icon
            :if={variant_success?(@ai_state, :balanced)}
            name="hero-check-mini"
            class="h-4 w-4"
          />
          <span>{variant_label(:balanced)}</span>
        </button>

        <button
          type="button"
          class={variant_button_classes(:sensitive, @ai_state)}
          phx-click="ai_recommend"
          phx-target={@myself}
          phx-value-variant="sensitive"
          disabled={@ai_state.status == :loading}
        >
          <.icon
            :if={variant_loading?(@ai_state, :sensitive)}
            name="hero-arrow-path"
            class="h-4 w-4 animate-spin"
          />
          <.icon
            :if={variant_success?(@ai_state, :sensitive)}
            name="hero-check-mini"
            class="h-4 w-4"
          />
          <span>{variant_label(:sensitive)}</span>
        </button>
      </div>

      <p
        :if={@ai_state.status == :loading}
        class="text-xs text-slate-600 dark:text-slate-300"
      >
        Fetching {human_variant(@ai_state.variant)} recommendation…
      </p>

      <p
        :if={@ai_state.status == :success}
        class="text-xs text-emerald-600 dark:text-emerald-400"
      >
        {@ai_state.message || success_caption(@ai_state.variant)}
      </p>

      <p
        :if={@ai_state.status == :error}
        class="text-xs text-rose-600 dark:text-rose-400"
      >
        {@ai_state.message || "Could not fetch AI recommendation. Try again."}
      </p>

      <p
        :if={@ai_state.status == :stale}
        class="text-xs text-amber-600 dark:text-amber-300"
      >
        {@ai_state.message}
      </p>
    </div>
    """
  end

  defp variant_button_classes(variant, ai_state) do
    base =
      "flex-1 inline-flex items-center justify-center gap-2 rounded-md border px-3 py-2 text-xs font-semibold transition focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-60"

    active? = variant_active?(ai_state, variant)

    color_classes =
      case {variant, active?} do
        {:conservative, true} ->
          "bg-emerald-600 text-white border-emerald-600 hover:bg-emerald-600 focus-visible:ring-emerald-400 dark:bg-emerald-500 dark:hover:bg-emerald-400"

        {:conservative, false} ->
          "bg-emerald-50 text-emerald-700 border-emerald-200 hover:bg-emerald-100 focus-visible:ring-emerald-400 dark:bg-emerald-900/30 dark:text-emerald-200 dark:border-emerald-700/50 dark:hover:bg-emerald-800/40"

        {:balanced, true} ->
          "bg-sky-600 text-white border-sky-600 hover:bg-sky-600 focus-visible:ring-sky-400 dark:bg-sky-500 dark:hover:bg-sky-400"

        {:balanced, false} ->
          "bg-sky-50 text-sky-700 border-sky-200 hover:bg-sky-100 focus-visible:ring-sky-300 dark:bg-sky-900/30 dark:text-sky-200 dark:border-sky-700/50 dark:hover:bg-sky-800/40"

        {:sensitive, true} ->
          "bg-amber-500 text-white border-amber-500 hover:bg-amber-500 focus-visible:ring-amber-400 dark:bg-amber-500 dark:hover:bg-amber-400"

        {:sensitive, false} ->
          "bg-amber-50 text-amber-700 border-amber-200 hover:bg-amber-100 focus-visible:ring-amber-300 dark:bg-amber-900/30 dark:text-amber-200 dark:border-amber-700/50 dark:hover:bg-amber-800/40"
      end

    "#{base} #{color_classes}"
  end

  defp variant_loading?(%{status: :loading, variant: variant}, variant), do: true
  defp variant_loading?(_, _), do: false

  defp variant_success?(%{status: :success, variant: variant}, variant), do: true
  defp variant_success?(_, _), do: false

  defp variant_active?(%{variant: variant, status: status}, variant)
       when status in [:loading, :success, :error, :stale],
       do: true

  defp variant_active?(_, _), do: false


  defp variant_label(:conservative), do: "Conservative"
  defp variant_label(:balanced), do: "Balanced"
  defp variant_label(:sensitive), do: "Sensitive"
  defp variant_label(_), do: "Balanced"

  defp put_changeset(socket, %Changeset{} = changeset) do
    strategy =
      Changeset.get_field(changeset, :analysis_strategy) ||
        socket.assigns.alert.analysis_strategy || :threshold

    socket
    |> assign(:changeset, changeset)
    |> assign(:strategy, strategy)
  end
end
