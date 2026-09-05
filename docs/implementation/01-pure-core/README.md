# Phase 01 — Pure world core and visibility

Status: completed in the 01–03 batch on 2026-09-04; see
[handoff.md](handoff.md) for acceptance evidence and explicit delivery limits.

## Validate phase 00 first

Read [phase 00's handoff](../00-baseline/handoff.md). Run existing account/auth/page tests
and the inspected boilerplate/config baseline; reconcile intervening changes.
Use exact existing commands from that handoff, inspect the implemented APIs and
repair any predecessor defect with a regression test before extending it.
Read [workflow](../workflow.md), [architecture](../architecture.md),
[product/personas](../product-and-personas.md), [experience time](../experience-time.md)
and [actions/knowledge](../play-and-knowledge.md). Read the full extended report
before structural changes; the current GM-first/session-time contracts supersede
its real-time and immediate shared-canon assumptions.

## Outcome and scope

A small original scene can be played as pure function calls. Introduce only the
values and operations needed for an actor to look, take an available item,
inspect inventory, and make a context-sensitive bounded choice. No processes, Repo access,
transport, rulebook implementation, or provider integration.

Proposed homes: `lib/genesis/core/` and `test/genesis/core/`; simple authored
fixtures under `test/support/fixtures/`. Public functions have named typespecs.

## TDD slices

1. **State and identifiers.** Model scoped world/branch/zone identity, actors,
   items, revisions, and version references as serializable values. Test invalid
   shapes and duplicate IDs. Supplied fixture IDs must never create new atoms.
   Do not equate a campaign, story run or connection with a world/branch; see
   [product hierarchy](../product-and-personas.md). Keep campaign schemas for 04.
2. **Intent reduction.** Write an exact test for transferring an item from a
   zone to one actor's inventory, preserving item identity and total quantity.
   Implement the reducer returning new state and effects. Repeating an illegal
   take, unknown actions, missing actors, and out-of-scope targets must fail
   without mutation. Persistence-level request deduplication comes later.
3. **Knowledge and effects.** Test two actors, one hidden item, a secret fact,
   and a GM. Implement actor-specific state projection and effect audiences.
   Unauthorized projections must omit secret IDs and metadata as well as text.
   Attempts to act on invisible objects must not disclose their existence.
4. **Determinism.** Supply time, random inputs, and generated IDs explicitly
   where needed. Run identical inputs twice and compare exact state/effects.
   Assert the original value remains unchanged and rejection consumes nothing.
   Follow [Tempo/time domains](../tempo-and-time.md): use world-scoped integer
   fictional coordinates, explicit units and calendar versions, separate from
   UTC timestamps and monotonic readings. Test zero duration and incompatible
   world/calendar comparisons. Do not install Tempo or read its clock in Core.
5. **Fixture journey.** Add a small scripted scene using the public functions.
   It must assert final item ownership, ordered effects, and different authorized
   views. Use this journey as the future integration fixture's foundation.
6. **Context and lasting facts.** Introduce only the typed context facts needed
   for this scene: one validated character trait, a prior deed produced by an
   earlier reducer action, and one present NPC companion's relationship or skill.
   Run paired cases that vary each factor independently with the same action/
   draws. Assert a minor change (e.g. cost) and a major change (e.g. admission
   versus confrontation), not merely different prose. Irrelevant context stays
   irrelevant. Persist the resulting deed/fact in returned state with source
   attribution; a later action consumes it without resetting it on scene entry.
   No full quest framework, recruitment workflow or historical generator yet.

## Decisions to record

Record the precise reducer success/rejection shapes, how explicit resolution
inputs are carried, canonical identifier format, effect audience vocabulary,
and projection API. Prefer a few structs and functions over generic protocols.
Do not freeze speculative fields for every future subsystem.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md). This contract is required in this phase.

Test published versus working StateScope and supplied local elapsed time: an action changes
only the Experience value, and pause does not advance the world. Use the small
event/fact/observation/belief/relationship/obligation/memory vocabulary with source/audience
fields actually consumed by the fixture. A false belief never changes a fact. Add
proposal/confirmation revision and two-step partial-success tests; no natural-language
parser yet.

## Handoff criteria

- [x] Scope/time, typed knowledge, confirmation and compound partial success have exact pure tests.

- [x] Pure scene journey succeeds with exact final state and effects.
- [x] Illegal and unauthorized requests leave state unchanged and leak no secret.
- [x] Actor/GM projections and effect audiences are tested before any UI exists.
- [x] Core contains no process, Repo, provider, or implicit-clock operations.
- [x] Fictional coordinate/unit and calendar-version contracts have exact tests;
  zero-duration events are not silently expanded into intervals.
- [x] Character, prior-choice and companion facts each drive meaningful tested
  variation; prior consequences survive later reductions and remain private
  where appropriate. Context is explicit rather than inferred from arbitrary text.
- [x] `mix precommit` passes and [handoff.md](handoff.md) names real tests/APIs.

Phase 02 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../02-rulesets/README.md).
