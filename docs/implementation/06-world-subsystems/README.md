# Phase 06 — Local world-subsystem foundations

## Validate phase 05 first

Read [phase 05's handoff](../05-gm-workspace/handoff.md). Run the actual native GM
create/curate/experience pause-resume journey, role/notes isolation and stale-save recovery.
Use exact existing commands from that handoff, inspect the implemented APIs and
repair any predecessor defect with a regression test before extending it.
Read [workflow](../workflow.md), [architecture](../architecture.md),
[product/personas](../product-and-personas.md), [experience time](../experience-time.md)
and [actions/knowledge](../play-and-knowledge.md). Read the full extended report
before structural changes; the current GM-first/session-time contracts supersede
its real-time and immediate shared-canon assumptions.
Read [world subsystems](../world-subsystems.md) and [living context](../living-history-and-context.md).

## Outcome and scope

A single-zone settlement has a small real economy, atomic commerce, and a
religious or secular institution whose resources, obligations and relationships
matter. GM forms and engine fixtures exercise trade, production and institutional support.
Working outcomes persist and publish through incorporation; player TUI controls follow in 11.

Proposed homes are small pure Core modules, versioned capabilities, existing
scoped Zone transactions/projections and native GM controls.
Do not build an independent service/process per subsystem. Cross-zone ownership
starts in 07; durable timed simulation in 08; regional/history evolution in 14.
No new dependency or LLM is required.

## TDD slices

1. **Capability and ownership contracts.** Extend phase 02 versioned data with
   the minimum supported/enabled/record-only capability manifest. Describe typed
   states, allowed intents, source/sink events, privacy and dependencies for
   local economy, commerce and institutions. Reject unavailable actions and
   incompatible bundles; do not return fake success from a stub. Local fields
   have one Zone owner; definitions are pinned content, not a new global writer.
2. **Economy and resources.** Reuse existing inventory identity for stockpiles,
   and model one configured currency in integer minor units or explicit barter.
   Implement one legal production recipe with input/output/waste/capacity and a
   supply-consuming rest action under bundle rules. Test exact balances and
   declared source/sink accounting, invalid/negative/oversized quantities,
   rounding, resource exhaustion and unauthorized issuance. With supplied time,
   actions are bounded immediate resolutions; no timer loop or undeclared
   elapsed-time simulation. Price/availability bands are deterministic data.
   This first recipe has zero completion delay. Reject nonzero-delay recipes
   until phase 08 implements durable start/completion; do not grant early output.
3. **Commerce.** Quote and settle buy/sell/barter between existing actors and
   a local market using inventory, funds, policy, eligibility and expiry
   revisions. Require explicit confirmation for changed terms. Commit goods,
   payment, receipt and history atomically. Test two buyers in one admitted experience buying the last
   item, and another experience denied claimed stock; changed stock/price, expired quote,
   repeat request and crash around
   commit. Denial cannot charge or deliver; no persistent unbounded reservations.
4. **Beliefs and institutions.** Add typed tradition/institution/site references,
   affiliation, observance/obligation and local standing. A voluntary offering
   transfers actual resources; one fulfilled obligation grants permitted aid
   or access through context. Test religious and secular data presets, private
   affiliation, refusal, false membership claims and witnessed versus unknown
   actions. Do not equate belief in a deity with a confirmed supernatural fact.
   No offering grants platform permissions or mind-control over a PC/NPC.
   Institutional representatives reference real actors; any NPC introduced now
   has stable persona/agency defaults and bounded deterministic choices. Phase
   07 expands the common creation paths, not retrofits identity onto blank agents.
5. **Local law and relationships.** Reuse institutional roles for one local
   access rule and a witnessed/reported violation or debt with a scoped response.
   Record cause, audience and the authority entitled to adjudicate. Unknown
   crimes cannot change everyone's reputation. Ordinary public/private role
   authorization remains separate from in-world institutional status.
6. **Connected player journey.** Extend Ashfall: a validated supply disruption
   changes a quote; a player buys/barters, converts grain to rations, consumes
   or donates supplies, and receives a context-dependent institutional response.
   Assert specific mechanical outcomes, conservation and irrelevant-context
   controls. Persist/restart and repeat across campaigns without duplicating
   goods or leaking private knowledge. Reactions are explicit local actions,
   not yet autonomous relief shipments or calendar-triggered observances.
7. **GM records and extensions.** Add native stock/treasury/recipe/institution
   controls, quote/confirm/offer and consequence previews. Player projections are
   transport-neutral values; shared TUI delivery follows in 11. Builder forms
   edit definitions through authorized contexts.
   Document other subsystem levels from the coverage matrix, their future
   read/write/event seams and unsupported actions. Two world presets demonstrate
   enabled religious/currency mechanics versus secular/barter alternatives.
   Test disabling/migration refusal when live holdings or obligations exist.
   Keep rich population, environment, logistics and historical evolution for
   their named later phases; no empty runtime scaffolds as completion evidence.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md). This contract is required in this phase.

Quote/action times use the Experience cursor or an explicit authorized world-edit context.
Paused gatherings do not expire quotes or produce stock. ExperienceEvents record temporary
outcomes; 04's zero-duration fixture proves incorporation before 08 schedules duration.
Regional effects never write directly into another group's working state.

## Handoff criteria

- [ ] GM controls honor scope claims, confirmation, paused time and
  provisional-versus-published resources.

- [ ] Economy, commerce and religious/secular institution foundations have real
  state transitions, source-linked consequences and durable replay/recovery.
- [ ] Money/items and recipe/source/sink accounting satisfy exact invariants;
  races/retries cannot duplicate settlement, charge on rejection or mint rewards.
- [ ] Contextual aid/access and local law reflect authorized actions/knowledge;
  beliefs, canon and platform permissions remain distinct.
- [ ] Two configurable presets work without world-name branches; disabled/
  record-only capabilities fail clearly and cannot silently corrupt live state.
- [ ] The connected journey works through native GM controls and engine APIs after restart,
  preserving cross-campaign ownership/privacy and persistent deeds.
- [ ] Each MVP subsystem has an honest implemented/record-only/deferred status,
  versioned extension contract and named next delivery phase.
- [ ] `mix precommit` passes; [handoff.md](handoff.md) names exact APIs, transaction
  boundaries, fixtures, red-test evidence and next-agent regression commands.

Phase 07 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../07-world-zones/README.md).
