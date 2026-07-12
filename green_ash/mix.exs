defmodule GreenAsh.MixProject do
  use Mix.Project

  @version "0.1.0"
  # Monorepo : le dépôt racine contient aussi les exemples (bank/, library/),
  # donc on pointe précisément sur le sous-dossier de la lib.
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
      # Solveur SAT requis dès qu'une resource hôte utilise Ash.Policy.Authorizer.
      {:picosat_elixir, "~> 0.2", only: [:dev, :test]},
      {:lazy_html, ">= 0.1.0", only: :test},
      # Pour `mix green_ash.install` (patch automatique du routeur hôte).
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
      # Le dépôt est un monorepo (bank/, library/ à côté) : la lib vit dans le
      # sous-dossier `green_ash/`, donc on force le pattern des liens "View
      # Source" plutôt que de laisser ex_doc les déduire de `source_url` (qui
      # pointe déjà vers ce sous-dossier pour l'affichage humain sur Hex).
      source_url_pattern:
        "https://github.com/nseaSeb/green_ash/blob/main/green_ash/%{path}#L%{line}",
      groups_for_modules: [
        Core: [GreenAsh.Registry, GreenAsh.Field, GreenAsh.Actor, GreenAsh.Command],
        "Web Integration": [
          GreenAsh.Router,
          GreenAsh.Web,
          GreenAsh.OnMount,
          GreenAsh.ActorController,
          GreenAsh.Components
        ],
        LiveViews: [GreenAsh.Live.Menu, GreenAsh.Live.Screen, GreenAsh.Live.Subfile],
        "Mix Tasks": [Mix.Tasks.GreenAsh.Install]
      ]
    ]
  end
end
