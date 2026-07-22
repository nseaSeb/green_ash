defmodule GreenAsh.Live.Screen do
  @moduledoc """
  Generic engine: renders an executable entry screen for ONE Ash action,
  entirely through introspection. The resource/action come from the route;
  the fields are inferred by `GreenAsh.Field` and the form by
  `AshPhoenix.Form`. An `:id` (PK token) loads a record for an update action.
  """
  use GreenAsh.Web, :live_view

  @impl true
  def mount(%{"resource" => slug} = params, _session, socket) do
    %{domains: domains, base: base, actor: actor, tenant: tenant} = socket.assigns

    with {:ok, resource} <- fetch_resource(domains, slug),
         :ok <- check_tenant(resource, tenant),
         {:ok, action} <- fetch_action(resource, params["action"]) do
      mount_action(socket, resource, action, params, actor, base)
    else
      :no_resource ->
        {:ok, push_navigate(socket, to: base)}

      {:notice, notice} ->
        # Escape leads to the menu, not to the list: for a tenant-required
        # resource the list is just as unopenable, so return_to would
        # otherwise bounce between screens.
        {:ok, assign(socket, notice: notice, return_to: base)}
    end
  end

  defp fetch_resource(domains, slug) do
    case Registry.resource_by_slug(domains, slug) do
      nil -> :no_resource
      resource -> {:ok, resource}
    end
  end

  # Only a refusal while no tenant is set: with one, the resource behaves like
  # any other.
  defp check_tenant(resource, tenant) do
    if Registry.tenant_required?(resource) and is_nil(tenant),
      do: {:notice, tenant_notice(resource)},
      else: :ok
  end

  # An action name from the URL that matches none leaves `action` nil, which
  # `Field.specs/2` cannot take — a raise inside `mount/3`, i.e. a 500.
  defp fetch_action(resource, name) do
    case Registry.action(resource, name) do
      nil -> {:notice, no_action_notice(resource, name)}
      action -> {:ok, action}
    end
  end

  defp mount_action(socket, resource, action, params, actor, base) do
    tenant = socket.assigns.tenant

    case load_subject(resource, params["id"], actor, tenant) do
      {:ok, subject} ->
        {:ok,
         socket
         |> assign(
           resource: resource,
           action: action,
           subject: subject,
           specs: resource |> Field.specs(action) |> Field.with_options(actor, tenant),
           result: nil,
           debug: false,
           message: socket.assigns.actor_notice || "",
           return_to: return_to(resource, base, socket.assigns.domains)
         )
         |> assign(form: fresh_form(subject, action, actor, tenant))}

      :error ->
        {:ok, push_navigate(socket, to: return_to(resource, base, socket.assigns.domains))}
    end
  end

  defp load_subject(resource, nil, _actor, _tenant), do: {:ok, resource}

  defp load_subject(resource, token, actor, tenant) do
    with {:ok, id} <- Registry.decode_pk(resource, token),
         {:ok, record} <- Ash.get(resource, id, actor: actor, tenant: tenant) do
      {:ok, record}
    else
      _ -> :error
    end
  end

  defp return_to(resource, base, domains) do
    case Ash.Resource.Info.primary_action(resource, :read) do
      nil -> base
      read -> ga_path(base, "/r/#{Registry.resource_slug(resource, domains)}/list/#{read.name}")
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
             form:
               fresh_form(
                 socket.assigns.subject,
                 socket.assigns.action,
                 socket.assigns.actor,
                 socket.assigns.tenant
               )
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

  # subject = the resource (create) or the loaded record (update/destroy).
  defp fresh_form(subject, action, actor, tenant) do
    subject |> AshPhoenix.Form.for_action(action.name, actor: actor, tenant: tenant) |> to_form()
  end

  defp ash_form(%Phoenix.HTML.Form{source: %AshPhoenix.Form{} = f}), do: f
  defp ash_form(%AshPhoenix.Form{} = f), do: f

  defp select_prompt(%{allow_nil?: true}), do: "—"
  defp select_prompt(_), do: nil

  @impl true
  def render(%{notice: _} = assigns) do
    ~H"""
    <.notice notice={@notice} />
    """
  end

  def render(assigns) do
    ~H"""
    <.styles />
    <div class="crt" phx-window-keydown="keydown" phx-key="Escape">
      <div class="crt-head">
        <span>GREEN·ASH / {String.upcase(short(@resource))}</span>
        <span class="crt-title">{Registry.action_label(@action)}</span>
        <span>◆ {Actor.label(@actor)}{tenant_suffix(@tenant)} · {@action.name} · {@action.type}</span>
      </div>
      <div class="crt-rule"></div>

      <div class="crt-body">
        <p class="crt-lead">Fill in the fields, then press Enter to execute.</p>

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
            <.button type="submit">Execute ⏎</.button>
            <button type="button" phx-click="toggle-debug" class="crt-linkbtn">
              debug: {if @debug, do: "on", else: "off"}
            </button>
          </div>
        </.form>

        <div :if={@result} style="margin-top:1.2rem">
          <%= case @result do %>
            <% {:ok, record} -> %>
              <div class="crt-ok">✔ OK — {short(@resource)} · {@action.name} executed.</div>
              <pre :if={@debug} class="crt-pre">{inspect(record, pretty: true, limit: :infinity)}</pre>
            <% :error -> %>
              <div class="crt-err">✘ Failed — see the field errors.</div>
              <pre :if={@debug} class="crt-pre">{inspect(AshPhoenix.Form.errors(ash_form(@form)), pretty: true)}</pre>
          <% end %>
        </div>

        <pre :if={@debug} class="crt-pre">params: {inspect(AshPhoenix.Form.params(ash_form(@form)), pretty: true)}</pre>
      </div>

      <div class="crt-foot">
        <div class="crt-rule"></div>
        <div class="crt-msg">{@message}</div>
        <form phx-submit="command" class="crt-cmd" autocomplete="off">
          <label>Command ===></label>
          <input type="text" name="cmd" value="" id="cmd" />
        </form>
        <div class="crt-keys">
          <b>Enter</b>=Execute &nbsp;·&nbsp; <b>Esc</b>=Back &nbsp;·&nbsp; <b>:debug</b>
          <b>:menu</b> <b>:help</b>
        </div>
      </div>
    </div>
    """
  end

  defp short(module), do: module |> Module.split() |> List.last()

  defp label(%{kind: :argument} = spec), do: spec.label <> " (arg)"

  # A picker is showing related records, so name the relationship rather than
  # the column it writes to: "Account", not "Account id".
  defp label(%{relationship: rel, input_type: "select"}) when not is_nil(rel),
    do: rel.name |> Phoenix.Naming.humanize() |> to_string()

  defp label(spec), do: spec.label
end
