defmodule AshAgentSession.Actions.StartSession do
  @moduledoc false

  use Ash.Resource.ManualCreate

  alias AshAgentSession.ContextSerializer

  @impl true
  def create(changeset, _opts, context) do
    resource = changeset.resource
    domain = changeset.domain
    context_attr = AshAgentSession.Info.context_attribute(resource)
    status_attr = AshAgentSession.Info.status_attribute(resource)

    input = Ash.Changeset.get_argument(changeset, :input)
    instruction_args = Ash.Changeset.get_argument(changeset, :instruction_args)

    messages = build_initial_messages(resource, input, instruction_args)
    agent_context = AshAgent.Context.new(messages, input: input)

    if status_attr do
      create_with_status_tracking(
        changeset,
        resource,
        domain,
        context_attr,
        status_attr,
        agent_context,
        context
      )
    else
      create_without_status(changeset, resource, context_attr, agent_context, context)
    end
  end

  defp create_with_status_tracking(
         changeset,
         resource,
         domain,
         context_attr,
         status_attr,
         agent_context,
         context
       ) do
    running_changeset =
      Ash.Changeset.force_change_attribute(changeset, status_attr, :running)

    case Ash.DataLayer.create(resource, running_changeset) do
      {:ok, record} ->
        run_agent_and_update(
          record,
          resource,
          domain,
          context_attr,
          status_attr,
          agent_context,
          context
        )

      {:error, error} ->
        {:error, error}
    end
  end

  defp run_agent_and_update(
         record,
         resource,
         domain,
         context_attr,
         status_attr,
         agent_context,
         context
       ) do
    {status, result_or_error, serialized} =
      try do
        case call_agent(resource, domain, agent_context, context) do
          {:ok, result} ->
            serialized = ContextSerializer.to_map(result.context)
            {:completed, result, serialized}

          {:error, error} ->
            {:failed, error, nil}
        end
      rescue
        e -> {:failed, e, nil}
      end

    update_changeset =
      record
      |> Ash.Changeset.new()
      |> Map.put(:domain, domain)
      |> Ash.Changeset.force_change_attribute(status_attr, status)

    update_changeset =
      if serialized do
        update_changeset
        |> Ash.Changeset.force_change_attribute(context_attr, serialized)
        |> Ash.Changeset.set_context(%{agent_result: result_or_error})
      else
        update_changeset
      end

    case Ash.DataLayer.update(resource, update_changeset) do
      {:ok, updated_record} ->
        if status == :completed do
          {:ok, updated_record}
        else
          {:error, result_or_error}
        end

      {:error, update_error} ->
        {:error, update_error}
    end
  end

  defp create_without_status(changeset, resource, context_attr, agent_context, context) do
    case call_agent(resource, changeset.domain, agent_context, context) do
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
