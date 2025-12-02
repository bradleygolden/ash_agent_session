defmodule AshAgentSession.Actions.StreamStartSession do
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

    user_input = input.arguments.input
    instruction_args = input.arguments[:instruction_args]

    messages = build_initial_messages(resource, user_input, instruction_args)
    agent_context = AshAgent.Context.new(messages, input: user_input)

    streaming_context = prepare_streaming_context(agent_context)
    serialized = ContextSerializer.to_map(streaming_context)

    changeset =
      resource
      |> Ash.Changeset.new()
      |> Map.put(:domain, domain)
      |> Ash.Changeset.force_change_attribute(:id, Ash.UUID.generate())
      |> Ash.Changeset.force_change_attribute(context_attr, serialized)

    changeset =
      if status_attr do
        Ash.Changeset.force_change_attribute(changeset, status_attr, :streaming)
      else
        changeset
      end

    case Ash.DataLayer.create(resource, changeset) do
      {:ok, record} ->
        start_stream(
          resource,
          domain,
          record,
          agent_context,
          streaming_context,
          context_attr,
          status_attr,
          flush_interval
        )

      {:error, error} ->
        {:error, error}
    end
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
        mark_failed(resource, domain, record, status_attr)
        {:error, error}
    end
  end

  defp prepare_streaming_context(agent_context) do
    streaming_message = ContextSerializer.streaming_assistant_message()
    %{agent_context | messages: agent_context.messages ++ [streaming_message]}
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

  defp mark_failed(resource, domain, record, status_attr) do
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
