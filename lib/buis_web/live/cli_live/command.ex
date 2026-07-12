defmodule BuisWeb.CliLive.Command do
  @moduledoc """
  Parseur des commandes de la ligne `:` (façon Vim), partagé par tous les écrans
  de la console. Il ne fait qu'interpréter une saisie en une directive ; c'est la
  LiveView appelante qui l'applique (navigation, toggle, message).

  Directives renvoyées :
    * `{:navigate, path}` — pousser une navigation live ;
    * `{:redirect, path}` — redirection HTTP complète (pour écrire la session) ;
    * `{:message, texte}` — afficher un message de statut ;
    * `:toggle_debug`     — basculer le mode debug (si l'écran le supporte) ;
    * `:whoami`           — le caller affiche l'acteur courant ;
    * `:noop`             — ne rien faire ;
    * `:not_command`      — l'entrée ne commence pas par `:` (au caller de décider).
  """
  alias BuisWeb.Cli.{Actor, Registry}

  @help "Commandes : :menu  :list <r>  :new <r>  :actor <r> <id>  :actor none  :whoami  :debug  :help  :q"

  def help, do: @help

  @doc """
  Interprète et applique une saisie sur le `socket`, en renvoyant `{:noreply, socket}`.

  Options (callbacks pour les cas propres à chaque écran) :
    * `:on_debug` — `fn socket -> {:noreply, socket} end` (défaut : message) ;
    * `:on_other` — `fn input, socket -> {:noreply, socket} end` pour une entrée
      non préfixée par `:` (défaut : message d'aide).
  """
  def apply_to(socket, input, opts \\ []) do
    on_debug = Keyword.get(opts, :on_debug, &default_debug/1)
    on_other = Keyword.get(opts, :on_other, &default_other/2)

    case parse(input) do
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

  @doc "Interprète une saisie de la ligne de commande."
  def parse(input) when is_binary(input) do
    case String.trim(input) do
      ":" <> rest -> dispatch(rest |> String.trim() |> String.split(~r/\s+/, trim: true))
      _ -> :not_command
    end
  end

  defp dispatch([]), do: :noop
  defp dispatch([cmd | args]), do: command(cmd, args)

  defp command(c, _) when c in ~w(q quit menu m), do: {:navigate, "/cli"}
  defp command("debug", _), do: :toggle_debug
  defp command(c, _) when c in ~w(whoami who), do: :whoami
  defp command(c, _) when c in ~w(help h ?), do: {:message, @help}

  defp command("actor", ["none"]), do: {:redirect, "/cli/actor?return=%2Fcli"}

  defp command("actor", [slug, id]),
    do: {:redirect, "/cli/actor?slug=#{URI.encode(slug)}&id=#{URI.encode(id)}&return=%2Fcli"}

  defp command("actor", _),
    do: {:message, "Usage : :actor <resource> <id>  |  :actor none"}

  defp command(c, [slug]) when c in ~w(list ls l) do
    with_resource(slug, fn resource ->
      case Ash.Resource.Info.primary_action(resource, :read) do
        nil -> {:message, "Pas de read primaire pour #{slug}."}
        read -> {:navigate, "/cli/r/#{Registry.resource_slug(resource)}/list/#{read.name}"}
      end
    end)
  end

  defp command(c, [slug]) when c in ~w(new open create) do
    with_resource(slug, fn resource ->
      case Ash.Resource.Info.primary_action(resource, :create) do
        nil -> {:message, "Pas de create primaire pour #{slug}."}
        create -> {:navigate, "/cli/r/#{Registry.resource_slug(resource)}/a/#{create.name}"}
      end
    end)
  end

  defp command(cmd, _args), do: {:message, "Commande inconnue : :#{cmd} — #{@help}"}

  defp with_resource(slug, fun) do
    case Registry.resource_by_slug(slug) do
      nil -> {:message, "Resource inconnue : #{slug}"}
      resource -> fun.(resource)
    end
  end
end
