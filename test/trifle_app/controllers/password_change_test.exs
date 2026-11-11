defmodule TrifleApp.PasswordChangeTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.AccountsFixtures

  alias Trifle.Accounts

  @new_password "a brand new password"

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  defp change(conn, current, new \\ @new_password) do
    post(conn, ~p"/users/settings/password", %{
      "user" => %{
        "password" => new,
        "password_confirmation" => new,
        "current_password" => current
      }
    })
  end

  defp topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  test "changes the password and replaces the session in the same response", %{
    conn: conn,
    user: user
  } do
    old_token = get_session(conn, :user_token)

    response = change(conn, valid_user_password())

    assert redirected_to(response) == ~p"/users/settings"
    assert Phoenix.Flash.get(response.assigns.flash, :info) =~ "Password updated"

    new_token = get_session(response, :user_token)
    assert new_token != old_token
    assert Accounts.get_user_by_session_token(new_token).id == user.id
    assert is_nil(Accounts.get_user_by_session_token(old_token))
    assert Accounts.get_user_by_email_and_password(user.email, @new_password)
  end

  test "every existing session is disconnected immediately, the caller's included", %{
    conn: conn,
    user: user
  } do
    own_token = get_session(conn, :user_token)
    other_token = Accounts.generate_user_session_token(user)
    TrifleWeb.Endpoint.subscribe(topic(own_token))
    TrifleWeb.Endpoint.subscribe(topic(other_token))

    change(conn, valid_user_password())

    own = topic(own_token)
    other = topic(other_token)
    assert_receive %Phoenix.Socket.Broadcast{topic: ^own, event: "disconnect"}, 500
    assert_receive %Phoenix.Socket.Broadcast{topic: ^other, event: "disconnect"}, 500
    assert is_nil(Accounts.get_user_by_session_token(other_token))
  end

  test "a wrong current password changes nothing and keeps the session", %{conn: conn, user: user} do
    token = get_session(conn, :user_token)
    TrifleWeb.Endpoint.subscribe(topic(token))

    response = change(conn, "not the password")

    assert redirected_to(response) == ~p"/users/settings"
    assert Phoenix.Flash.get(response.assigns.flash, :error) =~ "not changed"
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    assert Accounts.get_user_by_session_token(token)
    refute_receive %Phoenix.Socket.Broadcast{event: "disconnect"}, 100
  end

  test "an invalid new password changes nothing", %{conn: conn, user: user} do
    response = change(conn, valid_user_password(), "short")

    assert Phoenix.Flash.get(response.assigns.flash, :error) =~ "not changed"
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
  end

  test "requires a signed-in user" do
    response = change(build_conn(), valid_user_password())
    assert redirected_to(response) == ~p"/users/log_in"
  end

  test "the settings page only validates; the password changes when the form is submitted over HTTP",
       %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    form =
      form(lv, "#password_form", %{
        "user" => %{
          "password" => @new_password,
          "password_confirmation" => @new_password,
          "current_password" => valid_user_password()
        }
      })

    render_submit(form)

    # Nothing has changed yet: the socket did not perform the update.
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    assert Accounts.get_user_by_session_token(get_session(conn, :user_token))

    response = follow_trigger_action(form, conn)

    assert redirected_to(response) == ~p"/users/settings"
    assert Accounts.get_user_by_email_and_password(user.email, @new_password)
    assert get_session(response, :user_token) != get_session(conn, :user_token)
  end

  test "the settings page rejects a wrong current password without submitting", %{
    conn: conn,
    user: user
  } do
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    html =
      lv
      |> form("#password_form", %{
        "user" => %{
          "password" => @new_password,
          "password_confirmation" => @new_password,
          "current_password" => "not the password"
        }
      })
      |> render_submit()

    assert html =~ "is not valid"
    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
  end
end
