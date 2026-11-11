defmodule Trifle.Organizations.SSODomainVerificationTest do
  # Replaces the global DNS TXT resolver.
  use Trifle.DataCase, async: false

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationSSODomain

  setup do
    on_exit(fn -> Application.delete_env(:trifle, :sso_txt_resolver) end)
    publish(%{})

    %{organization: organization_fixture(%{name: "Acme #{System.unique_integer([:positive])}"})}
  end

  # Simulates DNS: a map of record name => list of TXT values.
  defp publish(records) do
    Application.put_env(:trifle, :sso_txt_resolver, fn name -> Map.get(records, name, []) end)
  end

  defp publish_for(%OrganizationSSODomain{} = domain) do
    publish(%{
      OrganizationSSODomain.verification_record_name(domain) => [
        "unrelated=1",
        OrganizationSSODomain.verification_record_value(domain)
      ]
    })
  end

  defp claim(organization, domains) do
    {:ok, provider} =
      Organizations.upsert_google_sso_provider(organization, %{
        "enabled" => true,
        "auto_provision_members" => true,
        "domains" => domains
      })

    provider.domains
  end

  test "a new domain is unverified and does not route sign-ins", %{organization: organization} do
    [domain] = claim(organization, ["corp.example"])

    refute OrganizationSSODomain.verified?(domain)
    assert is_binary(domain.verification_token)
    assert is_nil(Organizations.find_google_sso_provider_for_domain("corp.example"))
    refute Organizations.google_sso_enabled?(organization)

    user = user_fixture(%{email: "someone@corp.example"})

    assert {:error, :domain_not_allowed} =
             Organizations.ensure_membership_for_sso(user, :google, user.email)
  end

  test "verification needs the exact TXT value under the verification name", %{
    organization: organization
  } do
    [domain] = claim(organization, ["corp.example"])

    assert {:error, :record_not_found} = Organizations.verify_sso_domain(domain)

    publish(%{
      OrganizationSSODomain.verification_record_name(domain) => ["trifle-verification=wrong"],
      "corp.example" => [OrganizationSSODomain.verification_record_value(domain)]
    })

    assert {:error, :record_not_found} = Organizations.verify_sso_domain(domain)

    publish_for(domain)

    assert {:ok, verified} = Organizations.verify_sso_domain(domain)
    assert OrganizationSSODomain.verified?(verified)

    assert %{organization_id: org_id} =
             Organizations.find_google_sso_provider_for_domain("CORP.example")

    assert org_id == organization.id
    assert Organizations.google_sso_enabled?(organization)
  end

  test "editing the list keeps verified domains verified", %{organization: organization} do
    [domain] = claim(organization, ["corp.example"])
    publish_for(domain)
    {:ok, _} = Organizations.verify_sso_domain(domain)

    domains = claim(organization, ["corp.example", "second.example"])

    by_name = Map.new(domains, &{&1.domain, &1})
    assert OrganizationSSODomain.verified?(by_name["corp.example"])
    assert by_name["corp.example"].id == domain.id
    refute OrganizationSSODomain.verified?(by_name["second.example"])

    assert [%{domain: "second.example"}] = claim(organization, ["second.example"])
    assert is_nil(Organizations.find_google_sso_provider_for_domain("corp.example"))
  end

  test "an unverified claim cannot block the real owner, and is discarded once they verify", %{
    organization: squatter_org
  } do
    owner_org = organization_fixture(%{name: "Real Owner #{System.unique_integer([:positive])}"})

    [squatted] = claim(squatter_org, ["victim.example"])
    [owned] = claim(owner_org, ["victim.example"])

    publish_for(owned)

    assert {:error, :record_not_found} = Organizations.verify_sso_domain(squatted)
    assert {:ok, _} = Organizations.verify_sso_domain(owned)

    assert %{organization_id: org_id} =
             Organizations.find_google_sso_provider_for_domain("victim.example")

    assert org_id == owner_org.id
    assert is_nil(Repo.get(OrganizationSSODomain, squatted.id))
  end

  test "a domain verified by one organization cannot be verified by another", %{
    organization: organization
  } do
    other_org = organization_fixture(%{name: "Other #{System.unique_integer([:positive])}"})

    [first] = claim(organization, ["shared.example"])
    publish_for(first)
    {:ok, _} = Organizations.verify_sso_domain(first)

    [second] = claim(other_org, ["shared.example"])
    publish_for(second)

    assert {:error, :already_verified_elsewhere} = Organizations.verify_sso_domain(second)
  end

  test "public email providers cannot be claimed", %{organization: organization} do
    for domain <- ["gmail.com", "Outlook.com", "proton.me"] do
      assert {:error, _} =
               Organizations.upsert_google_sso_provider(organization, %{
                 "enabled" => true,
                 "domains" => [domain]
               })
    end
  end

  test "a domain can only be verified through its own organization", %{
    organization: organization
  } do
    other_org = organization_fixture(%{name: "Other #{System.unique_integer([:positive])}"})
    [domain] = claim(organization, ["corp.example"])

    assert %OrganizationSSODomain{} =
             Organizations.get_sso_domain_for_org(organization, domain.id)

    assert is_nil(Organizations.get_sso_domain_for_org(other_org, domain.id))
    assert is_nil(Organizations.get_sso_domain_for_org(organization, "not-a-uuid"))
  end
end
