# Handoff: 08 — Living time and window incorporation

Status: **complete within the explicit bounds below**, with final local validation
recorded at the end. Phase 09 has not been started. Browser QA remains
explicitly user-deferred, not represented as an automated pass.

## Publication and predecessor

The requested initial publication is complete: `d860d7f` contains 08A, after a fresh
`mix precommit` passed 365 tests (seed 547840). Remote CI exposed two Phase 07
recovery barriers using the default 100ms wait for database-backed work. The narrow
synchronization fix is `7dbf1b5`; its focused file passed 22 tests and its fresh
precommit passed 365 (seed 207900). Both commits were pushed to main, and
[GitHub CI 33995604294](https://github.com/houllette/genesis/actions/runs/33995604294)
passed. The new 08B–08D work described here is included in the Phase 08 completion
commit; the linked CI run covers only its predecessors.

[The archived 08A handoff](08a-handoff.md) retains calendar, deadline, serialization
and completion evidence. Its restrictions are historical, not current instructions.
Read the current architecture, experience-time and Tempo contracts before extending
these seams. No dependency or shipped migration was changed.

## Local time and dated laws

- Zones remain single writers. Local scene time and paid actions resolve due
  effects in their existing Zone transaction. World-owned jobs produce unpublished
  proposals, never independently write working/published Zone caches.
- Experience cursor = maximum elapsed among visited snapshots. Lagging places
  must catch up before acting/travelling. Catch-up runs their laws, not the elapsed
  adventure total again. **Do not sum per-place ledger contributions.** Travel is
  still a zero-duration relocation; explicitly record journey time as scene time.
- `experiences.start_offset` is a nonnegative offset from the pinned world base.
  Starting records individual pre-start due transitions, then sets play elapsed
  to zero. Pre-start effects are not extra Experience duration. Setup is bounded
  and atomic; an over-cap start writes no partial state or claims.
- Paid actions spanning due points retain the proposal and captured dice inputs.
  `ActionTime` applies due laws, revalidates the original terms, and resolves with
  those same inputs. Due transitions and the action commit together; duration and
  costs are charged once. Changed quotes/preconditions reject the entire transaction,
  never silently refresh a confirmation. The GM may explicitly advance a scene
  boundary before requesting new terms. Replay/incorporation use recorded results.

`Core.Schedule`, `DueWork`, `TimeSteps`, `RecordedChange` and `Timeline` are pure.
Definitions live in optional versioned `State.timeline`. Codec still omits nil
fields, preserving old checkpoint bytes/digests. Curation requires increasing
versions and a first point strictly after the current coordinate. No wall date,
gathering end, login, timer or restart chooses a fictional target.

Scheduled `produce`, `rest` (consumption), `disrupt` (authorized merchant loss),
`offer` (obligation) and `adjudicate` (institutional review) reuse Phase 06 laws and
real stock. They require a living local NPC, never an implicitly automated PC.
This is deterministic GM-authored work, not LLM autonomy or a hot NPC process.
Scheduled NPCs remain anchored to their place. Faction-wide autonomous planning
is not implemented here.

`condition` points set normal/harsh/closed place conditions. Harsh halves integer
production capacity; closed forbids production and travel involving that place.
A later normal point reopens it. This is the bounded seasonal/route law, not
weather simulation or automatic journey-time calculation.

Optional `availability: {from, to}` is half-open, so a due point at `to` is outside.
Mapped Gregorian/Coptic calendars use installed Tempo 1.6.4 interval endpoints;
ordinal worlds use explicit integer spans, never a hidden Gregorian epoch.
Recurrences support fixed seconds/minutes/hours/days and mapped months/years.
Each relative recurrence shifts the previous occurrence with Tempo's clamp rules,
not a fixed 30-day month or an original-month-day anniversary guarantee.
Unsupported relative calendars reject. Points are cursor-exclusive and target-
inclusive; equal-time due points use stable zone/schedule ordering.

Occurrence IDs hash world, generation, zone, schedule ID/version and coordinate,
not execution scope or batch. Exhausted work records one skip without creating
stock. Cross-zone condition dependencies retain an observed causal parent/root
when present. Causal depth is capped at 8. Arbitrary spawned schedules/effect
fan-out are rejected (spawn fan-out is zero); authored schedule/work caps bound
all expansion. Schedules have no authority to publish anything.

## Window preparation and reconciliation

Migration `20260905223006_add_timeline_preparations.exs` adds the offset and
`timeline_preparations`, widens the unique active-window index to all nonclosed
windows, and permits a null incorporation Experience ID for whole-window/downtime
publication. Legacy start receipts missing the new field restore offset zero.

Window: open → sealed → closed; cancellation reopens it. Preparation: preparing →
ready / needs_review → published or cancelled. Completion ready/needs_review still
holds claims. Publication closes included adventures as incorporated, exclusions
as closed_without_publication. Original snapshots/seals remain; new adventures
load published state, never excluded working rewards.

Preparation requires current steward and GM access to **every admitted adventure**,
a decision/reason for each, valid seals/claims/checkpoints/replay and unchanged
calendar/global dependencies. Sealing fences admission and working mutations;
authoring becomes drafts. Independent DB connections serialize on the World row.

Target = `base + max(included start_offset + reviewed total, default 0) + approved
additional downtime`. Totals already include recorded play. Corrections cannot
precede recorded play or retime choices. All excluded plus zero downtime advances
zero. A decision has mode include/exclude, nonblank reason and optional
elapsed_seconds override; original completion remains unchanged.

Manifests bind generation/world revision, completion digests/decisions/offsets,
sources, calendar, target, policy and base digests. Work/digest persist candidate
states, ordered records, generated occurrences, cursor, processed count and conflicts.
`PrepareTimeline` reloads the stored principal's current authority and executes
one bounded batch through World. Jobs carry only preparation/world/generation;
restart and duplicate/late terminal deliveries cannot invent extra time.

Timeline ordering: due points first, then commit cursor for equal-time local
records. Local due work is checked against its candidate occurrence and published
once with its source link. Multiple same-coordinate occurrences are checked
individually. Other records apply checked deltas/read dependencies; **terminal
working snapshots are not last-writer-wins replacements**. Conservative same-place
read checks can require review where a looser merge might be possible. Prior
stock/condition/resource conflicts never cause rerolls or model merges.

Conflicts identify place, coordinate and source. Cancel and prepare explicit revised
duration decisions or exclude the conflicting adventure. No automatic rewrite of
recorded choices exists. Audience-bounded window notices retain original/reviewed
totals and GM reasons; reasons should be shareable with affected participants.
Historical private event audiences are not widened by later membership.

## Native workflow and publication

`/worlds/:world_id/time` uses the existing authenticated browser pipeline and
require_authenticated_user live_session. Context checks additionally require steward
and all-window GM authority. It provides decisions, downtime, batch progress,
before/after people/resources/knowledge/conditions, cancellation and separate
preview/confirmation. Schedule creation is collapsed and typed, not JSON. Review
links to it; travel offers explicit place admission/catch-up; Experience creation
has a collapsed start-offset field. No broad UI polish or Phase 09 story work.

Runtime commands (current scope passed separately):

```elixir
{:admit_place, experience_id, zone_id}
{:scene_time, experience_id, zone_id, amount, revision, request_id}
{:prepare_time, %{"decisions" => decisions, "downtime_seconds" => seconds,
                 "reason" => reason}, request_id}
{:step_time, preparation_id, generation} # normally the durable worker
{:cancel_time, preparation_id, digest, reason}
{:preview_time, preparation_id}
{:incorporate, preview_id, request_id} # existing fenced publication
```

`amount` retains unit/value/reason. Preserve request IDs on ambiguous retries.
Preview binds candidate hashes, target, base and manifest, not just displayed time.
The old zero-time APIs remain supported. One transaction saves snapshots/indexes,
source-linked WorldEvents, global standings, calendar/revision, statuses, releases,
receipt and outbox. The existing ledger fences readers until every Zone cache is
installed. Audit events retain occurrence dates; snapshot transitions represent
an atomic publication batch, not arbitrary as-of state at its interior event dates.

Hard bounds: 8 published places per prepared window, 16 adventures, 16 schedules
per place, 512 source records, 1,024 timeline work steps, 32 steps per worker batch
(maximum 64), 64 local occurrences per command/start, and the existing 2MB Codec
payload limit. Approval spans/offsets/totals are at most 366 fixed days. Limits
reject or require review, never silently truncate. Larger worlds/long-history
replay require an explicit later capacity design.

## Verification and next phase

Phase 09 entry command:

```sh
mix test test/genesis/core/due_work_test.exs test/genesis/core/timeline_test.exs test/genesis/persistence/scheduled_time_test.exs test/genesis/persistence/preparations_test.exs test/genesis/persistence/timeline_review_test.exs test/genesis/persistence/timed_race_test.exs test/genesis/persistence/day103_test.exs test/genesis/persistence/local_time_footprint_test.exs test/genesis_web/live/time_live_test.exs --warnings-as-errors
```

Preserve Phase 07 transfer/standing/publication race/recovery and Phase 03/04
clock/deadline/serialization tests; final precommit runs them all. Meaningful red
tests caught absent commands, paid-action due-work rejection and the old positive-
time footprint restriction. A committed-connection test caught missing teardown
for the new table; cleanup now removes only its own jobs/preparation before its
window/user. The leftover generated test fixture was removed, not user data.

The day-100 → day-103 test includes a paid action, three weekly gatherings/pauses,
three local days, a parallel two-hour courier, a claimed-place/NPC conflict,
three dated supply events, a backward UTC jump, publication retry and a new
adventure reading the resulting stock. Separate cross-zone condition/trade
conflicts require review. Five publication crash stages cover two places; failed
preparation batches and World restart resume the saved cursor. Native tests cover
decision → prepare → impact → confirm → publish and unauthorized-user denial.

Implementation closeout `mix precommit`: **393 passed**, seed **52596**, 66.9 seconds. This includes
the full suite, warnings-as-errors, format, strict Credo, dependency audits,
usage-rule sync, compile-connected xref, security and docs checks. The first full
run identified two obsolete 08A expectations; the affected files passed 5 tests
(seed 414717), then the entire gate was refreshed. The injected-crash tests may
log a database client disconnect; they passed their recovery assertions.

Separate `MIX_ENV=test mix dialyzer`: passed, 0 errors/skips. `mix assets.build`:
passed. `git diff --check`: clean. Migration applied in test and development.
The existing development server was left running; **restart it before manual use**.
No Browser QA was performed, following the user's explicit deferral. The Elixir
validation funnel guided focused red/green checks and the complete handoff gate.
Remote main was reverified at `7dbf1b5`; its CI result covers the published 08A/CI
repair commits, **not the Phase 08 completion commit**. Check that commit's own
GitHub Actions run for remote validation.

Publication gate refresh: `mix precommit` passed **393 tests**, seed **47672**,
67.9 seconds, before staging the Phase 08 completion commit.
