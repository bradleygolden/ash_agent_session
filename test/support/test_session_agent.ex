defmodule AshAgentSession.Test.SessionAgent do
  @moduledoc false
  @dialyzer :no_match

  use Ash.Resource,
    domain: AshAgentSession.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshAgent.Resource, AshAgentSession.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :context, :map, public?: true
  end

  actions do
    defaults [:read]
  end

  agent do
    client("anthropic:claude-3-5-sonnet")
    instruction("You are a helpful assistant.")
    input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
    output_schema(Zoi.object(%{reply: Zoi.string()}, coerce: true))
  end

  agent_session do
    context_attribute :context
  end
end

defmodule AshAgentSession.Test.SessionAgentWithTemplate do
  @moduledoc false
  @dialyzer :no_match

  use Ash.Resource,
    domain: AshAgentSession.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshAgent.Resource, AshAgentSession.Resource]

  import AshAgent.Sigils

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :context, :map, public?: true
  end

  agent do
    client("anthropic:claude-3-5-sonnet")
    instruction(~p"You are {{ persona }}. Help the user with {{ task }}.")

    instruction_schema(
      Zoi.object(
        %{
          persona: Zoi.string(),
          task: Zoi.string()
        },
        coerce: true
      )
    )

    input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
    output_schema(Zoi.object(%{reply: Zoi.string()}, coerce: true))
  end

  agent_session do
    context_attribute :context
  end
end

defmodule AshAgentSession.Test.SessionAgentWithStatus do
  @moduledoc false
  @dialyzer :no_match

  use Ash.Resource,
    domain: AshAgentSession.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshAgent.Resource, AshAgentSession.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :context, :map, public?: true
    attribute :status, :atom, default: :pending, public?: true
  end

  actions do
    defaults [:read]
  end

  agent do
    client("anthropic:claude-3-5-sonnet")
    instruction("You are a helpful assistant.")
    input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
    output_schema(Zoi.object(%{reply: Zoi.string()}, coerce: true))
  end

  agent_session do
    context_attribute :context
    status_attribute(:status)
  end
end

defmodule AshAgentSession.Test.StreamingMockProvider do
  @moduledoc false
  @behaviour AshAgent.Provider

  def call(_client, _prompt, _schema, opts, _context, _tools, _messages) do
    response = Keyword.get(opts, :mock_response, %{reply: "default"})
    {:ok, response}
  end

  def stream(_client, _prompt, _schema, opts, _context, _tools, _messages) do
    chunks = Keyword.get(opts, :mock_chunks, default_chunks())

    stream =
      Stream.map(chunks, fn chunk ->
        if delay = Keyword.get(opts, :mock_chunk_delay_ms) do
          Process.sleep(delay)
        end

        chunk
      end)

    {:ok, stream}
  end

  def introspect do
    %{provider: :streaming_mock, features: [:sync_call, :streaming]}
  end

  defp default_chunks do
    [
      %{reply: "Hello "},
      %{reply: "world!"}
    ]
  end
end

defmodule AshAgentSession.Test.StreamingSessionAgent do
  @moduledoc false
  @dialyzer :no_match

  use Ash.Resource,
    domain: AshAgentSession.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshAgent.Resource, AshAgentSession.Resource]

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :context, :map, public?: true
    attribute :status, :atom, default: :pending, public?: true
  end

  actions do
    defaults [:read]
  end

  agent do
    provider(AshAgentSession.Test.StreamingMockProvider)
    client(:mock)
    instruction("You are a helpful assistant.")
    input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
    output_schema(Zoi.object(%{reply: Zoi.string()}, coerce: true))
  end

  agent_session do
    context_attribute :context
    status_attribute(:status)

    streaming do
      flush_interval(100)
    end
  end
end
