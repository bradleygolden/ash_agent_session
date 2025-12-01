defmodule AshAgentSession do
  @moduledoc """
  Session persistence extension for AshAgent.

  AshAgentSession provides cross-request state persistence for agent resources,
  enabling stateful conversations that survive between HTTP requests or process restarts.

  ## Overview

  | Library | Scope |
  |---------|-------|
  | ash_agent | Single call primitives (LLM interaction, structured I/O) |
  | ash_agent_tools | Multi-turn within one execution (tool calling loop) |
  | **ash_agent_session** | Cross-request state persistence |

  ## Usage

  Add the `AshAgentSession.Resource` extension to an existing agent resource:

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

  The extension generates these actions:

  - `:start_session` - Create a new session with an initial message
  - `:continue_session` - Continue an existing session with a new message
  - `:get_context` - Retrieve the deserialized context from a session

  ## Example

      # Start a new session
      {:ok, session} = MyApp.ChatAgent.start_session(%{message: "Hello!"})

      # Continue the conversation
      {:ok, session} = MyApp.ChatAgent.continue_session(session, %{message: "Follow up"})

      # Get the full context
      context = MyApp.ChatAgent.get_context(session)
  """

  alias AshAgentSession.ContextSerializer

  @doc """
  Serializes an `AshAgent.Context` struct to a map for storage.

  ## Examples

      context = AshAgent.Context.new([...])
      map = AshAgentSession.serialize_context(context)
  """
  defdelegate serialize_context(context), to: ContextSerializer, as: :to_map

  @doc """
  Deserializes a stored map back to an `AshAgent.Context` struct.

  Returns `{:ok, context}` on success, `{:error, errors}` on validation failure.

  ## Examples

      {:ok, context} = AshAgentSession.deserialize_context(stored_map)
  """
  defdelegate deserialize_context(map), to: ContextSerializer, as: :from_map

  @doc """
  Deserializes a stored map back to an `AshAgent.Context` struct.

  Raises on validation failure.

  ## Examples

      context = AshAgentSession.deserialize_context!(stored_map)
  """
  defdelegate deserialize_context!(map), to: ContextSerializer, as: :from_map!
end
