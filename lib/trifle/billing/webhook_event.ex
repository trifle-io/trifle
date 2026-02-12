defmodule Trifle.Billing.WebhookEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "billing_webhook_events" do
    field :stripe_event_id, :string
    field :event_type, :string
    field :status, :string, default: "received"
    field :processed_at, :utc_datetime
    field :error, :string
    field :payload, :map, default: %{}

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:stripe_event_id, :event_type, :status, :processed_at, :error, :payload])
    |> validate_required([:stripe_event_id, :event_type, :payload])
    |> unique_constraint(:stripe_event_id, name: :billing_webhook_events_stripe_event_id_index)
  end
end
