# Handoff: 03 — Zone authority and transport-neutral sessions

Status: complete for the explicitly ephemeral phase 03 contract; shared final
gate passed for phases 01–03.
Date: 2026-09-04. Predecessor: [phase 02](../02-rulesets/handoff.md).
This closes the selected 01–03 batch, not persistence or product readiness.

## Validated tree and entry evidence

Base `f46f5bde188c1e82ccfe50b7d45d10f7ab479754` on main, plus the uncommitted
01–03 implementation: `lib/genesis/{core,systems,engine,time}/`,
`lib/genesis/systems.ex`, application supervisor, `priv/systems/`,
`test/genesis/{core,systems,engine}/`, scene fixture, Mix dependency/lock and
reviewed documentation. Starting AGENTS.md/README.md/docs changes were preserved.
No migration, route, release, commit or push was made.

Environment: Elixir 1.20.4 / OTP 29 (pinned ERTS 17.0.6), macOS, PostgreSQL test
sandbox, Oban manual testing. Baseline account/auth/page refresh passed 68 tests.
Core and systems regressions ran during the batch; final evidence is below.

## Authority and protocol

`Genesis.Engine.Supervisor` starts `Genesis.Engine.Registry` and
`Genesis.Engine.Worlds`; tests supply distinct Registry/supervisor names.
No worlds start by default. `start_world/3` starts a real WorldSupervisor:
World followed by a DynamicSupervisor for its Zones/Sessions, using rest_for_one.

Registry keys:

- World tree: `{:world_tree, world_id}`; World: `{:world, world_id}`;
  workers: `{:workers, world_id}`. Generation is deliberately NOT a second
  live-World namespace. A competing generation returns `:generation_mismatch`.
- Zone: `{:zone, Scope.key(scope), zone_id}`. One writer owns each slice.

The trusted creator PID owns ephemeral `World.admit/3`, `grant/2`,
`revoke/2`, `pause/2` and `resume/2`. Grants are opaque references bound to
principal ID, campaign, actor, role, scope and zone. This is a test/bootstrap
authority boundary, not durable account membership; 04 must connect real access
checks to the existing Accounts.Scope without trusting client claims.

`World.attach/4` binds the calling consumer to a Session; that Session binds
to Zone after initialization, avoiding synchronous World→Session→Zone→World
deadlock. Only the consumer may use its Session. Public operations:

```elixir
Session.view(session)
Session.submit(session, %{id: request_id, revision: revision,
                          intent: %{type: "take", target_id: item_id}})
Session.propose(session, proposal_id, %{type: "help", target_id: npc_id})
Session.confirm(session, request_id, proposal_id)
Session.detach(session)
```

Direct take is the only unconfirmed mutation. Other actions retain a server-side
proposal; returned terms omit hidden context. Confirmation rechecks the current
binding, status, exact terms and revision before drawing or charging. Inputs have
closed shapes; clients cannot supply roles, context, clocks, sources or dice.

Success is `{:ok, %{durability: :ephemeral, view: projection, effects: effects}}`.
View alone returns `{:ok, projection}`; failures are explicit error atoms.
Receipts bind principal/request ID to payload, actor and campaign within the
scoped Zone. Retry returns original effects plus a fresh authorized projection;
revocation still rejects it. Existing receipts can be read while paused, but new
actions cannot execute. No receipt eviction silently re-enables a request.

## Claims, lifetimes and bounded delivery

One advancement window is admitted per World. Experience claims cover canonical
actor/item/zone identities independently of campaign/experience ID. Even the
same Experience cannot seed a second spendable copy into another Zone. Published
and rehearsal copies remain separate, read-only/non-exportable boundaries.
Nonzero start offsets and candidate admission are unsupported.

Pause/detach do not release claims, publish outcomes or advance fictional time.
Last detach marks disconnection only: no automatic safety, relocation or elapsed
time is invented. Phase 12 adds actual danger/checkpoint rules.

Zone and Session workers are temporary:

- Session crash preserves Zone state; a fresh attachment resynchronizes.
- Zone crash ends dependent Sessions, retains claims and marks that slice lost;
  re-admitting its original seed returns `:state_lost`, never rolls back play.
- World crash tears down all dependent workers, then starts empty ephemeral
  authority. Old tokens/state are lost. There is deliberately no recovery claim.

