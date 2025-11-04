defmodule Trifle.Organizations.OrganizationSSODomain do
  use Ecto.Schema
  import Ecto.Changeset

  alias Trifle.Organizations.OrganizationSSOProvider

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_sso_domains" do
    belongs_to :provider, OrganizationSSOProvider,
      foreign_key: :organization_sso_provider_id,
      references: :id

    field :domain, :string

    timestamps(updated_at: false)
  end

  def changeset(domain, attrs) do
    domain
    |> cast(attrs, [:organization_sso_provider_id, :domain])
    |> validate_required([:organization_sso_provider_id, :domain])
    |> update_change(:domain, &normalize_domain/1)
    |> validate_format(:domain, ~r/^[a-z0-9.-]+\.[a-z]{2,}$/i, message: "is not a valid domain")
    |> unique_constraint(:domain,
      name: :organization_sso_unique_domain_per_provider,
      message: "already added"
    )
    |> unique_constraint(:domain,
      name: :organization_sso_unique_domain_global,
      message: "is already used by another organization"
    )
  end

  defp normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_domain(domain), do: domain
end
