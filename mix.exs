defmodule MafiaEngine.MixProject do
  use Mix.Project

  def project do
    [
      app: :mafia_engine,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      dialyzer: dialyzer_opts()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MafiaEngine.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:propcheck, "~> 1.3", only: [:test, :dev]},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:gen_state_machine, "~> 3.0"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp description() do
    "A still under development package for the party game mafia."
  end

  defp package() do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "mafia_engine",
      # These are the default files included in the package
      files: ~w(lib priv .formatter.exs mix.exs README*),
      licenses: ["Apache-2.0"],
      links: %{}
    ]
  end

  defp dialyzer_opts do
    [
      plt_add_apps: [:ex_unit],
      # Writes the plt file in that path. Used in CI
      plt_file: {:no_warn, "priv/plts/sorted.plt"},
      flags: [
        :unmatched_returns,
        :no_unused,
        :no_match,
        :no_missing_calls,
        :error_handling,
        :underspecs
      ]
    ]
  end
end
