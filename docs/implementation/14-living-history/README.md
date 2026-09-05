# Phase 14 — Continuous history, connected consequences and world genesis

## Validate phase 13 first

Read [phase 13's handoff](../13-npc-agents/handoff.md). Run universal personas, scope-safe
memory/agency, quality corpus, stale-result fences, real embedding evidence and all
remaining provider gates.
Revalidate 08's Tempo/calendar-version, bounded recurrence and interval-boundary
regressions under [Tempo/time domains](../tempo-and-time.md) before scaling history.
Use exact existing commands from that handoff, inspect the implemented APIs and
repair any predecessor defect with a regression test before extending it.
Read [workflow](../workflow.md), [architecture](../architecture.md),
[product/personas](../product-and-personas.md), [experience time](../experience-time.md)
and [actions/knowledge](../play-and-knowledge.md). Read the full extended report
before structural changes; the current GM-first/session-time contracts supersede
its real-time and immediate shared-canon assumptions.
Read [world subsystems](../world-subsystems.md) and [living context](../living-history-and-context.md).
Read [story/canon](../story-and-canon.md); verify completed outcomes are incorporated, not
immediately published.
Read the complete [Lemieux contract](../lemieux-integration.md) and carry actual
upstream/live gates forward.
Read [TUI-first play](../tui-first-play.md) and [quality](../experience-quality.md); native
GM management stays primary.

## Outcome and scope

Player events become lasting, connected living history. A minimal world can
also be initialized by running those same causal laws through configurable
epochs. Both paths produce usable current state and a navigable chronicle.
This is not only a generator or a collection of historical prose. No LLM is
required for deterministic simulation; existing Lemieux enrichment stays optional.

Proposed homes: pure `Genesis.Core` simulation/legacy reducers, versioned
`Genesis.Content` world profiles, `Genesis.Engine` generation/consequence
coordination, scoped persistence/chronicle queries, Oban workers and both UIs.
Implement these numbered slices across fresh runs if needed; checkpoint each
green slice and stop at the phase boundary.

## TDD slices

1. **Continuous consequence model.** Define typed causal events and facts for
   infrastructure/routes, supply, faction pressure and commitments. Start in a
   live fixture: a validated player action closes a bridge, reroutes supply,
   changes local availability and produces a faction response. Test exact
   conservation/ordering, duplicate delivery and delayed work to an approved
   incorporation/downtime target when nobody is
   connected; no target means no progress. Effects that must be atomic use existing
   cross-owner coordination;
   delayed effects have explicit pending status and revalidate current facts.
   Continue phase 06's market/institution resources and phase 08's seasons/
   observances. A supply shock changes a later quote and relief obligation;
   player purchases/offerings affect the same stocks, not historical copies.
2. **Legacy and remembrance.** Store affected people/places, persistent versus
   expiring effects, source-linked historical episodes and disclosure provenance.
   Add permission-safe chronicle/entity-history queries and deterministic
   callback selection with relevance, budget and per-recipient cooldown. Test
   a major player deed after many unrelated events, through restart/campaign
   archive, and an unrelated conversation that should not mention it. A callback
   cannot repeat a reward or reveal a secret. Repairing a bridge updates present
   state without deleting the original event. Implement one supported cultural
   footprint, such as a steward-approved named memorial/annual observance linked
   to the deed, with a later calendar or location reference.
   Use the existing Tempo-backed temporal adapter for supported eras/reigns and
   anniversaries. Keep source-known approximate periods separate from exact
   engine occurrence coordinates and disclosure time. A vague legend cannot
   change chronology or grant an NPC exact dates it never learned.
3. **World profile and initial conditions.** Validate seed, epoch/calendar,
   geography/settlement graph, societies/factions, resource distributions,
   event density, historical horizon, module versions and population/event caps.
   Start with a small supported connected model, not a full geology/economy sim.
   Allow original presets and data overrides, rejecting missing mechanics or
   conflicting pins. Two profiles must differ mechanically without branching
   engine code on a world name. Persist the precise manifest and chosen seed.
   Extend the existing capability manifest, retaining playable/record-only/
   disabled distinctions and compatibility with secular/non-monetary worlds.
4. **Seeded historical evolution.** In an unpublished world, drive the same
   pure laws through ordered due events and coarse epochs. Include bounded
   population turnover/lineage, leadership succession, site growth/ruin and
   ownership of a notable artifact alongside the route/supply/faction chain.
   Institutional traditions, property and obligations reference those same
   people/sites; a succession does not discard a treasury or invent new goods.
   Track aggregates where individual detail is not needed; materialized figures
   reconcile them. Test lifetimes/lineage, no ghost leaders, unique artifact
   ownership, supported causal ordering and empty/extinct societies. Same seed,
   versions and parameters yield the same semantic events/state across batch
   sizes; persist keyed random draws so scheduling order does not reroll history.
5. **Resumable generation and activation.** One generation coordinator owns
   the unpublished world; no live Zone may write it simultaneously. Persist
   batch checkpoints/events/cursor, allow cancel/resume and bound CPU/memory/work
   per batch. A completed manifest points to a consistent launch checkpoint;
   activation atomically publishes that pointer after validation. Test crashes
   before/after publication, duplicate activation and denied access to partial
   state. Generation IDs and dates remain distinct from live administrative
   generation fences. Never regenerate a live world's past over player actions.
6. **Launch is not the end of simulation.** Continue the generated world with
   the same fact/event contracts under live World/Zone authority. A player acts
   on a historically damaged route or disputed artifact; later off-screen
   simulation reacts to their changes. Test equivalent small-world evolution
   on either side of the launch boundary, allowing only documented scheduling
   or resolution differences. Old unmet obligations, living people, ruins and
   legacies persist. Player involvement is attribution, not a separate history
   system with weaker persistence or visibility.
7. **Usable scale and presentation.** Small fixtures run quickly in normal
   tests. Separately run a bounded 2,000-year profile with fixed seed/version,
   declared site/population/event caps and no provider. Record measured runtime,
   peak memory, event/entity counts, causal examples and resume behavior; a
   year counter or repetitive generated text is not evidence of rich history.
   Include pre-epoch dates, calendar-version replay and bounded period queries;
   do not materialize every daily/second occurrence across 2,000 years at once.
   Show generation progress, pause/resume, world preview and chronicle in
   the native GM workbench; player history remains available through both TUI hosts. Player views expose
   only discoverable history. Do not start campaigns until activation succeeds.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md).

