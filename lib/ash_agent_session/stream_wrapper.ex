defmodule AshAgentSession.StreamWrapper do
  @moduledoc """
  Wraps an agent stream to provide incremental context persistence.

  This module transforms a raw agent stream (yielding `{:content, data}`, `{:thinking, text}`,
  and `{:done, result}` chunks) into a wrapped stream that:

  1. Accumulates streaming content in memory
  2. Periodically flushes accumulated content to the session's context
  3. Finalizes the context with parsed output when the stream completes

  ## Stream Chunk Types

  The wrapper handles these chunk types from `AshAgent.Runtime.stream/2`:

  - `{:thinking, text}` - Extended thinking content (accumulated in `streaming_thinking`)
  - `{:content, data}` - Raw content text (accumulated in `streaming_content`)
  - `{:done, result}` - Final result with parsed output

  All chunks are passed through unchanged to the consumer.
  """

  alias AshAgentSession.ContextSerializer

  defstruct [
    :resource,
    :domain,
    :record,
    :context,
    :context_attr,
    :status_attr,
    :flush_interval,
    :last_flush_at,
    :accumulated_content,
    :accumulated_thinking
  ]

  @doc """
  Wraps an agent stream with incremental persistence.

  ## Options

  - `:resource` - The Ash resource module (required)
  - `:domain` - The Ash domain (required)
  - `:record` - The session record to update (required)
  - `:context` - The initial `AshAgent.Context` with streaming placeholder (required)
  - `:context_attr` - The attribute name for context storage (required)
  - `:status_attr` - The attribute name for status (optional)
  - `:flush_interval` - Milliseconds between flushes (default: 500)

  ## Returns

  A stream that yields the same chunks as the input stream, but also persists
  incremental progress to the session record.
  """
  def wrap(stream, opts) do
    Stream.transform(
      stream,
      fn -> init_state(opts) end,
      &handle_chunk/2,
      &finalize/1
    )
  end

  defp init_state(opts) do
    %__MODULE__{
      resource: Keyword.fetch!(opts, :resource),
      domain: Keyword.fetch!(opts, :domain),
      record: Keyword.fetch!(opts, :record),
      context: Keyword.fetch!(opts, :context),
      context_attr: Keyword.fetch!(opts, :context_attr),
      status_attr: Keyword.get(opts, :status_attr),
      flush_interval: Keyword.get(opts, :flush_interval, 500),
      last_flush_at: System.monotonic_time(:millisecond),
      accumulated_content: "",
      accumulated_thinking: ""
    }
  end

  defp handle_chunk({:thinking, text}, state) do
    state = %{state | accumulated_thinking: state.accumulated_thinking <> to_string(text)}
    state = maybe_flush(state)
    {[{:thinking, text}], state}
  end

  defp handle_chunk({:content, data}, state) do
    content_text = extract_content_text(data)
    state = %{state | accumulated_content: state.accumulated_content <> content_text}
    state = maybe_flush(state)
    {[{:content, data}], state}
  end

  defp handle_chunk({:done, result} = chunk, state) do
    state = finalize_context(state, result)
    {[chunk], state}
  end

  defp handle_chunk(other, state) do
    {[other], state}
  end

  defp extract_content_text(data) when is_binary(data), do: data
  defp extract_content_text(data) when is_map(data), do: inspect(data)
  defp extract_content_text(data), do: to_string(data)

  defp maybe_flush(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_flush_at

    if elapsed >= state.flush_interval do
      flush_context(state, now)
    else
      state
    end
  end

  defp flush_context(state, now) do
    updated_context =
      state.context
      |> ContextSerializer.update_streaming_content(
        state.accumulated_content,
        state.accumulated_thinking
      )

    case persist_context(state, updated_context) do
      {:ok, _record} ->
        %{state | context: updated_context, last_flush_at: now}

      {:error, _reason} ->
        %{state | last_flush_at: now}
    end
  end

  defp finalize_context(state, result) do
    parsed_content = extract_parsed_content(result)
    thinking = if state.accumulated_thinking != "", do: state.accumulated_thinking, else: nil

    final_context =
      ContextSerializer.finalize_streaming_message(state.context, parsed_content, thinking)

    case persist_final_context(state, final_context) do
      {:ok, _record} ->
        %{state | context: final_context}

      {:error, _reason} ->
        state
    end
  end

  defp extract_parsed_content(%{output: output}), do: output
  defp extract_parsed_content(result), do: result

  defp persist_context(state, context) do
    serialized = ContextSerializer.to_map(context)

    changeset =
      state.record
      |> Ash.Changeset.new()
      |> Map.put(:domain, state.domain)
      |> Ash.Changeset.force_change_attribute(state.context_attr, serialized)

    Ash.DataLayer.update(state.resource, changeset)
  rescue
    _ -> {:error, :persistence_failed}
  end

  defp persist_final_context(state, context) do
    serialized = ContextSerializer.to_map(context)

    changeset =
      state.record
      |> Ash.Changeset.new()
      |> Map.put(:domain, state.domain)
      |> Ash.Changeset.force_change_attribute(state.context_attr, serialized)

    changeset =
      if state.status_attr do
        Ash.Changeset.force_change_attribute(changeset, state.status_attr, :completed)
      else
        changeset
      end

    Ash.DataLayer.update(state.resource, changeset)
  rescue
    _ -> {:error, :persistence_failed}
  end

  defp finalize(state) do
    if ContextSerializer.streaming?(state.context) do
      final_context =
        ContextSerializer.finalize_streaming_message(
          state.context,
          state.accumulated_content,
          if(state.accumulated_thinking != "", do: state.accumulated_thinking, else: nil)
        )

      persist_final_context(state, final_context)
    end

    :ok
  end
end
