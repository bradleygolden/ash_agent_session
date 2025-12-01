defmodule AshAgentSession.Actions.ContinueSession do
  @moduledoc false

  use Ash.Resource.ManualUpdate

  alias AshAgentSession.ContextSerializer

  @impl true
  def update(changeset, _opts, context) do
    resource = changeset.resource
    domain = changeset.domain
    record = changeset.data
    context_attr = AshAgentSession.Info.context_attribute(resource)

    input = Ash.Changeset.get_argument(changeset, :input)
    stored_context = Map.get(record, context_attr)

    with {:ok, agent_context} <- ContextSerializer.from_map(stored_context),
         updated_context <- add_user_message(agent_context, input),
         {:ok, result} <- call_agent(resource, domain, updated_context, context) do
      serialized = ContextSerializer.to_map(result.context)

      changeset =
        changeset
        |> Ash.Changeset.force_change_attribute(context_attr, serialized)
        |> Ash.Changeset.set_context(%{agent_result: result})

      Ash.DataLayer.update(resource, changeset)
    end
  end

  defp add_user_message(context, input) do
    message = AshAgent.Message.user(input)
    %{context | messages: context.messages ++ [message], input: input}
  end

  defp call_agent(resource, _domain, agent_context, _context) do
    AshAgent.Runtime.call(resource, agent_context)
  end
end
