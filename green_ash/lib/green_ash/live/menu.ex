defmodule GreenAsh.Live.Menu do
  @moduledoc """
  Main menu, AS400-style: full screen, numbered options, `Option ===>`
  command line, and keyboard navigation. Two levels discovered automatically
  (resources -> actions). A `:create` action opens the entry screen, `:read`
  opens a list; `:update`/`:destroy` redirect to a list.
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
        {:noreply, assign(s, message: "Debug mode is on the action screen.")}
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
      _ -> {:noreply, assign(socket, message: "Command not recognized: #{input}")}
    end
  end

  defp dispatch(nil, socket), do: {:noreply, assign(socket, message: "Invalid option.")}

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
       message: "\"#{name}\" (#{type}) runs on a record: open a list (Read option)."
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
        <p class="crt-lead">Select an option, then press Enter.</p>

        <div :for={opt <- @options} class="crt-opt" phx-click="select" phx-value-n={opt.n}>
          <span class="crt-num">{opt.n}.</span>
          <span>{opt.label}</span>
          <span :if={opt.detail} class="crt-detail">{opt.detail}</span>
        </div>

        <p :if={@options == []} class="crt-detail">(no resource exposed)</p>
      </div>

      <div class="crt-foot">
        <div class="crt-rule"></div>
        <div class="crt-msg">{@message}</div>
        <form phx-submit="command" class="crt-cmd" autocomplete="off">
          <label>Option ===></label>
          <input type="text" name="cmd" value="" id="cmd" phx-mounted={JS.focus()} />
        </form>
        <div class="crt-keys">
          <b>Enter</b>=Confirm &nbsp;·&nbsp; <b>Esc</b>/<b>0</b>=Back &nbsp;·&nbsp; commands <b>:</b>
          (e.g. <b>:list account</b>, <b>:help</b>)
        </div>
      </div>
    </div>
    """
  end

  defp program(%{level: :main}), do: "MAIN"
  defp program(%{resource: resource}), do: String.upcase(Registry.resource_label(resource))

  defp title(%{level: :main}), do: "MAIN MENU"
  defp title(%{resource: resource}), do: "MENU · " <> Registry.resource_label(resource)

  defp today, do: Calendar.strftime(Date.utc_today(), "%d/%m/%y")
end
