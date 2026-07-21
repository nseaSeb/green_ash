defmodule GreenAsh.Router do
  @moduledoc """
  Integration into the host's router.

  Place it in a `scope` going through a pipeline with a session
  (`fetch_session`), typically `:browser`, and behind a dev-only guard:

      if Application.compile_env(:my_app, :dev_routes) do
        import GreenAsh.Router

        scope "/" do
          pipe_through :browser
          green_ash "/cli"
        end
      end

  > #### Gate it {: .warning}
  >
  > The console has no access control of its own. It lists, creates, updates
  > and deletes any record of any exposed resource, and `:actor` loads any
  > record as the current actor — impersonation is the point of the tool.
  > Reachable in production, it is an unauthenticated admin panel over your
  > whole domain. `mix green_ash.install` writes the guard above for you;
  > mounting by hand is the path where nothing does.

  By default, the exposed domains are read **dynamically, on every request**
  from `Application.get_env(:my_app, :ash_domains, [])` — the same config key
  that `mix ash.setup`/`mix ash.codegen` already use. Adding a domain to this
  list (which the Ash generators themselves do) is enough to make it appear
  in the console, with no need to touch the router or rerun the installer.

  `domains:` remains available to explicitly pin a subset (or if your domains
  are not declared under the standard key):

      green_ash "/cli", domains: [MyApp.Bank, MyApp.Sales]
  """

  @doc """
  Mounts the console under `path`, in the current `scope`.

  ## Options

    * `:domains` — explicit list of `Ash.Domain` modules to expose. If
      omitted (recommended), read dynamically from
      `Application.get_env(otp_app, :ash_domains, [])`.
    * `:otp_app` — OTP application from which to read `:ash_domains` by
      default. Inferred automatically (`Mix.Project.config()[:app]`) if
      omitted.
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
