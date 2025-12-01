defmodule AshAgentSession.Verifiers.RequireAgentBlock do
  @moduledoc """
  Verifies that agent_session is only used on resources with an agent block.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Transformer
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    if has_agent_block?(dsl_state) do
      :ok
    else
      {:error,
       DslError.exception(
         module: module,
         path: [:agent_session],
         message: """
         agent_session requires an agent block to be defined on this resource.

         Add an agent block to your resource:

             agent do
               client "anthropic:claude-sonnet-4-20250514"
               instruction "Your instruction here"
               input_schema Zoi.object(%{...}, coerce: true)
               output_schema Zoi.object(%{...}, coerce: true)
             end
         """
       )}
    end
  end

  defp has_agent_block?(dsl_state) do
    case Transformer.get_option(dsl_state, [:agent], :client) do
      nil -> false
      _ -> true
    end
  end
end
