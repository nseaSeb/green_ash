defmodule GreenAsh.Router do
  @moduledoc """
  Intégration au routeur de l'hôte.

  À placer dans une `scope` passant par un pipeline avec session (`fetch_session`),
  typiquement `:browser` :

      import GreenAsh.Router

      scope "/" do
        pipe_through :browser
        green_ash "/cli"
      end

  Par défaut, les domaines exposés sont lus **dynamiquement, à chaque requête**
  depuis `Application.get_env(:mon_app, :ash_domains, [])` — la même clé de
  config que `mix ash.setup`/`mix ash.codegen` utilisent déjà. Ajouter un
  domaine à cette liste (ce que font les générateurs Ash eux-mêmes) suffit à
  le faire apparaître dans la console, sans retoucher le routeur ni relancer
  l'installeur.

  `domains:` reste disponible pour figer explicitement un sous-ensemble (ou
  si vos domaines ne sont pas déclarés sous la clé standard) :

      green_ash "/cli", domains: [MyApp.Bank, MyApp.Sales]
  """

  @doc """
  Monte la console sous `path`, dans le `scope` courant.

  ## Options

    * `:domains` — liste explicite de modules `Ash.Domain` à exposer. Si omise
      (recommandé), lue dynamiquement depuis `Application.get_env(otp_app, :ash_domains, [])`.
    * `:otp_app` — application OTP dont lire `:ash_domains` par défaut.
      Déduite automatiquement (`Mix.Project.config()[:app]`) si omise.
  """
  defmacro green_ash(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      otp_app = Keyword.get_lazy(opts, :otp_app, fn -> Mix.Project.config()[:app] end)

      explicit_domains =
        case Keyword.get(opts, :domains) do
          nil -> nil
          list -> Enum.map(list, &Atom.to_string/1)
        end

      scope path, alias: false, as: false do
        get "/actor", GreenAsh.ActorController, :set

        live_session :green_ash,
          session: %{
            "green_ash" => %{
              "domains" => explicit_domains,
              "otp_app" => otp_app && Atom.to_string(otp_app),
              "base" => path
            }
          },
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
