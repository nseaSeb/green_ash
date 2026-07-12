defmodule GreenAsh.Live.Screen do
  @moduledoc """
  Moteur générique : rend un écran de saisie exécutable pour UNE action Ash,
  entièrement par introspection. La resource/action viennent de la route ; les
  champs sont déduits par `GreenAsh.Field` et le formulaire par `AshPhoenix.Form`.
  Un `:id` (token de PK) charge un enregistrement pour une action update.
  """
  use GreenAsh.Web, :live_view

  @impl true
  def mount(%{"resource" => slug} = params, _session, socket) do
    %{domains: domains, base: base, actor: actor} = socket.assigns

    case Registry.resource_by_slug(domains, slug) do
      nil ->
        {:ok, push_navigate(socket, to: base)}

      resource ->
        action = Registry.action(resource, params["action"])

        case load_subject(resource, params["id"], actor) do
          {:ok, subject} ->
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
               return_to: return_to(resource, base)
             )
             |> assign(form: fresh_form(subject, action, actor))}

          :error ->
            {:ok, push_navigate(socket, to: return_to(resource, base))}
        end
    end
  end

  defp load_subject(resource, nil, _actor), do: {:ok, resource}

  defp load_subject(resource, token, actor) do
    with {:ok, id} <- Registry.decode_pk(resource, token),
         {:ok, record} <- Ash.get(resource, id, actor: actor) do
      {:ok, record}
    else
      _ -> :error
    end
  end

  defp return_to(resource, base) do
    case Ash.Resource.Info.primary_action(resource, :read) do
      nil -> base
      read -> ga_path(base, "/r/#{Registry.resource_slug(resource)}/list/#{read.name}")
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
        if socket.assigns.action.type == :create do
          {:noreply,
           socket
           |> assign(result: {:ok, result})
           |> assign(
             form: fresh_form(socket.assigns.subject, socket.assigns.action, socket.assigns.actor)
           )}
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
    Command.apply_to(socket, cmd,
      on_debug: fn s -> {:noreply, assign(s, debug: !s.assigns.debug)} end
    )
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket),
    do: {:noreply, push_navigate(socket, to: socket.assigns.return_to)}

  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  # subject = la resource (create) ou l'enregistrement chargé (update/destroy).
  defp fresh_form(subject, action, actor) do
    subject |> AshPhoenix.Form.for_action(action.name, actor: actor) |> to_form()
  end

  defp ash_form(%Phoenix.HTML.Form{source: %AshPhoenix.Form{} = f}), do: f
  defp ash_form(%AshPhoenix.Form{} = f), do: f

  defp select_prompt(%{allow_nil?: true}), do: "—"
  defp select_prompt(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.styles />
    <div class="crt" phx-window-keydown="keydown" phx-key="Escape">
      <div class="crt-head">
        <span>GREEN·ASH / {String.upcase(short(@resource))}</span>
        <span class="crt-title">{Registry.action_label(@action)}</span>
        <span>◆ {Actor.label(@actor)} · {@action.name} · {@action.type}</span>
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
            <.button type="submit">Exécuter ⏎</.button>
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
          <b>Entrée</b>=Exécuter &nbsp;·&nbsp; <b>Échap</b>=Retour &nbsp;·&nbsp; <b>:debug</b>
          <b>:menu</b> <b>:help</b>
        </div>
      </div>
    </div>
    """
  end

  defp short(module), do: module |> Module.split() |> List.last()

  defp label(%{kind: :argument} = spec), do: spec.label <> " (arg)"
  defp label(spec), do: spec.label
end
