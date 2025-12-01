defmodule AshAgentSession.Resource do
  @moduledoc """
  Ash extension that adds session persistence to agent resources.

  ## Usage

  Add this extension alongside `AshAgent.Resource`:

      defmodule MyApp.ChatAgent do
        use Ash.Resource,
          domain: MyApp.Agents,
          data_layer: AshPostgres.DataLayer,
          extensions: [AshAgent.Resource, AshAgentSession.Resource]

        agent do
          client "anthropic:claude-sonnet-4-20250514"
          instruction "You are a helpful assistant."
          input_schema Zoi.object(%{message: Zoi.string()}, coerce: true)
          output_schema Zoi.object(%{content: Zoi.string()}, coerce: true)
        end

        agent_session do
          context_attribute :context
        end

        attributes do
          uuid_primary_key :id
          attribute :context, :map
          timestamps()
        end
      end

  ## Generated Actions

  - `:start_session` - Create a new session with an initial message
  - `:continue_session` - Continue an existing session with a new message
  - `:get_context` - Retrieve the deserialized context from a session
  """

  alias AshAgentSession.DSL.Session

  use Spark.Dsl.Extension,
    sections: [Session.agent_session()],
    verifiers: [AshAgentSession.Verifiers.RequireAgentBlock],
    transformers: [AshAgentSession.Transformers.AddSessionActions]
end
