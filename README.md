# AshAgentSession

[![Hex.pm](https://img.shields.io/hexpm/v/ash_agent_session.svg)](https://hex.pm/packages/ash_agent_session)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Pre-1.0 Release** - API may change between minor versions.

Session persistence extension for AshAgent. Enables stateful agent conversations that persist across requests.

## Installation

```elixir
def deps do
  [
    {:ash_agent_session, "~> 0.1.0"}
  ]
end
```

## Overview

| Library | Scope |
|---------|-------|
| ash_agent | Single call primitives (LLM interaction, structured I/O) |
| ash_agent_tools | Multi-turn within one execution (tool calling loop) |
| **ash_agent_session** | Cross-request state persistence |

## Usage

Add `AshAgentSession.Resource` alongside `AshAgent.Resource` on your agent:

```elixir
defmodule MyApp.ChatAgent do
  use Ash.Resource,
    domain: MyApp.Agents,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAgent.Resource, AshAgentSession.Resource]

  agent do
    client "anthropic:claude-sonnet-4-20250514"

    instruction ~p"""
    You are a helpful assistant for {{ company_name }}.
    """

    instruction_schema Zoi.object(%{
      company_name: Zoi.string()
    }, coerce: true)

    input_schema Zoi.object(%{
      message: Zoi.string()
    }, coerce: true)

    output_schema Zoi.object(%{
      content: Zoi.string()
    }, coerce: true)
  end

  agent_session do
    context_attribute :context
  end

  attributes do
    uuid_primary_key :id
    attribute :context, :map
    timestamps()
  end

  postgres do
    table "chat_agents"
    repo MyApp.Repo
  end

  code_interface do
    define :start_session, args: [:input]
    define :continue_session, args: [:input]
    define :get_context, args: [:id]
  end
end
```

## Generated Actions

The extension generates these actions on your resource:

- `:start_session` - Create a new session with an initial message
- `:continue_session` - Continue an existing session with a new message
- `:get_context` - Retrieve the deserialized context from a session

## Example

```elixir
# Start a new session
{:ok, session} = MyApp.ChatAgent.start_session(%{message: "Hello!"})

# Continue the conversation
{:ok, session} = MyApp.ChatAgent.continue_session(session, %{message: "Follow up question"})

# Get the full context (for inspection or manual manipulation)
{:ok, context} = MyApp.ChatAgent.get_context(session.id)
```

## DSL Reference

### `agent_session` Section

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context_attribute` | atom | `:context` | The attribute name for storing the serialized context map |

## Requirements

- The resource must have an `agent` block defined (from `AshAgent.Resource`)
- The resource must have an attribute matching the `context_attribute` name with type `:map`
- The resource must have a data layer configured (ETS, Postgres, etc.)

## License

MIT License - see [LICENSE](LICENSE) for details.
