defmodule BuisWeb.CliLive.Menu do
  @moduledoc """
  Menu principal de la console, façon AS400 : plein écran, options numérotées,
  ligne de commande `Option ===>` et navigation clavier.

  Deux niveaux, découverts automatiquement via `BuisWeb.Cli.Registry` :
    * MAIN     : la liste des resources Ash exposées ;
    * RESOURCE : la liste des actions de la resource sélectionnée.

  Selon le type d'action choisie : `:create` -> écran de saisie
  (`BuisWeb.CliLive.Screen`), `:read` -> liste (`BuisWeb.CliLive.Subfile`),
  `:update`/`:destroy` -> renvoi vers une liste (ils s'exécutent sur un
  enregistrement sélectionné). Une ligne de commande `:` (façon Vim) complète
  la sélection numérotée.
  """
  use BuisWeb, :live_view

  alias BuisWeb.Cli.Registry
  alias BuisWeb.CliLive.{Command, UI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(level: :main, resource: nil, message: "")
     |> assign_options(), layout: false}
  end

  @impl true
  def handle_event("command", %{"cmd" => cmd}, socket) do
    case Command.parse(cmd) do
      :not_command ->
        select(String.trim(cmd), socket)

      {:navigate, path} ->
        {:noreply, push_navigate(socket, to: path)}

      {:message, msg} ->
        {:noreply, assign(socket, message: msg)}

      :toggle_debug ->
        {:noreply, assign(socket, message: "Le mode debug est sur l'écran d'action.")}

      :noop ->
        {:noreply, socket}
    end
  end

  def handle_event("select", %{"n" => n}, socket), do: select(n, socket)

  def handle_event("keydown", %{"key" => "Escape"}, socket), do: {:noreply, back(socket)}
  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  # --- Sélection ------------------------------------------------------------

  defp select("", socket), do: {:noreply, socket}
  defp select("0", socket), do: {:noreply, back(socket)}

  defp select(input, socket) do
    case Integer.parse(input) do
      {n, ""} -> dispatch(Enum.find(socket.assigns.options, &(&1.n == n)), socket)
      _ -> {:noreply, assign(socket, message: "Commande non reconnue : #{input}")}
    end
  end

  defp dispatch(nil, socket),
    do: {:noreply, assign(socket, message: "Option invalide.")}

  defp dispatch(%{target: {:resource, resource}}, socket) do
    {:noreply,
     socket
     |> assign(level: :resource, resource: resource, message: "")
     |> assign_options()}
  end

  defp dispatch(%{target: {:action, resource, action_name, :create}}, socket) do
    {:noreply,
     push_navigate(socket,
       to: ~p"/cli/r/#{Registry.resource_slug(resource)}/a/#{action_name}"
     )}
  end

  defp dispatch(%{target: {:action, resource, action_name, :read}}, socket) do
    {:noreply,
     push_navigate(socket,
       to: ~p"/cli/r/#{Registry.resource_slug(resource)}/list/#{action_name}"
     )}
  end

  defp dispatch(%{target: {:action, _resource, action_name, type}}, socket)
       when type in [:update, :destroy] do
    {:noreply,
     assign(socket,
       message:
         "« #{action_name} » (#{type}) s'exécute sur un enregistrement : ouvrez une liste (option Read)."
     )}
  end

  defp back(%{assigns: %{level: :resource}} = socket) do
    socket |> assign(level: :main, resource: nil, message: "") |> assign_options()
  end

  defp back(socket), do: socket

  # --- Construction des options ---------------------------------------------

  defp assign_options(%{assigns: %{level: :main}} = socket) do
    options =
      Registry.resources()
      |> Enum.with_index(1)
      |> Enum.map(fn {resource, n} ->
        %{
          n: n,
          label: Registry.resource_title(resource),
          detail: Registry.resource_label(resource),
          target: {:resource, resource}
        }
      end)

    assign(socket, options: options)
  end

  defp assign_options(%{assigns: %{level: :resource, resource: resource}} = socket) do
    options =
      resource
      |> Registry.actions()
      |> Enum.with_index(1)
      |> Enum.map(fn {action, n} ->
        %{
          n: n,
          label: Registry.action_label(action),
          detail: "#{action.name} · #{action.type}",
          target: {:action, resource, action.name, action.type}
        }
      end)

    assign(socket, options: options)
  end

  # --- Rendu ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <UI.styles />
    <div class="crt" phx-window-keydown="keydown">
      <div class="crt-head">
        <span>BUIS / {program(assigns)}</span>
        <span class="crt-title">{title(assigns)}</span>
        <span>{today()}</span>
      </div>
      <div class="crt-rule"></div>

      <div class="crt-body">
        <p class="crt-lead">Sélectionnez une option, puis appuyez sur Entrée.</p>

        <div
          :for={opt <- @options}
          class="crt-opt"
          phx-click="select"
          phx-value-n={opt.n}
        >
          <span class="crt-num">{opt.n}.</span>
          <span>{opt.label}</span>
          <span :if={opt.detail} class="crt-detail">{opt.detail}</span>
        </div>

        <p :if={@options == []} class="crt-detail">(aucune resource exposée)</p>
      </div>

      <div class="crt-foot">
        <div class="crt-rule"></div>
        <div class="crt-msg">{@message}</div>
        <form phx-submit="command" class="crt-cmd" autocomplete="off">
          <label>Option ===></label>
          <input type="text" name="cmd" value="" id="cmd" phx-mounted={JS.focus()} />
        </form>
        <div class="crt-keys">
          <b>Entrée</b>=Valider &nbsp;·&nbsp; <b>Échap</b>/<b>0</b>=Retour &nbsp;·&nbsp; commandes
          <b>:</b>
          (ex. <b>:list account</b>, <b>:help</b>)
        </div>
      </div>
    </div>
    """
  end

  defp program(%{level: :main}), do: "MAIN"
  defp program(%{resource: resource}), do: String.upcase(Registry.resource_label(resource))

  defp title(%{level: :main}), do: "MENU PRINCIPAL"
  defp title(%{resource: resource}), do: "MENU · " <> Registry.resource_label(resource)

  defp today, do: Calendar.strftime(Date.utc_today(), "%d/%m/%y")
end
