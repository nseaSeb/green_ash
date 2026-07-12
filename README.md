# GreenAsh — monorepo

Une console de test « écran vert » (LiveView, 100 % clavier, style AS400) générée
par **introspection** depuis vos resources Ash — zéro code d'UI.

```
.
├── green_ash/        # la librairie (package :green_ash), sans couplage à l'app hôte
└── examples/
    └── bank/         # app Phoenix + Ash de démonstration qui monte la console
```

## La librairie — `green_ash/`

Montée dans le routeur de l'hôte via une macro :

```elixir
import GreenAsh.Router

scope "/" do
  pipe_through :browser
  green_ash "/cli", domains: [MyApp.Bank]
end
```

Une resource Ash déclarée dans un domaine exposé apparaît alors dans `/cli` :
menu → listes (filtre + tri + pagination) → création / update métier / suppression
confirmée → inspection → acteur & policies → commandes façon Vim. **Sans code d'UI.**

- Découplée : ses propres composants, chemins relatifs à la base de montage, domaines
  injectés via `on_mount` — aucune dépendance aux composants/routes de l'hôte.
- Testée avec le data layer **ETS** (aucun Postgres requis) : `cd green_ash && mix test`.

## L'exemple — `examples/bank/`

App Phoenix 1.8 + Ash 3 + AshPostgres (Postgres docker, port 4200) qui dépend de la lib
en `path:` et la monte sous `/cli` (la racine `/` y redirige en dev).

```bash
cd examples/bank
mix deps.get
mix ash.setup          # crée bank_dev + migrations
mix phx.server         # http://localhost:4200
mix test               # tests d'intégration à travers la console montée
```

La resource de démo `Bank.Ledger.Account` (`lib/bank/ledger/account.ex`) illustre les
bonnes pratiques : `description` sur resource/actions, action métier avec argument
(`open`/`credit`), read filtrable (`search`), policy `destroy` réservée à un acteur.
