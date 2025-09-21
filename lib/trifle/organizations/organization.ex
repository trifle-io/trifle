defmodule Trifle.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required_fields ~w(name)a
  @optional_fields ~w(slug address_line1 address_line2 city state postal_code country timezone vat_number registration_number metadata address_country)a

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :address_line1, :string
    field :address_line2, :string
    field :city, :string
    field :state, :string
    field :postal_code, :string
    field :country, :string
    field :timezone, :string
    field :vat_number, :string
    field :registration_number, :string
    field :metadata, :map, default: %{}
    field :address_country, :string, virtual: true

    has_many :memberships, Trifle.Organizations.OrganizationMembership
    has_many :invitations, Trifle.Organizations.OrganizationInvitation
    has_many :databases, Trifle.Organizations.Database
    has_many :dashboards, Trifle.Organizations.Dashboard
    has_many :dashboard_groups, Trifle.Organizations.DashboardGroup
    has_many :transponders, Trifle.Organizations.Transponder

    timestamps()
  end

  def changeset(organization, attrs) do
    organization
    |> preload_virtual_fields()
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> maybe_put_slug()
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9\-]*$/,
      message: "must contain lowercase letters, numbers, and hyphens"
    )
    |> unique_constraint(:slug)
    |> store_address_country()
  end

  defp preload_virtual_fields(%__MODULE__{} = organization) do
    metadata_country = Map.get(organization.metadata || %{}, "address_country")
    address_country = organization.address_country || metadata_country || organization.country
    Map.put(organization, :address_country, address_country)
  end

  defp store_address_country(changeset) do
    case get_change(changeset, :address_country) do
      nil ->
        changeset

      address_country ->
        metadata = get_field(changeset, :metadata) || %{}

        updated_metadata =
          if blank?(address_country) do
            Map.delete(metadata, "address_country")
          else
            Map.put(metadata, "address_country", address_country)
          end

        put_change(changeset, :metadata, updated_metadata)
    end
  end

  defp maybe_put_slug(changeset) do
    case {get_change(changeset, :slug), get_field(changeset, :name)} do
      {nil, nil} -> changeset
      {nil, name} -> put_change(changeset, :slug, slugify(name))
      {"", name} when is_binary(name) -> put_change(changeset, :slug, slugify(name))
      _ -> changeset
    end
  end

  defp slugify(nil), do: nil

  defp slugify(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp blank?(value) when is_nil(value), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
