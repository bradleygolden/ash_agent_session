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

        changeset =
          changeset
          |> Ash.Changeset.force_change_attribute(context_attr, serialized)
          |> Ash.Changeset.set_context(%{agent_result: result})

        Ash.DataLayer.create(resource, changeset)

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_initial_messages(resource, input, instruction_args) do
    config = AshAgent.Info.agent_config(resource)

    system_prompt = get_system_prompt(config, instruction_args)

    messages =
      case system_prompt do
        nil -> []
        prompt -> [AshAgent.Message.system(prompt)]
      end

    messages ++ [AshAgent.Message.user(input)]
  end

  defp get_system_prompt(config, instruction_args) do
    case config.instruction do
      nil ->
        nil

      template ->
        args = instruction_args || %{}
        render_template(template, args)
    end
  end

  defp render_template(template, args) when is_binary(template) do
    context = build_template_context(args)

    with {:ok, parsed} <- Solid.parse(template),
         {:ok, rendered} <- Solid.render(parsed, context, []) do
      IO.iodata_to_binary(rendered)
    else
      _ -> template
    end
  end

  defp render_template(template, args) when is_struct(template, Solid.Template) do
    context = build_template_context(args)

    case Solid.render(template, context, []) do
      {:ok, rendered} -> IO.iodata_to_binary(rendered)
      {:error, _, _} -> ""
    end
  end

  defp build_template_context(args) when is_map(args) do
    Map.new(args, fn {k, v} -> {to_string(k), v} end)
  end

  defp call_agent(resource, _domain, agent_context, _context) do
    AshAgent.Runtime.call(resource, agent_context)
  end
end
