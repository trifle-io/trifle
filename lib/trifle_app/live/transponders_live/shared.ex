defmodule TrifleApp.TranspondersLive.Shared do
  use TrifleApp, :verified_routes

  @moduledoc """
  Shared helpers for the project/database transponder LiveViews.
  """

  alias Ecto.NoResultsError
  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Project, Transponder}

  @doc """
  Apply the base assignments and initial transponder stream for a source.
  """
  def assign_initial(socket, source_assigns) do
    transponders = list_transponders_for_source(source_assigns.source)

    socket
    |> Component.assign(source_assigns)
    |> Component.assign(:transponder, nil)
    |> Component.assign(:ui_action, :index)
    |> Component.assign(:transponders_empty, Enum.empty?(transponders))
    |> LiveView.stream(:transponders, transponders)
  end

  @doc """
  Assign common path helpers based on the current source.
  """
  def assign_paths(socket) do
    source_type = socket.assigns.source_type
    source = socket.assigns.source

    socket
    |> Component.assign(:index_path, transponder_index_path(source_type, source))
    |> Component.assign(:new_path, transponder_new_path(source_type, source))
    |> Component.assign(:show_path, fn id -> transponder_show_path(source_type, source, id) end)
    |> Component.assign(:edit_path, fn id -> transponder_edit_path(source_type, source, id) end)
    |> Component.assign(:cancel_path, transponder_form_cancel_path(source_type, source))
    |> Component.assign(:settings_path, transponder_settings_path(source_type, source))
  end

  @doc """
  Handle LiveView action updates when route params change.
  """
  def apply_action(socket, live_action, params) do
    source_type = socket.assigns.source_type
    source = socket.assigns.source
    base_action = base_action(live_action)

    socket =
      socket
      |> Component.assign(:page_title, page_title_for_action(base_action, source_type, source))
      |> Component.assign(:ui_action, base_action)

    case {base_action, params} do
      {:index, _} ->
        Component.assign(socket, :transponder, nil)

      {:new, _} ->
        Component.assign(socket, :transponder, %Transponder{
          source_type: Atom.to_string(source_type),
          type: Transponder.expression_type()
        })

      {action, %{"transponder_id" => transponder_id}} when action in [:show, :edit] ->
        transponder = load_transponder(source, transponder_id)

        socket
        |> Component.assign(:transponder, transponder)
        |> Component.assign(
          :page_title,
          page_title_for_action(action, source_type, source, transponder)
        )

      _ ->
        Component.assign(socket, :transponder, nil)
    end
  end

  @doc """
  Shared handler for the :saved message emitted by the form component.
  """
  def handle_form_saved(socket, transponder) do
    {:noreply,
     socket
     |> Component.assign(:transponders_empty, false)
     |> LiveView.stream_insert(:transponders, transponder)}
  end

  @doc """
  Shared handler for the :updated message emitted by the form component.
  """
  def handle_form_updated(socket, transponder), do: handle_form_saved(socket, transponder)

  def handle_delete(socket, %{"id" => id}) do
    source = socket.assigns.source
    transponder = load_transponder(source, id)
    {:ok, _} = Organizations.delete_transponder(transponder)

    remaining_transponders = list_transponders_for_source(source)
    remaining_ids = Enum.map(remaining_transponders, & &1.id)
    {:ok, _} = Organizations.update_transponder_order(source, remaining_ids)

    transponders = list_transponders_for_source(source)

    {:noreply,
     socket
     |> Component.assign(:transponders_empty, Enum.empty?(transponders))
     |> LiveView.stream(:transponders, transponders, reset: true)
     |> LiveView.put_flash(:info, "Transponder deleted successfully")}
  end

  def handle_toggle(socket, %{"id" => id}) do
    source = socket.assigns.source
    transponder = load_transponder(source, id)

    {:ok, updated_transponder} =
      Organizations.update_transponder(transponder, %{enabled: !transponder.enabled})

    {:noreply, LiveView.stream_insert(socket, :transponders, updated_transponder)}
  end

  def handle_duplicate(socket, %{"id" => id}) do
    source = socket.assigns.source
    original = load_transponder(source, id)
    next_order = Organizations.get_next_transponder_order(source)

    attrs =
      %{
        "name" => (original.name || original.key) <> " (copy)",
        "key" => original.key,
        "type" => original.type,
        "config" => original.config || %{},
        "enabled" => false,
        "order" => next_order
      }
      |> maybe_put_database_id(source)

    case create_transponder_for_source(source, attrs) do
      {:ok, transponder} ->
        {:noreply,
         socket
         |> Component.assign(:transponders_empty, false)
         |> LiveView.stream_insert(:transponders, transponder)
         |> LiveView.put_flash(:info, "Transponder duplicated")}

      {:error, _changeset} ->
        {:noreply, LiveView.put_flash(socket, :error, "Could not duplicate transponder")}
    end
  end

  def handle_reorder(socket, %{"ids" => ids}) do
    source = socket.assigns.source

    case Organizations.update_transponder_order(source, ids) do
      {:ok, _} ->
        transponders = list_transponders_for_source(source)

        {:noreply,
         socket
         |> Component.assign(:transponders_empty, Enum.empty?(transponders))
         |> LiveView.stream(:transponders, transponders, reset: true)
         |> LiveView.put_flash(:info, "Transponder order updated successfully")}

      {:error, _} ->
        {:noreply, LiveView.put_flash(socket, :error, "Failed to update transponder order")}
    end
  end

  def resolve_database_source(%{"id" => _database_id}, %{current_membership: nil}) do
    {:redirect, ~p"/organization/profile"}
  end

  def resolve_database_source(%{"id" => database_id}, %{current_membership: membership}) do
    database = Organizations.get_database_for_org!(membership.organization_id, database_id)

    {:ok,
     %{
       source_type: :database,
       source: database,
       database: database,
       nav_section: :databases,
       breadcrumb_links: [
         {"Databases", ~p"/dbs"},
         {database.display_name, ~p"/dashboards"},
         "Transponders"
       ],
       page_title: page_title_for_action(:index, :database, database)
     }}
  end

  def resolve_project_source(%{"id" => project_id}, assigns) do
    current_membership = assigns[:current_membership]

    cond do
      is_nil(current_membership) ->
        {:redirect, ~p"/projects"}

      true ->
        project =
          Organizations.get_project_for_org!(current_membership.organization_id, project_id)

        {:ok,
         %{
           source_type: :project,
           source: project,
           project: project,
           nav_section: :projects,
           breadcrumb_links: [
             {"Projects", ~p"/projects"},
             {project.name || "Project", ~p"/projects/#{project.id}/transponders"},
             "Transponders"
           ],
           page_title: page_title_for_action(:index, :project, project)
         }}
    end
  rescue
    NoResultsError -> {:redirect, ~p"/projects"}
  end

  def base_action(action) when action in [:index, :new, :show, :edit], do: action
  def base_action(_), do: :index

  def page_title_for_action(action, source_type, source, transponder \\ nil)

  def page_title_for_action(:index, :database, %Database{} = database, _transponder) do
    "Database · #{database.display_name} · Transponders"
  end

  def page_title_for_action(:index, :project, %Project{} = project, _transponder) do
    "Projects · #{project.name} · Transponders"
  end

  def page_title_for_action(:new, :database, %Database{} = database, _transponder) do
    "Database · #{database.display_name} · New Transponder"
  end

  def page_title_for_action(:new, :project, %Project{} = project, _transponder) do
    "Projects · #{project.name} · New Transponder"
  end

  def page_title_for_action(:show, source_type, source, %Transponder{} = transponder) do
    base = page_title_for_action(:index, source_type, source)
    transponder_label = transponder.name || transponder.key
    base <> " · " <> (transponder_label || "Transponder")
  end

  def page_title_for_action(:edit, source_type, source, %Transponder{} = transponder) do
    base = page_title_for_action(:index, source_type, source)
    transponder_label = transponder.name || transponder.key
    base <> " · Edit #{transponder_label || "Transponder"}"
  end

  def page_title_for_action(_other, _source_type, _source, _transponder) do
    "Transponders"
  end

  def list_transponders_for_source(%Database{} = database) do
    Organizations.list_transponders_for_database(database)
  end

  def list_transponders_for_source(%Project{} = project) do
    Organizations.list_transponders_for_project(project)
  end

  def load_transponder(%Database{} = database, id) do
    Organizations.get_transponder_for_source!(database, id)
  end

  def load_transponder(%Project{} = project, id) do
    Organizations.get_transponder_for_source!(project, id)
  end

  def create_transponder_for_source(%Database{} = database, attrs) do
    Organizations.create_transponder_for_database(database, attrs)
  end

  def create_transponder_for_source(%Project{} = project, attrs) do
    Organizations.create_transponder_for_project(project, attrs)
  end

  def maybe_put_database_id(attrs, %Database{} = database) do
    Map.put(attrs, "database_id", database.id)
  end

  def maybe_put_database_id(attrs, _), do: attrs

  def transponder_index_path(:database, %Database{id: id}), do: ~p"/dbs/#{id}/transponders"
  def transponder_index_path(:project, %Project{id: id}), do: ~p"/projects/#{id}/transponders"

  def transponder_new_path(:database, %Database{id: id}), do: ~p"/dbs/#{id}/transponders/new"
  def transponder_new_path(:project, %Project{id: id}), do: ~p"/projects/#{id}/transponders/new"

  def transponder_show_path(:database, %Database{id: id}, transponder_id),
    do: ~p"/dbs/#{id}/transponders/#{transponder_id}"

  def transponder_show_path(:project, %Project{id: id}, transponder_id),
    do: ~p"/projects/#{id}/transponders/#{transponder_id}"

  def transponder_edit_path(:database, %Database{id: id}, transponder_id),
    do: ~p"/dbs/#{id}/transponders/#{transponder_id}/edit"

  def transponder_edit_path(:project, %Project{id: id}, transponder_id),
    do: ~p"/projects/#{id}/transponders/#{transponder_id}/edit"

  def transponder_form_cancel_path(source_type, source) do
    transponder_index_path(source_type, source)
  end

  def transponder_settings_path(:database, %Database{id: id}), do: ~p"/dbs/#{id}/settings"
  def transponder_settings_path(:project, %Project{id: id}), do: ~p"/projects/#{id}/settings"
  def transponder_settings_path(_, _), do: nil
end
