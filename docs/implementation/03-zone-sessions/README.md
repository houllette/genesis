# Phase 03 — Zone authority and transport-neutral sessions

Status: completed in the 01–03 batch on 2026-09-04; see
[handoff.md](handoff.md) for acceptance evidence and explicit delivery limits.

## Validate phase 02 first

Read [phase 02's handoff](../02-rulesets/handoff.md). Run both rulesets, deterministic
checks, contextual composition, local-duration, milestone and defeat-policy tests.
Recheck explicit fictional units/calendar versions and unsupported calendar-relative
duration rejection. Read the [Tempo/time contract](../tempo-and-time.md) before
qualifying the selected dependency and adding the shell clock boundary.
Use exact existing commands from that handoff, inspect the implemented APIs and
repair any predecessor defect with a regression test before extending it.
Read [workflow](../workflow.md), [architecture](../architecture.md),
[product/personas](../product-and-personas.md), [experience time](../experience-time.md)
and [actions/knowledge](../play-and-knowledge.md). Read the full extended report
before structural changes; the current GM-first/session-time contracts supersede
its real-time and immediate shared-canon assumptions.

## Outcome and scope

Two authenticated test principals attach through Sessions to one Zone process.
The Zone serializes their actions and sends authorized updates. State is still
explicitly ephemeral in this phase; do not claim crash durability yet.

Proposed homes: `Genesis.Engine.Zone`, `Session`, lookup/supervision modules,
and `test/genesis/engine/`. Authentication fixtures may supply trusted scopes;
durable world membership arrives in phase 04.

## TDD slices

1. **Process ownership.** Start Registry and DynamicSupervisor with test-local
   names. Concurrent attempts to start the same scoped zone resolve to one
   authority. Distinct worlds and published/experience/rehearsal scopes with matching IDs stay isolated.
   Build actual supervision trees, not supervisors implemented as GenServers.
2. **Session protocol.** Attach a trusted principal/actor, read a projection,
   submit an intent with a request ID, and detach. Prove forged actor/role/world
   fields cannot grant authority. A spectator can observe only permitted state.
   Assemble current character/deed/companion context from Zone-owned state.
   Client-supplied history, relationship, companion presence or roll modifiers
   cannot become facts. Test a stale companion/deed revision before resolution;
   revalidate its read set and deliver only permitted reasons for the outcome.
3. **Contention.** Release two competing take requests with an explicit barrier.
   Assert one accepted result, one remaining owner, and consistent revisions.
   Do not assert which caller wins unless ordering is deliberately controlled.
4. **Delivery and back-pressure.** Deliver only actor projections/effects or
   safe invalidations. Define bounded calls, payload sizes and stale-revision
   responses. Test duplicate messages, missed updates and resync. Never send
   raw secret state to Session or transport processes and filter it afterward.
5. **Lifetimes.** Test independent session crashes, zone restart behavior, and
   two connections for one actor. Last detach marks disconnection under checkpoint/danger
   policy; a stale detach
   cannot park a reattached actor. Monitor processes and use synchronization
   messages instead of sleeps. Test global-name collisions explicitly.
6. **Tempo clock boundary.** Qualify and lock `:ex_tempo` under the time contract;
   record the tested release and transitive dependency impact. Implement the small
   UTC/monotonic boundary and inject readings into resolution, never clock reads
   in Core. Test exact UTC microseconds, two isolated clock pins, a supervised
   child's clock dependency, missing-pin failure and backward wall jumps while
   monotonic elapsed time increases. Test-clock pins alone do not freeze timers
   or propagate to children. No calendar simulator or extra clock GenServer yet.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md). This contract is required in this phase.

One Zone owns each StateScope slice. Test shared attachments in one Experience, and another
Experience denied a claimed actor. World owns assignment; implement ephemeral claims now and
durable claims in 04. Detach, StoryRun and model messages cannot publish world state or
advance time. Pause/resume is a domain operation, not process lifetime.

## Handoff criteria

- [x] Experience ownership and claims preserve one published-world authority; pause/detach
  never publish or advance.

- [x] One writer per scoped zone; two sessions contend without duplicating items.
- [x] Verified Tempo dependency and clock tests preserve UTC precision, child
  isolation, monotonic timing and unchanged fictional time; record actual commands.
- [x] Session state has attachment/delivery concerns, no canonical game copy or
  dependency on ExRatatui/LiveView.
- [x] Unauthorized principals and spectators cannot mutate through direct API
  calls; hidden data is absent from delivered messages.
- [x] Contextual resolution uses current server-owned facts and rejects forged/
  stale context; consulted revisions and causal attribution are explicit.
- [x] Crash and connection-lifetime behavior is explicit, including current
  in-memory data loss until phase 04.
- [x] `mix precommit` passes and [handoff.md](handoff.md) records process names,
  restart policy, protocol, and focused concurrency commands.

Phase 04 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../04-persistence/README.md).
