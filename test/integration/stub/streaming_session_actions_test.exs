defmodule AshAgentSession.Integration.Stub.StreamingSessionActionsTest do
  @moduledoc false
  use AshAgentSession.IntegrationCase

  alias AshAgentSession.Test.StreamingSessionAgent

  describe "stream_start_session" do
    test "creates a session and returns a stream" do
      input = %{message: "Hello"}

      {:ok, %{session: session, stream: stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_start_session, %{input: input})
        |> Ash.run_action()

      assert session.id != nil
      assert session.status == :streaming
      assert is_function(stream) or is_struct(stream, Stream)
    end

    test "stream yields chunks when consumed" do
      input = %{message: "Test streaming"}

      {:ok, %{stream: stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_start_session, %{input: input})
        |> Ash.run_action()

      chunks = Enum.to_list(stream)

      content_chunks = Enum.filter(chunks, &match?({:content, _}, &1))
      done_chunks = Enum.filter(chunks, &match?({:done, _}, &1))

      assert length(content_chunks) >= 1
      assert length(done_chunks) == 1
    end

    test "stream completes and updates session status" do
      input = %{message: "Complete test"}

      {:ok, %{session: session, stream: stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_start_session, %{input: input})
        |> Ash.run_action()

      _chunks = Enum.to_list(stream)

      [updated_session] = Ash.read!(StreamingSessionAgent)
      assert updated_session.id == session.id
      assert updated_session.status == :completed
    end

    test "context is persisted after stream completes" do
      input = %{message: "Persist test"}

      {:ok, %{session: session, stream: stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_start_session, %{input: input})
        |> Ash.run_action()

      _chunks = Enum.to_list(stream)

      {:ok, context} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:get_context, %{id: session.id})
        |> Ash.run_action()

      assert %AshAgent.Context{} = context
      assert length(context.messages) >= 2

      user_message = Enum.find(context.messages, &(&1.role == :user))
      assert user_message != nil
      assert user_message.content == %{message: "Persist test"}

      assistant_message = Enum.find(context.messages, &(&1.role == :assistant))
      assert assistant_message != nil
      assert assistant_message.content != nil
    end

    test "context has finalized assistant message after stream" do
      input = %{message: "Finalize test"}

      {:ok, %{session: session, stream: stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_start_session, %{input: input})
        |> Ash.run_action()

      _chunks = Enum.to_list(stream)

      {:ok, context} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:get_context, %{id: session.id})
        |> Ash.run_action()

      assistant_message = List.last(context.messages)
      assert assistant_message.role == :assistant
      refute Map.get(assistant_message.metadata, :streaming, false)
    end
  end

  describe "stream_continue_session" do
    test "continues an existing session and returns a stream" do
      {:ok, %{stream: first_stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_start_session, %{input: %{message: "First"}})
        |> Ash.run_action()

      _chunks = Enum.to_list(first_stream)

      [session] = Ash.read!(StreamingSessionAgent)

      {:ok, %{session: updated_session, stream: second_stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_continue_session, %{
          id: session.id,
          input: %{message: "Second"}
        })
        |> Ash.run_action()

      assert updated_session.id == session.id
      assert updated_session.status == :streaming
      assert is_function(second_stream) or is_struct(second_stream, Stream)
    end

    test "accumulates messages across multiple streaming turns" do
      {:ok, %{session: session, stream: first_stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_start_session, %{input: %{message: "Turn 1"}})
        |> Ash.run_action()

      _chunks = Enum.to_list(first_stream)

      {:ok, %{stream: second_stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_continue_session, %{
          id: session.id,
          input: %{message: "Turn 2"}
        })
        |> Ash.run_action()

      _chunks = Enum.to_list(second_stream)

      {:ok, context} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:get_context, %{id: session.id})
        |> Ash.run_action()

      user_messages = Enum.filter(context.messages, &(&1.role == :user))
      assert length(user_messages) == 2

      contents = Enum.map(user_messages, & &1.content)
      assert %{message: "Turn 1"} in contents
      assert %{message: "Turn 2"} in contents
    end

    test "status transitions from streaming to completed" do
      {:ok, %{session: session, stream: first_stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_start_session, %{input: %{message: "First"}})
        |> Ash.run_action()

      assert session.status == :streaming
      _chunks = Enum.to_list(first_stream)

      [session] = Ash.read!(StreamingSessionAgent)
      assert session.status == :completed

      {:ok, %{session: session, stream: second_stream}} =
        StreamingSessionAgent
        |> Ash.ActionInput.for_action(:stream_continue_session, %{
          id: session.id,
          input: %{message: "Second"}
        })
        |> Ash.run_action()

      assert session.status == :streaming
      _chunks = Enum.to_list(second_stream)

      [session] = Ash.read!(StreamingSessionAgent)
      assert session.status == :completed
    end
  end

  describe "streaming info helpers" do
    test "streaming? returns true for streaming-enabled resource" do
      assert AshAgentSession.Info.streaming?(StreamingSessionAgent) == true
    end

    test "flush_interval returns configured value" do
      assert AshAgentSession.Info.flush_interval(StreamingSessionAgent) == 100
    end

    test "streaming_config returns config map" do
      config = AshAgentSession.Info.streaming_config(StreamingSessionAgent)
      assert config == %{flush_interval: 100}
    end
  end
end
