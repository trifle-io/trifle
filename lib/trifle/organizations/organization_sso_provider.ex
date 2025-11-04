defmodule Trifle.Organizations.OrganizationSSOProvider do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.{Organization, OrganizationSSODomain}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(google)a

  schema "organization_sso_providers" do
    belongs_to :organization, Organization
    field :provider, Ecto.Enum, values: @providers
    field :enabled, :boolean, default: true
    field :auto_provision_members, :boolean, default: true

    has_many :domains, OrganizationSSODomain, preload_order: [asc: :domain]

    timestamps()
  end

  def providers, do: @providers

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:organization_id, :provider, :enabled, :auto_provision_members])
    |> validate_required([:organization_id, :provider])
    |> validate_inclusion(:provider, @providers)
    |> unique_constraint(:provider,
      name: :organization_sso_unique_provider_per_org,
      message: "already configured for this organization"
    )
  end

  def status_changeset(provider, attrs) do
    provider
    |> cast(attrs, [:enabled, :auto_provision_members])
    |> validate_required([:enabled, :auto_provision_members])
  end
end
