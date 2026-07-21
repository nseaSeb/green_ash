defmodule GreenAsh.Command do
  @moduledoc """
  Parser + application of the `:` command line (Vim-style), shared by all
  screens. Paths are built from the mount base (`base`) provided by the host,
  and resources are resolved among `domains`.

  Internal directives: `{:navigate, path}`, `{:redirect, path}`,
  `{:message, text}`, `{:columns, names}`, `:toggle_debug`, `:whoami`,
  `:noop`, `:not_command`.
  """
  alias GreenAsh.{Actor, Registry}

  @help "Commands: :menu  :list <r>  :new <r>  :cols <f...>  :actor <r> <id>  :actor none  :whoami  :debug  :help  :q"

  def help, do: @help

  @doc """
  Interprets and applies an input on the `socket` (`{:noreply, socket}`).

  Reads `socket.assigns.base` and `socket.assigns.domains`. Options:
    * `:on_debug` — `fn socket -> {:noreply, socket} end`;
    * `:on_columns` — `fn names, socket -> {:noreply, socket} end`;
    * `:on_other` — `fn input, socket -> {:noreply, socket} end` (input without `:`).
  """
  def apply_to(socket, input, opts \\ []) do
    on_debug = Keyword.get(opts, :on_debug, &default_debug/1)
    on_columns = Keyword.get(opts, :on_columns, &default_columns/2)
    on_other = Keyword.get(opts, :on_other, &default_other/2)
    %{base: base, domains: domains} = socket.assigns

    case parse(input, base, domains) do
      {:navigate, path} ->
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: path)}

      {:redirect, path} ->
        {:noreply, Phoenix.LiveView.redirect(socket, to: path)}

      {:message, msg} ->
        {:noreply, Phoenix.Component.assign(socket, :message, msg)}

      :whoami ->
        {:noreply,
         Phoenix.Component.assign(
           socket,
           :message,
           "Actor: " <> Actor.label(socket.assigns.actor)
         )}

      {:columns, names} ->
        on_columns.(names, socket)

      :toggle_debug ->
        on_debug.(socket)

      :noop ->
        {:noreply, socket}

      :not_command ->
        on_other.(input, socket)
    end
  end

  defp default_debug(socket),
    do: {:noreply, Phoenix.Component.assign(socket, :message, "Debug mode unavailable here.")}

  defp default_columns(_names, socket),
    do:
      {:noreply,
       Phoenix.Component.assign(socket, :message, "Columns apply to a list screen (:list <r>).")}

  defp default_other(_input, socket),
    do:
      {:noreply, Phoenix.Component.assign(socket, :message, "Use \":\" for a command. #{@help}")}

  @doc "Interprets an input (mount base + domains to resolve)."
  def parse(input, base, domains) when is_binary(input) do
    case String.trim(input) do
      ":" <> rest ->
        dispatch(rest |> String.trim() |> String.split(~r/\s+/, trim: true), base, domains)

      _ ->
        :not_command
    end
  end

  defp dispatch([], _base, _domains), do: :noop
  defp dispatch([cmd | args], base, domains), do: command(cmd, args, base, domains)

  defp command(c, _, base, _) when c in ~w(q quit menu m), do: {:navigate, base}
  defp command("debug", _, _, _), do: :toggle_debug
  defp command(c, _, _, _) when c in ~w(whoami who), do: :whoami
  defp command(c, _, _, _) when c in ~w(help h ?), do: {:message, @help}

  # Column choice belongs to whichever list screen is open, so the command only
  # carries the names; the screen validates them against what it renders.
  defp command(c, args, _base, _domains) when c in ~w(cols columns), do: {:columns, args}

  defp command("actor", ["none"], base, _),
    do: {:redirect, "#{base}/actor?return=#{URI.encode_www_form(base)}"}

  defp command("actor", [slug, id], base, _),
    do:
      {:redirect,
       "#{base}/actor?slug=#{URI.encode(slug)}&id=#{URI.encode(id)}&return=#{URI.encode_www_form(base)}"}

  defp command("actor", _, _, _),
    do: {:message, "Usage: :actor <resource> <id>  |  :actor none"}

  defp command(c, [slug], base, domains) when c in ~w(list ls l) do
    with_resource(domains, slug, fn resource ->
      case Ash.Resource.Info.primary_action(resource, :read) do
        nil ->
          {:message, "No primary read for #{slug}."}

        read ->
          {:navigate, "#{base}/r/#{Registry.resource_slug(resource, domains)}/list/#{read.name}"}
      end
    end)
  end

  defp command(c, [slug], base, domains) when c in ~w(new open create) do
    with_resource(domains, slug, fn resource ->
      case Ash.Resource.Info.primary_action(resource, :create) do
        nil ->
          {:message, "No primary create for #{slug}."}

        create ->
          {:navigate, "#{base}/r/#{Registry.resource_slug(resource, domains)}/a/#{create.name}"}
      end
    end)
  end

  defp command(cmd, _args, _base, _domains),
    do: {:message, "Unknown command: :#{cmd} — #{@help}"}

  defp with_resource(domains, slug, fun) do
    case Registry.resource_by_slug(domains, slug) do
      nil -> {:message, "Unknown resource: #{slug}"}
      resource -> fun.(resource)
    end
  end
end
