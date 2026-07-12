defmodule GreenAsh.Live.Subfile do
  @moduledoc """
  Subfile AS400 : liste des enregistrements d'une action `:read`, avec colonne
  "Opt" par ligne (codes dérivés des actions : update/destroy/afficher), filtre
  (arguments de la read action, côté requête), tri de colonne et pagination.
  Toutes les lectures/suppressions passent l'acteur courant.
  """
  use GreenAsh.Web, :live_view

  @per_page 20

  @impl true
  def mount(%{"resource" => slug, "action" => action_name}, _session, socket) do
    case Registry.resource_by_slug(socket.assigns.domains, slug) do
      nil ->
        {:ok, push_navigate(socket, to: socket.assigns.base)}

      resource ->
        action = Registry.action(resource, action_name)

        {:ok,
         socket
         |> assign(
           resource: resource,
           action: action,
           codes: build_codes(resource),
           columns: Enum.map(Ash.Resource.Info.public_attributes(resource), & &1.name),
           arg_specs: Field.specs(resource, action),
           args: %{},
           sort: nil,
           page: 0,
           has_next: false,
           expanded: MapSet.new(),
           confirm: [],
           message: ""
         )
         |> assign_filter_form()
         |> load_rows()}
    end
  end

  defp assign_filter_form(socket),
    do: assign(socket, filter_form: to_form(socket.assigns.args, as: :filter))

  defp load_rows(socket) do
    %{resource: resource, action: action, args: args, actor: actor, page: page, sort: sort} =
      socket.assigns

    fetched =
      resource
      |> Ash.Query.for_read(action.name, args, actor: actor)
      |> maybe_sort(sort)
      |> Ash.Query.limit(@per_page + 1)
      |> Ash.Query.offset(page * @per_page)
      |> Ash.read!(actor: actor)

    assign(socket, rows: Enum.take(fetched, @per_page), has_next: length(fetched) > @per_page)
  end

  defp maybe_sort(query, nil), do: query
  defp maybe_sort(query, {field, dir}), do: Ash.Query.sort(query, [{field, dir}])

  defp build_codes(resource) do
    actions = Registry.actions(resource)

    updates =
      actions
      |> Enum.filter(&(&1.type == :update))
      |> Enum.zip(~w(2 3 6 7 8 9))
      |> Enum.map(fn {a, code} ->
        %{code: code, label: Registry.action_label(a), kind: :update, action: a.name}
      end)

    destroy =
      case Enum.filter(actions, &(&1.type == :destroy)) do
        [d | _] -> [%{code: "4", label: "Supprimer", kind: :destroy, action: d.name}]
        [] -> []
      end

    updates ++ destroy ++ [%{code: "5", label: "Afficher", kind: :display, action: nil}]
  end

  @impl true
  def handle_event("filter", %{"filter" => params}, socket) do
    {:noreply, socket |> assign(args: params, page: 0) |> assign_filter_form() |> load_rows()}
  end

  def handle_event("page", %{"dir" => "next"}, socket) do
    if socket.assigns.has_next,
      do: {:noreply, socket |> update(:page, &(&1 + 1)) |> load_rows()},
      else: {:noreply, socket}
  end

  def handle_event("page", %{"dir" => "prev"}, socket) do
    {:noreply, socket |> update(:page, &max(&1 - 1, 0)) |> load_rows()}
  end

  def handle_event("sort", %{"col" => col}, socket) do
    field = String.to_existing_atom(col)

    {:noreply,
     socket |> assign(sort: next_sort(socket.assigns.sort, field), page: 0) |> load_rows()}
  end

  def handle_event("process", %{"opt" => opts}, socket) do
    by_token = Map.new(socket.assigns.rows, &{Registry.encode_pk(&1), &1})

    entries =
      for {token, code} <- opts,
          c = String.trim(code),
          c != "",
          rec = by_token[token],
          rec != nil,
          do: {rec, c}

    process(entries, socket)
  end

  def handle_event("process", _params, socket), do: {:noreply, socket}

  def handle_event("destroy-confirm", _params, socket) do
    actor = socket.assigns.actor

    results =
      Enum.map(socket.assigns.confirm, fn {record, action} ->
        case Ash.destroy(record, action: action, actor: actor) do
          :ok -> :ok
          {:error, %Ash.Error.Forbidden{}} -> :forbidden
          _ -> :error
        end
      end)

    {:noreply, socket |> assign(confirm: [], message: destroy_message(results)) |> load_rows()}
  end

  def handle_event("destroy-cancel", _params, socket),
    do: {:noreply, assign(socket, confirm: [], message: "Suppression annulée.")}

  def handle_event("command", %{"cmd" => cmd}, socket) do
    Command.apply_to(socket, cmd,
      on_debug: fn s ->
        {:noreply, assign(s, message: "Utilisez l'option 5 pour afficher un enregistrement.")}
      end
    )
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket),
    do: {:noreply, push_navigate(socket, to: socket.assigns.base)}

  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  defp process([], socket), do: {:noreply, assign(socket, message: "Aucune option saisie.")}

  defp process(entries, socket) do
    codes = socket.assigns.codes

    resolved =
      Enum.map(entries, fn {rec, code} -> {rec, Enum.find(codes, &(&1.code == code))} end)

    unknown = for {_rec, nil} <- resolved, do: :x
    displays = for {rec, %{kind: :display}} <- resolved, do: rec
    destroys = for {rec, %{kind: :destroy, action: a}} <- resolved, do: {rec, a}
    updates = for {rec, %{kind: :update, action: a}} <- resolved, do: {rec, a}

    cond do
      destroys != [] ->
        note =
          if updates != [], do: " (modifications ignorées : traitez-les séparément)", else: ""

        {:noreply,
         assign(socket, confirm: destroys, message: "Confirmez la suppression." <> note)}

      length(updates) > 1 ->
        {:noreply,
         socket
         |> assign(
           expanded: display_set(displays),
           message: "Une seule ligne à modifier à la fois (#{length(updates)} sélectionnées)."
         )
         |> load_rows()}

      match?([_], updates) ->
        [{rec, action}] = updates
        slug = Registry.resource_slug(socket.assigns.resource)

        {:noreply,
         push_navigate(socket,
           to: ga_path(socket.assigns.base, "/r/#{slug}/a/#{action}/#{Registry.encode_pk(rec)}")
         )}

      true ->
        {:noreply,
         socket
         |> assign(expanded: display_set(displays), message: message([], displays, unknown))
         |> load_rows()}
    end
  end

  defp display_set(records), do: records |> Enum.map(&Registry.encode_pk/1) |> MapSet.new()

  defp destroy_message(results) do
    done = Enum.count(results, &(&1 == :ok))
    forbidden? = Enum.any?(results, &(&1 == :forbidden))

    cond do
      forbidden? and done == 0 ->
        "Interdit : suppression réservée à un acteur (:actor <resource> <id>)."

      forbidden? ->
        "#{done} suppression(s) ; d'autres interdites (acteur requis)."

      true ->
        "#{done} suppression(s) effectuée(s)."
    end
  end

  defp message(destroys, displays, unknown) do
    []
    |> add(destroys != [], "#{length(destroys)} suppression(s)")
    |> add(displays != [], "#{length(displays)} affichage(s)")
    |> add(unknown != [], "#{length(unknown)} code(s) inconnu(s)")
    |> case do
      [] -> ""
      parts -> Enum.join(parts, " · ")
    end
  end

  defp add(list, true, item), do: list ++ [item]
  defp add(list, false, _item), do: list

  defp next_sort({field, :asc}, field), do: {field, :desc}
  defp next_sort({field, :desc}, field), do: nil
  defp next_sort(_other, field), do: {field, :asc}

  defp sort_indicator({field, :asc}, field), do: " ▲"
  defp sort_indicator({field, :desc}, field), do: " ▼"
  defp sort_indicator(_sort, _col), do: ""

  defp expanded?(set, row), do: MapSet.member?(set, Registry.encode_pk(row))

  defp cell(row, col), do: row |> Map.get(col) |> fmt() |> truncate()

  defp truncate(s) when byte_size(s) > 12, do: String.slice(s, 0, 11) <> "…"
  defp truncate(s), do: s

  defp fmt(nil), do: ""
  defp fmt(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt(%Date{} = d), do: Date.to_iso8601(d)
  defp fmt(%DateTime{} = d), do: Calendar.strftime(d, "%d/%m/%y %H:%M")
  defp fmt(v) when is_atom(v) or is_binary(v), do: to_string(v)
  defp fmt(v), do: inspect(v)

  defp today, do: Calendar.strftime(Date.utc_today(), "%d/%m/%y")

  @impl true
  def render(assigns) do
    ~H"""
    <.styles />
    <div class="crt" phx-window-keydown="keydown" phx-key="Escape">
      <div class="crt-head">
        <span>GREEN·ASH / {String.upcase(Registry.resource_label(@resource))}</span>
        <span class="crt-title">LISTE · {Registry.resource_title(@resource)}</span>
        <span>◆ {Actor.label(@actor)} · {today()}</span>
      </div>
      <div class="crt-rule"></div>

      <div class="crt-body">
        <div :if={@confirm != []} class="crt-confirm">
          <p class="crt-err">⚠ Confirmer la suppression de {length(@confirm)} enregistrement(s) ?</p>
          <button phx-click="destroy-confirm" class="btn">Confirmer</button>
          <button type="button" phx-click="destroy-cancel" class="crt-linkbtn">Annuler</button>
        </div>

        <form :if={@arg_specs != []} phx-change="filter" phx-submit="filter" class="crt-filter">
          <.input
            :for={spec <- @arg_specs}
            field={@filter_form[spec.name]}
            type={spec.input_type}
            label={"Filtre — " <> spec.label}
            options={spec.options || []}
            prompt="—"
            {spec.rest}
          />
        </form>

        <p class="crt-legend">
          Opt : <span :for={c <- @codes}><b>{c.code}</b>={c.label} &nbsp;</span>
        </p>

        <form phx-submit="process">
          <table class="sf">
            <thead>
              <tr>
                <th>Opt</th>
                <th :for={col <- @columns} phx-click="sort" phx-value-col={col} class="sf-th">
                  {Phoenix.Naming.humanize(col)}{sort_indicator(@sort, col)}
                </th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @rows do %>
                <tr class={expanded?(@expanded, row) && "exp"}>
                  <td>
                    <input
                      class="sf-opt"
                      name={"opt[#{Registry.encode_pk(row)}]"}
                      maxlength="2"
                      autocomplete="off"
                    />
                  </td>
                  <td :for={col <- @columns}>{cell(row, col)}</td>
                </tr>
                <tr :if={expanded?(@expanded, row)} class="exp">
                  <td></td>
                  <td colspan={length(@columns)}>
                    <pre class="crt-pre">{inspect(row, pretty: true, limit: :infinity)}</pre>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>

          <p :if={@rows == []} class="crt-detail">(aucun enregistrement)</p>
          <button type="submit" class="btn" style="margin-top:.8rem">Valider ⏎</button>
        </form>

        <div class="crt-pager">
          <button
            type="button"
            class="crt-linkbtn"
            phx-click="page"
            phx-value-dir="prev"
            disabled={@page == 0}
          >
            ‹ Préc
          </button>
          <span>Page {@page + 1}</span>
          <button
            type="button"
            class="crt-linkbtn"
            phx-click="page"
            phx-value-dir="next"
            disabled={!@has_next}
          >
            Suiv ›
          </button>
        </div>
      </div>

      <div class="crt-foot">
        <div class="crt-rule"></div>
        <div class="crt-msg">{@message}</div>
        <form phx-submit="command" class="crt-cmd" autocomplete="off">
          <label>Commande ===></label>
          <input type="text" name="cmd" value="" id="cmd" />
        </form>
        <div class="crt-keys">
          <b>Entrée</b>=Valider &nbsp;·&nbsp; <b>Échap</b>=Menu &nbsp;·&nbsp;
          <b>:actor &lt;r&gt; &lt;id&gt;</b> <b>:whoami</b> <b>:help</b>
        </div>
      </div>
    </div>
    """
  end
end
