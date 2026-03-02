defmodule Trifle.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Trifle.Repo

  alias Trifle.Accounts.{User, UserApiToken, UserToken, UserNotifier}

  @sso_generated_password_length 32

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a user by a user API token.
  """
  def get_user_by_api_token(token) when is_binary(token) do
    token
    |> UserApiToken.valid_query()
    |> join(:inner, [t], user in assoc(t, :user))
    |> select([_t, user], user)
    |> Repo.one()
  end

  def get_user_by_api_token(_), do: nil

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Finds or creates a user for SSO-authenticated flows.
  """
  def get_or_create_user_for_sso(email, attrs \\ %{}) when is_binary(email) do
    name = normalize_name(attrs)

    case get_user_by_email(email) do
      %User{} = user ->
        with {:ok, user} <- ensure_user_confirmed(user),
             {:ok, user} <- maybe_update_user_name(user, name) do
          {:ok, user}
        end

      nil ->
        create_user_for_sso(email, name)
    end
  end

  defp ensure_user_confirmed(%User{} = user) do
    if user.confirmed_at do
      {:ok, user}
    else
      user
      |> User.confirm_changeset()
      |> Repo.update()
    end
  end

  defp create_user_for_sso(email, name) do
    password =
      @sso_generated_password_length
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    hashed_password = Bcrypt.hash_pwd_salt(password)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %User{}
    |> User.sso_changeset(%{
      email: email,
      hashed_password: hashed_password,
      confirmed_at: now,
      name: name
    })
    |> Repo.insert()
  end

  defp maybe_update_user_name(user, nil), do: {:ok, user}

  defp maybe_update_user_name(%User{name: nil} = user, name)
       when is_binary(name) and name != "" do
    user
    |> Ecto.Changeset.change(name: name)
    |> Repo.update()
  end

  defp maybe_update_user_name(%User{name: existing} = user, _name)
       when is_binary(existing) and existing != "" do
    {:ok, user}
  end

  defp maybe_update_user_name(user, _), do: {:ok, user}

  defp normalize_name(%{} = attrs) do
    attrs
    |> Map.get(:name) ||
      Map.get(attrs, "name")
      |> normalize_name()
  end

  defp normalize_name(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_name(_), do: nil

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1})")
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user theme.

  ## Examples

      iex> change_user_theme(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_theme(user, attrs \\ %{}) do
    User.theme_changeset(user, attrs)
  end

  @doc """
  Returns a changeset for editing profile fields (currently name).
  """
  def change_user_profile(%User{} = user, attrs \\ %{}) do
    user
    |> User.profile_changeset(attrs)
  end

  @doc """
  Updates profile fields for a user.
  """
  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the user theme preference.

  ## Examples

      iex> update_user_theme(user, %{theme: "dark"})
      {:ok, %User{}}

      iex> update_user_theme(user, %{theme: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_theme(user, attrs) do
    user
    |> User.theme_changeset(attrs)
    |> Repo.update()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Creates and persists a user API token.
  """
  def create_user_api_token(%User{} = user, attrs \\ %{}) do
    token = UserApiToken.build_token()
    attrs = attrs || %{}
    attrs = Map.new(attrs)

    attrs =
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put_new(:name, "CLI token")
      |> Map.put(:token_hash, UserApiToken.hash_token(token))
      |> put_metadata(:created_by, attrs)
      |> put_metadata(:created_from, attrs)

    case %UserApiToken{}
         |> UserApiToken.changeset(attrs)
         |> Repo.insert() do
      {:ok, record} -> {:ok, record, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Updates the last-used timestamp for a user API token.
  """
  def touch_user_api_token(token, attrs \\ %{})

  def touch_user_api_token(token, attrs) when is_binary(token) do
    attrs = attrs || %{}
    attrs = Map.new(attrs)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    updates =
      [last_used_at: now]
      |> maybe_put_update(:last_used_from, metadata_value(attrs, :last_used_from))

    token
    |> UserApiToken.valid_query()
    |> Repo.update_all(set: updates)

    :ok
  end

  def touch_user_api_token(_token, _attrs), do: :ok

  @doc """
  Lists user API tokens for the given user.
  """
  def list_user_api_tokens(%User{} = user) do
    from(t in UserApiToken, where: t.user_id == ^user.id, order_by: [desc: t.inserted_at])
    |> Repo.all()
  end

  @doc """
  Deletes a user API token belonging to the given user.
  """
  def delete_user_api_token(%User{} = user, token_id) when is_binary(token_id) do
    case get_user_api_token(user, token_id) do
      nil -> {:error, :not_found}
      token -> Repo.delete(token)
    end
  end

  def delete_user_api_token(_user, _token_id), do: {:error, :not_found}

  defp get_user_api_token(%User{} = user, token_id) do
    from(t in UserApiToken, where: t.user_id == ^user.id and t.id == ^token_id)
    |> Repo.one()
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Admin functions

  @doc """
  Returns the list of users.
  """
  def list_users do
    Repo.all(User)
  end

  def count_users do
    Repo.aggregate(User, :count, :id)
  end

  def count_system_admins do
    from(u in User, where: u.is_admin == true)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Updates a user's admin status.

  ## Examples

      iex> update_user_admin_status(user_id, true)
      {:ok, %User{}}

      iex> update_user_admin_status(invalid_id, false)
      {:error, %Ecto.Changeset{}}

  """
  def update_user_admin_status(user_id, is_admin) do
    user =
      cond do
        is_binary(user_id) -> Repo.get!(User, user_id)
        is_integer(user_id) -> Repo.get!(User, user_id)
        true -> raise ArgumentError, "invalid user id type"
      end

    user
    |> Ecto.Changeset.change(is_admin: is_admin)
    |> Repo.update()
  end

  defp put_metadata(attrs, key, source) do
    case metadata_value(source, key) do
      nil -> attrs
      value -> Map.put(attrs, key, value)
    end
  end

  defp metadata_value(attrs, key) do
    attrs
    |> Map.get(key)
    |> case do
      nil -> Map.get(attrs, Atom.to_string(key))
      value -> value
    end
    |> normalize_metadata(key)
  end

  defp normalize_metadata(value, key) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, metadata_limit(key))
    end
  end

  defp normalize_metadata(_value, _key), do: nil

  defp metadata_limit(:created_by), do: 160
  defp metadata_limit(_), do: 255

  defp maybe_put_update(updates, _key, nil), do: updates
  defp maybe_put_update(updates, key, value), do: Keyword.put(updates, key, value)
end
