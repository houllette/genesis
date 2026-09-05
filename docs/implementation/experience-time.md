# Experience-based time and world incorporation

Accepted direction from the user's latest review: Genesis is a personal GM
world-building tool with interactive adventures, not an always-running MMO.
This contract replaces real-time world progression and immediate cross-campaign
canon. It governs phases 01 onward; [phase 08](08-living-time/README.md) delivers
the complete scheduling/incorporation protocol. These are planned capabilities.

[Tempo/time domains](tempo-and-time.md) defines the selected library boundary:
Tempo supports clock injection and calendar/interval arithmetic; Genesis owns
fictional coordinates and advancement authorization. UTC recording time and OTP
monotonic elapsed time cannot be substituted for an Experience's local cursor.

## Four separate concepts

| Concept | Meaning | What closing it does |
| --- | --- | --- |
| Engine Session | An authenticated browser/SSH attachment | Detaches a client; never finishes the adventure |
| PlaySession | A real-world gathering, perhaps on Discord or Zoom | Saves/pauses play; does not imply fictional time passed |
| Experience | A durable adventure, with or without a StoryRun, spanning any number of gatherings | GM completion or an authorized narrative terminal state seals actual outcomes and elapsed fictional time |
| Advancement window | A GM-managed group of experiences starting from one world checkpoint | Validated incorporation publishes their outcomes and advances the shared calendar once |

One Experience can take three Friday evenings and represent two fictional days.
Another can finish in twenty minutes and represent one fictional hour. Neither
uses elapsed wall time as game time. Lemieux.Session is a fifth, unrelated term:
an inference session has no authority to finish any of these domain records.

## The default: a paused published world, durable active experiences

The GM opens an advancement window at the published world's checkpoint and date.
An Experience pins that checkpoint, rules/story/profile versions, participants,
declared setting scope and a start offset within the window. It has a bounded
working state and its own append-only ExperienceEvents. Zone authority validates
and persists each action immediately **inside that experience**. Disconnects,
abandonment and process failures do not lose acknowledged choices.

The canonical atlas/calendar remains at its published checkpoint until
incorporation. GM screens offer labelled Published / In progress / Ready to
incorporate views, with source-linked differences. Player views show their
experience state and its provisional world status, not another group's secret
working state. This is staging for eventual shared canon, not a default disposable
solo sandbox and not permission to duplicate spendable characters or items.

At most one advancement window is open per world for the MVP. Independent
experiences may coexist in it. It is acceptable for a completed solo adventure
to wait for the multi-gathering group before the world advances; the GM is
coordinating a table's continuity, not providing uninterrupted public-server play.
The UI explains what is waiting and provides useful preparation work meanwhile.
Do not implement speculative branches of branches or automatic arbitrary merging.

Start offsets do not grant access to another ready experience's assets. Phase 08
must prepare an offset footprint through eligible due effects up to its start,
then validate dependencies before admitting actions. Earlier phases reject
nonzero start offsets; they cannot offer later-date play against unchanged base
stock. Sequential use of a changed actor or reward waits for incorporation.

## Time inside an experience

Use an explicit local elapsed-time ledger. Ruleset actions/scene transitions may
advance it; freeform narrative may only propose a duration. Turn order and
wall-time response deadlines are separate. Pausing a gathering suspends configured
choice/turn deadlines; save remaining duration or an explicit revised deadline.
Restarting next week must not auto-defend a hundred turns or consume seven days
of supplies. Provider deadlines still stop stalled inference without advancing
fiction. No unattended PC starvation, aging, asset decay or scheduled world war
is caused merely by not opening the application.

Represent local elapsed time in explicit integer units under a pinned world
calendar/epoch. Calendar-relative months/years are resolved from that calendar
and start coordinate, not a fixed Earth duration. Keep an exact event coordinate
distinct from a calendar interval's bounds and display precision. Persist pause
remainders or policy-bound UTC deadlines, never a VM's monotonic counter.

