defmodule BuisWeb.CliLive.Command do
  @moduledoc """
  Parseur des commandes de la ligne `:` (façon Vim), partagé par tous les écrans
  de la console. Il ne fait qu'interpréter une saisie en une directive ; c'est la
  LiveView appelante qui l'applique (navigation, toggle, message).

  Directives renvoyées :
    * `{:navigate, path}` — pousser une navigation live ;
    * `{:message, texte}` — afficher un message de statut ;
    * `:toggle_debug`     — basculer le mode debug (si l'écran le supporte) ;
    * `:noop`             — ne rien faire ;
    * `:not_command`      — l'entrée ne commence pas par `:` (au caller de décider).
  """
  alias BuisWeb.Cli.Registry

  @help "Commandes : :menu  :list <resource>  :new <resource>  :debug  :help  :q"

  def help, do: @help

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
  defp command(c, _) when c in ~w(help h ?), do: {:message, @help}

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
