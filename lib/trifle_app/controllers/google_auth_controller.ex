defmodule TrifleApp.GoogleAuthController do
  use TrifleApp, :controller

  alias Trifle.Accounts
  alias Trifle.Organizations
  alias TrifleApp.UserAuth

  plug :check_google_config
  plug :store_oauth_context when action in [:request]
  plug Ueberauth

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    message = oauth_error_message(failure)

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/users/log_in")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    email = auth.info.email
    name = auth.info.name || auth.info.first_name && auth.info.last_name && String.trim("#{auth.info.first_name} #{auth.info.last_name}") || auth.info.nickname
    verified? = Map.get(auth.info, :verified, false) || verified_from_raw(auth)

    cond do
      is_nil(email) ->
        oauth_failure(
          conn,
          "Google did not provide an email address. Please try a different sign in method."
        )

      verified? == false ->
        oauth_failure(
          conn,
          "Your Google email is not verified. Please verify it with Google before signing in."
        )

      true ->
        with {:ok, user} <- Accounts.get_or_create_user_for_sso(email, %{name: name}),
             {:ok, _} <- Organizations.ensure_membership_for_sso(user, :google, email) do
          conn
          |> maybe_restore_return_to()
          |> clear_oauth_context()
          |> put_flash(:info, "Signed in with Google")
          |> UserAuth.log_in_user(user, %{})
        else
          {:error, :auto_provision_disabled} ->
            oauth_failure(
              conn,
              "This organization allows Google sign-in but automatic membership is disabled. Please contact an administrator for an invite."
            )

          {:error, :domain_not_allowed} ->
            oauth_failure(
              conn,
              "Your email domain is not allowed for automatic sign in. Request access from your organization administrator."
            )

          {:error, :invalid_email_domain} ->
            oauth_failure(
              conn,
              "We couldn't determine your email domain. Please contact support."
            )

          {:error, %Ecto.Changeset{} = changeset} ->
            oauth_failure(
              conn,
              "We could not add you to the organization: #{format_changeset_errors(changeset)}"
            )

          {:error, reason} ->
            oauth_failure(conn, "Unable to sign you in with Google: #{inspect(reason)}")
        end
    end
  end

  defp oauth_failure(conn, message) do
    conn
    |> clear_oauth_context()
    |> put_flash(:error, message)
    |> redirect(to: ~p"/users/log_in")
  end

  defp oauth_error_message(%{errors: errors}) when is_list(errors) and errors != [] do
    errors
    |> Enum.map(fn %{message: message, description: desc} ->
      case {message, desc} do
        {nil, nil} -> nil
        {msg, nil} -> msg
        {nil, description} -> description
        {msg, description} -> "#{msg}: #{description}"
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
    |> case do
      "" -> "Google sign in was cancelled."
      message -> message
    end
  end

  defp oauth_error_message(_failure), do: "Google sign in failed. Please try again."

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end

  defp verified_from_raw(auth) do
    auth.extra
    |> Map.get(:raw_info, %{})
    |> Map.get(:user, %{})
    |> Map.get("email_verified")
    |> case do
      value when value in [true, "true", "TRUE", "1"] -> true
      _ -> false
    end
  end

  defp store_oauth_context(%{path_params: %{"provider" => "google"}} = conn, _) do
    conn
    |> maybe_put_session(:oauth_return_to, conn.params["return_to"])
    |> maybe_put_session(:oauth_invitation_token, conn.params["invitation_token"])
  end

  defp store_oauth_context(conn, _), do: conn

  defp maybe_put_session(conn, _key, value) when value in [nil, ""], do: conn
  defp maybe_put_session(conn, key, value), do: put_session(conn, key, value)

  defp maybe_restore_return_to(conn) do
    case get_session(conn, :oauth_return_to) do
      value when value in [nil, ""] -> conn
      return_to -> put_session(conn, :user_return_to, return_to)
    end
  end

  defp clear_oauth_context(conn) do
    conn
    |> delete_session(:oauth_return_to)
    |> delete_session(:oauth_invitation_token)
  end

  defp check_google_config(%{path_params: %{"provider" => "google"}} = conn, _) do
    config = google_oauth_config()
    client_id = Map.get(config, :client_id) || Map.get(config, "client_id")
    client_secret = Map.get(config, :client_secret) || Map.get(config, "client_secret")

    if client_id && client_secret do
      conn
    else
      conn
      |> put_flash(:error, "Google sign in is not configured for this deployment.")
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  defp check_google_config(conn, _) do
    conn
    |> send_resp(:not_found, "")
    |> halt()
  end

  defp google_oauth_config do
    base = normalize_config(Application.get_env(:trifle, :google_oauth, %{}))

    env_overrides =
      %{
        client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID") || System.get_env("GOOGLE_CLIENT_ID"),
        client_secret:
          System.get_env("GOOGLE_OAUTH_CLIENT_SECRET") || System.get_env("GOOGLE_CLIENT_SECRET"),
        redirect_uri:
          System.get_env("GOOGLE_OAUTH_REDIRECT_URI") || System.get_env("GOOGLE_REDIRECT_URI")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or String.trim(v) == "" end)
      |> Map.new()

    Map.merge(base, env_overrides, fn _key, _base, override -> override end)
  end

  defp normalize_config(config) when is_map(config), do: config
  defp normalize_config(config) when is_list(config), do: Map.new(config)
  defp normalize_config(_), do: %{}
end
