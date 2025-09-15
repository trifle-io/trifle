defmodule Trifle.Organizations do
  @moduledoc """
  The Organizations context.
  """

  import Ecto.Query, warn: false
  alias Trifle.Repo

  alias Trifle.Organizations.{Project, Database, Dashboard, Transponder, DashboardGroup}

  @doc """
  Returns the list of projects.

  ## Examples

      iex> list_projects()
      [%Project{}, ...]

  """
  def list_projects do
    Repo.all(Project)
  end

  def list_users_projects(%Trifle.Accounts.User{} = user) do
    query =
      from(
        p in Project,
        where: p.user_id == ^user.id
      )

    Repo.all(query)
  end

  @doc """
  Gets a single project.

  Raises `Ecto.NoResultsError` if the Project does not exist.

  ## Examples

      iex> get_project!(123)
      %Project{}

      iex> get_project!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Creates a project.

  ## Examples

      iex> create_project(%{field: value})
      {:ok, %Project{}}

      iex> create_project(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def create_users_project(attrs \\ %{}, %Trifle.Accounts.User{} = user) do
    attrs = Map.put(attrs, "user", user)

    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.

  ## Examples

      iex> update_project(project, %{field: new_value})
      {:ok, %Project{}}

      iex> update_project(project, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.

  ## Examples

      iex> delete_project(project)
      {:ok, %Project{}}

      iex> delete_project(project)
      {:error, %Ecto.Changeset{}}

  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.

  ## Examples

      iex> change_project(project)
      %Ecto.Changeset{data: %Project{}}

  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  alias Trifle.Organizations.ProjectToken

  @doc """
  Returns the list of project_tokens.

  ## Examples

      iex> list_project_tokens()
      [%ProjectToken{}, ...]

  """
  def list_project_tokens do
    Repo.all(ProjectToken)
  end

  def list_projects_project_tokens(%Project{} = project) do
    query =
      from(
        pt in ProjectToken,
        where: pt.project_id == ^project.id
      )

    Repo.all(query)
  end

  @doc """
  Gets a single project_token.

  Raises `Ecto.NoResultsError` if the Project token does not exist.

  ## Examples

      iex> get_project_token!(123)
      %ProjectToken{}

      iex> get_project_token!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project_token!(id), do: Repo.get!(ProjectToken, id)

  def get_project_by_token(token) when is_binary(token) do
    with token when not is_nil(token) <- Repo.get_by(ProjectToken, token: token) |> Repo.preload(:project),
      {:ok, _id} <- Phoenix.Token.verify(TrifleWeb.Endpoint, "project auth", token.token, max_age: 86400 * 365) do
      {:ok, token.project, token}
    else
      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Creates a project_token.

  ## Examples

      iex> create_project_token(%{field: value})
      {:ok, %ProjectToken{}}

      iex> create_project_token(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_project_token(attrs \\ %{}) do
    %ProjectToken{}
    |> ProjectToken.changeset(attrs)
    |> Repo.insert()
  end

  def create_projects_project_token(attrs \\ %{}, %Project{} = project) do
    attrs = Map.put(attrs, "project", project)

    %ProjectToken{}
    |> ProjectToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project_token.

  ## Examples

      iex> update_project_token(project_token, %{field: new_value})
      {:ok, %ProjectToken{}}

      iex> update_project_token(project_token, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_project_token(%ProjectToken{} = project_token, attrs) do
    project_token
    |> ProjectToken.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project_token.

  ## Examples

      iex> delete_project_token(project_token)
      {:ok, %ProjectToken{}}

      iex> delete_project_token(project_token)
      {:error, %Ecto.Changeset{}}

  """
  def delete_project_token(%ProjectToken{} = project_token) do
    Repo.delete(project_token)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project_token changes.

  ## Examples

      iex> change_project_token(project_token)
      %Ecto.Changeset{data: %ProjectToken{}}

  """
  def change_project_token(%ProjectToken{} = project_token, attrs \\ %{}) do
    ProjectToken.changeset(project_token, attrs)
  end

  ## Database functions

  @doc """
  Returns the list of databases.
  """
  def list_databases do
    from(d in Database, order_by: [asc: d.inserted_at, asc: d.id])
    |> Repo.all()
  end

  @doc """
  Gets a single database.

  Raises `Ecto.NoResultsError` if the Database does not exist.
  """
  def get_database!(id), do: Repo.get!(Database, id)

  @doc """
  Creates a database.
  """
  def create_database(attrs \\ %{}) do
    %Database{}
    |> Database.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a database.
  """
  def update_database(%Database{} = database, attrs) do
    database
    |> Database.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a database.
  """
  def delete_database(%Database{} = database) do
    Repo.delete(database)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking database changes.
  """
  def change_database(%Database{} = database, attrs \\ %{}) do
    Database.changeset(database, attrs)
  end

  @doc """
  Checks if the database is already set up.
  """
  def database_setup?(%Database{} = database) do
    Database.is_setup?(database)
  end

  @doc """
  Checks the database status and updates the tracking fields.
  """
  def check_database_status(%Database{} = database) do
    Database.check_status(database)
  end

  @doc """
  Sets up the database for Trifle::Stats.
  """
  def setup_database(%Database{} = database) do
    Database.setup(database)
  end

  @doc """
  Nukes all data from the database.
  """
  def nuke_database(%Database{} = database) do
    Database.nuke(database)
  end

  ## Transponder functions

  alias Trifle.Organizations.Transponder

  @doc """
  Returns the list of transponders for a database.
  """
  def list_transponders_for_database(%Database{} = database) do
    Repo.all(from t in Transponder, where: t.database_id == ^database.id, order_by: [asc: t.order, asc: t.key])
  end

  @doc """
  Gets a single transponder.
  """
  def get_transponder!(id), do: Repo.get!(Transponder, id)

  @doc """
  Creates a transponder.
  """
  def create_transponder(attrs \\ %{}) do
    %Transponder{}
    |> Transponder.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a transponder.
  """
  def update_transponder(%Transponder{} = transponder, attrs) do
    transponder
    |> Transponder.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a transponder.
  """
  def delete_transponder(%Transponder{} = transponder) do
    Repo.delete(transponder)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking transponder changes.
  """
  def change_transponder(%Transponder{} = transponder, attrs \\ %{}) do
    Transponder.changeset(transponder, attrs)
  end

  @doc """
  Updates the order of transponders for a database.
  """
  def update_transponder_order(%Database{} = database, transponder_ids) do
    Repo.transaction(fn ->
      transponder_ids
      |> Enum.with_index()
      |> Enum.each(fn {transponder_id, index} ->
        from(t in Transponder, where: t.id == ^transponder_id and t.database_id == ^database.id)
        |> Repo.update_all(set: [order: index])
      end)
    end)
  end

  @doc """
  Sets the next available order for a new transponder.
  """
  def get_next_transponder_order(%Database{} = database) do
    query = from(t in Transponder, 
      where: t.database_id == ^database.id, 
      select: max(t.order)
    )
    
    case Repo.one(query) do
      nil -> 0
      max_order -> max_order + 1
    end
  end

  @doc """
  Returns the next position index for dashboards within a group (global).
  Pass nil for top-level (ungrouped).
  """
  def get_next_dashboard_position_for_group(group_id) do
    base = from(d in Dashboard, select: max(d.position))
    query = case group_id do
      nil -> from(d in base, where: is_nil(d.group_id))
      id when is_binary(id) -> from(d in base, where: d.group_id == ^id)
    end

    case Repo.one(query) do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  @doc """
  Returns the list of dashboards for a database.
  """
  def list_dashboards_for_database(%Database{} = database) do
    from(d in Dashboard,
      where: d.database_id == ^database.id,
      order_by: [asc: d.position, asc: d.inserted_at],
      preload: :user
    )
    |> Repo.all()
  end

  @doc """
  Returns all dashboards across the organization (all databases).
  """
  def list_all_dashboards do
    from(d in Dashboard, order_by: [asc: d.inserted_at, asc: d.id], preload: [:user, :database])
    |> Repo.all()
  end

  # Removed database-scoped dashboard group listing in favor of global groups

  @doc """
  Returns dashboard groups at the organization level, optionally under a parent group.
  """
  def list_dashboard_groups_global(nil) do
    from(g in DashboardGroup,
      where: is_nil(g.parent_group_id),
      order_by: [asc: g.position]
    )
    |> Repo.all()
  end

  def list_dashboard_groups_global(parent_group_id) when is_binary(parent_group_id) do
    from(g in DashboardGroup,
      where: g.parent_group_id == ^parent_group_id,
      order_by: [asc: g.position]
    )
    |> Repo.all()
  end

  # Removed database-scoped dashboard listing in favor of user-or-visible global queries

  @doc """
  Returns dashboards either created by the given user or visible to everyone, filtered by group.
  """
  def list_dashboards_for_user_or_visible(%Trifle.Accounts.User{} = user, group_id \\ nil) do
    base = from(d in Dashboard,
      where: d.user_id == ^user.id or d.visibility == true,
      order_by: [asc: d.position, asc: d.inserted_at],
      preload: [:user, :database]
    )

    query =
      case group_id do
        nil -> from(d in base, where: is_nil(d.group_id))
        id when is_binary(id) -> from(d in base, where: d.group_id == ^id)
      end

    Repo.all(query)
  end

  @doc """
  Counts dashboards either created by the given user or visible to everyone.
  """
  def count_dashboards_for_user_or_visible(%Trifle.Accounts.User{} = user) do
    query = from(d in Dashboard,
      where: d.user_id == ^user.id or d.visibility == true,
      select: count(d.id)
    )
    Repo.one(query)
  end

  @doc """
  Builds a nested tree of groups and dashboards for the entire organization.
  Includes dashboards owned by user or visible to everyone.
  """
  def list_dashboard_tree_global(%Trifle.Accounts.User{} = user) do
    top_groups = list_dashboard_groups_global(nil)

    Enum.map(top_groups, fn g ->
      build_group_tree_global(user, g)
    end)
  end

  defp build_group_tree_global(%Trifle.Accounts.User{} = user, %DashboardGroup{} = group) do
    children = list_dashboard_groups_global(group.id)
    %{
      group: group,
      children: Enum.map(children, &build_group_tree_global(user, &1)),
      dashboards: list_dashboards_for_user_or_visible(user, group.id)
    }
  end

  @doc """
  Creates a dashboard group.
  """
  def create_dashboard_group(attrs \\ %{}) do
    %DashboardGroup{}
    |> DashboardGroup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a dashboard group.
  """
  def update_dashboard_group(%DashboardGroup{} = group, attrs) do
    group
    |> DashboardGroup.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a dashboard group, moving its children (groups and dashboards) to its parent.
  """
  def delete_dashboard_group(%DashboardGroup{} = group) do
    Repo.transaction(fn ->
      # Move dashboards to parent
      from(d in Dashboard, where: d.group_id == ^group.id)
      |> Repo.update_all(set: [group_id: group.parent_group_id])

      # Move child groups to parent
      from(g in DashboardGroup, where: g.parent_group_id == ^group.id)
      |> Repo.update_all(set: [parent_group_id: group.parent_group_id])

      Repo.delete!(group)
    end)
  end

  @doc """
  Gets a dashboard group by id.
  """
  def get_dashboard_group!(id), do: Repo.get!(DashboardGroup, id)

  @doc """
  Returns the next position index for dashboard groups under a parent group (global).
  """
  def get_next_dashboard_group_position(parent_group_id) do
    base = from(g in DashboardGroup, select: max(g.position))
    query = case parent_group_id do
      nil -> from(g in base, where: is_nil(g.parent_group_id))
      id when is_binary(id) -> from(g in base, where: g.parent_group_id == ^id)
    end
    case Repo.one(query) do
      nil -> 0
      max_pos -> max_pos + 1
    end
  end

  @doc """
  Reorders mixed nodes (groups and dashboards) within a container (global).
  items: list of maps %{"id" => id, "type" => "group" | "dashboard"}
  from_items: same for the source container after the move
  """
  def reorder_nodes(parent_group_id, items, from_parent_id, from_items, moved_id, moved_type) when is_list(items) do
    # Cycle protection for groups
    if moved_type == "group" and parent_group_id && group_descendant?(moved_id, parent_group_id) do
      {:error, :invalid_parent}
    else
      Repo.transaction(fn ->
        # Update target container in order
        Enum.with_index(items)
        |> Enum.each(fn {%{"id" => id, "type" => type}, idx} ->
          case type do
            "dashboard" ->
              from(d in Dashboard, where: d.id == ^id)
              |> Repo.update_all(set: [group_id: parent_group_id, position: idx])
            "group" ->
              from(g in DashboardGroup, where: g.id == ^id)
              |> Repo.update_all(set: [parent_group_id: parent_group_id, position: idx])
            _ -> :ok
          end
        end)

        # Normalize source container positions if different container
        if is_list(from_items) and from_parent_id != parent_group_id do
          Enum.with_index(from_items)
          |> Enum.each(fn {%{"id" => id, "type" => type}, idx} ->
            case type do
              "dashboard" ->
                from(d in Dashboard, where: d.id == ^id)
                |> Repo.update_all(set: [position: idx])
              "group" ->
                from(g in DashboardGroup, where: g.id == ^id)
                |> Repo.update_all(set: [position: idx])
              _ -> :ok
            end
          end)
        end
      end)
    end
  end
  # Returns true if possible_parent_id is a descendant of group_id
  defp group_descendant?(group_id, possible_parent_id) do
    case Repo.get(DashboardGroup, possible_parent_id) do
      nil -> false
      %DashboardGroup{parent_group_id: nil} -> group_id == possible_parent_id
      %DashboardGroup{parent_group_id: parent_id} = g ->
        group_id == g.id || group_descendant?(group_id, parent_id)
    end
  end

  @doc """
  Gets a single dashboard.
  """
  def get_dashboard!(id) do
    Dashboard
    |> Repo.get!(id)
    |> Repo.preload([:user, :database])
  end

  @doc """
  Creates a dashboard.
  """
  def create_dashboard(attrs \\ %{}) do
    %Dashboard{}
    |> Dashboard.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a dashboard.
  """
  def update_dashboard(%Dashboard{} = dashboard, attrs) do
    dashboard
    |> Dashboard.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a dashboard.
  """
  def delete_dashboard(%Dashboard{} = dashboard) do
    Repo.delete(dashboard)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking dashboard changes.
  """
  def change_dashboard(%Dashboard{} = dashboard, attrs \\ %{}) do
    Dashboard.changeset(dashboard, attrs)
  end

  @doc """
  Generates a public access token for a dashboard.
  """
  def generate_dashboard_public_token(%Dashboard{} = dashboard) do
    dashboard
    |> Dashboard.generate_public_token()
    |> Repo.update()
  end

  @doc """
  Removes the public access token from a dashboard.
  """
  def remove_dashboard_public_token(%Dashboard{} = dashboard) do
    dashboard
    |> Dashboard.remove_public_token()
    |> Repo.update()
  end

  @doc """
  Gets a dashboard by public access token for unauthenticated access.
  """
  def get_dashboard_by_token(dashboard_id, token) when is_binary(dashboard_id) and is_binary(token) do
    case Repo.get(Dashboard, dashboard_id) do
      %Dashboard{access_token: ^token} = dashboard when not is_nil(token) ->
        dashboard = Repo.preload(dashboard, [:user, :database])
        {:ok, dashboard}
      
      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns the list of DashboardGroup structs from top-level down to the given group_id.
  If `group_id` is nil, returns an empty list.
  """
  def get_dashboard_group_chain(nil), do: []
  def get_dashboard_group_chain(group_id) when is_binary(group_id) do
    chain = do_group_chain(group_id, [])
    Enum.reverse(chain)
  end

  defp do_group_chain(nil, acc), do: acc
  defp do_group_chain(group_id, acc) do
    case Repo.get(DashboardGroup, group_id) do
      nil -> acc
      %DashboardGroup{parent_group_id: parent} = g -> do_group_chain(parent, [g | acc])
    end
  end
end
