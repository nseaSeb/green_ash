defmodule GreenAsh do
  @moduledoc """
  GreenAsh — une console de test « écran vert » (LiveView, 100 % clavier, style
  AS400) générée par introspection depuis vos resources Ash, sans code d'UI.

  Montez-la dans votre routeur :

      import GreenAsh.Router

      scope "/" do
        pipe_through :browser
        green_ash "/cli", domains: [MyApp.Bank]
      end

  Voir `GreenAsh.Router` pour les options.
  """
end
