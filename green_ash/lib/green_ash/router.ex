defmodule GreenAsh.Router do
  @moduledoc """
  Intégration au routeur de l'hôte.

  À placer dans une `scope` passant par un pipeline avec session (`fetch_session`),
  typiquement `:browser` :

      import GreenAsh.Router

      scope "/" do
        pipe_through :browser
        green_ash "/cli", domains: [MyApp.Bank, MyApp.Sales]
      end

  `domains` : la liste des domaines Ash à exposer. La macro monte les LiveViews
  de la console et la route d'acteur, en injectant domaines + base via `on_mount`.
  """

  defmacro green_ash(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      domains = opts |> Keyword.fetch!(:domains) |> Enum.map(&Atom.to_string/1)

      scope path, alias: false, as: false do
        get "/actor", GreenAsh.ActorController, :set

        live_session :green_ash,
          session: %{"green_ash" => %{"domains" => domains, "base" => path}},
          on_mount: [GreenAsh.OnMount],
          layout: false do
          live "/", GreenAsh.Live.Menu
          live "/r/:resource/list/:action", GreenAsh.Live.Subfile
          live "/r/:resource/a/:action", GreenAsh.Live.Screen
          live "/r/:resource/a/:action/:id", GreenAsh.Live.Screen
        end
      end
    end
  end
end
