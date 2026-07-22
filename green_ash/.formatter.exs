[
  # Exporté vers les projets hôtes : l'installeur ajoute `import_deps:
  # [:green_ash]` à leur formateur, ce qui ne servait à rien tant que rien
  # n'était exporté. Sans ça, `mix format` chez l'utilisateur réécrit
  # `green_ash "/cli"` en `green_ash("/cli")` — et son router cesse de
  # ressembler à la documentation qu'il vient de copier.
  export: [locals_without_parens: [green_ash: 1, green_ash: 2]],
  import_deps: [:ash, :ash_phoenix, :phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{ex,exs}", "{lib,test}/**/*.{ex,exs}"]
]
