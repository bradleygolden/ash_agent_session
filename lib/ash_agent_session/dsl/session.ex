defmodule AshAgentSession.DSL.Session do
  @moduledoc """
  DSL for configuring session persistence on agent resources.
  """

  @agent_session %Spark.Dsl.Section{
    name: :agent_session,
    describe: """
    Configure session persistence for an agent resource.

    This section enables automatic context serialization and deserialization,
    allowing agent conversations to persist across requests.
    """,
    examples: [
      """
      agent_session do
        context_attribute :context
      end
      """
    ],
    schema: [
      context_attribute: [
        type: :atom,
        default: :context,
        doc: "The attribute name for storing the serialized context map."
      ],
      status_attribute: [
        type: :atom,
        doc:
          "The attribute name for storing session status (:pending, :running, :completed, :failed)."
      ]
    ]
  }

  def agent_session, do: @agent_session
end
