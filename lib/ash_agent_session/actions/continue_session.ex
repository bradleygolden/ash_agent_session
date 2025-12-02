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
    status_attr = AshAgentSession.Info.status_attribute(resource)

    input = Ash.Changeset.get_argument(changeset, :input)
    stored_context = Map.get(record, context_attr)

    with {:ok, agent_context} <- ContextSerializer.from_map(stored_context),
         updated_context <- add_user_message(agent_context, input) do
      if status_attr do
        update_with_status_tracking(
          record,
          resource,
          domain,
          context_attr,
          status_attr,
          updated_context,
          context
        )
      else
        update_without_status(changeset, resource, context_attr, updated_context, context)
      end
    end
  end

  defp update_with_status_tracking(
         record,
         resource,
         domain,
         context_attr,
         status_attr,
         agent_context,
         context
       ) do
    running_changeset =
      record
      |> Ash.Changeset.new()
      |> Map.put(:domain, domain)
      |> Ash.Changeset.force_change_attribute(status_attr, :running)

    case Ash.DataLayer.update(resource, running_changeset) do
      {:ok, running_record} ->
        run_agent_and_finalize(
          running_record,
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

  defp run_agent_and_finalize(
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

  defp update_without_status(changeset, resource, context_attr, agent_context, context) do
    case call_agent(resource, changeset.domain, agent_context, context) do
      {:ok, result} ->
        serialized = ContextSerializer.to_map(result.context)

        changeset =
          changeset
          |> Ash.Changeset.force_change_attribute(context_attr, serialized)
          |> Ash.Changeset.set_context(%{agent_result: result})

        Ash.DataLayer.update(resource, changeset)

      {:error, error} ->
        {:error, error}
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
