defmodule BuisWeb.CliLive.Screen do
  @moduledoc """
  Moteur générique : rend un écran de saisie exécutable pour UNE action Ash,
  entièrement par introspection (aucune connaissance spécifique de la resource).

  La resource et l'action proviennent des paramètres de route ; les champs sont
  déduits par `BuisWeb.CliLive.Field` et le formulaire par `AshPhoenix.Form`.
  """
  use BuisWeb, :live_view

  alias BuisWeb.Cli.Registry
  alias BuisWeb.CliLive.{Command, Field, UI}

  @impl true
  def mount(%{"resource" => slug} = params, _session, socket) do
    case Registry.resource_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/cli")}

      resource ->
        action = Registry.action(resource, params["action"])
        # subject = la resource (create) ou un enregistrement chargé (update/destroy).
        subject = subject(resource, params["id"])

        {:ok,
         socket
         |> assign(
           resource: resource,
           action: action,
           subject: subject,
           specs: Field.specs(resource, action),
           result: nil,
           debug: false,
           message: "",
           return_to: return_to(resource)
         )
         |> assign(form: fresh_form(subject, action)),
         layout: false}
    end
  end

  defp subject(resource, nil), do: resource
  defp subject(resource, id), do: Ash.get!(resource, id)

  # Après un update/destroy on revient à la liste (read primaire) si elle existe.
  defp return_to(resource) do
    case Ash.Resource.Info.primary_action(resource, :read) do
      nil -> ~p"/cli"
      read -> ~p"/cli/r/#{Registry.resource_slug(resource)}/list/#{read.name}"
    end
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(ash_form(socket.assigns.form), params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("submit", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(ash_form(socket.assigns.form), params: params) do
      {:ok, result} ->
        # create : on reste pour enchaîner les saisies ; sinon retour à la liste.
        if socket.assigns.action.type == :create do
          {:noreply,
           socket
           |> assign(result: {:ok, result})
           |> assign(form: fresh_form(socket.assigns.subject, socket.assigns.action))}
        else
          {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
        end

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form), result: :error)}
    end
  end

  def handle_event("toggle-debug", _params, socket),
    do: {:noreply, assign(socket, debug: !socket.assigns.debug)}

  def handle_event("command", %{"cmd" => cmd}, socket) do
    case Command.parse(cmd) do
      {:navigate, path} -> {:noreply, push_navigate(socket, to: path)}
      {:message, msg} -> {:noreply, assign(socket, message: msg)}
      :toggle_debug -> {:noreply, assign(socket, debug: !socket.assigns.debug)}
      :noop -> {:noreply, socket}
      :not_command -> {:noreply, assign(socket, message: "Utilisez « : » pour une commande. #{Command.help()}")}
    end
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/cli")}

  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  defp fresh_form(resource, action) do
    resource |> AshPhoenix.Form.for_action(action.name) |> to_form()
  end

  # AshPhoenix.Form peut être encapsulé par to_form/1 ; on récupère la source.
  defp ash_form(%Phoenix.HTML.Form{source: %AshPhoenix.Form{} = f}), do: f
  defp ash_form(%AshPhoenix.Form{} = f), do: f

  defp select_prompt(%{allow_nil?: true}), do: "—"
  defp select_prompt(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <UI.styles />
    <div class="crt" phx-window-keydown="keydown">
      <div class="crt-head">
        <span>BUIS / {String.upcase(short(@resource))}</span>
        <span class="crt-title">{Registry.action_label(@action)}</span>
        <span>{@action.name} · {@action.type}</span>
      </div>
      <div class="crt-rule"></div>

      <div class="crt-body">
        <p class="crt-lead">Renseignez les champs, puis Entrée pour exécuter.</p>

        <.form for={@form} phx-change="validate" phx-submit="submit">
          <.input
            :for={spec <- @specs}
            field={@form[spec.name]}
            type={spec.input_type}
            label={label(spec)}
            options={spec.options || []}
            prompt={select_prompt(spec)}
            {spec.rest}
          />

          <div class="crt-cmd" style="margin-top:1rem">
            <.button phx-disable-with="…">Exécuter ⏎</.button>
            <button type="button" phx-click="toggle-debug" class="crt-linkbtn">
              debug: {if @debug, do: "on", else: "off"}
            </button>
          </div>
        </.form>

        <div :if={@result} style="margin-top:1.2rem">
          <%= case @result do %>
            <% {:ok, record} -> %>
              <div class="crt-ok">✔ OK — {short(@resource)} · {@action.name} exécuté.</div>
              <pre :if={@debug} class="crt-pre">{inspect(record, pretty: true, limit: :infinity)}</pre>
            <% :error -> %>
              <div class="crt-err">✘ Échec — voir les erreurs sur les champs.</div>
              <pre :if={@debug} class="crt-pre">{inspect(AshPhoenix.Form.errors(ash_form(@form)), pretty: true)}</pre>
          <% end %>
        </div>

        <pre :if={@debug} class="crt-pre">params: {inspect(AshPhoenix.Form.params(ash_form(@form)), pretty: true)}</pre>
      </div>

      <div class="crt-foot">
        <div class="crt-rule"></div>
        <div class="crt-msg">{@message}</div>
        <form phx-submit="command" class="crt-cmd" autocomplete="off">
          <label>Commande ===></label>
          <input type="text" name="cmd" value="" id="cmd" />
        </form>
        <div class="crt-keys">
          <b>Entrée</b>=Exécuter &nbsp;·&nbsp; <b>Échap</b>=Retour au menu &nbsp;·&nbsp; <b>:debug</b> <b>:menu</b> <b>:help</b>
        </div>
      </div>
    </div>
    """
  end

  defp short(module), do: module |> Module.split() |> List.last()

  defp label(%{kind: :argument} = spec), do: spec.label <> " (arg)"
  defp label(spec), do: spec.label
end
