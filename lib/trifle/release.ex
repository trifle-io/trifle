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
      {:ok, _, _} = Ecto.Migrator.with_repo(List.first(repos()), fn _repo ->
        case Trifle.Accounts.get_user_by_email(email) do
          nil ->
            user_attrs = %{
              email: email,
              password: password
            }

            case Trifle.Accounts.register_user(user_attrs) do
              {:ok, user} ->
                # Confirm the user automatically
                confirmed_user = user
                |> Ecto.Changeset.change(%{confirmed_at: NaiveDateTime.utc_now()})
                |> Trifle.Repo.update!()

                # Set admin status if required
                if admin do
                  Trifle.Accounts.update_user_admin_status(confirmed_user.id, true)
                end

                IO.puts("✅ Created initial user: #{email} (admin: #{admin})")

              {:error, changeset} ->
                IO.puts("❌ Failed to create initial user: #{inspect(changeset.errors)}")
            end

          _user ->
            IO.puts("ℹ️ User #{email} already exists, skipping creation")
        end
      end)
    else
      IO.puts("ℹ️ No initial user email provided, skipping user creation")
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end