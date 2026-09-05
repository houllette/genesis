# Genesis

A personal, GM-first world-building and story-curation tool on Elixir/OTP.
Build a rich persistent setting, connect its people and institutions, prepare
adventures and incorporate what actually happens into the world's living history.
The native browser GM workbench is primary. Optional player interaction uses one
shared TUI over SSH or in a LiveView Play tab, with Lemieux-backed NPCs behind
engine validation.

The historical architecture report is [`ttrpg-elixir.md`](ttrpg-elixir.md);
the current implementation contracts supersede its real-time/player-first assumptions.

The [phased implementation plan](docs/implementation/README.md) reconciles the
research and provides a separate build brief and handoff for each fresh agent
run. Phases 01–03 now provide a pure scene engine, two original rulesets and
in-memory World/Zone/Session authority. See the
[batch handoff](docs/implementation/03-zone-sessions/handoff.md) for verification.
Published commit `083a563` adds [durable scoped state](docs/implementation/04-persistence/handoff.md)
and the [native GM workbench](docs/implementation/05-gm-workspace/handoff.md);
its GitHub Actions checks passed.
Visit `/worlds` after signing in to curate places, NPCs, items and notes, manage
campaigns, and prepare/pause/resume Experiences across gatherings. The user has
manually accepted the existing 05–06 interface; the handoffs record the evidence
limits and the decision to defer broader UI refinement.

Published `9e4c8cf` implements [phase 06 settlement systems](docs/implementation/06-world-subsystems/handoff.md):
finite stock, currency/barter, confirmed exchanges, one production recipe,
supply-consuming rest and religious/secular institutional obligations and aid.
Create a world with a **local systems** ruleset, then use a place's resource
controls and an Experience's working resource controls. Original demo worlds
retain their pinned rules; they are not silently upgraded.

Published `10c54f6` implements [phase 07A](docs/implementation/07-world-zones/handoff.md): a searchable,
linked atlas at `/worlds/:world_id/atlas`, reached from the world workspace.
Run `mix ecto.migrate` for the additive atlas table. Regions, lore and directed
links are authored references; existing people, objects and institutions are
read through their owning places. Records can be GM-only, world-visible or
campaign-scoped. New NPCs have stable, dormant persona defaults; old snapshots
are not rewritten. Atlas routes are descriptive only.

The bounded **07B** slice adds `/worlds/:world_id/connections`: directed
World-owned links with condition/capacity checks, plus registration of existing
institutions and their declared jurisdictions. Run `mix ecto.migrate` for the
additive `world_networks` table. Edits during an open window are drafts. Checks
do not move actors or reserve destinations; jurisdictions do not spread private
knowledge or enforce remote policy. Local stock, affiliations and receipts stay
unchanged.

**07C1** adds an Experience's **Travel & visited places** screen. It moves one
bound participating PC, all carried inventory and self-contained beliefs through
an eligible directed connection. Movement is durable, retryable and recovered
after interrupted coordination; published places and fictional time are unchanged.
Run `mix ecto.migrate` for scoped transfer/reservation tables and per-place bases.
Its initial single-PC restriction is superseded by 07D below; zero elapsed time
remains required. Visited-place claims survive return trips, pause and aborted
travel. Full time reconciliation (08), AI and player play surfaces remain later phases.

**07C2** adds **Review all outcomes** on an Experience. Review every visited
place, seal the complete footprint, then explicitly preview and confirm publication
as a world steward. This supports **one Experience, up to eight places, with zero
elapsed fictional time**. Sealing stops play, retains claims and currently cannot
be undone. Publication updates all places, ownership and source-linked history
atomically; an interrupted confirmation can safely retry its exact identity.
Run `mix ecto.migrate` for the additive `incorporation_operations` ledger. Its
world-wide fence blocks reads/admission/edits until caches are installed or safely
made cold after a crash. This is not phase-08 time reconciliation.

