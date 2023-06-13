defmodule Trifle.Organizations do
  @moduledoc """
  The Organizations context.
  """

  import Ecto.Query, warn: false
  alias Trifle.Repo

  alias Trifle.Organizations.Project

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
      {:ok, id} <- Phoenix.Token.verify(TrifleWeb.Endpoint, "project auth", token.token, max_age: 86400 * 365) do
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
end
