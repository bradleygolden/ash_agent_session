defmodule AshAgentSession.ContextSerializer do
  @moduledoc """
  Serializes and deserializes `AshAgent.Context` structs for storage.

  Uses Zoi for validation when deserializing stored maps back to structs.

  ## Streaming Fields

  During streaming, assistant messages may have streaming progress stored in metadata:

  - `streaming_content` - Accumulated raw content text
  - `streaming_thinking` - Accumulated thinking text
  - `streaming` - Boolean flag indicating message is being streamed

  When streaming completes, these fields are cleared and `content` is set to the
  final parsed output.
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

  @doc """
  Creates a streaming assistant message placeholder.

  This message has `content: nil` and streaming fields in metadata,
  indicating that content is being accumulated during streaming.
  """
  def streaming_assistant_message do
    %Message{
      role: :assistant,
      content: nil,
      metadata: %{
        streaming: true,
        streaming_content: "",
        streaming_thinking: ""
      }
    }
  end

  @doc """
  Updates the streaming content in a context's last assistant message.

  Accumulates content and thinking text in the message's metadata.
  """
  def update_streaming_content(%Context{} = ctx, content_delta, thinking_delta \\ nil) do
    messages = ctx.messages

    case List.last(messages) do
      %Message{role: :assistant, metadata: %{streaming: true} = metadata} = msg ->
        updated_metadata =
          metadata
          |> update_streaming_field(:streaming_content, content_delta)
          |> update_streaming_field(:streaming_thinking, thinking_delta)

        updated_msg = %{msg | metadata: updated_metadata}
        updated_messages = List.replace_at(messages, -1, updated_msg)
        %{ctx | messages: updated_messages}

      _ ->
        ctx
    end
  end

  defp update_streaming_field(metadata, _key, nil), do: metadata

  defp update_streaming_field(metadata, key, delta) do
    current = Map.get(metadata, key, "")
    Map.put(metadata, key, current <> to_string(delta))
  end

  @doc """
  Finalizes a streaming assistant message with the parsed content.

  Replaces the streaming placeholder with the final parsed output and
  clears streaming metadata.
  """
  def finalize_streaming_message(%Context{} = ctx, parsed_content, thinking \\ nil) do
    messages = ctx.messages

    case List.last(messages) do
      %Message{role: :assistant, metadata: %{streaming: true}} = msg ->
        final_metadata = build_final_metadata(msg.metadata, thinking)
        final_msg = %{msg | content: parsed_content, metadata: final_metadata}
        updated_messages = List.replace_at(messages, -1, final_msg)
        %{ctx | messages: updated_messages}

      _ ->
        ctx
    end
  end

  defp build_final_metadata(metadata, thinking) do
    base =
      metadata
      |> Map.delete(:streaming)
      |> Map.delete(:streaming_content)
      |> Map.delete(:streaming_thinking)

    if thinking, do: Map.put(base, :thinking, thinking), else: base
  end

  @doc """
  Checks if a context has an active streaming message.
  """
  def streaming?(%Context{} = ctx) do
    case List.last(ctx.messages) do
      %Message{role: :assistant, metadata: %{streaming: true}} -> true
      _ -> false
    end
  end

  @doc """
  Gets the accumulated streaming content from a context.

  Returns `nil` if there's no active streaming message.
  """
  def get_streaming_content(%Context{} = ctx) do
    case List.last(ctx.messages) do
      %Message{role: :assistant, metadata: %{streaming: true} = metadata} ->
        %{
          content: Map.get(metadata, :streaming_content, ""),
          thinking: Map.get(metadata, :streaming_thinking, "")
        }

      _ ->
        nil
    end
  end
end
