defmodule AshAgentSession.ContextSerializer do
  @moduledoc """
  Serializes and deserializes `AshAgent.Context` structs for storage.

  Uses Zoi for validation when deserializing stored maps back to structs.
  """

  alias AshAgent.Context
  alias AshAgent.Message

  @doc """
  Converts an `AshAgent.Context` struct to a map suitable for storage.

  ## Examples

      iex> context = AshAgent.Context.new([AshAgent.Message.user("Hello")])
      iex> AshAgentSession.ContextSerializer.to_map(context)
      %{messages: [%{role: :user, content: "Hello", metadata: %{}}], metadata: %{}, input: nil}
  """
  def to_map(%Context{} = ctx) do
    %{
      messages: Enum.map(ctx.messages, &message_to_map/1),
      metadata: ctx.metadata,
      input: ctx.input
    }
  end

  @doc """
  Deserializes a stored map back to an `AshAgent.Context` struct.

  Handles both atom and string keys for flexibility with different storage backends.

  ## Examples

      iex> map = %{messages: [%{role: :user, content: "Hello"}], metadata: %{}}
      iex> {:ok, context} = AshAgentSession.ContextSerializer.from_map(map)
      iex> length(context.messages)
      1
  """
  def from_map(nil), do: {:ok, Context.new([])}

  def from_map(map) when is_map(map) do
    messages_data = get_value(map, :messages, [])

    messages =
      Enum.map(messages_data, fn msg_data ->
        %Message{
          role: get_role(msg_data),
          content: get_value(msg_data, :content),
          metadata: get_value(msg_data, :metadata, %{})
        }
      end)

    context =
      Context.new(messages,
        metadata: get_value(map, :metadata, %{}),
        input: get_value(map, :input)
      )

    {:ok, context}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Deserializes a stored map back to an `AshAgent.Context` struct.

  Raises on failure.

  ## Examples

      iex> map = %{messages: [%{role: :user, content: "Hello"}]}
      iex> context = AshAgentSession.ContextSerializer.from_map!(map)
      iex> length(context.messages)
      1
  """
  def from_map!(map) do
    case from_map(map) do
      {:ok, context} -> context
      {:error, error} -> raise "Failed to deserialize context: #{inspect(error)}"
    end
  end

  defp message_to_map(%Message{} = msg) do
    %{
      role: msg.role,
      content: msg.content,
      metadata: msg.metadata || %{}
    }
  end

  defp get_value(map, key, default \\ nil) do
    Map.get(map, key) || Map.get(map, to_string(key)) || default
  end

  defp get_role(map) do
    role = get_value(map, :role)

    case role do
      r when is_atom(r) -> r
      r when is_binary(r) -> String.to_existing_atom(r)
    end
  end
end
