# Phase 05 — Native GM world-building workbench

## Validate phase 04 first

Read [phase 04's handoff](../04-persistence/handoff.md). Run scoped snapshot/
receipt crash tests, experience claims, provisional-versus-published history,
membership and source-provenance tests. Read [workflow](../workflow.md),
[architecture](../architecture.md), [product/personas](../product-and-personas.md),
[experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md), plus AGENTS auth/UI rules.
Also run 04's temporal serialization/precision and deadline-recovery tests under
the [Tempo/time contract](../tempo-and-time.md); GM views must label real gathering
dates separately from fictional world/Experience dates.

## Outcome and scope

A GM can create and manage a small world before inviting a player: curate places,
people, lore and campaigns, declare an Experience, save/pause/resume it and inspect
pending outcomes. This is the primary product surface, not a temporary admin screen.
No ExRatatui, LLM dependency or player impersonation is needed. Full duration/
incorporation arrives in 08; never fake it with a successful placeholder button.

Proposed homes: native GenesisWeb workspace LiveViews and existing Content,
Campaigns and Engine commands. Use current_scope first in contexts and existing
components/assets. The GM should not need JSON or terminal commands for this journey.

## TDD slices

1. **World library and setup.** Create/select a world with one demo ruleset and
   supported profile, sensible original presets and editable defaults. Add a
   campaign, role delegation and roster. Test invalid references, stale saves,
   wrong-world access and invitations; no public self-service hosting workflow.
2. **Curated records.** Create one zone/location, two NPCs with stable persona/
   agency defaults, an item and a linked private/public note. Reuse typed state
   and validated commands. Distinguish prototypes, instantiated entities, plans,
   beliefs and facts. Preview player-visible information without granting access.
   Full nested atlas/search expands in 07; do not create competing wiki fields.
3. **Experience setup.** Choose campaign, participants, scope claims, start
   checkpoint and optional meeting link. Start/pause/resume, add subsequent
   gathering records, and inspect local outcomes versus published world. Show
   a conflicting claim with a useful next action. No canonical time passes.
4. **Editing and status.** Make Published / Working / Draft labels unmistakable.
   During an open window canonical-base edits are gated; ordinary authoring saves
   produce drafts. Clearly show ready/incomplete experiences and current capability
   limits. Phase 04's zero-duration incorporation fixture is not full scheduling.
5. **Usable workflow.** World → People/Places → Campaign → Prepare Experience →
   pause/reopen should work without a connected player or developer assistance.
   Prioritize readable forms, linked context, useful empty states, validation,
   keyboard/focus and narrow layouts. Keep technical payloads in optional details.
6. **Permission and recovery.** Test revoked roles, tampered IDs, private notes,
   stale forms and disconnect after a successful save. Reopening shows the
   committed record/experience and cannot duplicate actors or claims.

## Routes

Place world library, record editors, campaigns and experience management inside
the existing live_session :require_authenticated_user and the scope using
[:browser, :require_authenticated_user]. Authentication precedes world permissions;
contexts and commands recheck specific builder/GM/steward authority. Pass
current_scope to Layouts.app and contexts. Keep public auth routes unchanged.
Record actual route paths and the reason for their scope in the handoff.

## Handoff criteria

- [ ] The GM creates and curates Ashfall without a player session or raw JSON.
- [ ] Native forms/read models use the existing authority and typed records.
- [ ] A paused experience resumes at the same fictional point across gatherings.
- [ ] Claimed scopes, pending outcomes and published state are visibly distinct.
- [ ] Role, note visibility, stale-save and recovery tests pass; actual browser
  workflow and keyboard/narrow-layout evidence are recorded.
- [ ] No placeholder claims full time reconciliation, AI or player-TUI delivery.
- [ ] mix precommit passes; [handoff.md](handoff.md) records routes, fixtures,
  actual APIs, red-test evidence and the next focused regression commands.

Phase 06 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../06-world-subsystems/README.md).
