# Handoff: 08 — Experience completion, fictional time and incorporation

Status: **in progress — 08A local-time/completion foundation implemented**.
The entire Phase 08 gate is not complete. Do not start Phase 09.
Base: published `9d41176f2f83b907ab3348b2bbe20eaae3a3df79`, plus the current
uncommitted 08A diff. No Phase 08 work has been committed or pushed.

## Entry and publication evidence — 2026-09-05

The user requested committing/pushing the finished Phase 07 work, then continuing
Phase 08. Reviewed the 89-file 07B–07D change set against the preceding handoff,
preserved its scope, ran `mix precommit`: **342 passed**, seed **147270**.
That full gate includes the listed 07D predecessor regressions plus 03 clock and
04 temporal/deadline tests; the same suite was not redundantly rerun immediately.
Committed exactly those paths, pushed `HEAD:main`, and verified the remote SHA.
[GitHub Actions 33993626247](https://github.com/houllette/genesis/actions/runs/33993626247)
completed successfully, including its separate Dialyzer job.

Read current architecture, experience-time, workflow, Tempo, story/canon and
subsystem contracts, their product/knowledge/history guidance and the historical
architecture report. The current GM-first/time contracts remain authoritative.
The Elixir validation funnel governed focused red/green work and final validation.
Browser QA remains explicitly user-deferred; native tests do not replace it.

## 08A delivered contracts

### Local time, persistence and ownership

- Existing reducers already advance `State.time` and `State.elapsed` for paid
  actions. New accepted action logs additionally carry a version-1 `time` map:
  exact from/to coordinate, elapsed before/after, seconds, calendar ID/version
  and second unit. This is persisted with the original transition/event/receipt,
  not a second action or a separate mutable ledger table.
- `Core.LocalTime` provides pure scene advancement, contribution data and
  completion validation. `Persistence.LocalTime.summary/1` derives the Experience
  cursor from bounded owned snapshots and their original immutable checkpoints.
  It checks time/elapsed coherence and accepted event coordinates. It does not
  compare an old Experience against a subsequently changed published snapshot.
- `Runtime.call(scope, world, {:status, experience, {:elapse, amount},
  origin_revision, request_id})` is the native GM scene-time command. `amount`
  is a closed string-key map with `unit`, integer `value`, and nonblank `reason`.
  It runs through the existing World command coordinator and owning Zone.
  Active status, current GM access, revision, reservations and duration are checked
  before committing a snapshot transition, metadata ExperienceEvent and receipt.
- Scene time changes no inventory/resources by itself. It records an explicit
  duration, not a production/consumption simulation. Zero duration is a real
  sourced point with a new revision; it is not widened to a one-second interval.
  Rejections and exact retries do not add time. New scene logs retain the original
  input, resolved seconds, calendar mapping and `local-time-v1` policy.
- Until multi-place time coordination exists, **positive-time actions and scene
  entries require a one-place admitted footprint**. Returning from another place
  does not shrink that footprint. Zero-time multi-zone play remains supported.
  Existing positive-time travel and publication guards remain intact.
- New local advancement and declared totals are capped at **31,622,400 seconds
  (366 fixed 24-hour days)**. Existing action-level rules retain their own bounds.
  World/coordinate bounds are separate. No local/candidate job, recurrence or timer
  was added; Oban still runs the existing durable outbox, manual in tests.

### Completion, review binding and recovery

`Runtime.call(scope, world, {:status, experience, {:finish, declaration},
origin_revision, request_id})` is the narrow completion entrypoint. It currently
requires a real current campaign GM; Phase 09 must supply explicit authorization
for a published terminal policy, not forge a GM identity.

The closed declaration has:

- `elapsed_seconds`: total including recorded play, **not additional duration**;
- `outcome`: `completed`, `failed` or `abandoned`;
- `reason`: nonblank explanation, at most 2,048 bytes;
- `basis`: full footprint/global-dependency review digest, from
  `Workspace.experience_review/3` (or internal `Seals.basis/1`);
- optional boolean `review_required`: true seals into `needs_review`, otherwise
  `ready`.

The declaration must cover the recorded cursor. A larger total is retained as the
end-of-adventure duration for later timeline preparation; it does **not** move
local action timestamps, run due work, or add the already recorded time twice.
Actual failed/abandoned expenditures and source events remain intact.

The basis binds all visited snapshot digests, base references, claims, event
identities/payload digests, optional global dependencies and the calendar mapping.
A destination change invalidates finish even if the origin revision is unchanged.
No UI confirmation silently rebases its form's captured basis. Same request with
a changed declaration conflicts; the caller must retry an ambiguous result with
the original payload.

Finish freezes the configured deadline remainder, fences further play across the
Experience and captures **completion format 3** in the same transaction. It adds
a principal-scoped stable completion ID, declared total, recorded elapsed time and
the declaration to the existing footprint seal. Validation checks the matching
immutable completion source and expected ready/needs-review status, not only a
mutable completion map. Claims remain held. A zero-time format-3 ready completion
can use the existing one-Experience publication path; positive declared totals
cannot, even when every snapshot still has zero elapsed time.

Legacy `:ready` and formats 1/2 remain readable for compatibility. Existing empty
calendar/global seals retain their encoding; no old snapshots, bundles, temporal
facts or receipts are rewritten. New nonempty calendar mappings join the seal.
There is no reopening, correction/exclusion, review-clear or reward-export path yet.

Fault tests kill the owning Zone at `control_before_commit`,
`control_after_commit` and `control_after_install`, for both scene time and
finish. Before commit everything rolls back; after commit the cold owner reloads
the saved result. Same-ID retry creates one transition/event and one time change.
Replay uses recorded transitions, not fresh duration arithmetic, draws or clocks.

### Calendar qualification and native workflow

The only new migration is
`20260905214235_add_world_calendar_mapping.exs`: additive `worlds.calendar`
jsonb/default empty map. Worlds may set it **at creation only**, through the
existing native world-library form or `Worlds.create_world/4`. Existing ordinal
worlds keep their calendar identity and empty mapping; no hidden Gregorian epoch
is assigned.

A mapping is a closed version-1 map: `format`, `id`, `version`,
`implementation` (`gregorian` or `coptic`) and an explicit midnight `epoch`
with integer year/month/day. Reviewed modules are allowlisted; no user module
lookup or atom creation. Calendar years 1–9999 are the supported display range.
Pre-epoch coordinates work within that range. Unsupported/malformed mappings,
incompatible calendar versions/worlds, fractional seconds and out-of-range
coordinates reject explicitly.

`Time.Calendar` uses the installed **ex_tempo 1.6.4**:
`Tempo.new/1`, `shift/2`, `to_naive_date_time/1` and
`Interval.new/2` / `relation/2`. It preserves second precision and supports
clamped calendar-relative months/years (including a 366-day year), not fixed
30-day months. Fixed second/minute/hour/day durations remain available to ordinal
worlds. Adjacent half-open spans meet without overlap; empty spans reject so point
events cannot be widened accidentally. This is adapter qualification, **not**
scheduled market/season/observance or recurrence support.

No routes were added. The existing authenticated WorldLibraryLive and ReviewLive
routes remain in the `[:browser, :require_authenticated_user]` pipeline and
`:require_authenticated_user` live_session; GM/steward authorization is still
enforced in contexts. Calendar creation controls are collapsed. Review now shows
the streamed, source-linked time ledger, explicit scene-time form and finish
outcome/total/reason controls, with optional needs-review status. Native tests
cover creation → calendar-relative scene → saved local time, and paid action →
scene time → abandoned completion with publication still unavailable.

Ledger entries/explanations require current GM access **and the frozen event
audience**. A newly added GM sees the permitted current cursor but not an earlier
private time explanation. Source navigation uses the existing authenticated
history entry, which rechecks access independently. No new player host or model
integration is implied.

## Verification

Focused command for the new slice:

```sh
mix test test/genesis/core/calendar_test.exs test/genesis/persistence/local_time_test.exs test/genesis/persistence/local_time_footprint_test.exs test/genesis_web/live/world_library_live_test.exs test/genesis_web/live/review_live_test.exs --warnings-as-errors
```

Meaningful initial red: scene/finish commands returned `:command_interrupted`
because their tuple was not supported by the old command codec/path. Tests then
verified concrete durations, costs, sealed totals and the positive-total
publication guard. Calendar qualification began with the absent adapter and
asserted exact non-Gregorian results after implementation. The fixture initially
bound a PC after starting its claimed Experience; corrected fixture setup binds
before start, matching the real authority contract.

Focused new/changed families passed **26 tests**, seed **210006**, before the final
zero-duration/invalid-input test. The 03 clock/04 deadline and replay family also
passed alongside earlier new tests (**22 tests**, seed **27290**), including
three real weeks, supervised clock injection and backward wall/monotonic tests.

The final input-boundary regression first reproduced a `BadMapError` from malformed
scene parameters. Guarded attribute maps and typed integer parsing now reject
malformed scene/completion values and revisions without losing the review or
changing Experience status. The affected LiveView file passed **4 tests**, seed
**909445**, before refreshing the full gate.

Final `mix precommit`: **365 passed**, seed **822562** (45.2 seconds), including
the full suite, warning checks, format, strict Credo, dependency audits, usage-rule
sync, compile-connected xref and security scan. `git diff --check` is clean.
Separate `MIX_ENV=test mix dialyzer`: passed, 0 errors/skips, after removing an
unreachable error branch (no suppression). `mix assets.build` passed.
Migration: applied successfully in test and development. The existing development
server was left running; restart it before manually using the new schema/code.
Browser QA: deliberately deferred by the user. No browser/viewport/accessibility
acceptance claimed. Remote CI success above covers Phase 07, not this dirty tree.

## Remaining Phase 08 work and next safe grouping

1. **08B — coherent timeline admission and due work.** Add bounded, versioned
   schedules and stable occurrence IDs, explicit local/approved targets, point
   semantics `cursor < due_at <= target`, recurrence work/event caps and cursor
   continuation. Reuse the existing production/consumption, obligation,
   observance, route/season and NPC/faction laws. Qualify chunk equivalence,
   exhausted inputs, timed trade and causal limits. Extend positive-time travel
   and multi-place local cursors together; do not merely delete the guards.
2. **08C — parallel window/candidate preparation.** Validate all included and
   excluded Experiences, start offsets and dependencies, calculate maximum end
   rather than sum, interleave recorded results and due effects with stable ties.
   Add bounded resumable candidate batches/Oban workers. No wall-date catch-up,
   rerolls, model merges or partial published caches.
3. **08D — review, correction/exclusion and atomic timed publication.** Preview
   affected people/resources/obligations/calendar, bind target/base/manifest,
   preserve original outcomes and GM reasons, quarantine excluded rewards and
   release only validated owned claims. Include all-excluded/no-automatic-time
   cases, outbox/status/calendar commits, restart and stale-confirmation tests.
4. Complete the day-100 → day-103 collision journey. This slice proves that an
   independent two-hour courier can finish while the group remains paused, with
   published time and claims unchanged. It does **not** yet prove their combined
   day-103 publication or supply consequence. Those are required remaining gates.

Next run: inspect this uncommitted diff, run the focused command above plus
`test/genesis/persistence/history_lifecycle_test.exs`,
`test/genesis/engine/clock_test.exs`, and the Phase 07 transfer/incorporation/
global-standing race/recovery suites before extending ownership or time.
Preserve companion trip accounting, identity references, exact stock flows,
format-2 compatibility, format-3 declarations and publication fences.
Run `mix precommit` at the next handoff. Phase 09 remains not started.
