defmodule AshAgentSession.Info do
  @moduledoc """
  Introspection helpers for AshAgentSession extensions.
  """

  use Spark.InfoGenerator, extension: AshAgentSession.Resource, sections: [:agent_session]

  alias Spark.Dsl.Extension

  @doc """
  Get the context attribute name for a session-enabled resource.

  ## Examples

      iex> AshAgentSession.Info.context_attribute(MyApp.ChatAgent)
      :context
  """
  def context_attribute(resource) do
    Extension.get_opt(resource, [:agent_session], :context_attribute, :context)
  end

  @doc """
  Get the full session configuration for a resource.

  ## Examples

      iex> AshAgentSession.Info.session_config(MyApp.ChatAgent)
      %{context_attribute: :context}
  """
  def session_config(resource) do
    %{
      context_attribute: context_attribute(resource)
    }
  end
end
