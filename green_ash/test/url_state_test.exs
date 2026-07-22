defmodule GreenAsh.UrlStateTest do
  @moduledoc """
  Filter, sort and page belong in the URL.

  They used to live only in the socket's assigns: a reload dropped you back on
  page 1 unsorted and unfiltered, and a screen could not be handed to anyone —
  the address bar said the same thing whatever you were looking at. Every one
  of these tests reaches the screen the way a pasted link would, through
  `handle_params/3`, with no prior events.
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
        tenant: nil,
        actor: nil,
        actor_notice: nil
      }
    }
  end

  defp open(holder, balance) do
    Account
    |> Ash.Changeset.for_create(:open, %{holder: holder, initial_deposit: Decimal.new(balance)})
    |> Ash.create!()
  end

  # Mounts straight from a URL's query, as LiveView does for a pasted link.
  defp visit(params, action \\ "search") do
    {:ok, socket} =
      Subfile.mount(%{"resource" => "account", "action" => action}, %{}, socket())

    {:noreply, socket} = Subfile.handle_params(params, "/cli", socket)
    socket
  end

  defp event(socket, name, params) do
    {:noreply, socket} = Subfile.handle_event(name, params, socket)
    socket
  end

  defp patched_to(socket) do
    {:live, :patch, %{to: to}} = socket.redirected
    to
  end

  defp holders(socket), do: Enum.map(socket.assigns.rows, & &1.holder)

  describe "the URL carries the screen" do
    test "a filter in the query filters, with no event fired" do
      open("Ada", "1")
      open("Grace", "2")

      assert holders(visit(%{"filter" => %{"holder" => "Ada"}})) == ["Ada"]
    end

    test "a sort in the query sorts" do
      open("Ada", "3")
      open("Grace", "1")
      open("Alan", "2")

      socket = visit(%{"sort" => "balance:desc"})

      assert holders(socket) == ["Ada", "Alan", "Grace"]
      assert socket.assigns.sort == {:balance, :desc}
    end

    test "a page in the query lands on that page" do
      for n <- 1..25, do: open("H#{String.pad_leading(to_string(n), 2, "0")}", "0")

      socket = visit(%{"page" => "2", "sort" => "holder:asc"})

      assert socket.assigns.page == 1
      assert length(socket.assigns.rows) == 5
      assert hd(holders(socket)) == "H21"
    end

    test "the three combine" do
      for n <- 1..25, do: open("H#{String.pad_leading(to_string(n), 2, "0")}", "0")
      open("Ada", "0")

      socket = visit(%{"filter" => %{"holder" => "H"}, "sort" => "holder:desc", "page" => "2"})

      assert holders(socket) |> Enum.all?(&String.starts_with?(&1, "H"))
      assert socket.assigns.page == 1
    end
  end

  describe "what the query cannot be trusted to say" do
    test "an unknown sort column is dropped, not turned into an atom" do
      open("Ada", "1")

      socket = visit(%{"sort" => "not_a_column:asc"})

      assert socket.assigns.sort == nil
      assert holders(socket) == ["Ada"]
    end

    test "a nonsense sort direction is dropped" do
      assert visit(%{"sort" => "holder:sideways"}).assigns.sort == nil
      assert visit(%{"sort" => "holder"}).assigns.sort == nil
      assert visit(%{"sort" => ""}).assigns.sort == nil
    end

    test "a nonsense page falls back to the first" do
      for value <- ["0", "-3", "abc", ""] do
        assert visit(%{"page" => value}).assigns.page == 0
      end
    end

    test "a filter that will not cast is reported, not raised" do
      socket = visit(%{"filter" => %{"holder" => %{"a" => 1}}})

      assert socket.assigns.read_error =~ "Read failed"
      assert socket.assigns.rows == []
    end
  end

  describe "the address bar keeps up with the screen" do
    test "sorting patches the URL rather than only the assigns" do
      socket = visit(%{}) |> event("sort", %{"col" => "balance"})

      assert patched_to(socket) == "/cli/r/account/list/search?sort=balance%3Aasc"
    end

    test "the sort cycles asc -> desc -> off, and the URL says so each time" do
      asc = visit(%{}) |> event("sort", %{"col" => "balance"})
      assert patched_to(asc) =~ "sort=balance%3Aasc"

      desc = visit(%{"sort" => "balance:asc"}) |> event("sort", %{"col" => "balance"})
      assert patched_to(desc) =~ "sort=balance%3Adesc"

      off = visit(%{"sort" => "balance:desc"}) |> event("sort", %{"col" => "balance"})
      refute patched_to(off) =~ "sort="
    end

    test "the first page is left out of the URL rather than spelled out" do
      # ?page=1 is noise on the commonest screen there is.
      assert patched_to(visit(%{"page" => "2"}) |> event("page", %{"dir" => "prev"})) ==
               "/cli/r/account/list/search"
    end

    test "paging keeps the filter and the sort" do
      # There has to be a second page for "next" to go anywhere.
      for n <- 1..25, do: open("Ada #{n}", "0")

      to =
        %{"filter" => %{"holder" => "Ada"}, "sort" => "balance:desc"}
        |> visit()
        |> event("page", %{"dir" => "next"})
        |> patched_to()

      assert to =~ "filter[holder]=Ada"
      assert to =~ "sort=balance%3Adesc"
      assert to =~ "page=2"
    end

    test "filtering resets to the first page, since the rows are different" do
      to =
        %{"page" => "3"}
        |> visit()
        |> event("filter", %{"filter" => %{"holder" => "Ada"}})
        |> patched_to()

      refute to =~ "page="
    end

    test "a round trip through the URL reproduces the screen" do
      for n <- 1..25, do: open("H#{String.pad_leading(to_string(n), 2, "0")}", "0")

      before = visit(%{"sort" => "holder:asc", "page" => "2"})

      # Exactly what a reload does: parse the address bar, mount again.
      query = %{"sort" => "holder:asc", "page" => "2"}
      reloaded = visit(query)

      assert holders(reloaded) == holders(before)
      assert reloaded.assigns.page == before.assigns.page
      assert reloaded.assigns.sort == before.assigns.sort
    end
  end
end
