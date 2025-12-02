defmodule AshAgentSession.Transformers.AddSessionActions do
  @moduledoc """
  Automatically adds session management actions to agent resources.

  This transformer generates:
  - `:start_session` - Create action to start a new session
  - `:continue_session` - Update action to continue an existing session
  - `:get_context` - Read action to retrieve the deserialized context

  When the `streaming` block is present in the DSL, it also generates:
  - `:stream_start_session` - Create action that returns a stream
  - `:stream_continue_session` - Update action that returns a stream
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshAgent.Transformers.AddAgentActions), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    with {:ok, dsl_state} <- add_start_session_action(dsl_state),
         {:ok, dsl_state} <- add_continue_session_action(dsl_state),
         {:ok, dsl_state} <- add_get_context_action(dsl_state) do
      maybe_add_streaming_actions(dsl_state)
    end
  end

  defp maybe_add_streaming_actions(dsl_state) do
    if streaming_enabled?(dsl_state) do
      with {:ok, dsl_state} <- add_stream_start_session_action(dsl_state) do
        add_stream_continue_session_action(dsl_state)
      end
    else
      {:ok, dsl_state}
    end
  end

  defp streaming_enabled?(dsl_state) do
    case Transformer.get_option(dsl_state, [:agent_session, :streaming], :flush_interval) do
      nil -> false
      _ -> true
    end
  end

  defp add_start_session_action(dsl_state) do
    action = %Ash.Resource.Actions.Create{
      name: :start_session,
      type: :create,
      description: "Start a new agent session with an initial message",
      arguments: [
        %Ash.Resource.Actions.Argument{
          name: :input,
          type: :map,
          allow_nil?: false,
          public?: true,
          description: "Input matching the agent's input_schema"
        },
        %Ash.Resource.Actions.Argument{
          name: :instruction_args,
          type: :map,
          allow_nil?: true,
          public?: true,
          description: "Arguments for the instruction template"
        }
      ],
      manual: {AshAgentSession.Actions.StartSession, []},
      primary?: false,
      accept: []
    }

    {:ok, Transformer.add_entity(dsl_state, [:actions], action)}
  end

  defp add_continue_session_action(dsl_state) do
    action = %Ash.Resource.Actions.Update{
      name: :continue_session,
      type: :update,
      description: "Continue an existing session with a new message",
      arguments: [
        %Ash.Resource.Actions.Argument{
          name: :input,
          type: :map,
          allow_nil?: false,
          public?: true,
          description: "Input matching the agent's input_schema"
        }
      ],
      manual: {AshAgentSession.Actions.ContinueSession, []},
      require_atomic?: false,
      primary?: false,
      accept: []
    }

    {:ok, Transformer.add_entity(dsl_state, [:actions], action)}
  end

  defp add_get_context_action(dsl_state) do
    action = %Ash.Resource.Actions.Action{
      name: :get_context,
      type: :action,
      description: "Get the deserialized context from a session",
      arguments: [
        %Ash.Resource.Actions.Argument{
          name: :id,
          type: :uuid,
          allow_nil?: false,
          public?: true,
          description: "The session ID"
        }
      ],
      returns: :struct,
      constraints: [instance_of: AshAgent.Context],
      run: {AshAgentSession.Actions.GetContextRun, []},
      primary?: false
    }

    {:ok, Transformer.add_entity(dsl_state, [:actions], action)}
  end

  defp add_stream_start_session_action(dsl_state) do
    action = %Ash.Resource.Actions.Action{
      name: :stream_start_session,
      type: :action,
      description: "Start a new agent session with streaming response",
      arguments: [
        %Ash.Resource.Actions.Argument{
          name: :input,
          type: :map,
          allow_nil?: false,
          public?: true,
          description: "Input matching the agent's input_schema"
        },
        %Ash.Resource.Actions.Argument{
          name: :instruction_args,
          type: :map,
          allow_nil?: true,
          public?: true,
          description: "Arguments for the instruction template"
        }
      ],
      run: {AshAgentSession.Actions.StreamStartSession, []},
      returns: :map,
      primary?: false
    }

    {:ok, Transformer.add_entity(dsl_state, [:actions], action)}
  end

  defp add_stream_continue_session_action(dsl_state) do
    action = %Ash.Resource.Actions.Action{
      name: :stream_continue_session,
      type: :action,
      description: "Continue an existing session with streaming response",
      arguments: [
        %Ash.Resource.Actions.Argument{
          name: :id,
          type: :uuid,
          allow_nil?: false,
          public?: true,
          description: "The session ID"
        },
        %Ash.Resource.Actions.Argument{
          name: :input,
          type: :map,
          allow_nil?: false,
          public?: true,
          description: "Input matching the agent's input_schema"
        }
      ],
      run: {AshAgentSession.Actions.StreamContinueSession, []},
      returns: :map,
      primary?: false
    }

    {:ok, Transformer.add_entity(dsl_state, [:actions], action)}
  end
end
