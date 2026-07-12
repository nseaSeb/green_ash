defmodule Mix.Tasks.GreenAsh.Install.Docs do
  @moduledoc false

  def short_doc, do: "Installs GreenAsh: mounts the console in your router"

  def example, do: "mix green_ash.install"

  def long_doc do
    """
    #{short_doc()}

    Adds `import GreenAsh.Router` and a `green_ash "/cli"` scope to your Phoenix
    router, gated behind `:dev_routes` (only enabled in dev). Exposed domains
    are read dynamically from your `:ash_domains` config at runtime, so newly
    added domains show up automatically — no need to re-run this installer.

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.GreenAsh.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :green_ash,
        adds_deps: [],
        installs: [],
        example: __MODULE__.Docs.example(),
        only: nil,
        positional: [],
        composes: [],
        schema: [],
        defaults: [],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)

      {igniter, router} =
        Igniter.Libs.Phoenix.select_router(igniter, "Which router should GreenAsh be added to?")

      igniter
      |> Igniter.Project.Formatter.import_dep(:green_ash)
      |> add_to_router(app_name, router)
    end

    defp add_to_router(igniter, _app_name, nil) do
      Igniter.add_warning(igniter, """
      No Phoenix router found or selected. Please ensure that Phoenix is set up
      and then run this installer again with

          mix igniter.install green_ash
      """)
    end

    defp add_to_router(igniter, app_name, router) do
      {igniter, has_browser_pipeline?} =
        Igniter.Libs.Phoenix.has_pipeline(igniter, router, :browser)

      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        case Igniter.Code.Common.move_to(
               zipper,
               &Igniter.Code.Function.function_call?(&1, :green_ash, [1, 2])
             ) do
          :error ->
            code =
              if has_browser_pipeline? do
                """
                if Application.compile_env(#{inspect(app_name)}, :dev_routes) do
                  import GreenAsh.Router

                  scope "/" do
                    pipe_through :browser

                    green_ash "/cli"
                  end
                end
                """
              else
                """
                if Application.compile_env(#{inspect(app_name)}, :dev_routes) do
                  import GreenAsh.Router

                  pipeline :green_ash_browser do
                    plug :accepts, ["html"]
                    plug :fetch_session
                    plug :fetch_live_flash
                    plug :protect_from_forgery
                    plug :put_secure_browser_headers
                  end

                  scope "/" do
                    pipe_through :green_ash_browser

                    green_ash "/cli"
                  end
                end
                """
              end

            {:ok, Igniter.Code.Common.add_code(zipper, code, placement: :after)}

          _ ->
            {:ok, zipper}
        end
      end)
    end
  end
else
  defmodule Mix.Tasks.GreenAsh.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'green_ash.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
