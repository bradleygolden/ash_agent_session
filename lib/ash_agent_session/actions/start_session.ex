defmodule AshAgentSession.Actions.StartSession do
  @moduledoc false

  use Ash.Resource.ManualCreate

  alias AshAgentSession.ContextSerializer

  @impl true
  def create(changeset, _opts, context) do
    resource = changeset.resource
    domain = changeset.domain
    context_attr = AshAgentSession.Info.context_attribute(resource)

    input = Ash.Changeset.get_argument(changeset, :input)
    instruction_args = Ash.Changeset.get_argument(changeset, :instruction_args)

    messages = build_initial_messages(resource, input, instruction_args)
    agent_context = AshAgent.Context.new(messages, input: input)

    case call_agent(resource, domain, agent_context, context) do
      {:ok, result} ->
        serialized = ContextSerializer.to_map(result.context)

        changeset
        |> Ash.Changeset.force_change_attribute(context_attr, serialized)
        |> Ash.Changeset.set_context(%{agent_result: result})
        |> Ash.create(return_notifications?: true)

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_initial_messages(resource, input, instruction_args) do
    messages = []

    messages =
      if instruction_args do
        [AshAgent.Message.system(render_instruction(resource, instruction_args)) | messages]
      else
        messages
      end

    messages ++ [AshAgent.Message.user(input)]
  end

  defp render_instruction(resource, args) do
    config = AshAgent.Info.agent_config(resource)

    case config.instruction do
      nil ->
        ""

      template ->
        {:ok, rendered} = Solid.render(template, args)
        IO.iodata_to_binary(rendered)
    end
  end

  defp call_agent(resource, _domain, agent_context, _context) do
    AshAgent.Runtime.call(resource, agent_context)
  end
end
