# Changelog

## 0.3.1 (2026-07-22)

### Fixed

- **`mix format` no longer rewrites the router snippet from the README.** The
  installer adds `import_deps: [:green_ash]` to the host's formatter, but the
  package exported nothing for it to import — so the formatter treated
  `green_ash` as an ordinary call and turned `green_ash "/cli"` into
  `green_ash("/cli")` the first time anyone formatted. Copy the README, run
  the formatter, and your router no longer matched the documentation you
  copied it from. The package now exports
  `locals_without_parens: [green_ash: 1, green_ash: 2]`.

  Existing routers are not disturbed: the formatter leaves parentheses where
  they already are, it just stops adding them.

## 0.3.0 (2026-07-22)

Takes over from 0.2.0 on both fronts it left open.

0.2.0 turned two crashes into explicit refusals (an actor that fails to load,
a resource requiring a tenant). The same class remained on six other paths,
each of them a 500 rather than a screen, and a seventh bug did the opposite —
it answered confidently with the wrong resource. All are fixed and covered by
tests.

It also said picking a tenant was "not supported yet". It is now, along with
the three other things a console like this is asked for daily: relationship
fields you pick from instead of pasting a UUID into, columns you choose, and
screens that live in the URL so they can be bookmarked or sent to someone.

### Added

- **A tenant can be chosen: `:tenant <value>`.** 0.2.0 stopped multitenant
  resources crashing the console by refusing to open them — Ash can say a
  resource needs a tenant, never which one you mean. Asking is the missing
  half. With one set, every read, write, policy check and relationship picker
  runs inside it, and the tenant shows in the header of every screen: a list
  scoped to the wrong tenant and an empty one are otherwise indistinguishable.
  `:tenant none` clears it; bare `:tenant`, like bare `:cols`, reports rather
  than clearing — checking which tenant you are in must not be the same
  keystroke as leaving it. `:whoami` reports it beside the actor. Without one
  the refusal stands exactly as before, but now names the way out. A
  tenant-scoped record can also be used as the actor once a tenant is set.

  The value is not validated. Ash accepts any term as a tenant, and a console
  whose job is to probe your resources has no business deciding which tenants
  are real. Both strategies are covered: `:attribute`, which scopes by a
  column, and `:context`, which hands the tenant to the data layer.

- **A `belongs_to` is a choice now, not a UUID you paste.** The action screen
  rendered a foreign key as what it is underneath — a box wanting a raw id —
  so filling one in meant leaving the console, listing the other resource,
  copying an id and coming back. The field offers the related records,
  labelled by name and a slice of the id, and is titled after the
  relationship rather than the column (`Account`, not `Account id`).

  It offers them only where it honestly can. Past 100 related records, or when
  the destination needs a tenant the console cannot set, or when the current
  actor may not read it, the field stays the id box it was — an empty select
  would read as "there are none". Introspection alone cannot know any of
  this, so the read is a separate step (`GreenAsh.Field.with_options/2`);
  `specs/2` still touches no data.

- `GreenAsh.Registry.pagination/1`, returning a read action's pagination
  config (or nil) — `required?` is what decides how the read must be run.

### Changed

- `GreenAsh.ActorController` becomes `GreenAsh.SessionController`, with an
  `actor` and a `tenant` action — it writes both, and a name saying "actor"
  while handling tenants would be a lie. The route it serves moves with it;
  the router macro is unchanged for hosts.
- `GreenAsh.Actor.resolve/2` and `from_session/2` take an optional tenant as a
  third argument.
- `GreenAsh.Field.with_options/2` takes an optional tenant as a third argument.

- `GreenAsh.Registry.action/2` returns `nil` for an unknown action name
  instead of raising.
- `GreenAsh.Registry.resource_slug/2` replaces the former one-argument version,
  taking the exposed domains: a slug cannot be known to be unambiguous without
  them.
- The internal `tenant_notice` assign is now `notice`, one shape covering
  every screen the console refuses to open. `Components.tenant_notice/1`
  becomes `Components.notice/1`, taking the notice map. Both were
  `@doc false` internals.

### Fixed

- **A cleared filter left `?filter[holder]=` in the URL.** An emptied field is
  an absent filter, not a filter on `""`, and the leftover key meant a screen
  you had filtered and cleared no longer matched the same screen never
  filtered. Empty values are dropped now.

- **A relationship picker did not see records created on the screen above it.**
  A create leaves you in place to make another, but the pickers were built once
  at mount — so a resource pointing at itself (`belongs_to :mentor, Author`)
  never offered the author you had just created. The specs are re-read after a
  successful create, alongside the form.

- **A pending deletion could fire on a record you could no longer see.**
  Marking a row for deletion put a confirmation banner up; filtering, sorting,
  paging or hiding a column then replaced the rows underneath it while the
  banner stayed, still holding the original record. Confirming deleted that
  one. The pending deletion is now dropped whenever the rows change, since it
  was only ever a claim about the rows on screen.

- **Paging an unordered read could repeat a record on two pages, or show it on
  neither.** Nothing obliges a data layer to return rows in the same order
  twice, and most reads declare no sort. Read replicas make this plain —
  consecutive pages can be served by different nodes — but a single instance
  is free to reorder too. The primary key is now appended as a final
  tiebreaker, which leaves your sort — and any the action declares — in charge
  and only settles what they leave open. Found by a test of the console's own
  paging that passed or failed depending on the run.

  Note what this does and does not buy: a total order makes the *ordering*
  reproducible, it does not freeze the rows. Paging is offset-based, so a write
  landing between two page requests still shifts the window. Keyset paging is
  the answer to that, and is not implemented yet.

