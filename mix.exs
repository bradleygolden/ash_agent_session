defmodule AshAgentSession.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/bradleygolden/ash_agent_session"

  def project do
    [
      app: :ash_agent_session,
      version: @version,
      elixir: "~> 1.18",
      consolidate_protocols: Mix.env() != :test,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def cli do
    [preferred_envs: [check: :test, precommit: :test]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:spark, "~> 2.2"},
      {:ash_agent, ash_agent_dep()},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.16", only: :test}
    ]
  end

  defp ash_agent_dep do
    if local_dep?(:ash_agent) do
      [in_umbrella: true]
    else
      [version: "~> 0.1.0"]
    end
  end

  defp local_dep?(app) do
    app
    |> to_string()
    |> then(&Path.expand("../#{&1}/mix.exs", __DIR__))
    |> File.exists?()
  end

  defp aliases do
    [
      precommit: ["check"],
      check: [
        "deps.get",
        "deps.compile",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "test --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "sobelow --exit",
        "deps.audit",
        "hex.audit",
        "dialyzer",
        "docs --warnings-as-errors"
      ]
    ]
  end

  defp description do
    "Session persistence extension for AshAgent."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit]
    ]
  end
end
