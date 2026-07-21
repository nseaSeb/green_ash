defmodule GreenAsh.Live.Subfile do
  @moduledoc """
  AS400 subfile: lists the records of a `:read` action, with an "Opt" column
  per row (codes derived from the actions: update/destroy/display), a filter
  (arguments of the read action, on the query side), column sorting, and
  pagination. All reads/deletes pass through the current actor.
  """
  use GreenAsh.Web, :live_view

  @per_page 20

  @impl true
  def mount(%{"resource" => slug, "action" => action_name}, _session, socket) do
    with {:ok, resource} <- fetch_resource(socket, slug),
         :ok <- check_tenant(resource),
         {:ok, action} <- fetch_read_action(resource, action_name) do
      mount_rows(socket, resource, action)
    else
      # An unknown slug is the one case with nothing to say: the URL names no
      # resource, so there is no screen to head it with. The menu it is.
      :no_resource -> {:ok, push_navigate(socket, to: socket.assigns.base)}
      {:notice, notice} -> {:ok, assign(socket, notice: notice)}
    end
  end

  defp fetch_resource(socket, slug) do
    case Registry.resource_by_slug(socket.assigns.domains, slug) do
      nil -> :no_resource
      resource -> {:ok, resource}
    end
  end

  defp check_tenant(resource) do
    if Registry.tenant_required?(resource),
      do: {:notice, tenant_notice(resource)},
      else: :ok
  end

  # Both halves guard a raise: an action name from the URL that matches no
  # action leaves `action` nil (which `Field.specs/2` cannot take), and a
  # non-read action reaches `Ash.Query.for_read/4`, which rejects it.
  defp fetch_read_action(resource, name) do
    case Registry.action(resource, name) do
      nil -> {:notice, no_action_notice(resource, name)}
      %{type: :read} = action -> {:ok, action}
      action -> {:notice, not_readable_notice(resource, action)}
    end
  end

  defp mount_rows(socket, resource, action) do
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
       read_error: nil,
       message: socket.assigns.actor_notice || ""
     )
     |> assign_filter_form()
     |> load_rows()}
  end

  defp assign_filter_form(socket),
    do: assign(socket, filter_form: to_form(socket.assigns.args, as: :filter))

  # A read is the console's most failure-prone call, and every failure here is
  # a legitimate answer rather than a fault: a policy forbidding the read (the
  # very thing this console exists to exercise), or a filter value that will
  # not cast. `Ash.read!/2` turned both into a 500; the reason belongs on the
  # screen instead.
  defp load_rows(socket) do
    %{resource: resource, action: action, args: args, actor: actor, page: page, sort: sort} =
      socket.assigns

    resource
    |> Ash.Query.for_read(action.name, args, actor: actor)
    |> maybe_sort(sort)
    |> read(action, actor, page)
    |> case do
      {:ok, rows} ->
        assign(socket,
          rows: Enum.take(rows, @per_page),
          has_next: length(rows) > @per_page,
          read_error: nil
        )

      {:error, error} ->
        assign(socket, rows: [], has_next: false, read_error: read_error_message(error, actor))
    end
  end

  # One extra row is fetched to know whether a next page exists without
  # counting. A paginated action must be paged through Ash's own `:page`
  # option — it answers with an `Ash.Page.*` struct rather than a list, and
  # refuses the read outright when its pagination is `required?`.
  defp read(query, action, actor, page) do
    result =
      if Registry.paginated?(action) do
        Ash.read(query, actor: actor, page: [limit: @per_page + 1, offset: page * @per_page])
      else
        query
        |> Ash.Query.limit(@per_page + 1)
        |> Ash.Query.offset(page * @per_page)
        |> Ash.read(actor: actor)
      end

    case result do
      {:ok, %{results: rows}} -> {:ok, rows}
      {:ok, rows} when is_list(rows) -> {:ok, rows}
      {:error, error} -> {:error, error}
    end
  end

  defp read_error_message(%Ash.Error.Forbidden{}, actor) do
    "Forbidden for #{Actor.label(actor)} — this read is denied by a policy." <>
      if(is_nil(actor), do: " Set an actor with :actor <resource> <id>.", else: "")
  end

  defp read_error_message(error, _actor), do: "Read failed — " <> error_text(error)

  # Ash errors carry a multi-line breadcrumb trail; the status line holds one
  # line, so keep the messages and drop the trail.
  defp error_text(error) do
    error
    |> Map.get(:errors, [error])
    |> Enum.map_join(" · ", &condense/1)
    |> String.slice(0, 240)
  end

  defp condense(error) do
    error
    |> Exception.message()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or &1 =~ ~r/^(Bread Crumbs:|> )/))
    |> Enum.join(" ")
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
        [d | _] -> [%{code: "4", label: "Delete", kind: :destroy, action: d.name}]
        [] -> []
      end

    updates ++ destroy ++ [%{code: "5", label: "Display", kind: :display, action: nil}]
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

  # The column name comes off the wire, so it is matched against the columns
  # actually rendered rather than turned into an atom: an unknown one is
  # ignored instead of raising.
  def handle_event("sort", %{"col" => col}, socket) do
    case Enum.find(socket.assigns.columns, &(to_string(&1) == col)) do
      nil ->
        {:noreply, socket}

      field ->
        {:noreply,
         socket |> assign(sort: next_sort(socket.assigns.sort, field), page: 0) |> load_rows()}
    end
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
    do: {:noreply, assign(socket, confirm: [], message: "Deletion cancelled.")}

  def handle_event("command", %{"cmd" => cmd}, socket) do
    Command.apply_to(socket, cmd,
      on_debug: fn s ->
        {:noreply, assign(s, message: "Use option 5 to display a record.")}
      end
    )
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket),
    do: {:noreply, push_navigate(socket, to: socket.assigns.base)}

  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  defp process([], socket), do: {:noreply, assign(socket, message: "No option entered.")}

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
          if updates != [], do: " (updates ignored: handle them separately)", else: ""

        {:noreply, assign(socket, confirm: destroys, message: "Confirm the deletion." <> note)}

      length(updates) > 1 ->
        {:noreply,
         socket
         |> assign(
           expanded: display_set(displays),
           message: "Only one row can be edited at a time (#{length(updates)} selected)."
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
        "Forbidden: deletion restricted to an actor (:actor <resource> <id>)."

      forbidden? ->
        "#{done} deletion(s); others forbidden (actor required)."

      true ->
        "#{done} deletion(s) completed."
    end
  end

  defp message(destroys, displays, unknown) do
    []
    |> add(destroys != [], "#{length(destroys)} deletion(s)")
    |> add(displays != [], "#{length(displays)} display(s)")
    |> add(unknown != [], "#{length(unknown)} unknown code(s)")
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
        <span>GREEN·ASH / {String.upcase(Registry.resource_label(@resource))}</span>
        <span class="crt-title">LIST · {Registry.resource_title(@resource)}</span>
        <span>◆ {Actor.label(@actor)} · {today()}</span>
      </div>
      <div class="crt-rule"></div>

      <div class="crt-body">
        <div :if={@confirm != []} class="crt-confirm">
          <p class="crt-err">⚠ Confirm deletion of {length(@confirm)} record(s)?</p>
          <button phx-click="destroy-confirm" class="btn">Confirm</button>
          <button type="button" phx-click="destroy-cancel" class="crt-linkbtn">Cancel</button>
        </div>

        <form :if={@arg_specs != []} phx-change="filter" phx-submit="filter" class="crt-filter">
          <.input
            :for={spec <- @arg_specs}
            field={@filter_form[spec.name]}
            type={spec.input_type}
            label={"Filter — " <> spec.label}
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

          <p :if={@rows == []} class="crt-detail">(no records)</p>
          <button type="submit" class="btn" style="margin-top:.8rem">Submit ⏎</button>
        </form>

        <div class="crt-pager">
          <button
            type="button"
            class="crt-linkbtn"
            phx-click="page"
            phx-value-dir="prev"
            disabled={@page == 0}
          >
            ‹ Prev
          </button>
          <span>Page {@page + 1}</span>
          <button
            type="button"
            class="crt-linkbtn"
            phx-click="page"
            phx-value-dir="next"
            disabled={!@has_next}
          >
            Next ›
          </button>
        </div>
      </div>

      <div class="crt-foot">
        <div class="crt-rule"></div>
        <div class={["crt-msg", @read_error && "crt-err"]}>{@read_error || @message}</div>
        <form phx-submit="command" class="crt-cmd" autocomplete="off">
          <label>Command ===></label>
          <input type="text" name="cmd" value="" id="cmd" />
        </form>
        <div class="crt-keys">
          <b>Enter</b>=Submit &nbsp;·&nbsp; <b>Esc</b>=Menu &nbsp;·&nbsp;
          <b>:actor &lt;r&gt; &lt;id&gt;</b> <b>:whoami</b> <b>:help</b>
        </div>
      </div>
    </div>
    """
  end
end
