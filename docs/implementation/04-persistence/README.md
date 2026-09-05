# Phase 04 — Durable state, audit and recovery

## Validate phase 03 first

Read [phase 03's handoff](../03-zone-sessions/handoff.md). Run scoped Zone contention,
assignment admission, trusted context, pause/detach and hidden-message tests.
Run 03's Tempo clock/child-isolation, precision and wall-versus-monotonic tests;
verify its dependency pin before using the [time contract](../tempo-and-time.md).
Use exact existing commands from that handoff, inspect the implemented APIs and
repair any predecessor defect with a regression test before extending it.
Read [workflow](../workflow.md), [architecture](../architecture.md),
[product/personas](../product-and-personas.md), [experience time](../experience-time.md)
and [actions/knowledge](../play-and-knowledge.md). Read the full extended report
before structural changes; the current GM-first/session-time contracts supersede
its real-time and immediate shared-canon assumptions.

## Outcome and scope

Every acknowledged mutation survives a process/node restart. The same request
can be retried without reapplying it, and a returning player gets authorized
history. Multiple campaigns reference one published world; bounded experience working states
are explicit, not duplicate canonical ownership. Membership
and campaign-owned records remain separately scoped. Use existing Postgres/Ecto;
no event-sourcing framework or new database.

Proposed homes: `Genesis.Persistence`, scoped world membership/character
contexts, migrations, and `test/genesis/persistence/`. Generate new migrations
with `mix ecto.gen.migration`; preserve shipped auth/Oban migrations.

## TDD slices

1. **Durable schema.** Add world/branch identity, separate campaign identity,
   world/campaign memberships and roles, party/character bindings,
   characters/location ownership, current zone snapshots, historical
   checkpoints, ExperienceEvent/WorldEvent, source-event mappings and request receipts as
   needed. Use database unique
   and foreign-key constraints, scoped indexes, versioned jsonb, and optimistic
   revisions. Never cast ownership/role fields from arbitrary player params.
   Enforce campaign→world and character-assignment constraints in Postgres.
   Campaign GM is not world steward. Archive retains history and world changes.
   Add fields only when used; linked lore and detailed authoring follow later.
   Keep UTC audit timestamps at microsecond precision, explicit fictional units/
   calendar versions and commit-order cursors distinct. Round-trip used temporal
   fields without storing opaque Tempo structs or arbitrary calendar module names.
2. **Atomic mutation.** First test transaction failure leaves no new state,
   receipt, or visible event. Commit current snapshot, event, receipt and any
   durable effects in one transaction before reply. Record resolved random
   outcomes, versions, audiences and actor/operator attribution. Retrying the
   same request returns its authorized recorded outcome; changed payload fails.
   Bind campaign/experience/window/StateScope in receipts/events. Test two
   campaigns claiming the same world item: one admitted experience, one owner.
   Record context/variant versions, causal parent/root IDs, affected identities,
   participant attribution and observation/disclosure sources for meaningful
   deeds. Store durable fact projections with source references; a player's past
   choices must survive reconnect and feed later resolution, not only the log UI.
3. **Crash matrix.** Inject failure before commit, after commit before cache
   installation, and after installation before reply/broadcast. Restart the
   authority and retry the same request. Assert exactly one durable mutation
   and correct projection at every boundary. Failed DB writes fail closed.
   Test deadline recovery from persisted UTC policy/remaining duration, not raw
   monotonic readings from the old VM. Restart and a backward wall-clock jump
   cannot reorder history or advance the fictional cursor. Preserve timestamp
   precision; phase 08 completes paused-choice deadline behavior.
4. **Replay and formats.** Restore current state and replay a historical
   checkpoint plus its recorded transitions to the same state. Do not reroll
   or invoke live effects. Unknown schema/rules versions and corrupted or
   discontinuous records produce useful errors. Verify append-only application
   APIs; use separate privileged migration credentials if DB permissions enforce
   append-only writes. Keep old-format fixtures when formats evolve.
5. **History and reconnect.** Page events with a documented durable cursor that
   cannot skip a transaction committing late. Test ordering across two zone
   fixtures, duplicate deliveries, cursor boundaries, revocation, whispers and
   newly joined members. Build a deterministic away digest from authorized
   events, not an unrestricted log passed to the UI.
6. **Campaign lifecycle and privacy.** Test two campaigns in one world and a
   third in another: membership cannot cross worlds or grant another campaign's
   notes/GM rights. Revocation invalidates live authority. Campaign archive
   preserves canonical events; character reassignment cannot duplicate assets.
7. **Lasting-deed recovery.** Change the fixture's relationship/access condition
   through a player action, restart, then resolve a later situation using that
   fact. Compare with a character who never made the choice. Incorporate through
   the zero-duration fixture, then archive without removing its world effect.
   Replay preserves the original sources and
   draws; text summaries never replace canonical facts or rerun their effects.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md). This contract is required in this phase.

Add the used window/base-checkpoint, experience/local-time/status, scoped log/snapshot and
durable zone/global claim records. Enforce unique active actor/item/opportunity assignment.
Acknowledged ExperienceEvents survive a crash while published state/calendar stays
unchanged; test history separation and idle restart.

Implement only a bounded single-zone, zero-duration incorporation fixture here: seal local
events, validate base/claims, then atomically commit canonical snapshot, WorldEvent/source
mappings, receipt and claim/status updates. Crash/retry without duplicate rewards. Reject
nonzero-duration/multi-scope incorporation until 08 (using 07's ownership contracts);
this is storage evidence, not full
scheduling. Archive/abandonment never silently discards accepted local outcomes.

Phases 05–07 may stage positive-duration actions, but their publication waits for
08. Earlier cross-campaign publication tests use an explicit zero-duration
fixture, never clear elapsed time on an accepted action.

## Handoff criteria

- [ ] Durable staging, claims and zero-duration incorporation pass crash/retry tests without
  premature shared-world publication.

- [ ] All acknowledged mutations survive the crash matrix without duplication.
- [ ] UTC precision, versioned fictional coordinates and deadline recovery have
  exact storage tests; persisted order never relies on a clock timestamp.
- [ ] State, event, receipt and durable job/outbox writes are atomic; player
  delivery occurs only after commit.
- [ ] World/campaign/role/character scope is enforced by contexts and authority
  calls; both campaigns still share one canonical resource owner.
- [ ] Current recovery and historical replay agree; history does not leak or
  skip late commits. Snapshot frequency and event ordering are documented.
- [ ] Deeds/context/fact provenance survive restart and campaign archive, and
  actually change a later resolution rather than merely appearing in history.
- [ ] `mix precommit` passes; [handoff.md](handoff.md) records migrations,
  constraints, serialization versions, crash tests and deterministic fixture setup.

Phase 05 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../05-gm-workspace/README.md).
