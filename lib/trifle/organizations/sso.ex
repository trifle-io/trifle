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
      %OrganizationSSOProvider{enabled: true, domains: domains} ->
        Enum.any?(domains, &OrganizationSSODomain.verified?/1)

      _ ->
        false
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
        Repo.preload(provider, :domains, force: true)
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
      # Only a domain whose ownership was proven routes sign-ins to an organization.
      where:
        p.provider == :google and p.enabled == true and not is_nil(d.verified_at) and
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
          case Organizations.join_organization(provider.organization, user, "member") do
            {:ok, membership} -> {:ok, membership}
            {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
            {:error, reason} -> {:error, reason}
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

  # Keeps existing rows (and their verification state) for domains that stay,
  # removes the ones dropped from the list and adds new, unverified ones.
  defp replace_provider_domains(%OrganizationSSOProvider{} = provider, domains) do
    existing =
      Repo.all(
        from d in OrganizationSSODomain, where: d.organization_sso_provider_id == ^provider.id
      )

    existing_names = Enum.map(existing, &normalize_domain(&1.domain))
    removed_ids = for d <- existing, normalize_domain(d.domain) not in domains, do: d.id

    Repo.delete_all(from d in OrganizationSSODomain, where: d.id in ^removed_ids)

    domains
    |> Enum.reject(&(&1 in existing_names))
    |> Enum.reduce_while(:ok, fn domain, :ok ->
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

  @doc """
  Checks DNS for the domain's verification record and, when present, marks the
  domain verified.

  The organization publishes a TXT record named
  `_trifle-verification.<domain>` with the value `trifle-verification=<token>`.
  Verifying a domain discards other organizations' unverified claims on it.

  Returns `{:ok, domain}`, `{:error, :record_not_found}` or
  `{:error, :already_verified_elsewhere}`.
  """
  def verify_sso_domain(%OrganizationSSODomain{} = domain) do
    cond do
      OrganizationSSODomain.verified?(domain) ->
        {:ok, domain}

      verification_record_present?(domain) ->
        domain
        |> OrganizationSSODomain.verified_changeset()
        |> Repo.update()
        |> case do
          {:ok, verified} ->
            Repo.delete_all(
              from d in OrganizationSSODomain,
                where:
                  d.id != ^verified.id and is_nil(d.verified_at) and
                    fragment("lower(?) = ?", d.domain, ^normalize_domain(verified.domain))
            )

            {:ok, verified}

          {:error, %Ecto.Changeset{}} ->
            {:error, :already_verified_elsewhere}
        end

      true ->
        {:error, :record_not_found}
    end
  end

  def get_sso_domain_for_org(%Organization{} = organization, domain_id) do
    with {:ok, id} <- Ecto.UUID.cast(domain_id) do
      from(d in OrganizationSSODomain,
        join: p in OrganizationSSOProvider,
        on: p.id == d.organization_sso_provider_id,
        where: d.id == ^id and p.organization_id == ^organization.id
      )
      |> Repo.one()
    else
      :error -> nil
    end
  end

  defp verification_record_present?(%OrganizationSSODomain{} = domain) do
    expected = OrganizationSSODomain.verification_record_value(domain)

    domain
    |> OrganizationSSODomain.verification_record_name()
    |> txt_lookup()
    |> Enum.any?(&(String.trim(&1) == expected))
  end

  # TXT lookups are replaceable in config so tests do not depend on real DNS:
  #   config :trifle, :sso_txt_resolver, fn name -> ["value", ...] end
  defp txt_lookup(name) do
    case Application.get_env(:trifle, :sso_txt_resolver) do
      resolver when is_function(resolver, 1) ->
        resolver.(name)

      _ ->
        name
        |> String.to_charlist()
        |> :inet_res.lookup(:in, :txt, timeout: 5_000)
        |> Enum.map(fn parts -> parts |> Enum.map(&to_string/1) |> Enum.join() end)
    end
  rescue
    _ -> []
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
