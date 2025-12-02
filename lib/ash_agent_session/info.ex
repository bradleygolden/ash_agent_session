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
  Get the status attribute name for a session-enabled resource.

  Returns `nil` if no status attribute is configured.

  ## Examples

      iex> AshAgentSession.Info.status_attribute(MyApp.ChatAgent)
      :status
  """
  def status_attribute(resource) do
    Extension.get_opt(resource, [:agent_session], :status_attribute, nil)
  end

  @doc """
  Get the full session configuration for a resource.

  ## Examples

      iex> AshAgentSession.Info.session_config(MyApp.ChatAgent)
      %{context_attribute: :context, status_attribute: nil}
  """
  def session_config(resource) do
    %{
      context_attribute: context_attribute(resource),
      status_attribute: status_attribute(resource),
      streaming?: streaming?(resource),
      flush_interval: flush_interval(resource)
    }
  end

  @doc """
  Check if streaming is enabled for a resource.

  Returns `true` if the `streaming` block is present in the DSL.

  ## Examples

      iex> AshAgentSession.Info.streaming?(MyApp.ChatAgent)
      true
  """
  def streaming?(resource) do
    case Extension.get_opt(resource, [:agent_session, :streaming], :flush_interval, nil) do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Get the streaming configuration for a resource.

  Returns `nil` if streaming is not configured.

  ## Examples

      iex> AshAgentSession.Info.streaming_config(MyApp.ChatAgent)
      %{flush_interval: 500}
  """
  def streaming_config(resource) do
    if streaming?(resource) do
      %{flush_interval: flush_interval(resource)}
    else
      nil
    end
  end

  @doc """
  Get the flush interval for streaming persistence.

  Returns the interval in milliseconds, or the default (500ms) if not configured.

  ## Examples

      iex> AshAgentSession.Info.flush_interval(MyApp.ChatAgent)
      500
  """
  def flush_interval(resource) do
    Extension.get_opt(resource, [:agent_session, :streaming], :flush_interval, 500)
  end
end
