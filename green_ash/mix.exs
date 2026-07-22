defmodule GreenAsh.MixProject do
  use Mix.Project

  @version "0.4.0"
  # Monorepo: the root repository also contains the examples (bank/, library/),
  # so we point precisely at the lib's subdirectory.
  @source_url "https://github.com/nseaSeb/green_ash/tree/main/green_ash"

  def project do
    [
      app: :green_ash,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "GreenAsh",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ash_phoenix, "~> 2.0"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:jason, "~> 1.2"},
      # SAT solver required as soon as a host resource uses Ash.Policy.Authorizer.
      {:picosat_elixir, "~> 0.2", only: [:dev, :test]},
      {:lazy_html, ">= 0.1.0", only: :test},
      # For `mix green_ash.install` (automatic patching of the host router).
      {:igniter, "~> 0.5", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A keyboard-driven LiveView console to probe your Ash resources — zero UI code."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"Source" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_ref: "main",
      # The repository is a monorepo (bank/, library/ alongside): the lib lives
      # in the `green_ash/` subdirectory, so we force the "View Source" link
      # pattern instead of letting ex_doc infer it from `source_url` (which
      # already points to this subdirectory for human display on Hex).
      source_url_pattern:
        "https://github.com/nseaSeb/green_ash/blob/main/green_ash/%{path}#L%{line}",
      groups_for_modules: [
        Core: [
          GreenAsh.Registry,
          GreenAsh.Field,
          GreenAsh.Actor,
          GreenAsh.Tenant,
          GreenAsh.Command
        ],
        "Web Integration": [
          GreenAsh.Router,
          GreenAsh.Web,
          GreenAsh.OnMount,
          GreenAsh.SessionController,
          GreenAsh.Components
        ],
        LiveViews: [GreenAsh.Live.Menu, GreenAsh.Live.Screen, GreenAsh.Live.Subfile],
        "Mix Tasks": [Mix.Tasks.GreenAsh.Install]
      ]
    ]
  end
end
