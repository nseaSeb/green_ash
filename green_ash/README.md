# GreenAsh

Une console de test « écran vert » (LiveView, 100 % clavier, style AS400) générée
par **introspection** depuis vos resources Ash — zéro code d'UI.

## Prérequis

Un projet Phoenix + Ash existant. Si vous partez de zéro :

```bash
mix archive.install hex igniter_new
mix archive.install hex phx_new
mix igniter.new mon_app --with phx.new --yes
cd mon_app
mix igniter.install ash,ash_phoenix,ash_postgres --yes
```

(En deux étapes séparées plutôt qu'en une seule commande combinée : plus
fiable en pratique.) Voir le
[Getting Started d'Ash](https://hexdocs.pm/ash/get-started.html) pour le détail.

## Installation

Avec [Igniter](https://hexdocs.pm/igniter) (recommandé — une seule commande) :

```bash
mix igniter.install green_ash
```

Ça ajoute la dépendance, **découvre automatiquement vos domaines Ash** et patche
votre routeur. Rien d'autre à écrire.

> Si vous préférez lancer `mix green_ash.install` directement (sans passer par
> `mix igniter.install`), votre projet doit déjà avoir `{:igniter, "~> 0.5", only: [:dev, :test]}`
> dans ses propres dépendances — Mix ne propage pas les dépendances `only:` d'une
> lib vers ses consommateurs. `mix igniter.install green_ash` s'en charge pour vous.

### Manuellement

Si vous préférez ne pas utiliser Igniter, ou pour comprendre ce que fait
l'installeur :

1. Ajoutez la dépendance dans `mix.exs` :

   ```elixir
   {:green_ash, "~> 0.1"}
   ```

2. Montez la console dans votre routeur, dans une scope avec le pipeline
   `:browser` (session requise) :

   ```elixir
   import GreenAsh.Router

   scope "/" do
     pipe_through :browser
     green_ash "/cli", domains: [MyApp.Bank, MyApp.Sales]
   end
   ```

C'est tout. `/cli` liste vos resources Ash, avec pour chacune : création,
liste (filtre + tri + pagination), modification/suppression métier (avec
confirmation), inspection des enregistrements, et un « acteur » de session
pour éprouver vos policies — le tout dérivé par introspection des actions.

**Recommandé** : gardez la route dev-only (comme fait l'installeur), en la
plaçant sous un `if Application.compile_env(:my_app, :dev_routes) do ... end`
— la console permet de créer/modifier/supprimer sans authentification propre
à votre app, ce n'est pas un panneau d'admin de production.

## Utilisation dans la console

- Navigation : chiffres + Entrée sur les menus, `j`/`k`/`Enter`/`Esc` dans les
  listes.
- Ligne de commande `:` (façon Vim) : `:list <resource>`, `:new <resource>`,
  `:actor <resource> <id>` / `:actor none` (pour éprouver vos policies),
  `:whoami`, `:debug` (inspection brute), `:menu`, `:help`.

## Ajouter une resource

Toute resource Ash déclarée dans un domaine passé à `domains:` apparaît seule
dans `/cli`, sans code d'UI. Quelques `description` sur la resource et ses
actions améliorent les libellés affichés (facultatif).

## Développer la lib

```bash
mix test        # aucun Postgres requis : harnais Ash.DataLayer.Ets
```

Voir `examples/bank/` et `examples/library/` (dans le monorepo) pour des exemples
complets sur Postgres.
