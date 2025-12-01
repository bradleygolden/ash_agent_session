# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-12-01

### Added

- Initial release
- `AshAgentSession.Resource` extension for adding session persistence to agents
- `agent_session` DSL block with `context_attribute` option
- `start_session` action for creating new sessions with instruction arguments
- `continue_session` action for continuing existing sessions
- `get_context_run` action for retrieving session context
- Context serialization for persisting conversation state
- Integration with AshAgent's context management
