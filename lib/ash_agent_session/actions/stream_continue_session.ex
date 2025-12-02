defmodule AshAgentSession.Actions.StreamContinueSession do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias AshAgentSession.ContextSerializer
  alias AshAgentSession.StreamWrapper

  @impl true
  def run(input, _opts, _context) do
    resource = input.resource
    domain = input.domain
    context_attr = AshAgentSession.Info.context_attribute(resource)
    status_attr = AshAgentSession.Info.status_attribute(resource)
    flush_interval = AshAgentSession.Info.flush_interval(resource)

    session_id = input.arguments.id
    user_input = input.arguments.input

    with {:ok, record} <- Ash.get(resource, session_id, domain: domain),
         {:ok, agent_context} <- ContextSerializer.from_map(Map.get(record, context_attr)),
         {:ok, updated_record} <-
           update_session_for_streaming(
             record,
             agent_context,
             user_input,
             resource,
             domain,
             context_attr,
             status_attr
           ) do
      updated_context = add_user_message(agent_context, user_input)
      streaming_context = prepare_streaming_context(updated_context)

      start_stream(
        resource,
        domain,
        updated_record,
        updated_context,
        streaming_context,
        context_attr,
        status_attr,
        flush_interval
      )
    end
  end

  defp update_session_for_streaming(
         record,
         agent_context,
         user_input,
         resource,
         domain,
         context_attr,
         status_attr
       ) do
    agent_context_with_user = add_user_message(agent_context, user_input)
    streaming_context = prepare_streaming_context(agent_context_with_user)
    serialized = ContextSerializer.to_map(streaming_context)

    changeset =
      record
      |> Ash.Changeset.new()
      |> Map.put(:domain, domain)
      |> Ash.Changeset.force_change_attribute(context_attr, serialized)

    changeset =
      if status_attr do
        Ash.Changeset.force_change_attribute(changeset, status_attr, :streaming)
      else
        changeset
      end

    Ash.DataLayer.update(resource, changeset)
  end

  defp start_stream(
         resource,
         domain,
         record,
         agent_context,
         streaming_context,
         context_attr,
         status_attr,
         flush_interval
       ) do
    case AshAgent.Runtime.stream(resource, agent_context) do
      {:ok, stream} ->
        wrapped_stream =
          StreamWrapper.wrap(stream,
            resource: resource,
            domain: domain,
            record: record,
            context: streaming_context,
            context_attr: context_attr,
            status_attr: status_attr,
            flush_interval: flush_interval
          )

        {:ok, %{session: record, stream: wrapped_stream}}

      {:error, error} ->
        mark_failed(record, resource, domain, status_attr)
        {:error, error}
    end
  end

  defp prepare_streaming_context(agent_context) do
    streaming_message = ContextSerializer.streaming_assistant_message()
    %{agent_context | messages: agent_context.messages ++ [streaming_message]}
  end

  defp add_user_message(context, input) do
    message = AshAgent.Message.user(input)
    %{context | messages: context.messages ++ [message], input: input}
  end

  defp mark_failed(record, resource, domain, status_attr) do
    if status_attr do
      changeset =
        record
        |> Ash.Changeset.new()
        |> Map.put(:domain, domain)
        |> Ash.Changeset.force_change_attribute(status_attr, :failed)

      Ash.DataLayer.update(resource, changeset)
    end
  end
end