Validate 12's useful GM/player loop and 13's scoped-memory quality evidence before scaling.
After generation, the world evolves through completed experiences and approved downtime
using 08's candidate/incorporation protocol. No second historical engine or real-time clock
is introduced. Measure fixed development/held-out profiles and seeds for diversity, causal
coherence, resources and usable opportunities under the quality contract.

## Handoff criteria

- [ ] Measured long history follows the pilot and continues through incorporation with
  declared quality criteria and no real-time drift.

- [ ] A player-caused event has durable physical/economic, social and historical
  consequences; a later relevant callback and approved memorial cite its sources.
- [ ] Deterministic callback selection suppresses repetition and respects actual
  knowledge; no resource/action is re-executed by remembrance.
- [ ] Generation and live play share tested causal laws; launch/restart/archive
  do not stop consequences or erase player attribution.
- [ ] Seeded batches/resume reproduce semantic history and current state;
  activation is atomic, idempotent and excludes partially generated worlds.
- [ ] Temporal precision/uncertainty, pre-epoch and calendar-version fixtures
  survive replay; historical spans never replace exact causal event ordering.
- [ ] Lineage/lifetimes, unique artifacts, resource ownership and causal links
  satisfy invariant tests; profile overrides work without world-specific code.
- [ ] Economy, commerce, institutional belief/obligations and environment connect
  through existing laws; generation/activation preserves resources and support levels.
- [ ] The bounded 2,000-year run has actual resource/count/quality evidence;
  limitations are recorded, not presented as full Dwarf Fortress parity.
- [ ] Both clients support appropriate chronicle/progress/return views, and
  `mix precommit` passes. [handoff.md](handoff.md) includes actual APIs, manifests,
  exact continuation/generation/callback tests and the measured scale run.

Phase 15 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../15-gm-tools/README.md).
