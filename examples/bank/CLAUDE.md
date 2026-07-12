# Bank — exemple GreenAsh

App Phoenix + Ash de démonstration qui monte la console **GreenAsh** (la lib du
monorepo, dans `../../green_ash`) sous `/cli`.

## Lancer / tester

```bash
mix deps.get
mix ash.setup     # crée bank_dev + migrations
mix phx.server    # http://localhost:4200  (/ redirige vers /cli en dev)
mix test          # tests d'intégration de la console montée
```

Postgres (docker) sur `localhost:5432`, `postgres/postgres`, DB `bank_dev`. Port 4200
(`config/runtime.exs`, surchargé par `PORT`).

## Montage de la console

Dans `lib/bank_web/router.ex` :

```elixir
import GreenAsh.Router

scope "/" do
  pipe_through :browser
  green_ash "/cli", domains: [Bank.Ledger]
end
```

Toute la mécanique (menu, listes filtre/tri/pagination, CRUD métier, acteur/policies,
commandes `:`) vit dans la lib et est générée par introspection — cette app ne contient
**que du métier**.

## La resource de démo

`Bank.Ledger.Account` (`lib/bank/ledger/account.ex`) : create métier `open` (argument
`initial_deposit`), update métier `credit`, read filtrable `search` (argument `holder`),
`read`/`destroy` par défaut, policy `destroy` réservée à un acteur (`actor_present()`).

Ajouter une resource Ash à un domaine exposé la fait apparaître seule dans `/cli`.
