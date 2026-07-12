defmodule BuisWeb.CliLive.Subfile do
  @moduledoc """
  Subfile AS400 : liste des enregistrements retournés par une action `:read`,
  avec une colonne "Opt" par ligne. Les codes d'option (2/3/6…=actions update,
  4=destroy, 5=afficher) sont dérivés par introspection des actions de la
  resource — aucune connaissance spécifique n'est codée ici.

  Saisir un code puis Entrée exécute l'action sur la ligne : les destroy/afficher
  s'appliquent en place, une action update (qui demande des arguments) ouvre
  l'écran de saisie (`BuisWeb.CliLive.Screen`) pour l'enregistrement choisi.
  """
  use BuisWeb, :live_view

  alias BuisWeb.Cli.Registry
  alias BuisWeb.CliLive.{Command, UI}

  @limit 200

  @impl true
  def mount(%{"resource" => slug, "action" => action_name}, _session, socket) do
    case Registry.resource_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/cli")}

      resource ->
        action = Registry.action(resource, action_name)

        {:ok,
         socket
         |> assign(
           resource: resource,
           action: action,
           pk: primary_key_field(resource),
           codes: build_codes(resource),
           columns: Enum.map(Ash.Resource.Info.public_attributes(resource), & &1.name),
           expanded: MapSet.new(),
           confirm: [],
           message: ""
         )
         |> load_rows(), layout: false}
    end
  end

  # Champ de clé primaire (on gère la PK simple ; sinon le 1er champ).
  defp primary_key_field(resource) do
    resource |> Ash.Resource.Info.primary_key() |> List.first()
  end

  defp load_rows(socket) do
    rows =
      socket.assigns.resource
      |> Ash.Query.for_read(socket.assigns.action.name)
      |> Ash.Query.limit(@limit)
      |> Ash.read!()

    assign(socket, rows: rows)
  end

  # Codes d'option applicables à une ligne, dérivés des actions de la resource.
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
  def handle_event("process", %{"opt" => opts}, socket) do
    entries =
      for {id, code} <- opts, trimmed = String.trim(code), trimmed != "", do: {id, trimmed}

    process(entries, socket)
  end

  def handle_event("process", _params, socket), do: {:noreply, socket}

  def handle_event("destroy-confirm", _params, socket) do
    done =
      Enum.count(socket.assigns.confirm, fn {id, action} ->
        case Ash.get(socket.assigns.resource, id) do
          {:ok, record} -> match?(:ok, Ash.destroy(record, action: action))
          _ -> false
        end
      end)

    {:noreply,
     socket
     |> assign(confirm: [], message: "#{done} suppression(s) effectuée(s).")
     |> load_rows()}
  end

  def handle_event("destroy-cancel", _params, socket),
    do: {:noreply, assign(socket, confirm: [], message: "Suppression annulée.")}

  def handle_event("command", %{"cmd" => cmd}, socket) do
    case Command.parse(cmd) do
      {:navigate, path} ->
        {:noreply, push_navigate(socket, to: path)}

      {:message, msg} ->
        {:noreply, assign(socket, message: msg)}

      :toggle_debug ->
        {:noreply,
         assign(socket, message: "Utilisez l'option 5 pour afficher un enregistrement.")}

      :noop ->
        {:noreply, socket}

      :not_command ->
        {:noreply, assign(socket, message: "Utilisez « : » pour une commande. #{Command.help()}")}
    end
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/cli")}

  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  defp process([], socket),
    do: {:noreply, assign(socket, message: "Aucune option saisie.")}

  defp process(entries, socket) do
    codes = socket.assigns.codes
    resolved = Enum.map(entries, fn {id, code} -> {id, Enum.find(codes, &(&1.code == code))} end)

    unknown = for {_id, nil} <- resolved, do: :x
    displays = for {id, %{kind: :display}} <- resolved, do: id
    destroys = for {id, %{kind: :destroy, action: a}} <- resolved, do: {id, a}

    update =
      Enum.find_value(resolved, fn
        {id, %{kind: :update, action: a}} -> {id, a}
        _ -> nil
      end)

    cond do
      # Les suppressions passent par un écran de confirmation (façon AS400).
      destroys != [] ->
        {:noreply, assign(socket, confirm: destroys, message: "Confirmez la suppression.")}

      update ->
        {id, action} = update

        {:noreply,
         push_navigate(socket,
           to: ~p"/cli/r/#{Registry.resource_slug(socket.assigns.resource)}/a/#{action}/#{id}"
         )}

      true ->
        {:noreply,
         socket
         |> assign(expanded: MapSet.new(displays), message: message([], displays, unknown))
         |> load_rows()}
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

  @impl true
  def render(assigns) do
    ~H"""
    <UI.styles />
    <div class="crt" phx-window-keydown="keydown" phx-key="Escape">
      <div class="crt-head">
        <span>BUIS / {String.upcase(Registry.resource_label(@resource))}</span>
        <span class="crt-title">LISTE · {Registry.resource_title(@resource)}</span>
        <span>{today()}</span>
      </div>
      <div class="crt-rule"></div>

      <div class="crt-body">
        <div :if={@confirm != []} class="crt-confirm">
          <p class="crt-err">
            ⚠ Confirmer la suppression de {length(@confirm)} enregistrement(s) ?
          </p>
          <button phx-click="destroy-confirm" class="btn">Confirmer</button>
          <button type="button" phx-click="destroy-cancel" class="crt-linkbtn">Annuler</button>
        </div>

        <p class="crt-legend">
          Opt : <span :for={c <- @codes}><b>{c.code}</b>={c.label} &nbsp;</span>
        </p>

        <form phx-submit="process">
          <table class="sf">
            <thead>
              <tr>
                <th>Opt</th>
                <th :for={col <- @columns}>{Phoenix.Naming.humanize(col)}</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @rows do %>
                <tr class={expanded?(@expanded, row, @pk) && "exp"}>
                  <td>
                    <input
                      class="sf-opt"
                      name={"opt[#{Map.get(row, @pk)}]"}
                      maxlength="2"
                      autocomplete="off"
                    />
                  </td>
                  <td :for={col <- @columns}>{cell(row, col)}</td>
                </tr>
                <tr :if={expanded?(@expanded, row, @pk)} class="exp">
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
      </div>

      <div class="crt-foot">
        <div class="crt-rule"></div>
        <div class="crt-msg">{@message}</div>
        <form phx-submit="command" class="crt-cmd" autocomplete="off">
          <label>Commande ===></label>
          <input type="text" name="cmd" value="" id="cmd" />
        </form>
        <div class="crt-keys">
          <b>Entrée</b>=Valider les options &nbsp;·&nbsp; <b>Échap</b>=Retour au menu &nbsp;·&nbsp;
          <b>:menu</b> <b>:help</b>
        </div>
      </div>
    </div>
    """
  end

  defp expanded?(set, row, pk), do: MapSet.member?(set, to_string(Map.get(row, pk)))

  defp cell(row, col), do: row |> Map.get(col) |> fmt() |> truncate()

  # Tronque les longues valeurs (ex. UUID) pour garder l'alignement colonne.
  defp truncate(s) when byte_size(s) > 12, do: String.slice(s, 0, 11) <> "…"
  defp truncate(s), do: s

  defp fmt(nil), do: ""
  defp fmt(%Decimal{} = d), do: Decimal.to_string(d)
  defp fmt(%Date{} = d), do: Date.to_iso8601(d)
  defp fmt(%DateTime{} = d), do: Calendar.strftime(d, "%d/%m/%y %H:%M")
  defp fmt(v) when is_atom(v) or is_binary(v), do: to_string(v)
  defp fmt(v), do: inspect(v)

  defp today, do: Calendar.strftime(Date.utc_today(), "%d/%m/%y")
end
