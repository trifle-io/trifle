defmodule Trifle.Organizations.Dashboard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "dashboards" do
    field :name, :string
    field :visibility, :boolean, default: false  # Now means Personal (false) / Everyone (true)
    field :access_token, :string  # For public URL access, nullable
    field :payload, :map, default: %{}
    field :key, :string

    belongs_to :database, Trifle.Organizations.Database
    belongs_to :user, Trifle.Accounts.User

    timestamps()
  end

  def changeset(dashboard, attrs) do
    # Handle payload separately to avoid Ecto's automatic casting
    {payload_raw, attrs_without_payload} = Map.pop(attrs, "payload")
    
    dashboard
    |> cast(attrs_without_payload, [:database_id, :user_id, :name, :visibility, :access_token, :key])
    |> validate_required([:database_id, :user_id, :name, :key])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:key, min: 1)
    |> handle_payload_field(payload_raw)
    |> unique_constraint(:access_token)
  end

  defp handle_payload_field(changeset, payload_raw) do
    case payload_raw do
      nil -> 
        put_change(changeset, :payload, %{})
      "" ->
        put_change(changeset, :payload, %{})
      payload when is_binary(payload) ->
        # Trim whitespace
        trimmed_payload = String.trim(payload)
        
        if trimmed_payload == "" do
          put_change(changeset, :payload, %{})
        else
          case Jason.decode(trimmed_payload) do
            {:ok, parsed} when is_map(parsed) ->
              put_change(changeset, :payload, parsed)
            {:ok, _parsed} ->
              add_error(changeset, :payload, "must be a valid JSON object")
            {:error, %Jason.DecodeError{position: pos, data: data} = error} ->
              # More detailed error message with position
              context = String.slice(data, max(0, pos - 20), 40)
              add_error(changeset, :payload, "invalid JSON at position #{pos}: #{Exception.message(error)}. Context: '#{context}'")
            {:error, error} ->
              add_error(changeset, :payload, "invalid JSON: #{inspect(error)}")
          end
        end
      %{} = payload ->
        # Already a map, keep it
        put_change(changeset, :payload, payload)
      _other ->
        add_error(changeset, :payload, "must be a JSON object")
    end
  end

  @doc """
  Generates a new public access token for the dashboard
  """
  def generate_public_token(dashboard) do
    token = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
    changeset(dashboard, %{access_token: token})
  end

  @doc """
  Removes the public access token from the dashboard
  """
  def remove_public_token(dashboard) do
    changeset(dashboard, %{access_token: nil})
  end

  def visibility_display(true), do: "Everyone"
  def visibility_display(false), do: "Personal"
end