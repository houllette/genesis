# Curated experiences and shared canon

The latest user review replaces immediate per-action **world** canon with
experience-based staging and GM-led incorporation. Read
[experience time](experience-time.md) before implementing any StoryRun. The GM
curates setting, tone, narrative purpose, hooks and constraints; players and
validated NPC actions determine what happens within them.

## Distinguish authoring, play and publication

| Record | Meaning | Authority |
| --- | --- | --- |
| Published world state/lore | Established facts at the world's checkpoint | World/Zone commands and validated incorporation |
| Draft/StoryDefinition | Possible situations and suggested directions | Authorized draft/review/publish workflow; does not execute future events |
| Experience state/ExperienceEvent | What actually resolved in a particular ongoing adventure | Scoped Zone commits state, event, receipt and story progress atomically |
| Canonical WorldEvent | Incorporated outcome or approved world transition | World coordinator maps sources and publishes once |
| Belief/observation/memory | What an eligible actor knows or infers | Sourced state-level knowledge policy; not automatic truth |

Durable is not synonymous with published. An experience's accepted actions survive
crashes and failed/abandoned stories while awaiting reconciliation. They cannot
be spent in another run or disclosed as already incorporated world history.
A secret outcome may become canonical without becoming public. Definitions and
recaps never execute the events they describe.

## Beats guide situations, not guaranteed endings

A versioned beat defines purpose, discovery/eligibility predicates, participants,
stakes, constraints, optional suggested approaches, required capabilities,
resolution predicates and bounded follow-ups. It also defines local duration
contributions and terminal completion rules. Its declared elapsed-time formula
must agree with recorded local events; it cannot rely on how many evenings play took.

Support completed, failed, bypassed, invalidated, expired and abandoned paths.
A required beat is an authoring dependency, not permission to revive a dead NPC
or reset a stockpile. When no continuation fits, present a useful needs-review or
unavailable state and preserve permitted independent actions.

Character origins, deeds and actual companions can change role bindings, prices,
stakes, opposition, follow-ups or an entire direction. Variant precedence and
compatibility are data with deterministic selection and recorded sources. Recheck
uncommitted prerequisites after a changed roster or GM amendment; never reroll an
already accepted outcome merely by reopening a page.

The [action/knowledge contract](play-and-knowledge.md) defines freeform goals,
confirmation, compound partial success, consent and GM rulings. An unsupported
capability fails explicitly. Offering “fight” before encounter support exists is
not an implemented option; authoring diagnostics must identify that dependency.

## Experience and StoryRun orchestration

StoryRun binds a definition/version and participants to an Experience, its
advancement window and working scope. Its cursor changes in the same transaction
as the corresponding action, event, receipt and outbox. Global/cross-zone changes
use the coordinator; neither StoryRun nor Session writes around Zone authority.

Solo, sync and async runs share these semantics. Persist participant choices,
waiting reason, knowledge/context revisions and an explicit tie/default policy.
A party vote cannot command another PC without consent. A paused experience
suspends its configured wall deadlines; a disconnected client alone does not
finish the story or advance the calendar. Narrative terminal predicates may seal
completion under published policy; canonical incorporation has its own authority.

One-off rewards/opportunities have world/campaign/actor uniqueness keys and
experience claims. Repeatability needs an explicit reset/resource policy.
Incorporating or retrying completion never grants the same award twice.

Overlapping adventures use the scope-claim and timeline-validation rules in the
time contract. Independent runs can proceed; a conflict with a claimed person,
zone or unique object is shown before interaction. Unexpected cross-scope effects
are reviewed during preparation, not merged by overwriting either result.
The MVP deliberately allows ready runs to wait for a paused group.

## AI and GM review

All generation, interpretation, dialogue, reflection and optional recaps use
Lemieux through the Genesis host. GM-defined automation policy controls purposes,
allowed actions, territory, protected facts, cost and causal limits. Campaign and
experience policy may narrow it, not expand it. NPC agendas are intentions;
out-of-policy structural/lore changes become reviewable proposals.

World reactions occur only within admitted local time or an approved incorporation/
downtime target. Oban may compute a candidate while nobody is connected, but an
idle application does not invent elapsed fictional time. Delayed/duplicate jobs
must match window, experience, generation and policy fences. A model cannot mark
its own proposal approved or expand its spending envelope.

The native GM workbench presents draft context, dependencies, possible consequences
and selected-player previews. Publishing content is separate from incorporating
resolved outcomes. One produces opportunities; the other changes shared history.

## Rehearsal

A GM may preview a bounded immutable checkpoint with isolated working state and
originally scoped copied actors. Label it non-canon before entry and throughout.
No parent mutable reads, reward export or automatic sandbox merge. Ordinary
experiences are instead intended to incorporate their actual outcomes; do not
silently classify solo play as rehearsal to avoid continuity accounting.

## Required cases

- Spare the proposed antagonist, negotiate, refuse or leave; subsequent beats adapt.
- Pause a multi-gathering experience, complete an independent solo errand, then
  incorporate their valid timeline once without real-time drift or summed overlaps.
- Reject conflicting scope acquisition and preserve both sides of an unexpected
  incorporation conflict for GM review; never resurrect resources or reroll history.
- Abandon after spending: preserve local costs/consequences for explicit closure.
- Publish a possible fire without burning a building; play it, complete, review
  and incorporate before the published atlas changes.
- Keep unrevealed notes, private dialogue, rehearsal history and another
  experience's provisional future out of player/NPC context.
- Fence duplicate completions, stale confirmations and old jobs after restore;
  preserve original source attribution through every canonical event.
