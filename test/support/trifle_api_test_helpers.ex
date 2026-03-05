defmodule TrifleApi.TestHelpers do
  @moduledoc false

  alias Trifle.Organizations

  def create_scoped_token!(user, organization_id, source_type, source_id, read, write) do
    permissions = scoped_permissions(source_type, source_id, read, write)

    {:ok, _record, value} =
      Organizations.create_organization_api_token(user, %{
        organization_id: organization_id,
        name: "API test token",
        permissions: permissions
      })

    value
  end

  def scoped_permissions(source_type, source_id, read, write) do
    source_key = "#{source_type}:#{source_id}"

    %{
      "wildcard" => %{"read" => false, "write" => false},
      "sources" => %{
        source_key => %{"read" => read, "write" => write}
      }
    }
  end
end