An authored story declares duration rules: minimum elapsed duration, per-beat or
action time, and terminal elapsed-time calculation. A GM may enter/confirm the
duration for an unstructured or off-platform adventure. Record the inputs and
override reason. The conclusion cannot precede its latest accepted local event,
skip already-paid costs or contradict an established local timeline. Do not add
the narrative's total again to durations already recorded by actions.

Local effects due before that experience's local cursor may resolve in its
working state through the same pure laws. Mark them with stable due-event IDs so
world incorporation does not execute them a second time. Background tasks may
prepare drafts and paused-run data, but cannot advance the published calendar.

## Overlap: prevent obvious collisions, review the remainder

Start with conservative, durable **scope claims**, not a sophisticated simulation
merge algorithm:

- A world character, companion, unique item or one-off opportunity has at most
  one active experience assignment. Enforce this in Postgres, not only the UI.
- Claim writable zones and any mutable global resources when launching an
  experience. Only one experience writes a claimed zone within the window in the
  MVP. Other experiences may read the pinned base for permitted lore, not interact
  with a stale copy of its merchant. Keep footprints small so unrelated places
  can host independent stories. World-global dependencies may serialize more work.
- Starting or extending into a claimed scope returns an actionable conflict:
  join the existing experience where authorized, wait, or let the GM relocate/
  schedule the adventure. Joining uses its one working state, not an overlay merge.
- Claims are durable domain records that survive nights of paused play. They
  are not database transactions, held database locks or synchronous GenServer
  calls waiting for a human. Do not expire them because a client disconnected.
- Track read dependencies as well as writes. A regional consequence can conflict
  with another adventure even when their initial zone claims did not overlap.
  Incorporation validates causal order, preconditions, quantities and source
  revisions. A conflict is never resolved by last-writer-wins or an LLM rewrite.

World editing remains available as drafts while a window is open. Changing its
canonical base requires a deliberate amendment operation that invalidates pending
previews and revalidates affected experiences; ordinary wiki saves cannot bypass
claims. The simplest first release may require closing the window before such
an amendment. Never leave two independently editable copies of canonical fields.

## Completion is not the same as publication

Experience lifecycle: `draft → active ↔ paused → ready → incorporated`, with
explicit `needs_review` and `closed_without_publication` outcomes. “Failed” and
“abandoned” are story outcomes, not reasons to discard accepted actions. Closing
such an experience seals whatever actually happened, including costs and losses.

A GM with the required scope may mark the experience ready and confirm its
duration. A published story may delegate that operation to a validated terminal
predicate, including a bounded completion policy. No connected GM is required
for a solo player to finish such a story. Automatic *world incorporation* is a
separate opt-in policy, permitted only when all admitted experiences in the window
are ready, the timeline is valid and no conflicts/review-required changes remain.
Default world incorporation remains a GM review action.

While a group is paused, a solo run can become ready without changing its world.
New sequential experiences that rely on its reward wait for incorporation.
Unrelated experiences can still be admitted to the same window by the GM before
sealing. Beginning incorporation fences admission, edits and new experience actions.

For a conflict, show the exact facts, affected stories and proposed consequences.
The GM can revise an uncommitted proposal, bring participants into a consistent
continuation, or explicitly adjudicate a correction and revalidate it. Retiming
an experience requires rechecking all time-dependent outcomes, not just moving
its timestamps. Preserve the original play record and make material corrections
visible to affected players. A plot preference cannot silently undo their choices.
If a consistent reconciliation is impossible, stop for GM direction; do not
publish contradictory history. An explicit decision not to publish preserves the
play record and quarantines its rewards rather than silently exporting them.

A closed_without_publication experience is explicitly excluded in the sealed
window manifest with the GM's reason and source record. Its rewards/working assets
cannot escape; validated closure releases its assignments/claims without applying
its proposed world changes. Remaining included experiences determine the target
date. If all are excluded, closing the window does not advance time unless the GM
separately approves downtime. This is exceptional adjudication, not automatic
discarding of a failed story or a way to farm a reward and cancel its costs.

Before exclusion, validate dependencies from included experiences. Quarantine
the excluded assets, reconcile dependents and release only claims still owned by
that experience/generation. Ready status alone never releases a claim.

