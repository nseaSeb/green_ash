defmodule GreenAsh.Live.Menu do
  @moduledoc """
  Menu principal, façon AS400 : plein écran, options numérotées, ligne de
  commande `Option ===>` et navigation clavier. Deux niveaux découverts
  automatiquement (resources -> actions). Une action `:create` ouvre l'écran de
  saisie, `:read` une liste ; `:update`/`:destroy` renvoient vers une liste.
  """
  use GreenAsh.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(level: :main, resource: nil, message: "") |> assign_options()}
  end

  @impl true
  def handle_event("command", %{"cmd" => cmd}, socket) do
    Command.apply_to(socket, cmd,
      on_other: fn input, s -> select(String.trim(input), s) end,
      on_debug: fn s ->
        {:noreply, assign(s, message: "Le mode debug est sur l'écran d'action.")}
      end
    )
  end

  def handle_event("select", %{"n" => n}, socket), do: select(n, socket)

  def handle_event("keydown", %{"key" => "Escape"}, socket), do: {:noreply, back(socket)}
  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  defp select("", socket), do: {:noreply, socket}
  defp select("0", socket), do: {:noreply, back(socket)}

  defp select(input, socket) do
    case Integer.parse(input) do
      {n, ""} -> dispatch(Enum.find(socket.assigns.options, &(&1.n == n)), socket)
      _ -> {:noreply, assign(socket, message: "Commande non reconnue : #{input}")}
    end
  end

  defp dispatch(nil, socket), do: {:noreply, assign(socket, message: "Option invalide.")}

  defp dispatch(%{target: {:resource, resource}}, socket) do
    {:noreply,
     socket |> assign(level: :resource, resource: resource, message: "") |> assign_options()}
  end

  defp dispatch(%{target: {:action, resource, name, :create}}, socket) do
    {:noreply,
     push_navigate(socket,
       to: ga_path(socket.assigns.base, "/r/#{Registry.resource_slug(resource)}/a/#{name}")
     )}
  end

  defp dispatch(%{target: {:action, resource, name, :read}}, socket) do
    {:noreply,
     push_navigate(socket,
       to: ga_path(socket.assigns.base, "/r/#{Registry.resource_slug(resource)}/list/#{name}")
     )}
  end

  defp dispatch(%{target: {:action, _resource, name, type}}, socket)
       when type in [:update, :destroy] do
    {:noreply,
     assign(socket,
       message:
         "« #{name} » (#{type}) s'exécute sur un enregistrement : ouvrez une liste (option Read)."
     )}
  end

  defp back(%{assigns: %{level: :resource}} = socket) do
    socket |> assign(level: :main, resource: nil, message: "") |> assign_options()
  end

  defp back(socket), do: socket

  defp assign_options(%{assigns: %{level: :main, domains: domains}} = socket) do
    options =
      domains
      |> Registry.resources()
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

  @impl true
  def render(assigns) do
    ~H"""
    <.styles />
    <div class="crt" phx-window-keydown="keydown" phx-key="Escape">
      <div class="crt-head">
        <span>GREEN·ASH / {program(assigns)}</span>
        <span class="crt-title">{title(assigns)}</span>
        <span>◆ {Actor.label(@actor)} · {today()}</span>
      </div>
      <div class="crt-rule"></div>

      <div class="crt-body">
        <p class="crt-lead">Sélectionnez une option, puis appuyez sur Entrée.</p>

        <div :for={opt <- @options} class="crt-opt" phx-click="select" phx-value-n={opt.n}>
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
