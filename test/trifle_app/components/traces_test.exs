defmodule TrifleApp.Components.TracesTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TrifleApp.Components.Traces

  @endpoint TrifleWeb.Endpoint

  test "every trace filter uses an associated floating label and shared field styling" do
    params = %{
      "path" => "jobs/App.Worker",
      "state" => "warning",
      "reference" => "first",
      "tags" => "queue:default, scheduled",
      "tag_mode" => "all",
      "duration_min" => "250"
    }

    doc =
      render_component(&Traces.filters/1, params: params, paths: ["jobs", "jobs/App.Worker"])
      |> Floki.parse_document!()

    doc = doc ++ trace_list(%{}, params: params, filters_open: true)
    fields = Floki.find(doc, "form input, form select")
    assert length(fields) == 6

    for field <- fields do
      [id] = Floki.attribute(field, "id")
      [name] = Floki.attribute(field, "name")
      [label] = Floki.find(doc, "label[for='#{id}'].filter-field-label")
      [label_class] = Floki.attribute(label, "class")
      assert "-top-2" in String.split(label_class)
      assert "left-2" in String.split(label_class)
      assert Floki.text(label) |> String.trim() != ""

      [field_class] = Floki.attribute(field, "class")
      assert "h-10" in String.split(field_class)
      assert "focus:ring-teal-500" in String.split(field_class)
      assert "dark:bg-slate-800" in String.split(field_class)

      values =
        case field do
          {"select", _, _} -> Floki.attribute(Floki.find(field, "option[selected]"), "value")
          _ -> Floki.attribute(field, "value")
        end

      assert values == [params[name]]
    end

    assert Floki.attribute(doc, "#trace-filter-path", "list") == ["trace-paths"]
    assert Floki.attribute(doc, "#trace-paths option", "value") == ["jobs", "jobs/App.Worker"]
    assert Floki.attribute(doc, "#trace-filter-duration", "type") == ["number"]
    assert Floki.attribute(doc, "#trace-filter-duration", "min") == ["0"]
    assert Floki.attribute(doc, "#trace-filter-duration", "step") == ["1"]
    assert Floki.attribute(doc, "#trace-filters", "phx-submit") == ["apply_activity_filters"]
    assert Floki.attribute(doc, "#trace-filters", "phx-change") == ["apply_activity_filters"]
    assert Floki.attribute(doc, "#trace-filter-path", "phx-debounce") == ["blur"]
    assert Floki.attribute(doc, "#trace-list-filters", "phx-submit") == ["apply_list_filters"]
    assert Floki.attribute(doc, "#trace-list-filters", "phx-change") == []
  end

  test "activity has only path and state, with list filters and Apply grouped in the list" do
    doc = render_component(&Traces.filters/1, params: %{}, paths: []) |> Floki.parse_document!()

    assert Floki.find(doc, ".trace-filter-container > form.trace-filter-pair") != []

    assert Floki.attribute(doc, "#trace-filters input, #trace-filters select", "name") ==
             ["path", "state"]

    assert Floki.find(doc, "#trace-filters button") == []

    list = trace_list(%{}, filters_open: true)

    assert Floki.attribute(list, "#trace-list-filters input, #trace-list-filters select", "name") ==
             ["reference", "tags", "tag_mode", "duration_min"]

    assert Floki.find(list, "#trace-list-filters button[type='submit']")
           |> Floki.text()
           |> String.trim() == "Apply filters"

    assert Floki.find(list, ".trace-list-filter-fields") != []
    assert Floki.find(list, "#trace-filter-path, #trace-filter-state") == []
  end

  test "trace filters retain their unfiltered defaults" do
    doc = render_component(&Traces.filters/1, params: %{}, paths: []) |> Floki.parse_document!()

    assert Floki.attribute(doc, "#trace-filter-path", "placeholder") == ["All traces"]
    assert Floki.attribute(doc, "#trace-filter-state option[selected]", "value") == [""]
    list = trace_list(%{})
    assert Floki.attribute(list, "#trace-filter-tag-mode option[selected]", "value") == ["any"]
    assert Floki.find(list, "#trace-list-filters[hidden]") != []

    assert Floki.find(
             list,
             "#trace-list-filters-toggle[aria-expanded='false'][aria-controls='trace-list-filters']"
           ) != []
  end

  test "reference lookup uses the concise floating label" do
    doc =
      render_component(&Traces.list/1,
        traces: [],
        path_colors: %{},
        params: %{},
        collapsed: false,
        loading: false
      )
      |> Floki.parse_document!()

    assert Floki.find(doc, "label.filter-field-label[for='trace-reference-input']") != []

    assert Floki.find(doc, "label[for='trace-reference-input']") |> Floki.text() |> String.trim() ==
             "Trace reference"

    assert Floki.attribute(doc, "#trace-reference-input", "aria-label") == ["Trace reference"]
    assert Floki.find(doc, "#trace-list h2") == []
    refute Floki.text(doc) =~ "newest first"
    assert Floki.find(doc, "#trace-reference-input[name='reference']:not([required])") != []
    assert Floki.attribute(doc, "#trace-list-filters", "phx-submit") == ["apply_list_filters"]
  end

  test "the unselected list has full width and only selected traces enable the split layout" do
    for selected <- [nil, "first"], collapsed <- [false, true] do
      doc =
        render_component(&Traces.list/1,
          traces: [],
          path_colors: %{},
          params: %{},
          selected: selected,
          collapsed: collapsed,
          loading: false
        )
        |> Floki.parse_document!()

      [class] = Floki.attribute(doc, "#trace-list", "class")
      classes = String.split(class)
      assert "w-full" in classes
      refute Floki.text(doc) =~ "Expand list"
      assert Floki.find(doc, "#trace-list button[phx-click='close_trace']") == []

      if selected do
        assert "lg:w-96" in classes
        refute "border-r" in classes
      else
        refute "lg:w-96" in classes
        refute "border-r" in classes
        refute "hidden" in classes
      end
    end
  end

  test "detail actions use accessible expand and close icons aligned on the right" do
    [widget_button] =
      activity(expanded: false)
      |> Floki.parse_document!()
      |> Floki.find(".grid-widget-expand")

    [widget_class] = Floki.attribute(widget_button, "class")
    widget_classes = String.split(widget_class) -- ["grid-widget-expand"]
    [widget_icon_class] = Floki.attribute(widget_button, "svg", "class")
    widget_icon_styles = String.split(widget_icon_class) -- ["h-4", "w-4"]

    for collapsed <- [false, true] do
      doc =
        render_component(&Traces.detail/1,
          selected: "first",
          path_colors: %{},
          entries: [],
          collapsed: collapsed,
          loading: false,
          part: 0,
          source_id: "source",
          previews: %{},
          preview_loading: false
        )
        |> Floki.parse_document!()

      action = if collapsed, do: "Restore split view", else: "Expand detail"
      buttons = Floki.find(doc, "#trace-detail-header [data-detail-actions] button")
      [actions_class] = Floki.attribute(doc, "[data-detail-actions]", "class")
      assert "shrink-0" in String.split(actions_class)
      assert Floki.find(doc, "[data-detail-heading].items-center > [data-detail-actions]") != []
      refute "absolute" in String.split(actions_class)
      refute "border-b" in String.split(actions_class)

      assert Floki.attribute(buttons, "aria-label") == [
               action,
               "Close detail"
             ]

      assert Floki.attribute(buttons, "title") == [
               action,
               "Close detail"
             ]

      assert Floki.text(buttons) |> String.trim() == ""
      assert length(Floki.find(buttons, "svg[aria-hidden='true']")) == 2

      assert Floki.find(doc, "[data-copy-kind='trace']") == []

      assert Floki.find(doc, "[data-copy-text]") == []

      for button <- buttons do
        [icon_class] = Floki.attribute(button, "svg", "class")
        # Tailwind 3.2 needs separate dimensions; `size-6` generates no CSS.
        assert "h-6" in String.split(icon_class)
        assert "w-6" in String.split(icon_class)
        refute "size-6" in String.split(icon_class)
        assert String.split(icon_class) -- ["h-6", "w-6"] == widget_icon_styles
        assert Floki.attribute(button, "svg", "viewbox") == ["0 0 24 24"]
        assert Floki.attribute(button, "svg", "fill") == ["none"]
        assert Floki.attribute(button, "svg", "stroke-width") == ["1.5"]
        assert Floki.attribute(button, "svg", "stroke") == ["currentColor"]
        assert Floki.attribute(button, "path", "stroke-linecap") == ["round"]
        assert Floki.attribute(button, "path", "stroke-linejoin") == ["round"]
        [class] = Floki.attribute(button, "class")
        assert String.split(class) -- ["max-lg:hidden", "disabled:opacity-50"] == widget_classes
      end

      assert Floki.attribute(doc, "button[phx-click='toggle_list']", "aria-pressed") == [
               to_string(collapsed)
             ]

      assert Floki.find(doc, "button[aria-label='Close detail'][phx-click='close_trace']") != []

      expected =
        if collapsed,
          do:
            "M9 9V4.5M9 9H4.5M9 9 3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5 5.25 5.25",
          else:
            "M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"

      assert Floki.attribute(doc, "button[phx-click='toggle_list'] path", "d") == [expected]

      assert Floki.attribute(doc, "button[phx-click='close_trace'] path", "d") == [
               "M6 18 18 6M6 6l12 12"
             ]

      refute Floki.text(doc) =~ "Back to list"
    end
  end

  test "slim sticky header and footer keep content between them in both layouts" do
    for collapsed <- [false, true], loading <- [false, true] do
      doc =
        detail(%{meta: %{"id" => 42}, tags: ["queue:default"]},
          collapsed: collapsed,
          loading: loading
        )

      assert Floki.find(doc, "#trace-detail[phx-hook], #trace-detail[data-sticky-below]") == []
      assert Floki.find(doc, "#trace-detail.overflow-auto") == []

      assert Floki.find(
               doc,
               "#trace-detail > #trace-detail-header.sticky.z-20.overflow-auto.bg-white"
             ) != []

      assert Floki.attribute(doc, "#trace-detail-header", "class") |> hd() =~ "dark:bg-slate-900"

      for selector <- [
            "[data-detail-actions]",
            "h2",
            "[data-detail-reference]",
            "[data-detail-timing]"
          ] do
        assert Floki.find(doc, "#trace-detail-header #{selector}") != []
      end

      assert length(Floki.find(doc, "#trace-detail-header [data-detail-actions] button")) == 2
      assert Floki.find(doc, "#trace-detail-header [data-copy-kind='trace']") == []

      assert Floki.find(doc, "[data-detail-sections] [data-copy-button]")
             |> Floki.text()
             |> String.trim() == "Copy"

      assert Floki.find(
               doc,
               "[data-detail-sections] > [data-copy-kind='trace'] + button[phx-value-section='tags']"
             ) != []

      assert Floki.find(
               doc,
               "[data-detail-summary] > [data-detail-reference] + [data-detail-timing]"
             ) != []

      assert Floki.find(doc, "#trace-detail-header [data-trace-arguments]") == []
      assert Floki.find(doc, ".trace-entry-body [data-trace-arguments]") != []
      assert Floki.find(doc, "#trace-detail-header .trace-entry-body") == []

      assert Floki.find(
               doc,
               "#trace-detail.flex-col > .trace-entry-body.flex-1 + #trace-detail-footer.sticky.bottom-0"
             ) != []

      for selector <- [
            "[data-entry-counts]",
            "[data-trace-tags]",
            "[data-trace-attachments]",
            "#trace-metadata-first"
          ] do
        assert Floki.find(doc, "#trace-detail-footer #{selector}") != []
        assert Floki.find(doc, "#trace-detail-header #{selector}") == []
      end

      assert length(Floki.find(doc, "#trace-detail-footer .trace-footer-panel[hidden]")) == 3
      assert length(Floki.find(doc, "[data-detail-sections] button[aria-expanded='false']")) == 3
      assert Floki.find(doc, "#trace-detail-footer summary") == []
    end
  end

  test "copy payload is escaped text for loaded parts only, without attachment previews" do
    record = %{parts: 3, meta: %{args: %{name: "<script>input</script>"}}}

    entries = [
      %{part: 1, row: 0, entry: %{type: :raw, state: :success, message: "↳ <output>"}},
      %{part: 1, row: 1, entry: %{type: :media, state: :success, message: "private.txt"}}
    ]

    doc =
      detail(record,
        part: 1,
        entries: entries,
        previews: %{{1, 1} => %{text: "attachment contents", truncated: false}}
      )

    assert Floki.find(doc, "#trace-copy-source-first[data-copy-ready='true']") != []
    assert Floki.find(doc, "[data-copy-button][disabled]") == []

    [payload] =
      Floki.find(doc, "#trace-copy-source-first [data-copy-text].hidden[aria-hidden='true']")

    text = Floki.text(payload)
    assert text =~ "Loaded parts: 1/3"
    assert text =~ "<script>input</script>"
    assert text =~ "↳ <output>"
    refute text =~ "private.txt"
    refute text =~ "attachment contents"
    assert Floki.find(payload, "script, output") == []
    assert Floki.find(doc, "[data-copy-status][role='status'][aria-live='polite']") != []
    assert Floki.find(doc, "[data-copy-success].hidden svg") != []
    [class] = Floki.attribute(doc, "#trace-detail-header h2", "class")
    assert "min-w-0" in String.split(class)
  end

  test "arguments in the scrolling content support Ruby positional and Oban named arguments" do
    for arguments <- [
          [42, %{"region" => "eu", "nested" => [false, nil, 0]}],
          %{"monitor_id" => "monitor-42", "options" => %{"limit" => 10}},
          %{"args" => "an argument named args", "id" => 42}
        ] do
      meta = arguments
      doc = detail(%{meta: meta})
      [section] = Floki.find(doc, ".trace-entry-body [data-trace-arguments]")
      [preview] = Floki.find(section, "[data-arguments-preview]")

      assert Floki.text(preview) |> Jason.decode!() == arguments
      assert Floki.find(section, "details") == []
      assert Floki.find(section, "[data-arguments-expand]") == []

      assert Floki.find(
               doc,
               ".trace-entry-body > div:has([data-trace-arguments]) + ol.trace-entries"
             ) != []
    end
  end

  test "absent arguments do not add an empty header row" do
    for meta <- [nil, %{}, []] do
      assert Floki.find(detail(%{meta: meta}), "[data-trace-arguments]") == []
    end

    for value <- [false, 0, "", %{}] do
      doc = detail(%{meta: [value]})

      assert Floki.find(doc, "[data-arguments-preview]") |> Floki.text() |> Jason.decode!() == [
               value
             ]
    end
  end

  test "long nested arguments have a bounded Unicode preview and complete expandable JSON" do
    arguments = [
      %{"data" => [String.duplicate("東京👩🏽‍💻", 300)], "markup" => "<script>alert(1)</script>"}
    ]

    for meta <- [arguments, hd(arguments)] do
      doc = detail(%{meta: meta}, loading: true)
      [section] = Floki.find(doc, "#trace-arguments-source-first")
      [preview] = Floki.find(section, "[data-arguments-preview]")
      text = Floki.text(preview)
      assert String.valid?(text)
      assert String.length(text) == 241
      assert String.ends_with?(text, "…")
      assert Floki.find(section, "details[open]") == []

      assert Floki.find(section, "details > summary [data-arguments-expand]")
             |> Floki.text()
             |> String.trim() == "Expand all"

      assert Floki.find(section, "[data-arguments-full]") |> Floki.text() |> Jason.decode!() ==
               meta

      assert Floki.find(section, "script") == []
      [full_class] = Floki.attribute(section, "[data-arguments-full]", "class")
      assert "whitespace-pre-wrap" in String.split(full_class)
      assert "[overflow-wrap:anywhere]" in String.split(full_class)
      # Presentation truncation never changes raw metadata or copied trace data.
      assert Floki.find(doc, "#trace-metadata-first pre")
             |> Floki.text()
             |> Jason.decode!()
             |> Map.fetch!("meta") == meta

      assert Floki.find(doc, "[data-copy-kind='trace'] [data-copy-text]") |> Floki.text() =~
               String.duplicate("東京👩🏽‍💻", 300)
    end

    other = detail(%{reference: "second", meta: arguments})
    assert Floki.find(other, "#trace-arguments-source-second-disclosure") != []
    assert Floki.find(other, "#trace-arguments-source-first-disclosure") == []
  end

  test "copy and copied feedback use the supplied clipboard SVGs" do
    doc = detail(%{})

    assert Floki.attribute(doc, "#trace-copy-source-first [data-copy-button] path", "d") == [
             "M8.25 7.5V6.108c0-1.135.845-2.098 1.976-2.192.373-.03.748-.057 1.123-.08M15.75 18H18a2.25 2.25 0 0 0 2.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 0 0-1.123-.08M15.75 18.75v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5A3.375 3.375 0 0 0 6.375 7.5H5.25m11.9-3.664A2.251 2.251 0 0 0 15 2.25h-1.5a2.251 2.251 0 0 0-2.15 1.586m5.8 0c.065.21.1.433.1.664v.75h-6V4.5c0-.231.035-.454.1-.664M6.75 7.5H4.875c-.621 0-1.125.504-1.125 1.125v12c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V16.5a9 9 0 0 0-9-9Z"
           ]

    assert Floki.attribute(doc, "#trace-copy-source-first [data-copy-success] path", "d") == [
             "M11.35 3.836c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75 2.25 2.25 0 0 0-.1-.664m-5.8 0A2.251 2.251 0 0 1 13.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m8.9-4.414c.376.023.75.05 1.124.08 1.131.094 1.976 1.057 1.976 2.192V16.5A2.25 2.25 0 0 1 18 18.75h-2.25m-7.5-10.5H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V18.75m-7.5-10.5h6.375c.621 0 1.125.504 1.125 1.125v9.375m-8.25-3 1.5 1.5 3-3.75"
           ]
  end

  test "small reference copy control copies only the ID and stays ready while parts load" do
    for loading <- [false, true] do
      doc = detail(%{reference: "01M2GF4HFJEPPRWCY4VW3GMBJN"}, loading: loading)
      [control] = Floki.find(doc, "#trace-detail-header [data-copy-kind='reference']")

      assert Floki.attribute(control, "id") == [
               "trace-reference-copy-source-01M2GF4HFJEPPRWCY4VW3GMBJN"
             ]

      assert Floki.attribute(control, "phx-hook") == ["TraceCopy"]
      assert Floki.attribute(control, "data-copy-ready") == ["true"]
      assert Floki.find(control, "button[disabled]") == []
      assert Floki.attribute(control, "button", "aria-label") == ["Copy trace reference"]
      assert Floki.attribute(control, "button", "title") == ["Copy trace reference"]
      assert Floki.find(control, "button svg.h-4.w-4") != []
      assert Floki.find(control, "[data-copy-success] svg.h-4.w-4") != []
      assert Floki.text(Floki.find(control, "[data-copy-text]")) == "01M2GF4HFJEPPRWCY4VW3GMBJN"

      for target <- ["[data-copy-button]", "[data-copy-success]"] do
        assert Floki.attribute(control, "#{target} path", "d") ==
                 Floki.attribute(doc, "[data-detail-sections] #{target} path", "d")
      end

      assert Floki.attribute(
               doc,
               "[data-detail-sections] [data-copy-ready]",
               "data-copy-ready"
             ) ==
               [to_string(!loading)]
    end
  end

  test "trace rows and detail use matching state icons and colors without visible labels" do
    check = "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"

    exclamation =
      "M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z"

    question =
      "M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 5.25h.008v.008H12v-.008Z"

    for {state, color, dark_color, path} <- [
          {:success, "text-teal-500", "dark:text-teal-400", check},
          {"warning", "text-amber-500", "dark:text-amber-400", question},
          {:error, "text-red-600", "dark:text-red-400", exclamation},
          {"running", "text-blue-600", "dark:text-blue-400", exclamation}
        ] do
      doc = trace_list(%{state: state})
      [row] = Floki.find(doc, "#trace-list a")
      [icon] = Floki.find(doc, "#trace-list a > span[role='img']")
      label = state |> to_string() |> String.capitalize()

      assert Floki.attribute(icon, "aria-label") == [label]
      assert Floki.attribute(icon, "title") == [label]
      assert Floki.attribute(icon, "data-trace-state") == [to_string(state)]
      assert Floki.text(icon) == ""
      assert Floki.attribute(icon, "svg", "aria-hidden") == ["true"]
      assert Floki.attribute(icon, "svg", "viewbox") == ["0 0 24 24"]
      assert Floki.attribute(icon, "svg", "stroke-width") == ["1.5"]
      assert Floki.attribute(icon, "path", "d") == [path]
      [class] = Floki.attribute(icon, "svg", "class")
      assert String.split(class) == ["h-6", "w-6", color, dark_color]
      refute Floki.text(row) =~ to_string(state)
      refute Floki.text(row) =~ "queue:default"
      assert Floki.attribute(row, "href") |> hd() =~ "reference=first"

      detail_doc = detail(%{state: state})
      [detail_icon] = Floki.find(detail_doc, "#trace-detail-header h2 > [role='img']")
      assert Floki.attribute(detail_icon, "aria-label") == [label]
      assert Floki.attribute(detail_icon, "path", "d") == [path]
      assert Floki.attribute(detail_icon, "svg", "class") == [class]
    end
  end

  test "detail header separates trace state from compact per-state entry counts" do
    for counters <- [
          %{
            states: %{success: 6, warning: 2, error: 1, debug: 3},
            types: %{text: 5, head: 2, raw: 1, media: 4}
          },
          %{
            "states" => %{"success" => 6, "warning" => 2, "error" => 1, "debug" => 3},
            "types" => %{"text" => 5, "head" => 2, "raw" => 1, "media" => 4}
          }
        ] do
      doc = detail(%{counters: counters})
      assert Floki.find(doc, "#trace-detail-header h2 > [role='img'][aria-label='Success']") != []
      assert Floki.find(doc, "#trace-detail-header h2 .text-teal-500") != []
      refute Floki.text(Floki.find(doc, "#trace-detail-header h2")) =~ "success"

      assert Enum.map(Floki.find(doc, "[data-entry-counts] dd"), &Floki.text/1) ==
               ["6", "2", "1", "3"]

      assert Floki.attribute(doc, "[data-entry-counts] [data-trace-metadata]", "title") ==
               [
                 "Success entries: 6",
                 "Warning entries: 2",
                 "Error entries: 1",
                 "Debug entries: 3"
               ]

      entry_icon =
        "M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 0 1 0 3.75H5.625a1.875 1.875 0 0 1 0-3.75Z"

      assert Floki.attribute(doc, "[data-entry-counts] svg path", "d") ==
               List.duplicate(entry_icon, 4)

      for {state, color, dark_color} <- [
            {"success", "text-slate-500", "dark:text-slate-400"},
            {"warning", "text-amber-500", "dark:text-amber-400"},
            {"error", "text-red-600", "dark:text-red-400"},
            {"debug", "text-violet-500", "dark:text-violet-400"}
          ] do
        [class] = Floki.attribute(doc, "[data-trace-metadata='entries-#{state}']", "class")
        assert color in String.split(class)
        assert dark_color in String.split(class)
      end

      assert Floki.find(doc, "[data-entry-counts] .text-teal-500") == []
      assert Floki.find(doc, "[data-entry-counts] [data-trace-metadata='entries']") == []
      assert Floki.find(doc, "button[phx-value-section='attachments']") |> Floki.text() =~ "(4)"
      assert Floki.find(doc, "button[phx-value-section='attachments'] svg.h-4.w-4") != []

      timing = Floki.find(doc, "[data-detail-timing]")

      assert Floki.find(timing, "[title='Started'] svg") == []
      assert Floki.find(timing, "[title='Duration'] svg.h-4.w-4") != []

      assert Floki.attribute(timing, "svg path", "d") == [
               "m3.75 13.5 10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75Z"
             ]

      assert Floki.attribute(timing, "[title]", "title") == ["Started", "Duration", "Last update"]

      assert timing
             |> Floki.filter_out(".sr-only")
             |> Floki.text(sep: " ")
             |> String.replace(~r/\s+/, " ")
             |> String.trim() ==
               "2026-09-14 10:00:00 UTC → 125 ms → 2026-09-14 10:00:01 UTC"

      assert Floki.find(doc, "#trace-detail-header [title='Duration']") |> Floki.text() =~
               "125 ms"

      refute Floki.text(doc) =~ "Metadata, context and counters"

      assert Floki.find(doc, "#trace-metadata-first-toggle") |> Floki.text() |> String.trim() ==
               "Metadata"

      assert Floki.find(doc, "#trace-metadata-first:not([hidden])") == []
    end
  end

  test "raw block results stay inline and never count as attachments" do
    for raw_count <- [1, 2] do
      result = "↳ %{state: :success}"

      doc =
        detail(%{counters: %{types: %{raw: raw_count, media: 0}}},
          attachments_requested: true,
          footer_section: "attachments",
          entries: [%{entry: %{type: :raw, state: :success, message: result}, part: 1, row: 0}]
        )

      assert Floki.find(doc, "button[phx-value-section='attachments']") |> Floki.text() =~ "(0)"

      assert Floki.find(doc, "[data-trace-attachments] p") |> Floki.text() |> String.trim() ==
               "No stored attachments."

      assert Floki.find(doc, "[data-trace-attachments] a") == []
      refute Floki.find(doc, "[data-trace-attachments]") |> Floki.text() =~ "raw"
      assert Floki.find(doc, "#trace-entry-1-0 pre") |> Floki.text() == result
    end
  end

  test "entry rows use neutral or colored messages instead of visible state labels" do
    for string_keys? <- [false, true] do
      entries =
        Enum.with_index([:success, :warning, :error, :debug], fn state, row ->
          entry = %{
            type: :text,
            state: state,
            at: 1_700_000_000,
            message: "<script>message #{row}</script>\nSecond line"
          }

          entry =
            if string_keys?,
              do:
                Map.new(entry, fn {key, value} ->
                  {to_string(key), if(is_atom(value), do: to_string(value), else: value)}
                end),
              else: entry

          %{entry: entry, part: 1, row: row}
        end)

      doc = detail(%{}, entries: entries)
      assert Floki.find(doc, "ol.trace-entries[aria-label='Trace entries'] > li") |> length() == 4
      assert Floki.find(doc, ".trace-entries script") == []

      for {state, color, dark_color} <- [
            {"success", "text-slate-700", "dark:text-slate-200"},
            {"warning", "text-amber-700", "dark:text-amber-400"},
            {"error", "text-red-600", "dark:text-red-400"},
            {"debug", "text-violet-600", "dark:text-violet-400"}
          ] do
        [row] = Floki.find(doc, ".trace-entry[data-entry-state='#{state}']")
        [message] = Floki.find(row, ".trace-entry-message")
        [class] = Floki.attribute(message, "class")
        assert color in String.split(class)
        assert dark_color in String.split(class)
        assert Floki.find(row, ".sr-only") |> Floki.text() == "#{state}:"
        refute row |> Floki.filter_out(".sr-only") |> Floki.text() =~ state

        assert Floki.attribute(row, "time.trace-entry-timestamp", "datetime") ==
                 ["2023-11-14T22:13:20Z"]

        assert Floki.find(row, ".trace-entry-message time") == []
        assert Floki.find(row, ".trace-entry-number[aria-hidden='true'].select-none") != []
        assert Floki.find(row, "time.trace-entry-timestamp.select-none") != []
        assert Floki.find(message, ".select-none") == []
        assert Floki.find(message, "pre") |> Floki.text() =~ "\nSecond line"
      end

      assert Floki.find(doc, ".trace-entries .text-teal-500, .trace-entries .text-teal-600") == []
    end
  end

  test "entries start flush with the header and keep horizontal padding inside each row" do
    entry = %{part: 1, row: 0, entry: %{type: :text, state: :success, message: "Loaded entry"}}

    for collapsed <- [false, true] do
      doc = detail(%{parts: 2}, entries: [entry], part: 1, collapsed: collapsed)
      [scroll] = Floki.find(doc, "#trace-detail > .trace-entry-body")
      [class] = Floki.attribute(scroll, "class")
      assert "pb-4" in String.split(class)
      refute Enum.any?(String.split(class), &String.starts_with?(&1, ["pt-", "py-"]))
      refute "p-4" in String.split(class)
      refute "px-4" in String.split(class)
      refute "overflow-auto" in String.split(class)
      assert Floki.find(doc, "#trace-detail.overflow-auto") == []
      assert Floki.find(doc, "#trace-detail > #trace-detail-header.sticky") != []
      [row] = Floki.find(scroll, "ol.trace-entries > li.trace-entry.border-b.px-4")
      [row_class] = Floki.attribute(row, "class")
      assert "py-0.5" in String.split(row_class)
      assert Floki.find(scroll, "ol.trace-entries.text-xs.leading-5") != []
      assert Floki.find(scroll, "button[phx-click='load_part'].px-4") != []
    end

    for options <- [
          [preview_loading: true],
          [preview_error: "Preview unavailable"],
          []
        ] do
      doc = detail(%{parts: 0}, options)
      messages = Floki.find(doc, ".trace-entry-body > p")
      assert messages != []

      for message <- messages do
        [class] = Floki.attribute(message, "class")
        assert "px-4" in String.split(class)
      end
    end
  end

  test "detail reuses the widget loading bar at its top while retaining loaded entries" do
    entry = %{part: 1, row: 0, entry: %{type: :text, state: :success, message: "Loaded entry"}}

    for collapsed <- [false, true] do
      doc = detail(%{parts: 12}, entries: [entry], part: 1, loading: true, collapsed: collapsed)

      assert Floki.find(doc, "#trace-detail[aria-busy='true']") != []

      assert Floki.find(
               doc,
               "#trace-detail-header > #trace-detail-loading.grid-widget-refresh-indicator[role='status']"
             ) != []

      assert Floki.text(Floki.find(doc, "#trace-detail-loading .sr-only")) =~
               "1/12 parts loaded"

      assert Floki.text(Floki.find(doc, ".trace-entry-message")) =~ "Loaded entry"
      assert Floki.find(doc, "button[phx-click='load_part']") == []
    end

    doc = detail(%{parts: 102}, entries: [entry], part: 100)
    assert Floki.find(doc, "#trace-detail[aria-busy='false']") != []
    assert Floki.find(doc, "#trace-detail-loading") == []
    assert Floki.text(Floki.find(doc, "button[phx-click='load_part']")) =~ "100/102 loaded"
  end

  test "entry numbers span parts and wrapped messages without changing indentation or raw results" do
    long_message = "First line\n" <> String.duplicate("long-word", 100)

    entries = [
      %{part: 1, row: 0, entry: %{type: :head, state: :success, message: "Block", level: 0}},
      %{part: 1, row: 1, entry: %{type: :text, state: :success, message: long_message, level: 2}},
      %{part: 2, row: 0, entry: %{type: :raw, state: :success, message: "↳ 42", level: 100}}
    ]

    doc = detail(%{length: 1000}, entries: entries)
    assert Floki.attribute(doc, ".trace-entries", "style") == ["--trace-line-width: 4ch;"]

    assert Floki.find(doc, ".trace-entry-number") |> Enum.map(&(Floki.text(&1) |> String.trim())) ==
             ["1", "2", "3"]

    assert Floki.find(doc, "#trace-entry-1-0 pre.font-semibold") |> Floki.text() == "Block"
    assert Floki.find(doc, "#trace-entry-1-1 pre") |> Floki.text() == long_message
    [class] = Floki.attribute(doc, "#trace-entry-1-1 pre", "class")
    assert "whitespace-pre-wrap" in String.split(class)
    assert "[overflow-wrap:anywhere]" in String.split(class)
    assert Floki.find(doc, "#trace-entry-2-0 pre") |> Floki.text() == "↳ 42"

    assert Floki.attribute(doc, ".trace-entry-message", "style") == [
             "--trace-entry-indent: 0rem;",
             "--trace-entry-indent: 2rem;",
             "--trace-entry-indent: 12rem;"
           ]
  end

  test "attachment sizes are visible before preview or download in rows and the attachment list" do
    for {bytes, label} <- [
          {0, "0 B"},
          {512, "512 B"},
          {1023, "1023 B"},
          {1024, "1 KiB"},
          {1536, "1.5 KiB"},
          {102_400, "100 KiB"},
          {1_048_576, "1 MiB"},
          {2_621_440, "2.5 MiB"},
          {1_073_741_824, "1 GiB"},
          {1_099_511_627_776, "1 TiB"}
        ],
        string_keys? <- [false, true] do
      entry = %{type: :media, state: :success, message: "report.txt", size: bytes}

      entry =
        if string_keys?,
          do: Map.new(entry, fn {key, value} -> {to_string(key), value} end),
          else: entry

      doc =
        detail(%{},
          entries: [%{part: 1, row: 0, entry: entry}],
          footer_section: "attachments",
          attachments_requested: true,
          attachments: [%{name: "report.txt", part: 1, row: 0, size: bytes}]
        )

      for selector <- [
            ".trace-entry-message [data-attachment-size]",
            "[data-trace-attachments] [data-attachment-size]"
          ] do
        [size] = Floki.find(doc, selector)
        assert String.trim(Floki.text(size)) == label
        assert Floki.attribute(size, "data-size-bytes") == [to_string(bytes)]
        assert Floki.attribute(size, "title") == ["#{bytes} bytes"]
        assert Floki.attribute(size, "aria-label") == ["Attachment size: #{label}"]
        [class] = Floki.attribute(size, "class")
        assert "whitespace-nowrap" in String.split(class)
        assert "shrink-0" in String.split(class)
      end

      assert Floki.find(
               doc,
               ".trace-entry-message [data-attachment-size] + button[phx-click='preview']"
             ) != []

      assert Floki.find(doc, "[data-trace-attachments] a + [data-attachment-size]") != []
      assert Floki.find(doc, ".trace-entry-message pre") == []
    end
  end

  test "images and videos display inline by default and retain sizes and downloads" do
    for {name, kind, tag, label} <- [
          {"screen.PNG", "image", "img", "Hide image"},
          {"clip.webm", "video", "video", "Hide video"},
          {"clip.mp4", "video", "video", "Hide video"}
        ],
        collapsed <- [false, true] do
      entry = %{
        part: 1,
        row: 3,
        entry: %{type: :media, state: :success, message: name, size: 1536}
      }

      doc = detail(%{}, entries: [entry], collapsed: collapsed)
      [preview] = Floki.find(doc, "[phx-hook='TraceMedia'][phx-update='ignore']")
      assert Floki.attribute(preview, "data-media-kind") == [kind]
      assert Floki.text(Floki.find(preview, "[data-attachment-size]")) =~ "1.5 KiB"
      assert Floki.text(Floki.find(preview, "button[aria-expanded='true']")) =~ label
      assert Floki.find(preview, "[data-media-preview]:not(.hidden) #{tag}[src]") != []
      assert Floki.find(preview, "[autoplay], [phx-click='preview']") == []
      assert Floki.find(preview, "[data-media-status][role='status']") != []
      [inline_url] = Floki.attribute(preview, "data-media-url")
      assert Floki.attribute(preview, tag, "src") == [inline_url]
      [download_url] = Floki.attribute(preview, "a", "href")
      assert inline_url =~ "inline=true"
      refute download_url =~ "inline=true"

      for url <- [inline_url, download_url] do
        assert url =~ "part=1"
        assert url =~ "row=3"
        assert url =~ "reference=first"
        assert url =~ "source_id=source"
      end

      if kind == "video" do
        assert Floki.find(preview, "video[controls][playsinline][preload='metadata']") != []
        assert Floki.attribute(preview, "video", "aria-label") == [name]
      else
        assert Floki.attribute(preview, "img", "alt") == [name]
        assert Floki.attribute(preview, "img", "loading") == ["lazy"]
      end

      other = detail(%{reference: "second"}, entries: [entry])

      refute Floki.attribute(other, "[phx-hook='TraceMedia']", "id") ==
               Floki.attribute(preview, "id")
    end
  end

  test "active attachments and ordinary text never render as inline media" do
    for name <- ["payload.svg", "page.html", "report.txt"] do
      entry = %{part: 1, row: 0, entry: %{type: :media, state: :success, message: name}}
      doc = detail(%{}, entries: [entry])
      assert Floki.find(doc, "[phx-hook='TraceMedia'], img, video, iframe, object") == []
      assert Floki.find(doc, ".trace-entry-message a") != []
    end
  end

  test "unknown or invalid attachment sizes are not presented as zero or rendered unsafely" do
    for fields <- [
          %{},
          %{size: nil},
          %{size: -1},
          %{size: "2048"},
          %{size: "<script>"},
          %{size: 1.5}
        ] do
      entry = Map.merge(%{type: :media, state: :success, message: "legacy.txt"}, fields)
      attachment = Map.merge(%{name: "legacy.txt", part: 1, row: 0}, fields)

      doc =
        detail(%{},
          entries: [%{part: 1, row: 0, entry: entry}],
          footer_section: "attachments",
          attachments_requested: true,
          attachments: [attachment]
        )

      sizes = Floki.find(doc, "[data-attachment-size]")
      assert length(sizes) == 2

      for size <- sizes do
        assert String.trim(Floki.text(size)) == "Size unknown"
        assert Floki.attribute(size, "data-size-bytes") == []
        assert Floki.attribute(size, "title") == ["Attachment size was not recorded"]
      end

      assert Floki.find(doc, "script") == []
      assert Floki.find(doc, "button[phx-click='preview']") != []
    end
  end

  test "timestamps can be omitted independently while media previews and downloads stay intact" do
    entries = [
      %{
        part: 2,
        row: 3,
        entry: %{
          type: :media,
          state: :success,
          at: ~U[2026-09-14 10:00:00Z],
          message: "report.txt",
          size: 102_400
        }
      }
    ]

    for show_timestamps <- [false, true] do
      doc =
        detail(%{},
          entries: entries,
          show_entry_timestamps: show_timestamps,
          previews: %{{2, 3} => %{text: "<script>safe preview</script>", truncated: true}}
        )

      assert Floki.attribute(doc, ".trace-entries", "data-show-timestamps") == [
               to_string(show_timestamps)
             ]

      assert length(Floki.find(doc, ".trace-entry-timestamp")) ==
               if(show_timestamps, do: 1, else: 0)

      assert Floki.find(doc, ".trace-entry-number") |> Floki.text() |> String.trim() == "1"

      assert Floki.find(doc, "button[phx-click='preview'][phx-value-part='2'][phx-value-row='3']") !=
               []

      assert Floki.find(doc, ".trace-entry-message pre") |> Floki.text() ==
               "<script>safe preview</script>"

      assert Floki.find(doc, ".trace-entry-message [data-attachment-size]")
             |> Floki.text()
             |> String.trim() == "100 KiB"

      assert Floki.find(doc, ".trace-entries script") == []
      [href] = Floki.attribute(doc, ".trace-entry-message a", "href")

      assert URI.decode_query(URI.parse(href).query) == %{
               "source_id" => "source",
               "reference" => "first",
               "part" => "2",
               "row" => "3"
             }
    end
  end

  test "detail paths and tag pills are escaped, wrap safely and link to the filtered list" do
    path = "jobs/" <> String.duplicate("LongWorker", 30) <> "/<script>"
    tag = "queue:critical&<urgent>"

    params = %{
      "source_id" => "source",
      "reference" => "first",
      "detail" => "expanded",
      "timeframe" => "2d",
      "granularity" => "1h"
    }

    doc = detail(%{key: path, tags: [tag]}, params: params)
    links = Floki.find(doc, "#trace-detail-header [data-trace-path] a")
    assert length(links) == 3

    assert Floki.find(doc, "#trace-detail-header [data-trace-path]")
           |> Floki.text()
           |> String.trim() == path

    assert Enum.map(links, &Floki.text/1) ==
             ["jobs/", String.duplicate("LongWorker", 30) <> "/", "<script>"]

    colors = TrifleApp.DesignSystem.PathColors.build([path], "/")
    parts = TrifleApp.DesignSystem.PathColors.parts(path, colors, "/")

    assert Enum.flat_map(links, &Floki.attribute(&1, "style")) ==
             Enum.map(parts, &"color: #{&1.color} !important")

    for {link, prefix} <-
          Enum.zip(links, ["jobs", "jobs/" <> String.duplicate("LongWorker", 30), path]) do
      [href] = Floki.attribute(link, "href")
      query = URI.decode_query(URI.parse(href).query)
      assert query["path"] == prefix
      assert query["source_id"] == "source"
      assert query["timeframe"] == "2d"
      refute Map.has_key?(query, "reference")
      refute Map.has_key?(query, "detail")
    end

    [tag_link] = Floki.find(doc, "[data-trace-tag]")
    assert Floki.attribute(tag_link, "data-trace-tag") == [tag]
    assert Floki.find(tag_link, "svg") != []
    assert Floki.text(tag_link) |> String.trim() == tag
    [href] = Floki.attribute(tag_link, "href")
    query = URI.decode_query(URI.parse(href).query)
    assert query["tags"] == tag
    assert query["tag_mode"] == "any"
    refute Map.has_key?(query, "reference")
    assert Floki.find(doc, "script, urgent") == []
    assert Floki.find(doc, "[data-detail-heading] > h2.min-w-0") != []
  end

  test "tags start collapsed with a count and keep large sets wrapped and scrollable" do
    tags = Enum.map(1..100, &"tag:#{&1}")
    doc = detail(%{tags: tags})
    [section] = Floki.find(doc, "section[data-trace-tags]")
    assert Floki.attribute(section, "id") == ["trace-tags-source-first"]
    assert Floki.attribute(section, "hidden") == ["hidden"]
    assert Floki.find(doc, "#trace-tags-source-first-toggle svg.h-4.w-4") != []

    assert Floki.find(doc, "#trace-tags-source-first-toggle .tabular-nums") |> Floki.text() ==
             "(100)"

    assert Floki.find(doc, ".trace-footer-panel[data-trace-tags] > div.flex-wrap") != []
    assert Floki.attribute(section, "[data-trace-tag]", "data-trace-tag") == tags

    for link <- Floki.find(section, "[data-trace-tag]") do
      [tag] = Floki.attribute(link, "data-trace-tag")
      [href] = Floki.attribute(link, "href")
      assert URI.decode_query(URI.parse(href).query)["tags"] == tag
    end

    other = detail(%{reference: "second", tags: tags})

    assert Floki.attribute(other, "section[data-trace-tags]", "id") == [
             "trace-tags-source-second"
           ]

    assert Floki.find(other, "section[data-trace-tags]:not([hidden])") == []

    for empty <- [[], nil] do
      assert detail(%{tags: empty}) |> Floki.find("[data-trace-tags]") == []
    end
  end

  test "footer buttons share icons and accessible panel controls without chevrons" do
    doc = detail(%{tags: ["queue:default"]})
    [section] = Floki.find(doc, "#trace-metadata-first")
    assert Floki.attribute(section, "hidden") == ["hidden"]

    assert Floki.find(doc, "#trace-metadata-first-toggle") |> Floki.text() |> String.trim() ==
             "Metadata"

    assert Floki.attribute(doc, "#trace-metadata-first-toggle svg path", "d") == [
             "M17.25 6.75 22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3-4.5 16.5"
           ]

    for button <- Floki.find(doc, "[data-detail-sections] button[aria-controls]") do
      assert Floki.attribute(button, "svg", "class") == ["h-4 w-4 shrink-0"]
      assert Floki.attribute(button, "svg", "stroke-width") == ["1.5"]
      assert Floki.attribute(button, "aria-expanded") == ["false"]
      [panel_id] = Floki.attribute(button, "aria-controls")
      [button_id] = Floki.attribute(button, "id")
      assert Floki.attribute(doc, "##{panel_id}", "aria-labelledby") == [button_id]
      assert Floki.find(doc, "##{panel_id}[hidden]") != []
      assert length(Floki.find(button, "svg")) == 1
    end
  end

  test "attachments start collapsed and render download links by persisted part and row" do
    initial = detail(%{})
    assert Floki.find(initial, "[data-trace-attachments]:not([hidden])") == []

    assert Floki.find(
             initial,
             "button[phx-click='toggle_footer_section'][phx-value-section='attachments']"
           ) !=
             []

    assert Floki.find(initial, "[data-trace-attachments] a") == []

    doc =
      detail(%{},
        attachments_requested: true,
        attachments: [%{name: "report & <data>.csv", part: 2, row: 8}],
        attachments_next_part: 10
      )

    [link] = Floki.find(doc, "[data-trace-attachments] a")
    [href] = Floki.attribute(link, "href")
    assert URI.parse(href).path == "/traces/attachment"

    assert URI.decode_query(URI.parse(href).query) == %{
             "source_id" => "source",
             "reference" => "first",
             "part" => "2",
             "row" => "8"
           }

    assert Floki.text(link) |> String.trim() == "report & <data>.csv"
    assert Floki.find(doc, "button[phx-click='more_attachments']") != []
    assert Floki.find(link, "data") == []
  end

  defp detail(overrides, assigns_overrides \\ []) do
    record =
      struct(
        Trifle.Traces.TraceRecord,
        Map.merge(
          %{
            reference: "first",
            key: "jobs/App.Worker",
            state: :success,
            tags: [],
            length: 12,
            duration: 125,
            first_at: ~U[2026-09-14 10:00:00Z],
            last_at: ~U[2026-09-14 10:00:01Z]
          },
          overrides
        )
      )

    assigns = %{
      record: record,
      path_colors: TrifleApp.DesignSystem.PathColors.build([record.key], "/"),
      selected: record.reference,
      entries: [],
      collapsed: false,
      loading: false,
      part: 0,
      source_id: "source",
      previews: %{},
      preview_loading: false,
      params: %{"source_id" => "source", "reference" => record.reference}
    }

    render_component(&Traces.detail/1, Map.merge(assigns, Map.new(assigns_overrides)))
    |> Floki.parse_document!()
  end

  test "long trace paths wrap independently of timing and the state icon offsets both lines" do
    path = "jobs/" <> String.duplicate("LongWorkerName", 40) <> "/<script>unsafe</script>"

    for selected <- [nil, "first"] do
      doc = trace_list(%{key: path}, selected: selected)
      [row] = Floki.find(doc, "#trace-list a")
      assert length(Floki.children(row)) == 2
      assert Floki.find(doc, "#trace-list a > span.shrink-0[role='img']") != []
      [content] = Floki.find(row, ".trace-row-content.min-w-0.flex-1")
      [class] = Floki.attribute(content, "class")
      classes = String.split(class)
      assert "grid-cols-1" in classes
      assert "md:grid-cols-[minmax(0,1fr)_auto]" in classes == is_nil(selected)
      [path_element] = Floki.find(content, "[data-trace-path]")
      assert Floki.text(path_element) |> String.trim() == path
      [path_class] = Floki.attribute(path_element, "class")
      assert "min-w-0" in String.split(path_class)
      assert "[overflow-wrap:anywhere]" in String.split(path_class)
      refute "break-all" in String.split(path_class)
      assert Floki.find(path_element, "script") == []

      [timing] = Floki.find(content, ".trace-row-timing")

      assert Floki.text(timing, sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim() ==
               "2026-09-14 10:00:00 UTC"

      assert Floki.find(content, ".trace-row-summary > [data-trace-path] + .trace-row-metadata") !=
               []

      assert Floki.text(Floki.find(content, "[data-trace-metadata='duration'] dd")) == "125 ms"
      refute Floki.text(timing) =~ "125 ms"
      refute Floki.text(timing) =~ "@"
      assert Floki.find(content, "[role='img']") == []
    end
  end

  test "metadata shows entry, tag and media counts from the index and keeps duration with them" do
    for counters <- [%{types: %{media: 3}}, %{"types" => %{"media" => 3}}],
        selected <- [nil, "first"] do
      doc =
        trace_list(
          %{length: 42, tags: ["queue:default", "scheduled"], counters: counters, duration: 1500},
          selected: selected
        )

      [metadata] = Floki.find(doc, ".trace-row-summary > dl.trace-row-metadata")
      # A generic label here would hide the individual counts in the link's accessible name.
      assert Floki.attribute(metadata, "aria-label") == []
      [class] = Floki.attribute(metadata, "class")
      assert "flex-wrap" in String.split(class)

      assert Floki.attribute(metadata, "[data-trace-metadata]", "data-trace-metadata") ==
               ["entries", "tags", "attachments", "duration"]

      assert Enum.map(Floki.find(metadata, "dd"), &Floki.text/1) == ["42", "2", "3", "1500 ms"]

      assert Enum.map(Floki.find(metadata, "dt .sr-only"), &Floki.text/1) ==
               ["Entries", "Tags", "Attachments", "Duration"]

      assert Floki.attribute(metadata, "[data-trace-metadata]", "title") ==
               ["Entries: 42", "Tags: 2", "Attachments: 3", "Duration: 1500 ms"]

      assert length(Floki.find(metadata, "div.inline-flex.items-center.whitespace-nowrap")) == 4
      assert length(Floki.find(metadata, "svg.h-4.w-4[aria-hidden='true']")) == 4
      refute Floki.text(metadata) =~ "queue:default"
      refute Floki.text(metadata) =~ "scheduled"
    end
  end

  test "metadata uses the supplied SVG paths including the lightning bolt for duration" do
    doc = trace_list(%{})

    assert Floki.attribute(doc, "[data-trace-metadata='entries'] path", "d") == [
             "M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 0 1 0 3.75H5.625a1.875 1.875 0 0 1 0-3.75Z"
           ]

    assert Floki.attribute(doc, "[data-trace-metadata='tags'] path", "d") == [
             "M9.568 3H5.25A2.25 2.25 0 0 0 3 5.25v4.318c0 .597.237 1.17.659 1.591l9.581 9.581c.699.699 1.78.872 2.607.33a18.095 18.095 0 0 0 5.223-5.223c.542-.827.369-1.908-.33-2.607L11.16 3.66A2.25 2.25 0 0 0 9.568 3Z",
             "M6 6h.008v.008H6V6Z"
           ]

    assert Floki.attribute(doc, "[data-trace-metadata='attachments'] path", "d") == [
             "m18.375 12.739-7.693 7.693a4.5 4.5 0 0 1-6.364-6.364l10.94-10.94A3 3 0 1 1 19.5 7.372L8.552 18.32m.009-.01-.01.01m5.699-9.941-7.81 7.81a1.5 1.5 0 0 0 2.112 2.13"
           ]

    assert Floki.attribute(doc, "[data-trace-metadata='duration'] path", "d") == [
             "m3.75 13.5 10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75Z"
           ]

    for svg <- Floki.find(doc, ".trace-row-metadata svg") do
      assert Floki.attribute(svg, "stroke-width") == ["1.5"]
      assert Floki.attribute(svg, "stroke") == ["currentColor"]
      assert Floki.attribute(svg, "viewbox") == ["0 0 24 24"]
      assert Floki.attribute(svg, "fill") == ["none"]
    end
  end

  test "metadata tolerates missing counters and zero values on new traces" do
    for counters <- [nil, %{}, %{types: nil}, %{types: %{}}, %{"types" => %{}}] do
      doc = trace_list(%{length: nil, tags: nil, counters: counters, duration: nil})

      assert Enum.map(Floki.find(doc, ".trace-row-metadata dd"), &Floki.text/1) ==
               ["0", "0", "0", "0 ms"]
    end
  end

  test "unknown trace states remain accessible with a neutral fallback icon" do
    doc = trace_list(%{state: nil})

    assert Floki.find(doc, "#trace-list [role='img'][aria-label='Unknown'] svg.text-slate-500") !=
             []
  end

  test "compact activity omits explanatory text, color labels and event counters" do
    for loading <- [false, true] do
      html = activity(loading: loading, expanded: false)
      refute html =~ "Source, timeframe, path and state"
      refute html =~ "Tags and duration filter only the list below"
      refute html =~ "Activity state colors"
      refute html =~ "recorded events"
      assert html =~ "traces-dashboard-grid"

      assert Floki.find(
               Floki.parse_document!(html),
               "#traces-dashboard-grid[data-hide-on-patch='false']"
             ) != []
    end
  end

  test "activity uses shared initial loading states and clears expanded data" do
    html = activity(loading: true)
    assert html =~ "Loading activity"
    assert html =~ ~s(data-widget-loading-state="initial")
    doc = Floki.parse_document!(html)
    assert Floki.attribute(doc, "#expanded-widget-trace-activity", "data-chart") == []
  end

  test "activity widget and expanded modal can render in separate layout contexts" do
    widget = activity(presentation: "widget") |> Floki.parse_document!()
    expanded = activity(presentation: "expanded") |> Floki.parse_document!()

    assert Floki.find(widget, "section[aria-label='Trace activity'] #traces-dashboard-grid") != []
    assert Floki.find(widget, "#traces-expanded-widget") == []

    assert Floki.find(expanded, "#traces-dashboard-grid, section[aria-label='Trace activity']") ==
             []

    assert Floki.find(expanded, "#traces-expanded-widget #expanded-widget-trace-activity") != []
  end

  test "storage errors remain visible beside the widget and in its expanded view" do
    html = activity(error: "Activity is unavailable. Refresh to retry.")
    doc = Floki.parse_document!(html)
    assert length(Floki.find(doc, "[role='status']")) == 2
    assert Floki.text(Floki.find(doc, "#traces-expanded-widget")) =~ "Activity is unavailable."
  end

  test "expanded titles and literal series names are escaped" do
    path = "jobs/<script>App.Worker</script>"
    data = %{series: [%{name: path, data: [[1_700_000_000_000, 1]]}], paths: [path], total: 1}
    html = activity(path: path, activity: data)
    doc = Floki.parse_document!(html)
    assert Floki.find(doc, "script") == []
    [chart] = Floki.attribute(doc, "#expanded-widget-trace-activity", "data-chart")
    assert hd(Jason.decode!(chart)["series"])["name"] == path
  end

  defp trace_list(trace_overrides, overrides \\ []) do
    trace =
      Map.merge(
        %{
          reference: "first",
          key: "jobs/Trifle.Monitors.Jobs.DispatchRunner",
          state: :success,
          first_at: ~U[2026-09-14 10:00:00Z],
          duration: 125,
          tags: ["queue:default"],
          length: 10,
          counters: %{types: %{media: 0}}
        },
        trace_overrides
      )

    assigns = %{
      traces: [trace],
      path_colors: TrifleApp.DesignSystem.PathColors.build([trace.key], "/"),
      params: %{},
      selected: nil,
      collapsed: false,
      loading: false
    }

    render_component(&Traces.list/1, Map.merge(assigns, Map.new(overrides)))
    |> Floki.parse_document!()
  end

  defp activity(overrides) do
    assigns = %{
      activity: %{series: [], paths: [], total: 0},
      path: nil,
      loading: false,
      error: nil,
      timezone: "Etc/UTC",
      expanded: true
    }

    render_component(&Traces.activity/1, Map.merge(assigns, Map.new(overrides)))
  end
end