**07D** completes the remaining Phase 07 implementation. Existing NPCs can be
invited, deterministically agree/refuse, and be dismissed without losing their
history or inventory. Set willingness and a 1–8-trip commitment in the NPC editor;
use the Experience resource action controls to invite/resolve/dismiss. Travel
moves the entire eligible party atomically (up to eight actors). An optional
arrival exchange buys, sells, barters or contributes carried goods at the destination
within that same transaction; it is a real courier journey, not remote stock editing.
In **History & sources**, a GM can recognize an accepted institutional contribution
once. This changes scoped standing and a relief-supported flag, not affiliation or
universal knowledge; both publish with the Experience. The atlas exposes accepted
knowledge sources and a collapsed typed-annotation editor. Campaign notes remain
separate from canonical facts. Run `mix ecto.migrate` for `world_standings` and
`global_dependencies`, then restart any already-running development server.
Phase 07 is published as `9d41176`; its GitHub CI passed. Browser QA remains user-deferred.
Never use the ephemeral fixture mode for real adventures.

**Phase 08A (in progress, uncommitted)** adds explicit scene time and completion
to the existing Experience review screen. Inspect recorded action durations, add
explained scene time in a single-place Experience, then finish with a total that
includes—not adds to—time already recorded. Completed, failed and abandoned
outcomes keep their actual expenditures; optional needs-review status holds them
for later reconciliation. Sealing still does not publish or release claims.
Positive-time and multi-Experience publication are not enabled yet.

New-world creation has collapsed optional Gregorian/Coptic calendar controls with
an explicit epoch; existing ordinal worlds are unchanged. Month/year arithmetic
uses that pinned calendar. Run `mix ecto.migrate` for the additive `worlds.calendar`
column and restart the development server before manual use. See the
[Phase 08 handoff](docs/implementation/08-living-time/handoff.md) for exact limits,
validation and the next implementation slices.

The [living-history contract](docs/implementation/living-history-and-context.md)
connects generated history with ongoing play: character choices and companions
change situations, major deeds leave lasting consequences, and later stories
and NPCs can remember them when relevant.

The [world-subsystem plan](docs/implementation/world-subsystems.md) scopes basic
economies, commerce, religion/institutions and other connected mechanics, with
explicit working foundations and deferred extension boundaries.

The [experience-time contract](docs/implementation/experience-time.md) defines
adventures spanning multiple gatherings: save outcomes during play, pause fictional
time between meetings, then review elapsed time and incorporate completed adventures
without silently colliding with another campaign.

The [Tempo integration contract](docs/implementation/tempo-and-time.md) assigns
testable system-clock reads and supported calendar/interval operations to Tempo,
while preserving OTP timeout timing, Oban scheduling and explicit fictional time.
Phase 03 pins `:ex_tempo` 1.6.4 and tests its UTC clock boundary; supported
fictional calendar simulation remains phase 08.

## Requirements

Erlang and Elixir versions are pinned in `.tool-versions` (asdf/mise), and
PostgreSQL must be reachable with the credentials in `config/dev.exs`.

## Getting started

```sh
mix setup          # deps, database, assets
mix phx.server     # or: iex -S mix phx.server
```

Then visit [`localhost:4000`](http://localhost:4000). Register at
`/users/register`; in development the confirmation email lands in the local
mailbox at `/dev/mailbox`.

## Tests

```sh
mix test                                   # whole suite
mix test test/path/to/file_test.exs        # one file
mix test test/path/to/file_test.exs:42     # one test
```

Oban runs in `testing: :manual` mode, so tests assert that jobs were enqueued
rather than executing them.

## Before you push

```sh
mix precommit
```

This is the single alias CI mirrors: dependency audits, a warnings-as-errors
compile, formatting, Credo, usage-rules freshness, the compile-time dependency
check, Sobelow, docs, and the test suite. A green `precommit` is local evidence,
not a guarantee that remote CI or the additional release gates have passed.
Dialyzer runs in CI in its own job (`mix dialyzer`) — it's too slow for the edit
loop.

## Agent tooling

[Tidewave](https://hexdocs.pm/tidewave) is mounted in the dev endpoint, giving
an agent a live connection to the running application — evaluating code in it,
reading its logs, querying the dev database, and reading docs pinned to the
locked dependency versions. Two things to know:

- It only answers **while the server is running** (`mix phx.server`).
- `.mcp.json` in the repo root is project-scoped and stays **pending approval**
  until you approve it in an interactive `claude` session. `/mcp` confirms the
  connection.

Tidewave binds to localhost and ships no authentication; it is dev-only.

`AGENTS.md` (which `CLAUDE.md` includes) carries the conventions and architecture
constraints agents are expected to follow.
