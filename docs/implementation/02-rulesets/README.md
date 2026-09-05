# Phase 02 — Ruleset bundles and deterministic checks

Status: completed in the 01–03 batch on 2026-09-04; see
[handoff.md](handoff.md) for acceptance evidence and explicit delivery limits.

## Validate phase 01 first

Read [phase 01's handoff](../01-pure-core/handoff.md). Run the pure scene,
rejection/visibility, paired-context, working/public scope and no-idle-time tests.
Validate 01's fictional coordinate/unit, zero-duration and calendar-version
regressions under [Tempo/time domains](../tempo-and-time.md).
Use exact existing commands from that handoff, inspect the implemented APIs and
repair any predecessor defect with a regression test before extending it.
Read [workflow](../workflow.md), [architecture](../architecture.md),
[product/personas](../product-and-personas.md), [experience time](../experience-time.md)
and [actions/knowledge](../play-and-knowledge.md). Read the full extended report
before structural changes; the current GM-first/session-time contracts supersede
its real-time and immediate shared-canon assumptions.

## Outcome and scope

Two small original bundles, `fantasy_demo` and `cyberpunk_demo`, define different
attributes, resources, slots, and available actions using one engine. The first
uses d20 checks; the second uses d10 checks and a technology resource. Document
their actual rules instead of claiming full 5e or Cyberpunk compatibility.

Proposed homes: `Genesis.Systems`, `Genesis.Core.Check`, `priv/systems/`, and
`test/genesis/systems/`. Prefer JSON/Elixir data and standard-library functions.
No dependency addition is authorized by this phase brief. NimbleParsec being
transitive does not make it an approved direct dependency.

## TDD slices

1. **Bundle validation.** Reject duplicate attributes, missing resource/slot
   references, invalid defaults, and unknown action types. Version bundles and
   produce a stable content digest. Worlds will pin these references later.
2. **Character schema.** A small `GameSystem` behaviour exposes genuinely
   variable pure resolution and declarative sheet metadata. Use one validation
   path for character creation, persistence data, and future UI forms. Test
   resource bounds, equipment rules, and incompatible bundle data.
3. **Check resolution.** Test exact boundaries for roll-over d20/d10, 2d6
   full/partial/failure, success-counting pools, and four Fudge dice. Enumerate
   bounded inputs to prove range and threshold properties. Compare outcomes
   using supplied draws; do not test random sample frequencies.
4. **Formula and dice limits.** Support a small allowlisted expression tree
   for derived attributes and modifiers. Detect cycles/missing dependencies;
   define stacking order and caps. Reject excessive dice, recursive expressions,
   division by zero, and unknown operators. If text grammar is added, it parses
   to these values and never evaluates Elixir. Bound exploding-die chains and
   record every draw, including cap behavior.
5. **Cross-system journey.** Create valid characters in both bundles, equip
   different items, resolve a common action, and prove the core contains no
   fantasy-only attribute or slot assumptions. Rejected checks preserve state.
6. **Composable context rules.** Version a small vocabulary of traits, conditions,
   context modifiers and permitted consequences. Test explicit priority/stacking,
   missing facts, incompatible combinations and companion-dependent actions.
   Add two data configurations with different contextual results through the
   same engine; do not branch on character/world names. Record each mechanic's
   reads, owned writes and events using existing modules, not an unused plugin
   framework. Distinguish ruleset mechanics from later WorldProfile policy.
   Name supported versus unavailable capabilities and required dependencies;
   reject an action requiring an absent mechanic instead of returning stub
   success. Reserve no empty subsystem processes or speculative full schemas.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md). This contract is required in this phase.

Declare action/scene durations, milestone eligibility and default nonlethal defeat in both
original bundles. Time comes from explicit fictional inputs, not wall duration. Test one
social-access award with unique identity, an opt-in exceptional-risk profile and a
retirement/asset-transfer transition without copied inventory. Later encounters/stories
consume these pure rules, not a second advancement ledger.

Follow [Tempo/time domains](../tempo-and-time.md): bundle durations use explicit units;
calendar-relative months/years need a pinned calendar/start and must not silently
become fixed Earth seconds. Such expressions stay unsupported until 08's calendar
adapter exists. Record that capability limit; Tempo clock integration belongs to 03.

## Handoff criteria

- [x] Both bundles have tested duration, milestone, defeat/consent and nonduplicating
  retirement/transfer rules.

- [x] Both bundles validate and execute through the same documented interfaces.
- [x] Check boundaries, modifier order, dependency cycles and resource limits
  have meaningful deterministic tests.
- [x] Unknown/unsafe formulas and incompatible saved data fail explicitly.
- [x] Schema metadata is usable by either transport without Ecto/UI in Core.
- [x] Context modifiers compose deterministically across both bundles; a new
  rule has a meaningful interaction test rather than an isolated flavor field.
- [x] `mix precommit` passes; [handoff.md](handoff.md) records bundle versions,
  actual behaviour callbacks, supported mechanics and deliberate limits.

Phase 03 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../03-zone-sessions/README.md).
