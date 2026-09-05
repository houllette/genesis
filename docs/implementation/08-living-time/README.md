# Phase 08 — Experience completion, fictional time and incorporation

## Validate phase 07 first

Read [phase 07's handoff](../07-world-zones/handoff.md). Run scope-claim/transfer
races, coordinator recovery, companion ownership, record privacy and local
trade/production/obligation tests. Recheck 04's experience snapshot/receipt/
publication fixture and 05's pause/resume workspace. Read [workflow](../workflow.md),
[architecture](../architecture.md), the full [experience-time contract](../experience-time.md),
[story/canon](../story-and-canon.md), [world subsystems](../world-subsystems.md)
and AGENTS background-job rules. Historical real-time scheduling is superseded.
Read [Tempo/time domains](../tempo-and-time.md); rerun 03's clock-isolation and
04's temporal serialization/deadline recovery tests against the actual Tempo pin.

## Outcome and scope

A multi-gathering adventure and independent solo errand complete in one advancement
window. The GM reviews actual outcomes and elapsed fictional time, then publishes
one consistent world update. No real-time drift, duplicate costs or partial canon.
This is the complete time/run foundation; story terminal predicates arrive in 09.

Proposed homes: pure local-time/completion/incorporation reducers, World coordinator,
durable manifests/claims/candidates/cursors, Oban preparation workers and native
GM impact/reconciliation views. Build these slices across fresh runs if needed.

## TDD slices

1. **Local time and pause.** Persist explicit action/scene duration contributions
   and an Experience cursor. Test multiple gatherings, zero elapsed time, paused
   turn/choice deadlines, changed wall clocks and long application downtime.
   A GM-declared total must cover accepted local event times without double-counting
   action durations. Restart and reconnect alone cannot change the calendar.
   Use independently supplied UTC, monotonic and fictional readings. Qualify a
   pure Tempo-backed adapter for one supported non-Gregorian calendar mapping,
   month/year arithmetic, half-open availability spans and calendar rollover.
   Test zero-duration events and incompatible/unsupported calendar rejection;
   allowlisted implementations only, never modules generated from user data.
2. **Completion.** GM-authorized finish seals actual local outcomes and duration.
   Failed/abandoned play seals partial results; it does not erase expenditures.
   Persist ready/needs_review/incorporated states and completion IDs. Duplicate
   finish and altered payload reuse fail safely. Fence new actions after sealing.
   Keep a narrow engine completion entrypoint for 09's authorized terminal predicate.
3. **Window admission and conflicts.** Enforce one open window and one active
   assignment per PC/NPC/item/opportunity. Acquire durable writable-zone/global
   claims, including scope extension before travel. They survive paused gatherings
   without long DB transactions. Independent zones can host separate experiences;
   overlapping merchant/zone claims offer join/wait/GM-reschedule. Draft world
   edits cannot mutate the pinned base. Test stale/amended dependencies.
4. **Timeline and candidate.** Seal admitted experiences, then interleave recorded
   local transitions with due effects from the common checkpoint in fictional
   order. Compute max(start offset + elapsed), not summed parallel durations.
   Sequential start offsets and additional following downtime are explicit.
   Revalidate read dependencies/resources after each relevant prior transition.
   A conflict with an accepted outcome goes to review; never reroll or LLM-merge it.
5. **Same laws, explicit target.** Reuse production/consumption, obligations,
   institutional observance, route/season modifier and one NPC/faction routine.
   Resolve local due work within local time; deduplicate its IDs at incorporation.
   Preserve source causes/participants and real occurrence dates. No target means
   no elapsed-time simulation. Test equivalent chunks, exhausted inputs, timed
   production versus trade, duplicate delivery and causal depth/fan-out limits.
   Use Tempo intervals for supported market/observance windows and seasonal/
   production spans. Bound recurrence expansion by approved target AND work/event
   caps; persist stable occurrence IDs and cursor. Test adjacent `[start, end)`
   spans and point-event `cursor < due_at <= target` semantics across chunks.
   The scheduler must not treat fictional dates as UTC jobs or bypass scope claims.
6. **Durable preparation.** Oban runs manual in tests: assert enqueue, then execute
   selected workers explicitly. Persist candidate batches, versions, hashes and
   continuation cursors. Bound event/zone scope before admission. Restart resumes
   authorized work, never catches up to today's wall date. Neither workers nor
   model callbacks publish a partial candidate or bypass scoped Zone/World ownership.
7. **Review and atomic publication.** Show affected people, places, resources,
   obligations, stories and elapsed time in the native workbench. Confirmation
   binds base revision, manifest digest and target; changed plans invalidate it.
   Commit affected snapshots, WorldEvents/source mappings, calendar, receipts,
   claims release, statuses and outbox atomically; install caches before exposure.
   Crash before/after publication and retry: one published result, no mixed world.
8. **Collision journey.** At day 100 the three-day Dock Crew experience spans
   three weekly gatherings while the two-hour courier finishes independently.
   The world remains day 100 until all are ready and approved; incorporation
   ends at day 103. Include a claimed NPC conflict and a causal cross-zone conflict.
   Preserve original play records through an explicit GM correction or deliberate
   nonpublication; quarantine unpublished rewards. Do not silently rewrite choices.
   Test excluded-experience claim release and an all-excluded window: no reward
   transfer or automatic time advance, with source records and GM reason retained.
   Advance the UTC test clock three weeks with no fictional change; a backward
   wall jump cannot extend monotonic provider timeouts or alter the final day 103.

## Handoff criteria

- [ ] Meeting end, logout, idleness and restart never advance fictional time.
- [ ] Completion seals recorded choices and coherent duration; all pending states
  and paused deadlines survive recovery.
- [ ] Independent experiences coexist; conflicting assignments/claims fail clearly.
- [ ] Concurrent durations use max end; local and global due effects run once.
- [ ] Tempo calendar/interval fixtures prove supported conversions, boundary
  behavior, version/precision preservation and capped recurrence expansion.
  Unsupported fantasy calendars fail explicitly; no Gregorian fallback is hidden.
- [ ] Candidate preparation is bounded/resumable; conflicts need actionable review.
- [ ] Canonical snapshots/events/calendar/publication receipt commit atomically;
  retries and stale confirmations cannot create partial or duplicate history.
- [ ] The GM can explain and approve Ashfall's changes through native UI.
- [ ] mix precommit passes; [handoff.md](handoff.md) records state transitions,
  actual schema/API, target/ordering semantics, crash tests and browser evidence.

Phase 09 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../09-authored-stories/README.md).
