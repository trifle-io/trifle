defmodule Trifle.Chat.SessionRecord do
  @moduledoc """
  Database representation of a chat session backed by Postgres JSONB embeds.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias __MODULE__.Message
  alias __MODULE__.ProgressEvent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_sessions" do
    belongs_to :user, Trifle.Accounts.User
    belongs_to :organization, Trifle.Organizations.Organization

    field :source_type, :string
    field :source_id, :binary_id
    field :pending_started_at, :utc_datetime

    embeds_many :messages, Message, on_replace: :delete
    embeds_many :progress_events, ProgressEvent, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Casts incoming attributes onto the chat session record.
  """
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:user_id, :organization_id, :source_type, :source_id, :pending_started_at])
    |> validate_required([:user_id, :organization_id, :source_type, :source_id])
    |> cast_embed(:messages, with: &Message.changeset/2, required: false)
    |> cast_embed(:progress_events, with: &ProgressEvent.changeset/2, required: false)
  end

  defmodule Message do
    @moduledoc false

    use Ecto.Schema
    import Ecto.Changeset

    alias __MODULE__.ToolCall

    @primary_key false

    embedded_schema do
      field :role, :string
      field :content, :string
      field :created_at, :utc_datetime
      field :tool_call_id, :string
      field :name, :string

      embeds_many :tool_calls, ToolCall, on_replace: :delete
    end

    def changeset(message, attrs) do
      message
      |> cast(attrs, [:role, :content, :created_at, :tool_call_id, :name])
      |> validate_required([:role])
      |> cast_embed(:tool_calls, with: &ToolCall.changeset/2, required: false)
    end

    defmodule ToolCall do
      @moduledoc false

      use Ecto.Schema
      import Ecto.Changeset

      alias __MODULE__.Function

      @primary_key false

      embedded_schema do
        field :id, :string
        field :type, :string

        embeds_one :function, Function, on_replace: :update
      end

      def changeset(tool_call, attrs) do
        tool_call
        |> cast(attrs, [:id, :type])
        |> cast_embed(:function, with: &Function.changeset/2, required: false)
      end

      defmodule Function do
        @moduledoc false

        use Ecto.Schema
        import Ecto.Changeset

        @primary_key false

        embedded_schema do
          field :name, :string
          field :arguments, :string
        end

        def changeset(function, attrs) do
          function
          |> cast(attrs, [:name, :arguments])
        end
      end
    end
  end

  defmodule ProgressEvent do
    @moduledoc false

    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :id, :string
      field :type, :string
      field :payload, :map
      field :text, :string
      field :started_at, :utc_datetime
      field :finished_at, :utc_datetime
      field :display, :boolean, default: true
    end

    def changeset(event, attrs) do
      event
      |> cast(attrs, [:id, :type, :payload, :text, :started_at, :finished_at, :display])
      |> validate_required([:id, :type])
    end
  end
end
