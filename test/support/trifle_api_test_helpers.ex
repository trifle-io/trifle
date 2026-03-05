defmodule TrifleApi.TestHelpers do
  @moduledoc false

  alias Trifle.Organizations

  def create_scoped_token!(user, organization_id, source_type, source_id, read, write) do
    permissions = scoped_permissions(source_type, source_id, read, write)

    case Organizations.create_organization_api_token(user, %{
           organization_id: organization_id,
           name: "API test token",
           permissions: permissions
         }) do
      {:ok, _record, value} ->
        value

      {:error, reason} ->
        raise """
        Failed to create scoped token in test helper.
        user_id=#{inspect(user && user.id)}
        organization_id=#{inspect(organization_id)}
        source_type=#{inspect(source_type)}
        source_id=#{inspect(source_id)}
        read=#{inspect(read)}
        write=#{inspect(write)}
        reason=#{inspect(reason)}
        """
    end
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