## Incorporation protocol

1. **Seal:** record immutable completion manifests, local events/draws, start/end
   offsets, dependencies, claims and policy versions for every experience in the
   window. An incomplete experience blocks sealing; only the GM can explicitly
   close/adjudicate it. Never advance around an active run and backdate it later.
2. **Prepare:** from the common checkpoint, build a candidate timeline ordered
   by fictional occurrence and stable tie rules. Interleave accepted experience
   transitions with eligible due world consequences through the same pure laws.
   Use recorded experience results, not replacement rolls or fresh LLM calls. If integrating a due
   consequence makes a recorded outcome impossible, mark a conflict for review.
3. **Advance once:** the target date is the maximum of each start offset plus
   its elapsed duration, plus any separately approved downtime *after* the window.
   Concurrent durations are not summed; sequential starts must be explicit.
   Apply local and global due-event identities once. Timed work outside the target
   stays pending, even if its Oban worker runs on a later real-world date.
4. **Review:** show the GM changes to people, holdings, institutions, routes,
   future beats and calendar, including causal explanations and unexpected
   effects. The candidate and confirmation bind base revision, manifest digest,
   rules/policy and target date. Editing anything invalidates that confirmation.
5. **Publish atomically:** the World coordinator commits the bounded candidate's
   affected snapshots, canonical WorldEvents mapped to ExperienceEvent sources,
   calendar, receipt, claims release, run status and outbox in one transaction.
   Install/reload affected caches before releasing publication fences. Retry with
   the same incorporation ID returns the same result. A partial world is never
   exposed as published.
6. **Continue:** subsequent campaigns start from the new checkpoint. Existing
   records retain causal links, beliefs, legacies and distinct knowledge. Recaps
   summarize the actual incorporation; they do not create a second set of events.

Preparation is resumable bounded work with durable candidate batches/cursors;
the final publication is not a transaction kept open during simulation or review.
For the personal-use MVP, cap affected zones/events before admission and reject
oversized windows explicitly. Do not promise unbounded atomic commits. Reuse
snapshot-plus-log persistence; this is not full event sourcing. Canonical commit
order, fictional occurrence time and an observer's learned time remain distinct.
After a restart, resume an already-authorized candidate, not simulation up to today.

GM-only downtime without an adventure uses the same preview/approve/incorporate
path with a declared target. This is how the living world develops between stories.
Pre-play history generation uses the same laws in an unpublished world; it never
regenerates an existing world's past.

LLM-assisted reactions are proposed in a separate bounded orchestration step,
within an active Experience or an explicitly authorized downtime preparation.
Persist/admit their validated intents before sealing the candidate; changing that
set invalidates its preview. Pure timeline preparation/replay never calls a model
or rerolls an accepted action. Newly due deterministic simulation uses supplied,
versioned keyed draws recorded with the candidate, stable across retries/chunks.

## Mandatory collision fixture

At day 100, the GM starts the Dock Crew's three-day bridge adventure and an
independent courier's two-hour errand in another claimed zone. The group plays
over three weekly gatherings; the courier finishes on the first evening.
Canonical day 100 and published bridge state remain unchanged between gatherings.
The courier is visibly ready, not silently merged or rewarded in another run.

When both finish, incorporate to day 103, not day 103 plus two hours and not three
real weeks later. Resolve a dated supply consequence at its correct position.
The next campaign sees the altered bridge, stock and relationship, and can later
hear a permitted reference to the deed. Private dialogue remains private.

Also test a solo request for the group's claimed merchant, scope expansion,
abandonment after spending, elapsed-time correction, pause/deadline recovery,
cross-zone dependency conflict, double completion, crash during preparation and
after publication, a stale confirmation, and no time change after idle restart.
Advance the test UTC clock through the three real weeks independently of the
fictional cursor; separately test a backward wall-clock jump and monotonic timeout
behavior. Tempo recurrence bounds and interval adjacency must not change the
expected day-103 result or bypass conservative scope claims.
