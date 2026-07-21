defmodule GreenAsh.ColumnsTest do
  @moduledoc """
  Which columns a list shows, and how wide a cell may be.

  Lists rendered every public attribute at a fixed width of twelve, which on
  any real resource meant a wall of truncated stubs. The choice is made from
  the console now (`:cols`) and kept in the URL, so a narrowed screen can be
  bookmarked like any other.
  """
  use ExUnit.Case, async: true

  alias GreenAsh.Live.Subfile
  alias GreenAsh.TestSupport.{Account, Bank}

  @domains [Bank]

  defp socket do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        domains: @domains,
        base: "/cli",
        actor: nil,
        actor_notice: nil
      }
    }
  end

  defp visit(params) do
    {:ok, socket} = Subfile.mount(%{"resource" => "account", "action" => "read"}, %{}, socket())
    {:noreply, socket} = Subfile.handle_params(params, "/cli", socket)
    socket
  end

  defp command(socket, cmd) do
    {:noreply, socket} = Subfile.handle_event("command", %{"cmd" => cmd}, socket)
    socket
  end

  defp patched_to(socket) do
    {:live, :patch, %{to: to}} = socket.redirected
    to
  end

  defp render(socket) do
    socket.assigns
    |> Map.put(:__changed__, nil)
    |> Subfile.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "choosing the columns" do
    test "every public attribute is shown by default" do
      socket = visit(%{})

      assert socket.assigns.columns == socket.assigns.all_columns
      assert :holder in socket.assigns.columns
      assert :balance in socket.assigns.columns
    end

    test ":cols narrows the list, in the order given" do
      socket = visit(%{}) |> command(":cols balance holder")

      assert patched_to(socket) == "/cli/r/account/list/read?cols=balance%2Cholder"
    end

    test "the order asked for is the order rendered" do
      socket = visit(%{"cols" => "balance,holder"})

      assert socket.assigns.columns == [:balance, :holder]
      # Not the declaration order, which puts holder first.
      assert socket.assigns.all_columns |> Enum.take(2) == [:id, :holder]
    end

    test "a narrowed list renders only those headers" do
      html = visit(%{"cols" => "holder"}) |> render()

      assert html =~ "Holder"
      refute html =~ "Opened on"
    end

    test ":cols all restores them, and says nothing in the URL" do
      socket = visit(%{"cols" => "holder"}) |> command(":cols all")

      assert patched_to(socket) == "/cli/r/account/list/read"
    end

    test ":cols with no argument lists what is on offer, and patches nothing" do
      socket = visit(%{}) |> command(":cols")

      assert socket.assigns.message =~ "holder"
      assert socket.assigns.message =~ "balance"
      assert socket.redirected == nil
    end

    test "a typo is named back rather than silently dropped" do
      socket = visit(%{}) |> command(":cols holder blaance")

      assert socket.assigns.message =~ "No such column: blaance"
      # And nothing changed: a half-applied column list would be worse than none.
      assert socket.redirected == nil
    end
  end

  describe "columns from the URL" do
    test "an unknown column in the query is dropped, not obeyed" do
      assert visit(%{"cols" => "holder,not_a_column"}).assigns.columns == [:holder]
    end

    test "a query naming nothing valid falls back to every column" do
      # A bare screen would look broken; a full one merely ignores a stale link.
      socket = visit(%{"cols" => "gone,also_gone"})

      assert socket.assigns.columns == socket.assigns.all_columns
    end

    test "the sort survives a column being hidden" do
      # Sorting by something you have hidden is reasonable; dropping the sort
      # would look like the sort had failed.
      socket = visit(%{"cols" => "holder", "sort" => "balance:desc"})

      assert socket.assigns.columns == [:holder]
      assert socket.assigns.sort == {:balance, :desc}
    end

    test "the columns survive paging and sorting" do
      to =
        %{"cols" => "holder,balance"}
        |> visit()
        |> then(&elem(Subfile.handle_event("sort", %{"col" => "holder"}, &1), 1))
        |> patched_to()

      assert to =~ "cols=holder%2Cbalance"
      assert to =~ "sort=holder%3Aasc"
    end
  end

  describe "cell width" do
    setup do
      Account
      |> Ash.Changeset.for_create(:open, %{
        holder: "Éléonore de la Rochefoucauld",
        initial_deposit: Decimal.new("1")
      })
      |> Ash.create!()

      :ok
    end

    test "a long value is cut at 24 characters, not 12" do
      html = visit(%{"cols" => "holder"}) |> render()

      assert html =~ "Éléonore de la Rochefou…"
      refute html =~ "Éléonore de…"
    end

    test "the cut counts characters, not bytes" do
      # "Éléonore de la Rochefoucauld" is 28 characters but 32 bytes: a
      # byte-based cut lands mid-word and disagrees with the width shown for
      # unaccented text of the same length.
      html = visit(%{"cols" => "holder"}) |> render()

      [_, shown] = Regex.run(~r|<td[^>]*>\s*([^<]*…)\s*</td>|, html)
      assert String.length(String.trim(shown)) == 24
      assert byte_size(String.trim(shown)) > 24
    end

    test "the full value stays reachable as the cell's title" do
      html = visit(%{"cols" => "holder"}) |> render()

      assert html =~ ~s(title="Éléonore de la Rochefoucauld")
    end

    test "a value that fits is left alone" do
      html = visit(%{"cols" => "status"}) |> render()

      refute html =~ "…"
    end
  end
end