Both hops coalesce change notifications until the next authorized view:
`{:genesis_changed, session_pid}` contains no game state. Slow readers get the
latest projection; Session retains no canonical scene or event history.
Monitor identity prevents stale detach/DOWN messages affecting newer bindings.

Bounds: 32 World trees, 80 workers per World, 16 admitted zone scopes,
256 grants per World, 64 bindings and 64 retained proposals per Zone,
1,000 receipts per Zone by default (test-injectable). Zone calls use 3-second
timeouts, World authorization 2 seconds, consumer Session calls 5 seconds.
Scene constructors cap entity counts and action/check/formula inputs. These are
deterministic internal limits, not a measured public-network flood guarantee.

## Qualified Tempo boundary

Pinned Hex `:ex_tempo == 1.6.4`; release and
[v1.6.4 API source](https://github.com/elixir-tempo/tempo/blob/v1.6.4/lib/tempo/clock.ex)
were checked before installation. `mix.lock` is the artifact authority.
New required transitives: astro 2.5.0, calendrical 1.3.0, localize 1.2.0 and geo
3.6.0. Existing NimbleParsec 1.4.2 was unchanged. No optional timezone/import
packages or unpinned Git dependency were added. Dev/test compilation succeeded;
Tempo compiled 92 files, with a grammar file exceeding the 10-second slow-compile
notice. This is observed build impact, not a benchmark.

`Genesis.Time.Clock.system/0` provides separate UTC/monotonic functions.
`read/1` validates UTC and integer monotonic milliseconds; `remaining/2`
uses only monotonic time. UTC defaults to `Tempo.Clock.utc_now/0`, preserving
microseconds. No clock decides when fiction advances.

Clock tests select Tempo.Clock.Test AND pin it in the reading process. Two
concurrent children have independent pins; parent pins are not inherited.
Injected child dependencies prove exact UTC values, missing-pin failure and
backward wall time alongside forward monotonic elapsed time. No global clock
environment changes or sleeps are used. Calendar simulation remains phase 08.

## Verification evidence

- Core: 10 tests; rulesets: 13 tests; engine: 18 tests (15 authority, 3 clocks).
- Latest authority-only run: `mix test test/genesis/engine/authority_test.exs`,
  **15 passed**, seed 480412.
- Meaningful red regressions exposed duplicate same-Experience asset claims,
  cross-campaign receipt replay and competing generation owners; all were fixed.
  Barrier contention tests assert one winner, not an arbitrary scheduling order.
- `mix credo --strict`: no issues; compile-connected xref: zero dependencies.
- Final `mix precommit`: **passed**, 153 tests, seed 181284. Includes dependency
  retirement/advisory and vulnerability audits (none found), warnings-as-errors
  compilation, formatting, Credo, generated usage-rule sync, compile-connected
  xref, Sobelow and documentation generation. No check was narrowed or suppressed.
  The first attempt stopped at Sobelow's runtime file-path finding. Fixed demo
  assets now use tracked build resources with no runtime filesystem input;
  focused bundle tests and Sobelow passed before the final rerun.
- Final `MIX_ENV=test mix dialyzer`: **passed**, zero errors/skips/unnecessary
  skips, on the final code including the bundle-loader change.
- Local Markdown link check: 51 implementation/ruleset documents, zero broken
  relative file links. `git diff --check`: passed. Final prose updates record
  these observed results; no application code changed after the green gates.
- Remote CI, browser/SSH usability, live inference and scale: not run; outside
  this batch. No gameplay route exists and no real adventure should use this shell.

## Phase 04 entry and next batch

```sh
mix test test/genesis/core test/genesis/systems test/genesis/engine
```

Then follow [04 persistence](../04-persistence/README.md), with
[05 GM workbench](../05-gm-workspace/README.md) as the next natural batch.

Persist snapshot + accepted transition/event + request receipt + outbox before
reply, along with memberships, claims, versions and scope generation fences.
Replace loss semantics with tested recovery; do not promote this receipt cache
into a durable guarantee or hold DB transactions across GenServer calls.
Define explicit safe serialization (no arbitrary term/module/atom decoding).
Stable compound step IDs and award/consent uniqueness need transactional rules.

The first incorporation proof is zero-duration and single-zone. Positive elapsed
outcomes wait for phase 08, not silently reset to zero. Preserve original draws,
causal sources, audience identities and exact pinned rules. Continue using the
existing World authority; 07 extends it rather than creating a competitor.
