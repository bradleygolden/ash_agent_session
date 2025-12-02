defmodule AshAgentSession.ContextSerializerTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context
  alias AshAgent.Message
  alias AshAgentSession.ContextSerializer

  describe "to_map/1" do
    test "serializes a context with messages" do
      context =
        Context.new([
          Message.system("You are helpful"),
          Message.user(%{message: "Hello"})
        ])

      result = ContextSerializer.to_map(context)

      assert %{messages: messages, metadata: %{}, input: nil} = result
      assert length(messages) == 2
      assert Enum.at(messages, 0).role == :system
      assert Enum.at(messages, 1).role == :user
    end

    test "preserves metadata" do
      context =
        Context.new([Message.user("test")], metadata: %{session_id: "abc123"})

      result = ContextSerializer.to_map(context)

      assert result.metadata == %{session_id: "abc123"}
    end

    test "preserves input" do
      context =
        Context.new([Message.user(%{message: "test"})], input: %{message: "test"})

      result = ContextSerializer.to_map(context)

      assert result.input == %{message: "test"}
    end
  end

  describe "from_map/1" do
    test "deserializes a map with atom keys" do
      map = %{
        messages: [
          %{role: :user, content: "Hello", metadata: %{}}
        ],
        metadata: %{},
        input: nil
      }

      assert {:ok, context} = ContextSerializer.from_map(map)
      assert %Context{} = context
      assert length(context.messages) == 1
      assert hd(context.messages).role == :user
      assert hd(context.messages).content == "Hello"
    end

    test "deserializes a map with string keys" do
      map = %{
        "messages" => [
          %{"role" => "user", "content" => "Hello", "metadata" => %{}}
        ],
        "metadata" => %{},
        "input" => nil
      }

      assert {:ok, context} = ContextSerializer.from_map(map)
      assert %Context{} = context
      assert length(context.messages) == 1
      assert hd(context.messages).role == :user
    end

    test "handles nil input" do
      assert {:ok, context} = ContextSerializer.from_map(nil)
      assert %Context{} = context
      assert context.messages == []
    end

    test "preserves message metadata" do
      map = %{
        messages: [
          %{role: :assistant, content: "response", metadata: %{tokens: 100}}
        ],
        metadata: %{}
      }

      assert {:ok, context} = ContextSerializer.from_map(map)
      assert hd(context.messages).metadata == %{tokens: 100}
    end
  end

  describe "from_map!/1" do
    test "returns context on success" do
      map = %{
        messages: [%{role: :user, content: "test"}],
        metadata: %{}
      }

      context = ContextSerializer.from_map!(map)
      assert %Context{} = context
    end
  end

  describe "roundtrip" do
    test "serializing and deserializing preserves data" do
      original =
        Context.new(
          [
            Message.system("Be helpful"),
            Message.user(%{question: "What is 2+2?"}),
            Message.assistant(%{answer: "4"})
          ],
          metadata: %{turn: 1},
          input: %{question: "What is 2+2?"}
        )

      serialized = ContextSerializer.to_map(original)
      {:ok, deserialized} = ContextSerializer.from_map(serialized)

      assert length(deserialized.messages) == length(original.messages)
      assert deserialized.metadata == original.metadata
      assert deserialized.input == original.input

      for {orig_msg, deser_msg} <- Enum.zip(original.messages, deserialized.messages) do
        assert orig_msg.role == deser_msg.role
        assert orig_msg.content == deser_msg.content
      end
    end
  end

  describe "streaming_assistant_message/0" do
    test "creates a placeholder message with streaming metadata" do
      msg = ContextSerializer.streaming_assistant_message()

      assert %Message{} = msg
      assert msg.role == :assistant
      assert msg.content == nil
      assert msg.metadata.streaming == true
      assert msg.metadata.streaming_content == ""
      assert msg.metadata.streaming_thinking == ""
    end
  end

  describe "update_streaming_content/3" do
    test "accumulates content delta" do
      msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), msg])

      ctx = ContextSerializer.update_streaming_content(ctx, "Hi ")
      ctx = ContextSerializer.update_streaming_content(ctx, "there!")

      last_msg = List.last(ctx.messages)
      assert last_msg.metadata.streaming_content == "Hi there!"
    end

    test "accumulates thinking delta" do
      msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), msg])

      ctx = ContextSerializer.update_streaming_content(ctx, nil, "Let me ")
      ctx = ContextSerializer.update_streaming_content(ctx, nil, "think...")

      last_msg = List.last(ctx.messages)
      assert last_msg.metadata.streaming_thinking == "Let me think..."
    end

    test "accumulates both content and thinking" do
      msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), msg])

      ctx = ContextSerializer.update_streaming_content(ctx, "Hello", "Thinking")

      last_msg = List.last(ctx.messages)
      assert last_msg.metadata.streaming_content == "Hello"
      assert last_msg.metadata.streaming_thinking == "Thinking"
    end

    test "returns unchanged context if last message is not streaming" do
      ctx = Context.new([Message.user("Hello"), Message.assistant("Hi")])

      updated = ContextSerializer.update_streaming_content(ctx, "More content")

      assert updated == ctx
    end
  end

  describe "finalize_streaming_message/3" do
    test "replaces streaming placeholder with parsed content" do
      msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), msg])
      ctx = ContextSerializer.update_streaming_content(ctx, "raw content", nil)

      final_ctx = ContextSerializer.finalize_streaming_message(ctx, %{reply: "Hello!"})

      last_msg = List.last(final_ctx.messages)
      assert last_msg.content == %{reply: "Hello!"}
      refute Map.has_key?(last_msg.metadata, :streaming)
      refute Map.has_key?(last_msg.metadata, :streaming_content)
      refute Map.has_key?(last_msg.metadata, :streaming_thinking)
    end

    test "preserves thinking in final metadata" do
      msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), msg])

      final_ctx = ContextSerializer.finalize_streaming_message(ctx, %{reply: "Hi"}, "My thinking")

      last_msg = List.last(final_ctx.messages)
      assert last_msg.metadata.thinking == "My thinking"
    end

    test "returns unchanged context if last message is not streaming" do
      ctx = Context.new([Message.user("Hello"), Message.assistant("Hi")])

      updated = ContextSerializer.finalize_streaming_message(ctx, %{new: "content"})

      assert updated == ctx
    end
  end

  describe "streaming?/1" do
    test "returns true when last message is streaming" do
      msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), msg])

      assert ContextSerializer.streaming?(ctx) == true
    end

    test "returns false when last message is not streaming" do
      ctx = Context.new([Message.user("Hello"), Message.assistant("Hi")])

      assert ContextSerializer.streaming?(ctx) == false
    end

    test "returns false for empty context" do
      ctx = Context.new([])

      assert ContextSerializer.streaming?(ctx) == false
    end
  end

  describe "get_streaming_content/1" do
    test "returns accumulated content and thinking" do
      msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), msg])
      ctx = ContextSerializer.update_streaming_content(ctx, "content", "thinking")

      result = ContextSerializer.get_streaming_content(ctx)

      assert result == %{content: "content", thinking: "thinking"}
    end

    test "returns nil when not streaming" do
      ctx = Context.new([Message.user("Hello"), Message.assistant("Hi")])

      assert ContextSerializer.get_streaming_content(ctx) == nil
    end
  end
end
