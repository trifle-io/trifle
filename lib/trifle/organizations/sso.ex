defmodule Trifle.Organizations.SSO do
  @moduledoc """
  Organization SSO providers: provider configuration, domain allow-lists,
  and auto-provisioning of memberships on SSO sign-in.
  """

  import Ecto.Query, warn: false

  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.Organization
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Organizations.OrganizationSSODomain
  alias Trifle.Organizations.OrganizationSSOProvider
  alias Trifle.Repo

  def list_sso_providers(%Organization{} = organization) do
    organization
    |> Repo.preload(sso_providers: [:domains])
    |> Map.get(:sso_providers, [])
  end

  def get_sso_provider_for_org(%Organization{} = organization, provider) do
    if provider in OrganizationSSOProvider.providers() do
      from(p in OrganizationSSOProvider,
        where: p.organization_id == ^organization.id and p.provider == ^provider,
        preload: [:domains]
      )
      |> Repo.one()
    else
      nil
    end
  end

  def google_sso_enabled?(%Organization{} = organization) do
    case get_sso_provider_for_org(organization, :google) do
      %OrganizationSSOProvider{enabled: true, domains: [_ | _]} -> true
      _ -> false
    end
  end

  def upsert_google_sso_provider(%Organization{} = organization, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
        other -> other
      end)

    Repo.transaction(fn ->
      provider =
        organization
        |> get_sso_provider_for_org(:google)
        |> case do
          nil ->
            %OrganizationSSOProvider{}
            |> OrganizationSSOProvider.changeset(%{
              "organization_id" => organization.id,
              "provider" => :google,
              "enabled" => Map.get(attrs, "enabled", true),
              "auto_provision_members" => Map.get(attrs, "auto_provision_members", true)
            })
            |> Repo.insert()

          %OrganizationSSOProvider{} = provider ->
            provider
            |> OrganizationSSOProvider.changeset(%{
              "enabled" => Map.get(attrs, "enabled", provider.enabled),
              "auto_provision_members" =>
                Map.get(attrs, "auto_provision_members", provider.auto_provision_members)
            })
            |> Repo.update()
        end
        |> case do
          {:ok, provider} -> provider
          {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback({:changeset, changeset})
          {:error, reason} -> Repo.rollback(reason)
        end

      domains = normalize_domains(Map.get(attrs, "domains", []))

      with :ok <- replace_provider_domains(provider, domains) do
        Repo.preload(provider, :domains)
      else
        {:error, %Ecto.Changeset{} = changeset} -> Repo.rollback({:changeset, changeset})
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def find_google_sso_provider_for_domain(domain) when domain in [nil, ""] do
    nil
  end

  def find_google_sso_provider_for_domain(domain) when is_binary(domain) do
    normalized = normalize_domain(domain)

    from(p in OrganizationSSOProvider,
      join: d in OrganizationSSODomain,
      on: d.organization_sso_provider_id == p.id,
      where:
        p.provider == :google and p.enabled == true and
          fragment("lower(?) = ?", d.domain, ^normalized),
      preload: [:organization]
    )
    |> Repo.one()
  end

  def ensure_membership_for_sso(%User{} = user, :google, email) when is_binary(email) do
    case Organizations.get_membership_for_user(user) do
      %OrganizationMembership{} = membership ->
        {:ok, membership}

      nil ->
        domain =
          email
          |> String.split("@")
          |> List.last()
          |> normalize_domain()

        with {:domain, domain} when is_binary(domain) <- {:domain, domain},
             %OrganizationSSOProvider{} = provider <- find_google_sso_provider_for_domain(domain),
             true <- provider.auto_provision_members do
          case Organizations.create_membership(provider.organization, user) do
            {:ok, membership} -> {:ok, membership}
            {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
          end
        else
          {:domain, _} -> {:error, :invalid_email_domain}
          false -> {:error, :auto_provision_disabled}
          nil -> {:error, :domain_not_allowed}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def ensure_membership_for_sso(_, _, _), do: {:error, :unsupported_provider}

  defp replace_provider_domains(%OrganizationSSOProvider{} = provider, []) do
    Repo.delete_all(
      from d in OrganizationSSODomain,
        where: d.organization_sso_provider_id == ^provider.id
    )

    :ok
  end

  defp replace_provider_domains(%OrganizationSSOProvider{} = provider, domains) do
    Repo.delete_all(
      from d in OrganizationSSODomain,
        where: d.organization_sso_provider_id == ^provider.id
    )

    Enum.reduce_while(domains, :ok, fn domain, :ok ->
      %OrganizationSSODomain{}
      |> OrganizationSSODomain.changeset(%{
        organization_sso_provider_id: provider.id,
        domain: domain
      })
      |> Repo.insert()
      |> case do
        {:ok, _record} -> {:cont, :ok}
        {:error, %Ecto.Changeset{} = changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp normalize_domains(domains) when is_list(domains) do
    domains
    |> Enum.map(&normalize_domain/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp normalize_domains(value) when is_binary(value) do
    value
    |> String.split(~r/[,;\s]+/, trim: true)
    |> normalize_domains()
  end

  defp normalize_domains(_), do: []

  defp normalize_domain(nil), do: nil

  defp normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
  end
end
