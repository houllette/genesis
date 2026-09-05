# Phase 15 — Live GM control and bounded rewind

## Validate phase 14 first

Read [phase 14's handoff](../14-living-history/handoff.md). Run generation/activation,
measured history quality, session-based live continuation, old legacy retrieval and
incorporation/catch-up recovery.
Carry 14's Tempo temporal-precision/uncertainty, pre-epoch and calendar-version
regressions into checkpoint restore; real audit time and spend are not rewound.
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

Extend the native GM workbench delivered in 05–10; this is not its first useful
release. A GM can run gatherings and optionally use compact terminal controls: inspect
zones/roster, narrate, spawn validated entities, adjudicate, whisper, roll
secretly, possess an authorized NPC and manage scoped content. A world steward
can coordinate shared canon/automation policy, pause and restore the whole
world, with an explicit warning about every affected campaign and open window.
All actions preserve engine validation, attribution and knowledge boundaries.

Proposed homes: GM capability policy/intents, world coordination, audit views,
GM LiveViews and `Genesis.TUI` views. Reuse existing contexts and player render
primitives; UI convenience must not create a privileged alternate write path.

## TDD slices

1. **Capabilities and audit.** Extend the existing matrix for player, spectator,
   builder, campaign GM/co-GM and world steward. Default co-GM to delegated play
   tools; world security/global canon policy and rewind require world-steward
   authority. Campaign authority cannot reveal another campaign's private notes
   or seize its actors. Test direct
   unauthorized calls and mid-session revocation. Audit the real principal
   separately from an NPC/character spoken through.
2. **Live interventions.** Implement bounded spawn from known definitions,
   narrate, adjudicate, whisper, secret roll and canonical fact pin/revision.
   Validate targets and resource changes. Test exact permitted effects and
   absence of secret result/metadata in player payloads and ordinary history.
   Use the universal persona/agency creation contract for every spawned NPC.
   Shared-fact edits respect world-delegated territory and expected versions;
   one campaign GM cannot overwrite another's newly committed consequence.
3. **Possession.** Acquire explicit NPC control, cancel/fence AI work, speak as
   the NPC, and release. Race a pending provider reply and two GM possession
   attempts. Disconnect/revocation expires control by documented policy; old
   AI output cannot overwrite human intervention.
   Scope possession and intent review to the NPC's world capabilities, not merely
   who opened a GM screen. Human dialogue/actions join the same memory/history
   pipeline; model takeover cannot ignore what happened during possession.
4. **Pause and checkpoints.** Coordinate a world-wide quiescence barrier,
   including transfers, published state, open windows/claims, experience/story
   cursors, completion manifests, prepared candidates and encounters,
   persona/agency state and due work. Capture complete
   consistent state. Frozen logical time must not advance from delayed workers;
   chat/inspection policy remains explicit. Test crash/restart during pause and
   checkpoint creation and recover to a known state.
   Distinguish stopping a PlaySession/campaign from pausing world time. Show all
   affected campaigns before taking a world-wide barrier; no private campaign
   rollback masquerading as undo of shared reality.
5. **Rewind as new generation.** Preview the selected checkpoint and affected
   world state, then require a fresh explicit GM confirmation with an expected
   revision. Restore atomically/coordinated under pause; append a rewind event,
   retain history and increase generation. Rebuild schedules and resync clients.
   Fence old actions, workers, possession tokens and provider replies. Keep
   memberships, security grants, spending ledger and independent sandboxes intact.
   Restore game relationships and fence memories/reflections from the discarded
   future while retaining their audit records. Test memory retrieval after rewind.
   Test interruption before/after commit, duplicate confirmation and retries.
   Restore published and experience run/objective/claim progress coherently with the world.
   Preserve out-of-character notes, meeting records and audits, but mark summaries
   of discarded events as historical; they must not enter new-generation AI context.
6. **GM workspace.** Extend earlier campaign library/atlas/authoring rather than
   starting a separate GM-only data model. Implement zone/roster, story state, hidden information,
   action console and audit feed with useful focus/keyboard flow. Provide
   equivalent browser actions in the existing authenticated route/session scope,
   with action-specific campaign/world authorization in every context. Show consequences and relevant
   evidence before technical details. Inspect the native workspace and any implemented
   terminal controls.
   Support prepare → gather → run → close/recap, and prepare → publish → log off
   → review actual outcomes. Link personas, relationships, source events and
   invalidated beats; preview the selected player's knowledge without granting it.
   Include campaign/world automation switches, pinned facts and a review inbox
   for out-of-policy AI proposals. Generated recaps, if added, also use Lemieux.
7. **History and customization workspace.** Let the steward inspect a major
   event's causal chain, affected places/people and unresolved consequences,
   authorize a memorial/anniversary or later repair, and distinguish present
   facts from old states and disputed beliefs. Changes are new commands/events,
   not edits to an original deed. Provide validated WorldProfile controls and
   contextual preview across different characters/companion rosters; preserve
   pinned mechanics or require an explicit migration. Respect world-scoped
   authority, show consequential configuration changes and test invalid overrides.
   Preview is sandbox/read-only and cannot make a hypothetical outcome canon.
   Show subsystem support levels and dependencies, owned stock/treasuries and
   institutional obligations. Changing currency, disabling religion or removing
   a recipe with pending work requires an explicit migration/settlement policy.
   Preview exact affected holdings/work and reject orphaning changes. Test a
   rewind during trade/production: checkpointed balances, obligations and work
   agree, old quotes/jobs are fenced, and inference spending remains unrewound.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md).

Review dependencies and elapsed-time changes before a GM amendment. A checkpoint includes
published and paused/pending experience state; restore cannot free an actor while leaving an
old completion eligible. Fence manifests, claims, previews, jobs and model results. Rehearse
a paused three-gathering experience and ready solo errand through restore and one
incorporation. Lore pins guide preparation; they cannot silently erase actual choices to
force an ending.

## Handoff criteria

- [ ] Advanced GM control extends the early workbench and coherently restores published plus
  pending experience state.

- [ ] Builder/campaign-GM/world-steward matrix is enforced at the engine boundary; interventions
  and impersonation are durably attributed.
- [ ] Secret rolls/whispers/facts remain absent from unauthorized live/history/
  model payloads. Possession safely supersedes in-flight AI.
- [ ] Pause and full-checkpoint rewind recover from crashes, retain append-only
  history and reject every stale generation of work.
- [ ] GM interface describes rewind scope and confirms it explicitly; arbitrary
  single-event undo is not offered. Native and implemented terminal workflows were inspected.
- [ ] Live-session and async-builder journeys work; all-campaign rewind includes
  personas/run progress without leaking discarded futures through recaps or AI.
- [ ] GM history/context tools expose meaningful causal provenance and safe
  customization; commemorations/repairs add history instead of rewriting deeds.
- [ ] `mix precommit` passes; [handoff.md](handoff.md) includes the capability
  matrix, actual routes, rewind/recovery procedure and failure tests.

Phase 16 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../16-release-readiness/README.md).
