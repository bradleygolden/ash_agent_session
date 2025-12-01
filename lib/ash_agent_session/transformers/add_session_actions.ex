defmodule AshAgentSession.Transformers.AddSessionActions do
  @moduledoc """
  Automatically adds session management actions to agent resources.

  This transformer generates:
  - `:start_session` - Create action to start a new session
  - `:continue_session` - Update action to continue an existing session
  - `:get_context` - Read action to retrieve the deserialized context
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
      {:ok, dsl_state}
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
end
