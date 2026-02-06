defmodule TrifleApp.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At the first glance, this module may seem daunting, but its goal is
  to provide some core building blocks in your application, such modals,
  tables, and forms. The components are mostly markup and well documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: TrifleApp.Gettext

  alias Phoenix.LiveView.JS
  require Decimal

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr(:id, :string, required: true)
  attr(:show, :boolean, default: false)
  attr(:on_cancel, JS, default: %JS{})
  slot(:inner_block, required: true)

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-14 shadow-lg ring-1 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr(:id, :string, default: "flash", doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:title, :string, default: nil)
  attr(:kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup")
  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  slot(:inner_block, doc: "the optional inner block that renders the flash message")

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 w-80 sm:w-96 z-[12000] rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} title="Success!" flash={@flash} />
    <.flash kind={:error} title="Error!" flash={@flash} />
    <.flash
      id="disconnected"
      kind={:error}
      title="We can't find the internet"
      phx-disconnected={show("#disconnected")}
      phx-connected={hide("#disconnected")}
      hidden
    >
      Attempting to reconnect <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr(:for, :any, required: true, doc: "the datastructure for the form")
  attr(:as, :any, default: nil, doc: "the server side parameter to collect all input under")

  attr(:rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target),
    doc: "the arbitrary HTML attributes to apply to the form tag"
  )

  slot(:inner_block, required: true)
  slot(:actions, doc: "the slot for form actions, such as a submit button")

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr(:type, :string, default: nil)
  attr(:class, :any, default: nil)
  attr(:rest, :global, include: ~w(disabled form name value))

  slot(:inner_block, required: true)

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-teal-500 hover:bg-teal-600 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `%Phoenix.HTML.Form{}` and field name may be passed to the input
  to build input names and error messages, or all the attributes and
  errors may be passed explicitly.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:help, :string, default: nil)
  attr(:value, :any)

  attr(:type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week)
  )

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"
  )

  attr(:errors, :list, default: [])
  attr(:checked, :boolean, doc: "the checked flag for checkbox inputs")
  attr(:prompt, :string, default: nil, doc: "the prompt for select inputs")
  attr(:options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2")
  attr(:multiple, :boolean, default: false, doc: "the multiple flag for select inputs")

  attr(:rest, :global,
    include: ~w(autocomplete cols disabled form list max maxlength min minlength
                pattern placeholder readonly required rows size step)
  )

  slot(:inner_block)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn -> Phoenix.HTML.Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
      <p :if={@help} class="mt-1 text-sm text-zinc-500">{@help}</p>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="mt-1 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
      <p :if={@help} class="mt-1 text-sm text-zinc-500">{@help}</p>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          "min-h-[6rem] border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
      <p :if={@help} class="mt-1 text-sm text-zinc-500">{@help}</p>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={normalized_input_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
      <p :if={@help} class="mt-1 text-sm text-zinc-500">{@help}</p>
    </div>
    """
  end

  defp normalized_input_value(type, %Decimal{} = value) when type in ["number", "range"] do
    value
    |> Decimal.normalize()
    |> decimal_to_plain_string()
  end

  defp normalized_input_value(_type, %Decimal{} = value) do
    value
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp normalized_input_value(type, {decimal, _})
       when type in ["number", "range"] and is_struct(decimal, Decimal) do
    decimal
    |> Decimal.normalize()
    |> decimal_to_plain_string()
  end

  defp normalized_input_value(type, value)
       when type in ["number", "range"] and is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" ->
        ""

      trimmed ->
        case Decimal.parse(trimmed) do
          {decimal, rest} when rest in ["", nil] ->
            decimal
            |> Decimal.normalize()
            |> decimal_to_plain_string()

          :error ->
            Phoenix.HTML.Form.normalize_value(type, value)
        end
    end
  end

  defp normalized_input_value(type, value) when type in ["number", "range"] and is_integer(value),
    do: Integer.to_string(value)

  defp normalized_input_value(type, value) when type in ["number", "range"] and is_float(value) do
    value
    |> Decimal.from_float()
    |> Decimal.normalize()
    |> decimal_to_plain_string()
  end

  defp normalized_input_value(type, value) do
    Phoenix.HTML.Form.normalize_value(type, value)
  end

  defp decimal_to_plain_string(%Decimal{} = decimal) do
    if Decimal.equal?(decimal, Decimal.round(decimal, 0)) do
      decimal
      |> Decimal.to_integer()
      |> Integer.to_string()
    else
      Decimal.to_string(decimal, :normal)
    end
  end

  @doc """
  Renders a label.
  """
  attr(:for, :string, default: nil)
  slot(:inner_block, required: true)

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800 dark:text-white">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot(:inner_block, required: true)

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr(:class, :any, default: nil)

  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800 dark:text-white">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600 dark:text-slate-300">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil, doc: "the function for generating the row id")
  attr(:row_click, :any, default: nil, doc: "the function for handling phx-click on each row")

  attr(:row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"
  )

  slot :col, required: true do
    attr(:label, :string)
  end

  slot(:action, doc: "the slot for showing user actions in the last table column")

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pr-6 pb-4 font-normal">{col[:label]}</th>
            <th class="relative p-0 pb-4"><span class="sr-only">{gettext("Actions")}</span></th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr(:title, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr(:navigate, :any, required: true)
  slot(:inner_block, required: true)

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders the Trifle brand icon.
  """
  attr(:class, :any, default: nil)
  attr(:rest, :global)

  def trifle_logo(assigns) do
    ~H"""
    <svg
      width="100%"
      height="100%"
      viewBox="0 0 72 84"
      version="1.1"
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink"
      xml:space="preserve"
      xmlns:serif="http://www.serif.com/"
      style="fill-rule:evenodd;clip-rule:evenodd;stroke-linejoin:round;stroke-miterlimit:2;"
      fill="currentColor"
      aria-hidden="true"
      {@rest}
    >
      <g>
        <g transform="matrix(1,0,0,1,0.442181,0.243718)">
          <path d="M31.5,2.441C32.41,0.973 33.062,0.441 34.328,0.133C35.938,-0.258 37.812,0.203 40.109,1.551C42.781,3.121 44.746,4.824 46.457,7.059C48.188,9.324 48.191,9.328 49.949,9.789C51.508,10.203 55.07,11.488 56.129,12.023C57.98,12.957 59.535,14.426 60.996,16.617C61.805,17.828 61.949,17.945 63.098,18.285C66.676,19.355 68.371,20.211 69.688,21.609C71.105,23.117 71.52,24.871 71.086,27.527C70.887,28.754 69.461,35.641 68.605,39.504C67.988,42.305 67.125,46.43 66.637,48.918C66.496,49.637 65.625,54.031 64.698,58.684C63.773,63.336 62.844,68.066 62.633,69.188C61.766,73.816 61.184,75.285 59.305,77.625C57.098,80.367 53.527,82.055 48.273,82.836C45.016,83.32 43.504,83.402 37.293,83.445C29.031,83.5 25.117,83.285 21.359,82.578C17.242,81.801 14.508,80.531 12.48,78.457C11.734,77.691 11.434,77.301 10.84,76.352C9.531,74.262 9.191,73.16 8.128,67.578C7.801,65.844 7.367,63.633 7.16,62.66C6.957,61.691 6.012,56.98 5.059,52.195C2.784,40.777 2.594,39.84 1.444,34.504C0.905,32.008 0.375,29.453 0.262,28.832C-0.293,25.77 0.008,24.168 1.418,22.66C2.879,21.09 5.582,19.801 8.984,19.051C9.707,18.891 10.469,18.684 10.672,18.594C11.09,18.41 11.07,18.434 11.984,17.023C13.133,15.25 14.125,14.156 15.531,13.113C17.25,11.84 19.172,10.898 22.293,9.797C25.559,8.645 26.203,8.363 27.125,7.688C28.543,6.645 29.918,4.992 31.5,2.441ZM34.734,6.745C35.085,6.25 35.374,5.622 35.582,4.758C35.642,4.51 36.817,4.538 37.579,5.188C38.595,6.055 38.775,6.146 40.189,7.537C41.072,8.406 41.063,8.663 42.614,10.601C43.985,12.316 44.749,12.811 45.393,13.308C46.28,13.999 47.615,14.101 49.764,14.691C51.299,15.113 53.209,15.944 53.881,16.279C54.552,16.615 55.159,17.202 55.686,17.714C56.073,18.085 56.538,18.716 56.968,19.56C58.136,21.853 58.887,22.126 61.519,22.946C63.828,23.665 65.197,23.828 65.792,24.277C65.952,24.398 63.632,24.709 61.726,25.201C59.468,25.787 54.561,26.193 51.514,26.517C44.788,27.232 39.696,27.33 32.606,27.244C26.172,27.166 24.206,27.315 19.572,27.054C18.458,26.992 9.227,26.125 7.371,25.535C6.559,25.273 5.683,25.054 5.683,25.054C5.683,25.054 8.711,24.248 11.304,23.517C13.336,22.943 14.174,22.668 14.788,22.096C15.344,21.579 16.143,21.105 16.928,19.617C17.814,17.933 17.884,17.679 18.685,16.874C19.814,15.737 20.523,15.249 23.5,14.374C28.055,13.031 29.767,11.527 31.388,10.039C32.485,9.031 33.836,8.014 34.734,6.745ZM36.966,32.393C40.358,32.42 55.253,31.273 58.916,30.863C62.753,30.434 65.952,29.492 65.902,29.784C65.866,30.001 65.332,33.197 64.996,34.904C64.438,37.72 63.254,42.159 63.254,42.159C63.254,42.159 62.357,42.276 60.488,41.743C58.488,41.173 54.915,35.081 52.086,35.097C49.199,35.113 45.938,38.551 43.796,38.648C41.816,38.738 38.558,33.922 36.472,33.895C34.387,33.867 29.347,38.691 24.985,43.37C20.948,47.7 18.168,50.684 15.659,50.376C14.338,50.213 13.783,49.631 9.421,48.619C8.96,48.512 7.428,39.915 7.123,38.458C6.619,36.024 4.879,29.776 4.898,29.752C4.898,29.752 14.403,31.881 19.164,32.039C23.695,32.188 33.764,32.368 36.966,32.393ZM51.768,39.812C53.68,39.816 56.64,45.333 58.792,45.922C61.955,46.788 62.39,46.771 62.39,46.771C62.39,46.771 62.127,48.142 61.66,50.519L60.646,54.754C60.646,54.754 59.789,54.705 59.182,54.3C57.837,53.401 54.638,52.125 53.532,51.498C51.618,50.413 48.266,49.504 46.242,49.345C43.402,49.123 41.191,49.616 37.837,50.69C34.954,51.614 33.852,52.399 31.434,52.954C28.804,53.557 25.944,52.846 25.309,52.662C22.189,51.755 24.074,50.945 28.314,46.258C30.729,43.589 34.162,39.638 36.024,39.584C37.63,39.538 41.474,43.47 43.607,43.444C45.731,43.417 49.622,39.808 51.768,39.812ZM23.993,56.884C26.927,57.485 29.623,57.595 32.211,57.26C34.625,56.948 37.69,55.258 41.236,54.095C43.228,53.441 47.171,53.611 48.72,54.064C51.122,54.767 53.572,56.026 56.297,57.621C58.173,58.72 59.945,59.259 59.945,59.259L59.126,63.698C59.126,63.698 57.441,63.054 56.319,62.559C53.256,61.208 50.066,61.336 47.892,61.89C43.691,62.962 41.873,63.71 38.188,64.952C34.321,66.255 32.594,66.921 29.925,67.705C28.272,68.19 26.087,68.692 23.407,68.997C19.602,69.43 18.697,69.379 17.055,69.166C14.794,68.872 12.426,67.466 12.426,67.466C12.426,67.466 9.719,53.428 9.957,53.456C13.092,53.82 13.177,54.293 15.642,54.841C17.86,55.335 20.597,56.188 23.993,56.884ZM51.557,66.165C57.88,66.668 58.404,68.352 58.404,68.352C58.404,68.352 58.512,70.388 56.584,73.763C56.142,74.537 54.963,75.751 54.271,76.216C53.26,76.891 51.77,77.506 50.285,77.885C45.918,78.998 37.197,79.369 27.236,78.779C24.16,78.599 20.977,77.844 18.607,76.869C14.811,75.306 13.653,72.496 13.653,72.496C13.653,72.496 16.258,73.228 17.004,73.295C18.403,73.421 19.037,73.52 20.954,73.52C23.326,73.52 26.06,73.097 28.169,72.648C31.017,72.041 33.737,71.276 35.728,70.431C37.806,69.549 42.729,67.943 45.969,66.928C47.182,66.548 49.871,66.031 51.557,66.165Z" />
        </g>
        <g transform="matrix(2.779089,0,-0,-7.279669,-18.643586,306.024137)">
          <ellipse cx="12.041" cy="36.556" rx="0.898" ry="0.342" />
        </g>
      </g>
    </svg>
    """
  end

  @doc """
  Renders a [Hero Icon](https://heroicons.com).

  Hero icons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid an mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/heroicons` directory and bundled
  within your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr(:name, :string, required: true)
  attr(:id, :string, default: nil)
  attr(:class, :any, default: nil)

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span id={@id} class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(TrifleApp.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(TrifleApp.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders clickable breadcrumbs with proper navigation links.

  ## Examples

      # Simple string breadcrumbs (legacy support)
      breadcrumb_links(["Projects", "MyProject", "Settings"])
      
      # Clickable breadcrumbs with routes
      breadcrumb_links([
        {"Database", ~p"/dbs"},
        {"MongoDB", ~p"/dbs/123"},
        {"Dashboards", ~p"/dashboards"},
        "Weekly Sales"
      ])
  """
  def breadcrumb_links(assigns) do
    ~H"""
    <h1 class="text-lg font-semibold leading-6 text-gray-900 dark:text-white">
      <%= for {item, index} <- Enum.with_index(@breadcrumbs) do %>
        <%= if index > 0 do %>
          •
        <% end %>
        <%= cond do %>
          <% is_tuple(item) -> %>
            <.link
              navigate={elem(item, 1)}
              class="text-lg font-semibold leading-6 text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400"
            >
              {elem(item, 0)}
            </.link>
          <% true -> %>
            {item}
        <% end %>
      <% end %>
    </h1>
    """
  end

  @doc """
  Formats a breadcrumb list into a string with proper spacing and dividers.
  Uses non-breaking spaces to ensure proper spacing in HTML.

  ## Examples

      format_breadcrumb(["Projects", "MyProject", "Settings"])
      # => "Projects &nbsp;&nbsp;&nbsp;▸&nbsp;&nbsp;&nbsp; MyProject &nbsp;&nbsp;&nbsp;▸&nbsp;&nbsp;&nbsp; Settings"
      
  """
  def format_breadcrumb(breadcrumbs) when is_list(breadcrumbs) do
    breadcrumbs
    |> Enum.map(fn
      # Extract text from tuples
      {text, _path} -> text
      # Keep strings as is
      text -> text
    end)
    |> Enum.join(" • ")
  end

  def format_breadcrumb(breadcrumb) when is_binary(breadcrumb) do
    breadcrumb
  end

  @doc """
  Checks if the breadcrumbs contain any clickable links (tuples).
  """
  def has_clickable_breadcrumbs?(breadcrumbs) when is_list(breadcrumbs) do
    Enum.any?(breadcrumbs, &is_tuple/1)
  end

  def has_clickable_breadcrumbs?(_), do: false

  @doc """
  Returns theme classes based on user preference.

  ## Examples
      
      iex> theme_classes("light")
      ""
      
      iex> theme_classes("dark") 
      "dark"
      
      iex> theme_classes("system")
      ""
  """
  def theme_classes(theme) when theme in ["light", "dark", "system"] do
    case theme do
      "dark" -> "dark"
      "light" -> ""
      # system uses default (no override classes)
      _ -> ""
    end
  end

  def theme_classes(_), do: ""

  @doc """
  Returns theme data attributes for JavaScript theme handling.
  """
  def theme_data_attrs(theme) when theme in ["light", "dark", "system"] do
    %{"data-theme" => theme}
  end

  def theme_data_attrs(_), do: %{"data-theme" => "system"}
end
