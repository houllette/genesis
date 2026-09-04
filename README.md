# Genesis

A living-world, system-agnostic tabletop RPG engine on Elixir/OTP. One shared
persistent world supports invited solo curated stories, GM-less group stories
(synchronous or asynchronous), and live GM sessions — with LLM-driven NPCs and
narrative content held behind hard engine validation. Players connect over a
terminal UI (ExRatatui over SSH) or LiveView in the browser; both are transports
onto the same authoritative world state.

The architecture report that drives the design is [`ttrpg-elixir.md`](ttrpg-elixir.md).

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
check, Sobelow, docs, and the test suite. A green `precommit` means a green PR.
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
