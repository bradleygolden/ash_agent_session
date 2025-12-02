defmodule AshAgentSession.StreamWrapperTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context
  alias AshAgent.Message
  alias AshAgentSession.ContextSerializer
  alias AshAgentSession.StreamWrapper

  defmodule MockResource do
    @moduledoc false
  end

  defmodule MockDomain do
    @moduledoc false
  end

  describe "wrap/2" do
    test "passes through content chunks unchanged" do
      stream =
        Stream.iterate(1, &(&1 + 1)) |> Stream.take(3) |> Stream.map(&{:content, "chunk#{&1}"})

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      chunks = Enum.to_list(wrapped)

      assert chunks == [{:content, "chunk1"}, {:content, "chunk2"}, {:content, "chunk3"}]
    end

    test "passes through thinking chunks unchanged" do
      stream = [{:thinking, "step 1"}, {:thinking, "step 2"}] |> Stream.cycle() |> Stream.take(2)

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      chunks = Enum.to_list(wrapped)

      assert chunks == [{:thinking, "step 1"}, {:thinking, "step 2"}]
    end

    test "passes through done chunk unchanged" do
      result = %{output: %{reply: "Hello!"}}
      stream = [{:content, "Hello"}, {:done, result}]

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      chunks = Enum.to_list(wrapped)

      assert [{:content, "Hello"}, {:done, ^result}] = chunks
    end

    test "passes through unknown chunk types unchanged" do
      stream = [{:unknown, "data"}, {:other, 123}]

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      chunks = Enum.to_list(wrapped)

      assert chunks == [{:unknown, "data"}, {:other, 123}]
    end
  end

  describe "internal state accumulation" do
    test "accumulates content from multiple chunks" do
      stream = [{:content, "a"}, {:content, "b"}, {:content, "c"}]

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      _chunks = Enum.to_list(wrapped)
    end

    test "accumulates thinking from multiple chunks" do
      stream = [{:thinking, "x"}, {:thinking, "y"}]

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      _chunks = Enum.to_list(wrapped)
    end
  end

  describe "content extraction" do
    test "handles binary content" do
      stream = [{:content, "hello"}]

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      chunks = Enum.to_list(wrapped)
      assert chunks == [{:content, "hello"}]
    end

    test "handles map content" do
      stream = [{:content, %{text: "hello"}}]

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      chunks = Enum.to_list(wrapped)
      assert chunks == [{:content, %{text: "hello"}}]
    end
  end

  describe "stream transformation" do
    test "is lazy and only processes when consumed" do
      counter = :counters.new(1, [:atomics])

      stream =
        Stream.iterate(1, fn n ->
          :counters.add(counter, 1, 1)
          n + 1
        end)
        |> Stream.take(3)
        |> Stream.map(&{:content, "chunk#{&1}"})

      streaming_msg = ContextSerializer.streaming_assistant_message()
      ctx = Context.new([Message.user("Hello"), streaming_msg])

      wrapped =
        StreamWrapper.wrap(stream,
          resource: MockResource,
          domain: MockDomain,
          record: %{id: "test"},
          context: ctx,
          context_attr: :context,
          flush_interval: 10_000
        )

      assert :counters.get(counter, 1) == 0

      _chunks = Enum.to_list(wrapped)

      assert :counters.get(counter, 1) == 2
    end
  end
end