- **Columns are yours to choose.** Lists rendered every public attribute at a
  fixed width of twelve characters, which on any real resource is a wall of
  truncated stubs. `:cols holder balance` picks them, in the order given;
  `:cols` alone lists what is on offer; `:cols all` restores them. The choice
  rides in the URL like the rest of the screen, so a narrowed list can be
  bookmarked. A name the resource does not have is named back rather than
  dropped in silence.

- **Cells are cut at 24 characters instead of 12, and the full value is kept
  as the cell's `title`.** The cut also used to compare `byte_size` while
  slicing by character, so accented text was measured against a length it
  never had — "Éléonore" is 8 characters and 11 bytes.

- **Filter, sort and page live in the URL.** They were socket state only: a
  reload dropped you back on an unsorted, unfiltered first page, and a screen
  could not be handed to anyone — the address bar said the same thing whatever
  you were looking at. They are now query parameters
  (`?filter[holder]=Ada&sort=balance:desc&page=2`), read in `handle_params/3`,
  so a pasted link reproduces the screen and the browser's Back button walks
  the list the way it looks like it should. Values from the query are checked
  against the screen before use: an unknown sort column or a nonsense page is
  dropped, not obeyed. The first page is left out of the URL rather than
  spelled out.

- **A read denied by a policy no longer takes the console down.** This was
  the worst of them: the console exists to let you watch your policies decide,
  and any read policy that refuses the current actor — `authorize_if
  actor_present()` on a read, say — reached `Ash.read!/2` and raised inside
  `mount/3`. Opening the list gave a LiveView error page, with nothing to say
  which policy refused or that setting an actor would help. The refusal is now
  shown on the status line, naming the current actor and, when there is none,
  the `:actor` command that sets one.

- **A read declaring `pagination required?: true` no longer crashes.** Ash
  refuses such a read without page options, and answers with an
  `Ash.Page.Offset`/`Keyset` struct rather than a list — the console called
  `length/1` on it, an `ArgumentError`. These reads now go through Ash's own
  `:page` option, and the console's page size is derived from the action's
  `max_page_size` rather than from its own constant: Ash caps an oversized
  page silently rather than erroring, so a console asking for more than the
  cap would have shown a short page and reported no next page — losing
  records with no visible symptom. Reads that merely *allow* pagination keep
  the previous limit/offset path, which the cap does not apply to.

- **An action name that matches nothing no longer 500s.** The name comes
  straight from the URL and was fed to `String.to_existing_atom/1`, which
  raises when no such atom exists; when the atom happened to exist without
  naming an action, the nil that followed broke `GreenAsh.Field.specs/2`
  instead. Both now open a screen saying the resource declares no such action.

- **A non-read action can no longer be opened as a list.** `/r/x/list/create`
  reached `Ash.Query.for_read/4` with a create action. It now says so.

- **A filter value that will not cast no longer kills the screen.** Typing
  something an argument cannot hold (a filter on an `:integer`, say) raised
  out of `handle_event/3`, losing the screen's state on reconnect. The cast
  error is shown instead, and clears on the next successful read.

- **The sort column is no longer converted to an atom.** It arrives from the
  client; it is now matched against the columns actually rendered, and an
  unknown one is ignored rather than raising.

- **Two resources sharing a module segment no longer share a slug.** Slugs
  were the last module segment, so `MyApp.Bank.Account` and
  `MyApp.Sales.Account` were both `"account"` — an ordinary shape once an app
  has more than one domain. This did not merely hide the second resource:
  every link to it, every `:list` and every `:actor` naming it, resolved to
  the first, so the console showed one resource while claiming to show
  another. Colliding resources now take a domain-qualified slug
  (`"bank_account"`). Slugs are unchanged wherever nothing collides, so
  existing URLs stay put.

## 0.2.0 (2026-07-16)

### Fixed

- **An actor that fails to load no longer vanishes silently.** `:actor
  <resource> <id>` with a stale id, or a resource no longer among the exposed
  domains, left the console running as "anonymous" with no explanation. Every
  policy result after that read as a verdict on the policy when it was really
  a verdict on an actor that was never loaded. The reason is now shown on the
  screen. This affects every console, multitenant or not.

- **Multitenant resources no longer crash the console.** A resource declaring
  a multitenancy strategy without `global? true` cannot be read without a
  tenant — Ash raises `Ash.Error.Invalid.TenantRequired` — and the console has
  no tenant to set, so opening one from the menu raised inside `mount/3`. Such
  resources are now flagged in the menu and open a screen stating the
  constraint. Resources marked `global? true` are unaffected, matching Ash's
  own rule.

  Picking a tenant from the console is **not supported yet**: this release
  turns the crash into an explicit refusal, it does not make multitenant
  resources browsable.

### Added

- `GreenAsh.Actor.resolve/2`, which reports why a stored actor failed to load
  (`{:ok, record}` / `:none` / `{:error, message}`). `from_session/2` keeps
  its contract and still returns the record or nil, discarding the reason.
- `GreenAsh.Registry.tenant_required?/1`, mirroring the multitenancy check Ash
  performs before a read.
- LiveViews mounted in the console receive an `actor_notice` assign alongside
  `actor`.

## 0.1.1 (2026-07-13)

- Translated remaining French console strings and Ash resource labels to
  English.

## 0.1.0 (2026-07-12)

Initial release.

- LiveView console generated by introspection from Ash domains/resources:
  menu, filterable/sortable/paginated lists, create/update/destroy actions
  with confirmation, record inspection, session-based actor for exercising
  policies, Vim-style command line.
- `mix igniter.install green_ash`: adds the dependency, auto-discovers Ash
  domains, patches the host router.
