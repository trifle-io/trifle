defmodule Trifle.SystemNotifications.Jobs.Dispatch do
  @moduledoc false

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [period: 604_800, fields: [:worker, :args], keys: [:notification_id]]

  import Ecto.Query

  alias Trifle.Accounts.User
  alias Trifle.Repo
  alias Trifle.SystemNotifications.Jobs.Deliver

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "notification_id" => notification_id,
          "event" => event,
          "payload" => payload
        }
      }) do
    User
    |> where([user], user.is_admin == true)
    |> select([user], user.id)
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn recipient_id, :ok ->
      args = %{
        "notification_id" => notification_id,
        "recipient_id" => recipient_id,
        "event" => event,
        "payload" => payload
      }

      case Oban.insert(Deliver.new(args)) do
        {:ok, _job} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def perform(%Oban.Job{}), do: :discard
end
