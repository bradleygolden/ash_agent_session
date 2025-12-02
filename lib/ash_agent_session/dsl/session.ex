defmodule AshAgentSession.DSL.Session do
  @moduledoc """
  DSL for configuring session persistence on agent resources.
  """

  @streaming %Spark.Dsl.Section{
    name: :streaming,
    describe: """
    Configure streaming session actions and incremental persistence.

    When this section is present, streaming actions (`stream_start_session`,
    `stream_continue_session`) are generated for the resource.

    During streaming, partial content is stored in the context's assistant message
    via `streaming_content` and `streaming_thinking` fields, enabling recovery
    from interrupted streams.
    """,
    examples: [
      """
      streaming do
      end
      """,
      """
      streaming do
        flush_interval 500
      end
      """
    ],
    schema: [
      flush_interval: [
        type: :pos_integer,
        default: 500,
        doc: "Milliseconds between context persistence during streaming (reduces write pressure)"
      ]
    ]
  }

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
      """,
      """
      agent_session do
        context_attribute :context
        status_attribute :status

        streaming do
          flush_interval 500
        end
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
          "The attribute name for storing session status (:pending, :running, :streaming, :completed, :failed)."
      ]
    ],
    sections: [@streaming]
  }

  def agent_session, do: @agent_session
end
