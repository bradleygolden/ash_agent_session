defmodule AshAgentSession.Actions.GetContextRun do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias AshAgentSession.ContextSerializer

  @impl true
  def run(input, _opts, context) do
    resource = input.resource
    domain = input.domain
    context_attr = AshAgentSession.Info.context_attribute(resource)
    id = input.arguments.id

    opts = [domain: domain]

    opts =
      if actor = context.actor do
        Keyword.put(opts, :actor, actor)
      else
        opts
      end

    case Ash.get(resource, id, opts) do
      {:ok, record} ->
        stored_context = Map.get(record, context_attr)
        ContextSerializer.from_map(stored_context)

      {:error, error} ->
        {:error, error}
    end
  end
end
