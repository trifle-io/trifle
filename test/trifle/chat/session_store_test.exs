defmodule Trifle.Chat.SessionStoreTest do
  use Trifle.DataCase

  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Chat.Bus
  alias Trifle.Chat.SessionStore

  test "append_message_and_clear_pending broadcasts final assistant message without pending state" do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})

    {:ok, session} =
      SessionStore.create(to_string(user.id), to_string(organization.id), %{
        type: "workspace",
        id: to_string(organization.id)
      })

    :ok = Bus.subscribe(session.id)

    {:ok, pending_session} = SessionStore.reset_progress(session, DateTime.utc_now())
    assert_receive {:chat_session_updated, _, %{pending_started_at: %DateTime{}}}

    {:ok, final_session} =
      SessionStore.append_message_and_clear_pending(pending_session, %{
        role: "assistant",
        content: "Final answer"
      })

    assert final_session.pending_started_at == nil
    assert [%{role: "assistant", content: "Final answer"}] = final_session.messages

    assert_receive {:chat_session_updated, _, broadcast_session}
    assert broadcast_session.pending_started_at == nil
    assert [%{role: "assistant", content: "Final answer"}] = broadcast_session.messages
  end
end
