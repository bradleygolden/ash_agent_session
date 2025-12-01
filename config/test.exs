import Config

config :ash, :validate_domain_resource_inclusion?, false

System.put_env("ANTHROPIC_API_KEY", "test-key-12345")

config :ash_agent, :req_llm_options, req_http_options: [plug: {Req.Test, AshAgentSession.LLMStub}]

config :logger, level: :error
