defmodule TrifleApp.UserSessionController do
  use TrifleApp, :controller

  alias Trifle.Accounts
  alias TrifleApp.UserAuth

  # Per client and per targeted account, so neither one machine nor a botnet can
  # grind through passwords.
  plug TrifleWeb.Plugs.RateLimit, [policy: :login] when action == :create

  plug TrifleWeb.Plugs.RateLimit,
       [policy: :login_account, by: {:param, ["user", "email"]}] when action == :create

  # Guessing the current password from a signed-in session is limited like a login.
  plug TrifleWeb.Plugs.RateLimit,
       [policy: :login_account, by: :user] when action == :update_password

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log_in")
    end
  end

  @doc """
  Changes the signed-in user's password and rotates the session in one request.

  Doing both here means there is no moment where the password has changed but an
  old session is still accepted: every existing session (this browser's other
  tabs, other devices, a copied cookie) is deleted and disconnected, and only
  this response carries the new one.
  """
  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_user
    current_password = params["current_password"] || user_params["current_password"] || ""
    attrs = Map.take(user_params, ["password", "password_confirmation"])

    case Accounts.update_user_password(user, current_password, attrs) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Password updated successfully!")
        |> put_session(:user_return_to, ~p"/users/settings")
        |> UserAuth.log_in_user(user)

      {:error, _changeset} ->
        conn
        |> put_flash(
          :error,
          "Password was not changed. Check your current password and the new password, then try again."
        )
        |> redirect(to: ~p"/users/settings")
    end
  end

  def update_password(conn, _params) do
    conn
    |> put_flash(:error, "Password was not changed.")
    |> redirect(to: ~p"/users/settings")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
