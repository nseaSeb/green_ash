# BUIS — Console CLI (LiveView, style AS400) pour tester un back Ash

Objectif : un dev back écrit **uniquement du métier** (des resources Ash) et obtient
« gratuitement » une console de test 100 % clavier sous `/cli`, sans écrire d'UI.

## Lancer / tester

```bash
mix phx.server        # http://localhost:4200  (racine redirige vers /cli en dev)
mix test              # suite complète
```

Base de données : Postgres (docker) sur `localhost:5432`, `postgres/postgres`, DB `buis_dev`.
Port HTTP : **4200** (défini dans `config/runtime.exs`, surchargé par `PORT`).

## Principe

Tout est piloté par **introspection Ash** — aucun écran ne connaît de resource en dur.
La découverte se fait via la config `:ash_domains` (`config/config.exs`).

- `BuisWeb.Cli.Registry` — découverte domaines/resources/actions + résolution slug ↔ module.
- `BuisWeb.CliLive.Menu` (`/cli`) — menu AS400 numéroté (resources → actions), + ligne `:`.
- `BuisWeb.CliLive.Subfile` (`/cli/r/:resource/list/:action`) — liste d'une read action,
  colonne « Opt » par ligne (codes dérivés des actions : `2…`=update, `4`=destroy, `5`=afficher),
  suppression confirmée.
- `BuisWeb.CliLive.Screen` (`/cli/r/:resource/a/:action[/:id]`) — formulaire d'action générique
  via `AshPhoenix.Form`, champs déduits par `BuisWeb.CliLive.Field` (type Ash → widget, fallback
  JSON). `:id` = mode update sur un enregistrement.
- `BuisWeb.CliLive.Field` — mapper type Ash → `type=` HTML (+ options d'enum, fallback textarea).
- `BuisWeb.CliLive.Command` — parseur + application de la ligne `:`
  (`:menu :list <r> :new <r> :actor <r> <id> :actor none :whoami :debug :help :q`).
- `BuisWeb.Cli.Actor` + `BuisWeb.CliActorController` — « acteur » de la console,
  stocké en session (le contrôleur l'écrit ; une LiveView ne peut pas via le socket),
  threadé dans tous les appels Ash (`actor:`) pour éprouver les policies.
- `BuisWeb.CliLive.UI` — feuille de style « terminal vert » partagée.

Les routes `/cli` sont **dev-only** (bloc `dev_routes` du routeur).

### Acteur & policies

`Account` porte `Ash.Policy.Authorizer` (dép. `:picosat_elixir` requise). Exemple :
`destroy` exige un acteur (`actor_present()`), le reste est libre. Dans la console :
`:actor account <id>` pour agir en tant que ce compte, `:actor none` pour redevenir
anonyme, `:whoami` pour vérifier — l'acteur courant est affiché dans l'en-tête (`◆ …`).

### Filtres de liste

Si une read action a des **arguments**, le subfile les rend comme barre de filtre
(côté requête, toute la table) via `Ash.Query.for_read`. Cf. `Account.read :search`
(argument `holder`, `filter expr(contains(...))`).

## Ajouter une resource → elle apparaît seule dans `/cli`

1. Créer le module Ash (data_layer `AshPostgres.DataLayer`), l'ajouter à un domaine
   (`resources do resource ... end`), et déclarer le domaine dans `:ash_domains`.
2. `mix ash.codegen <nom>` puis `mix ash.setup` (migrations).
3. `iex`/`/cli` : la resource est listée au menu, listable et exécutable — **sans code UI**.

Bonnes pratiques qui améliorent l'affichage (facultatif) :
- `description "..."` sur la resource et les actions → libellés lisibles au menu.
- Les `argument`s d'action sont rendus comme champs ; garder les `change` **tolérants au nil**
  (l'argument est absent pendant la construction du formulaire) — cf. `Buis.Bank.Account.credit`.

## Exemple de référence

`Buis.Bank.Account` (`lib/buis/bank/account.ex`) : create métier `open` (avec argument
`initial_deposit`), update métier `credit`, `read`/`destroy` par défaut. C'est le banc de test
du renderer et des tests (`test/buis_web/cli_live/`).
