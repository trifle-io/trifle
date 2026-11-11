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
    # Random value the organization publishes in DNS to prove it owns the domain.
    field :verification_token, :string
    # Set once the DNS record was seen. Only verified domains route sign-ins.
    field :verified_at, :utc_datetime

    timestamps(updated_at: false)
  end

  # Mailbox providers: anyone can have an address there, nobody "owns" the domain.
  @public_email_domains ~w(
    gmail.com googlemail.com outlook.com hotmail.com live.com msn.com yahoo.com
    ymail.com icloud.com me.com mac.com aol.com proton.me protonmail.com pm.me
    gmx.com gmx.net mail.com zoho.com yandex.com fastmail.com hey.com
  )

  def public_email_domain?(domain) when is_binary(domain),
    do: String.downcase(String.trim(domain)) in @public_email_domains

  def public_email_domain?(_), do: false

  def verified?(%__MODULE__{verified_at: %DateTime{}}), do: true
  def verified?(_), do: false

  @doc "DNS name the verification TXT record is published under."
  def verification_record_name(%__MODULE__{domain: domain}), do: "_trifle-verification.#{domain}"

  @doc "Value the TXT record must contain."
  def verification_record_value(%__MODULE__{verification_token: token}),
    do: "trifle-verification=#{token}"

  def changeset(domain, attrs) do
    domain
    |> cast(attrs, [:organization_sso_provider_id, :domain])
    |> validate_required([:organization_sso_provider_id, :domain])
    |> update_change(:domain, &normalize_domain/1)
    |> validate_format(:domain, ~r/^[a-z0-9.-]+\.[a-z]{2,}$/i, message: "is not a valid domain")
    |> validate_change(:domain, fn :domain, value ->
      if public_email_domain?(value),
        do: [domain: "is a public email provider and cannot be claimed"],
        else: []
    end)
    |> put_verification_token()
    |> unique_constraint(:domain,
      name: :organization_sso_unique_domain_per_provider,
      message: "already added"
    )
    |> unique_constraint(:domain,
      name: :organization_sso_unique_domain_global,
      message: "is already used by another organization"
    )
  end

  def verified_changeset(domain, verified_at \\ DateTime.utc_now()) do
    domain
    |> change(verified_at: DateTime.truncate(verified_at, :second))
    |> unique_constraint(:domain,
      name: :organization_sso_unique_domain_global,
      message: "is already verified by another organization"
    )
  end

  defp put_verification_token(changeset) do
    if get_field(changeset, :verification_token) do
      changeset
    else
      token = 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
      put_change(changeset, :verification_token, token)
    end
  end

  defp normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_domain(domain), do: domain
end
