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
end
