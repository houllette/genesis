# Handoff: 01 — Pure world core and visibility

Status: implemented in the 01–03 batch; final-gate evidence is recorded in the
[batch handoff](../03-zone-sessions/handoff.md). Date: 2026-09-04.

## Entry validation

Base `f46f5bde188c1e82ccfe50b7d45d10f7ab479754`, branch main. The starting tree
already had modified AGENTS.md/README.md and untracked implementation docs.
Those changes were preserved. The historical phase 00 inspection is not a game
readiness claim. Re-ran:

```sh
mix test test/genesis/accounts_test.exs test/genesis_web/user_auth_test.exs test/genesis_web/controllers/page_controller_test.exs
```

Observed **68 passed**, seed 103144. Read the historical report and all current
shared contracts/phase briefs; [execution review](../execution-review.md) records
the resolved contradictions.

## Delivered contracts

Implementation: `lib/genesis/core/`; fixture:
`test/support/fixtures/scene_fixtures.ex`; acceptance: `test/genesis/core/`.

- `Scope.new/1` validates bounded UTF-8 string IDs and explicit kind, world,
  generation, window and experience/rehearsal identity. `Scope.key/1` includes
  all five; campaign identity is deliberately not a consistency boundary.
- `State.new/1` validates scope, bounded actors/items/knowledge, unique ownership,
  action/context data and rules references. Constructors accept lists; state
  indexes entities by ID. Item quantity transfers intact, not by copying items.
- `FictionalTime.new/4`, `advance/2`, `compare/2` use integer fictional seconds,
  world/calendar/version and bounded coordinates (including pre-epoch dates).
  UTC recording time is supplied separately. Incompatible coordinates fail.
  Zero duration stays zero. Pause/resume changes status/revision, never time.
- `Scene.reduce(state, actor_id, intent, inputs)` returns
  `{:ok, new_state, effects}` or `{:error, reason}`. Intent is exactly
  `%{type: string, target_id: string}`; trusted inputs supply scope, expected
  revision, event ID, draws and UTC recorded_at. Rejection returns no mutated
  value. Published state cannot be played into.
- `State.view/2`, `inventory/2` and `Scene.effects_for/2` project at the state
  boundary. Own private fields and GM information differ from public actor
  summaries. Hidden target IDs, knowledge sources and relationship endpoints
  do not leak. Hidden and absent targets share `:unavailable`.
- `Scene.propose/4` returns a proposal or target clarification, without a roll,
  reservation or mutation. `confirm/3` recomputes exact terms and revisions.
  `proposal_view/1` is the safe preview, not the full server proposal.
- `Compound.run/3` accepts 1–8 explicit steps. On rejection it returns
  `{:partial, state, effects, zero_based_index, reason}`, retaining accepted
  earlier steps. This is pure sequencing, not yet a durable command endpoint.
- Typed knowledge distinguishes event/fact/observation/belief/relationship/
  obligation/memory. A false belief does not qualify as a deed. Context reads
  validated traits, actual prior deed facts and a living present companion's
  skill/relationship. Priority then ID determines composition. Source IDs stay
  on internal records; output explanations are separately projected.
- Event audiences freeze identities at occurrence. New membership does not
  grant an old event. Accepted events record scope, revision, read set, source
  IDs, variants, rules pin, draws, resolution and fictional/UTC coordinates.

These are internal Elixir value contracts, not an approved durable JSON codec.
Knowledge version starts at 1; phase 04 must define explicit serialization and
event transition/replay formats without persisting executable terms.

## Evidence and limits

`mix test test/genesis/core`: **10 tests** in the final batch suite.
Constructor and transfer tests first failed against unimplemented functions.
Paired cases independently vary trait, deed, companion and irrelevant context;
tests assert cost/admission changes, privacy, exact ownership and elapsed time.
Compound distraction followed by an invalid take preserves the first action.

The Ashfall fixture is a programmatic scene, not observed GM usability or a
browser/TUI journey. Core reads no clocks, starts no processes and accesses no
Repo/provider. All values remain in memory until 04. No full recruitment,
quest engine, canonical incorporation or calendar simulation is claimed.

## Next entry checks

Phase 02 is completed in the same batch; inspect its [handoff](../02-rulesets/handoff.md).
Before extending either contract, run:

```sh
mix test test/genesis/core
```

Use `Genesis.SceneFixtures.scene/0` and `inputs/2` as in the tests, not a
second hand-maintained scene. The pure inputs are trusted; a network caller must
never be allowed to choose actor, role, source records, rolls or rules pins.
