defmodule AshAgentSession.Test.SessionAgent do
  @moduledoc false

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
