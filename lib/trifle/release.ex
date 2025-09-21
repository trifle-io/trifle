defmodule Trifle.Release do
  @moduledoc """
  Tasks to run in production releases.
  """

  @app :trifle

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_initial_user do
    load_app()

    email = System.get_env("INITIAL_USER_EMAIL")
    password = System.get_env("INITIAL_USER_PASSWORD", "password")
    admin = System.get_env("INITIAL_USER_ADMIN", "true") |> String.downcase() == "true"

    if email && String.trim(email) != "" do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(List.first(repos()), fn _repo ->
          case Trifle.Accounts.get_user_by_email(email) do
            nil ->
              create_user(email, password, admin)

            user ->
              reset_user(email, user, password, admin)
          end
        end)
    else
      IO.puts("ℹ️ No initial user email provided, skipping user creation")
    end
  end

  defp create_user(email, password, admin) do
    user_attrs = %{email: email, password: password}

    case Trifle.Accounts.register_user(user_attrs) do
      {:ok, user} ->
        timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        confirmed_user =
          user
          |> Ecto.Changeset.change(%{confirmed_at: timestamp})
          |> Trifle.Repo.update!()

        if admin do
          Trifle.Accounts.update_user_admin_status(confirmed_user.id, true)
        end

        IO.puts("✅ Created initial user: #{email} (admin: #{admin})")

      {:error, changeset} ->
        IO.puts("❌ Failed to create initial user: #{inspect(changeset.errors)}")
    end
  end

  defp reset_user(email, user, password, admin) do
    {:ok, _user} =
      Trifle.Accounts.reset_user_password(user, %{
        password: password,
        password_confirmation: password
      })

    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    user
    |> Ecto.Changeset.change(%{confirmed_at: timestamp})
    |> Trifle.Repo.update!()

    Trifle.Accounts.update_user_admin_status(user.id, admin)

    IO.puts("🔐 Reset user credentials: #{email} (admin: #{admin})")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)

    Enum.each([:crypto, :ssl, :public_key, :inets], fn app ->
      {:ok, _} = Application.ensure_all_started(app)
    end)

    {:ok, _} = Application.ensure_all_started(@app)
  end
end
