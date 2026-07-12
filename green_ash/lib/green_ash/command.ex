defmodule GreenAsh.Command do
  @moduledoc """
  Parseur + application de la ligne de commande `:` (façon Vim), partagé par
  tous les écrans. Les chemins sont construits à partir de la base de montage
  (`base`) fournie par l'hôte, et les resources résolues parmi `domains`.

  Directives internes : `{:navigate, path}`, `{:redirect, path}`,
  `{:message, texte}`, `:toggle_debug`, `:whoami`, `:noop`, `:not_command`.
  """
  alias GreenAsh.{Actor, Registry}

  @help "Commandes : :menu  :list <r>  :new <r>  :actor <r> <id>  :actor none  :whoami  :debug  :help  :q"

  def help, do: @help

  @doc """
  Interprète et applique une saisie sur le `socket` (`{:noreply, socket}`).

  Lit `socket.assigns.base` et `socket.assigns.domains`. Options :
    * `:on_debug` — `fn socket -> {:noreply, socket} end` ;
    * `:on_other` — `fn input, socket -> {:noreply, socket} end` (entrée sans `:`).
  """
  def apply_to(socket, input, opts \\ []) do
    on_debug = Keyword.get(opts, :on_debug, &default_debug/1)
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
           "Acteur : " <> Actor.label(socket.assigns.actor)
         )}

      :toggle_debug ->
        on_debug.(socket)

      :noop ->
        {:noreply, socket}

      :not_command ->
        on_other.(input, socket)
    end
  end

  defp default_debug(socket),
    do: {:noreply, Phoenix.Component.assign(socket, :message, "Mode debug indisponible ici.")}

  defp default_other(_input, socket),
    do:
      {:noreply,
       Phoenix.Component.assign(socket, :message, "Utilisez « : » pour une commande. #{@help}")}

  @doc "Interprète une saisie (base de montage + domaines pour résoudre)."
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

  defp command("actor", ["none"], base, _),
    do: {:redirect, "#{base}/actor?return=#{URI.encode_www_form(base)}"}

  defp command("actor", [slug, id], base, _),
    do:
      {:redirect,
       "#{base}/actor?slug=#{URI.encode(slug)}&id=#{URI.encode(id)}&return=#{URI.encode_www_form(base)}"}

  defp command("actor", _, _, _),
    do: {:message, "Usage : :actor <resource> <id>  |  :actor none"}

  defp command(c, [slug], base, domains) when c in ~w(list ls l) do
    with_resource(domains, slug, fn resource ->
      case Ash.Resource.Info.primary_action(resource, :read) do
        nil -> {:message, "Pas de read primaire pour #{slug}."}
        read -> {:navigate, "#{base}/r/#{Registry.resource_slug(resource)}/list/#{read.name}"}
      end
    end)
  end

  defp command(c, [slug], base, domains) when c in ~w(new open create) do
    with_resource(domains, slug, fn resource ->
      case Ash.Resource.Info.primary_action(resource, :create) do
        nil -> {:message, "Pas de create primaire pour #{slug}."}
        create -> {:navigate, "#{base}/r/#{Registry.resource_slug(resource)}/a/#{create.name}"}
      end
    end)
  end

  defp command(cmd, _args, _base, _domains),
    do: {:message, "Commande inconnue : :#{cmd} — #{@help}"}

  defp with_resource(domains, slug, fun) do
    case Registry.resource_by_slug(domains, slug) do
      nil -> {:message, "Resource inconnue : #{slug}"}
      resource -> fun.(resource)
    end
  end
end
