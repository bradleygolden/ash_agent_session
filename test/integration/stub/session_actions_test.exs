defmodule AshAgentSession.Integration.Stub.SessionActionsTest do
  @moduledoc false
  use AshAgentSession.IntegrationCase

  alias AshAgentSession.LLMStub
  alias AshAgentSession.Test.SessionAgent
  alias AshAgentSession.Test.SessionAgentWithStatus
  alias AshAgentSession.Test.SessionAgentWithTemplate

  describe "start_session" do
    test "creates a new session with agent response" do
      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.object_response(%{"reply" => "Hello!"}))

      input = %{message: "Hi there"}

      {:ok, session} =
        SessionAgent
        |> Ash.Changeset.for_create(:start_session, %{input: input})
        |> Ash.create()

      assert session.id != nil
      assert is_map(session.context)

      {:ok, context} = AshAgentSession.ContextSerializer.from_map(session.context)

      assert %AshAgent.Context{} = context
      assert length(context.messages) >= 2

      user_message = Enum.find(context.messages, &(&1.role == :user))
      assert user_message != nil
      assert user_message.content == %{message: "Hi there"}
    end

    test "stores agent_result in changeset context" do
      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.object_response(%{"reply" => "Hello!"}))

      input = %{message: "Test message"}

      {:ok, session, notifications} =
        SessionAgent
        |> Ash.Changeset.for_create(:start_session, %{input: input})
        |> Ash.create(return_notifications?: true)

      assert session.id != nil
      assert is_list(notifications)
    end

    test "with instruction_args renders template" do
      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "Template response"})
      )

      input = %{message: "Help me"}
      instruction_args = %{"persona" => "a coding expert", "task" => "debugging"}

      {:ok, session} =
        SessionAgentWithTemplate
        |> Ash.Changeset.for_create(:start_session, %{
          input: input,
          instruction_args: instruction_args
        })
        |> Ash.create()

      {:ok, context} = AshAgentSession.ContextSerializer.from_map(session.context)

      system_message = Enum.find(context.messages, &(&1.role == :system))
      assert system_message != nil
      assert system_message.content =~ "a coding expert"
      assert system_message.content =~ "debugging"
    end
  end

  describe "continue_session" do
    test "appends to existing conversation" do
      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "First response"})
      )

      {:ok, session} =
        SessionAgent
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "First message"}})
        |> Ash.create()

      {:ok, initial_context} = AshAgentSession.ContextSerializer.from_map(session.context)
      initial_message_count = length(initial_context.messages)

      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "Second response"})
      )

      {:ok, updated_session} =
        session
        |> Ash.Changeset.for_update(:continue_session, %{input: %{message: "Second message"}})
        |> Ash.update()

      {:ok, updated_context} = AshAgentSession.ContextSerializer.from_map(updated_session.context)

      assert length(updated_context.messages) > initial_message_count

      messages = updated_context.messages
      user_messages = Enum.filter(messages, &(&1.role == :user))
      assert length(user_messages) == 2
      assert Enum.any?(user_messages, &(&1.content == %{message: "First message"}))
      assert Enum.any?(user_messages, &(&1.content == %{message: "Second message"}))
    end

    test "preserves message history across multiple turns" do
      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "Response 1"})
      )

      {:ok, session} =
        SessionAgent
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "Turn 1"}})
        |> Ash.create()

      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "Response 2"})
      )

      {:ok, session} =
        session
        |> Ash.Changeset.for_update(:continue_session, %{input: %{message: "Turn 2"}})
        |> Ash.update()

      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "Response 3"})
      )

      {:ok, session} =
        session
        |> Ash.Changeset.for_update(:continue_session, %{input: %{message: "Turn 3"}})
        |> Ash.update()

      {:ok, context} = AshAgentSession.ContextSerializer.from_map(session.context)

      user_messages = Enum.filter(context.messages, &(&1.role == :user))
      assert length(user_messages) == 3
      contents = Enum.map(user_messages, & &1.content)
      assert contents == [%{message: "Turn 1"}, %{message: "Turn 2"}, %{message: "Turn 3"}]
    end
  end

  describe "get_context" do
    test "retrieves and deserializes stored context" do
      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.object_response(%{"reply" => "Hello!"}))

      {:ok, session} =
        SessionAgent
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "Test"}})
        |> Ash.create()

      {:ok, context} =
        SessionAgent
        |> Ash.ActionInput.for_action(:get_context, %{id: session.id})
        |> Ash.run_action()

      assert %AshAgent.Context{} = context
      assert is_list(context.messages)
      assert length(context.messages) >= 2
    end

    test "returns error for non-existent session" do
      fake_id = Ash.UUID.generate()

      result =
        SessionAgent
        |> Ash.ActionInput.for_action(:get_context, %{id: fake_id})
        |> Ash.run_action()

      assert {:error, _} = result
    end
  end

  describe "full conversation lifecycle" do
    test "complete multi-turn conversation" do
      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "Welcome!"})
      )

      {:ok, session} =
        SessionAgent
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "Hello"}})
        |> Ash.create()

      assert session.id != nil

      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "I can help with that."})
      )

      {:ok, session} =
        session
        |> Ash.Changeset.for_update(:continue_session, %{
          input: %{message: "Can you help me?"}
        })
        |> Ash.update()

      Req.Test.stub(
        AshAgentSession.LLMStub,
        LLMStub.object_response(%{"reply" => "You're welcome!"})
      )

      {:ok, session} =
        session
        |> Ash.Changeset.for_update(:continue_session, %{input: %{message: "Thank you"}})
        |> Ash.update()

      {:ok, final_context} =
        SessionAgent
        |> Ash.ActionInput.for_action(:get_context, %{id: session.id})
        |> Ash.run_action()

      assert %AshAgent.Context{} = final_context

      user_messages = Enum.filter(final_context.messages, &(&1.role == :user))
      assert length(user_messages) == 3

      contents = Enum.map(user_messages, & &1.content)
      assert %{message: "Hello"} in contents
      assert %{message: "Can you help me?"} in contents
      assert %{message: "Thank you"} in contents
    end
  end

  describe "status_attribute lifecycle" do
    test "start_session sets status to completed on success" do
      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.object_response(%{"reply" => "Hello!"}))

      {:ok, session} =
        SessionAgentWithStatus
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "Hi"}})
        |> Ash.create()

      assert session.status == :completed
    end

    test "continue_session sets status to completed on success" do
      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.object_response(%{"reply" => "First"}))

      {:ok, session} =
        SessionAgentWithStatus
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "First message"}})
        |> Ash.create()

      assert session.status == :completed

      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.object_response(%{"reply" => "Second"}))

      {:ok, updated_session} =
        session
        |> Ash.Changeset.for_update(:continue_session, %{input: %{message: "Second message"}})
        |> Ash.update()

      assert updated_session.status == :completed
    end

    test "start_session sets status to failed on agent error" do
      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.error_response())

      result =
        SessionAgentWithStatus
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "Hi"}})
        |> Ash.create()

      assert {:error, _} = result

      [session] = Ash.read!(SessionAgentWithStatus)
      assert session.status == :failed
    end

    test "continue_session sets status to failed on agent error" do
      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.object_response(%{"reply" => "First"}))

      {:ok, session} =
        SessionAgentWithStatus
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "First message"}})
        |> Ash.create()

      assert session.status == :completed

      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.error_response())

      result =
        session
        |> Ash.Changeset.for_update(:continue_session, %{input: %{message: "Second message"}})
        |> Ash.update()

      assert {:error, _} = result

      [failed_session] = Ash.read!(SessionAgentWithStatus)
      assert failed_session.status == :failed
    end

    test "works without status_attribute configured (backwards compatible)" do
      Req.Test.stub(AshAgentSession.LLMStub, LLMStub.object_response(%{"reply" => "Hello!"}))

      {:ok, session} =
        SessionAgent
        |> Ash.Changeset.for_create(:start_session, %{input: %{message: "Hi"}})
        |> Ash.create()

      assert session.id != nil
      refute Map.has_key?(session, :status)
    end
  end
end
