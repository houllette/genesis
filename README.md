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
campaigns, and prepare/pause/resume Experiences across gatherings. Phase 05's
actual browser usability gate is still open.

The next local slice implements [phase 06 settlement systems](docs/implementation/06-world-subsystems/handoff.md):
finite stock, currency/barter, confirmed exchanges, one production recipe,
supply-consuming rest and religious/secular institutional obligations and aid.
Create a world with a **local systems** ruleset, then use a place's resource
controls and an Experience's working resource controls. Original demo worlds
retain their pinned rules; they are not silently upgraded. Phase 06 also carries
the browser qualification gate. Cross-zone work (07),
full time reconciliation (08), AI and player play surfaces remain later phases.
Never use the ephemeral fixture mode for real adventures.

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
