# Workflow for each fresh agent run

## Read a bounded context packet

1. Read repository `AGENTS.md`, this workflow, and the selected phase README.
2. Read [architecture decisions](architecture.md) and the research sections
   named by the phase. Read the full extended report before structural changes.
   Read [product/personas](product-and-personas.md),
   [experience time](experience-time.md) and [actions/knowledge](play-and-knowledge.md)
   from 01, plus [Tempo/time domains](tempo-and-time.md); [story/canon](story-and-canon.md)
   from 08; the complete [Lemieux integration](lemieux-integration.md) from 10.
   Current GM-first and
   session-time requirements supersede historical real-time/immediate-canon advice.
   Read [living history/context](living-history-and-context.md) from phase 01.
   Use the index's revised 00–16 order: GM workbench 05, Lemieux 10, player TUI 11,
   pilot 12, full NPCs 13, long history 14, advanced GM tools 15 and release 16.
   Read [experience quality](experience-quality.md) for the early pilot and later gates.
   Read [TUI-first play](tui-first-play.md) from 11 and
   [world subsystems](world-subsystems.md) for 02's capability vocabulary and
   from 06 onward. Phase 11 combines browser and SSH play; 06 now owns local
   subsystem foundations. Do not follow obsolete transport-only folder names.
3. Read the preceding phase's `handoff.md` and inspect its actual code/tests.
   Read older handoffs only for contracts this phase consumes.
4. Check `git status --short`, branch, remote, `.tool-versions`, and `mix.exs`.
   Preserve unrelated work. A handoff describes a specific revision; reconcile
   any later changes before treating its evidence as current.

The plan describes future files and commands as proposals. A handoff must name
real files and exact runnable commands. Do not report a proposed test as passing.

Read the [final execution review](execution-review.md) for sequencing, claims,
audiences, proposals and replay. For an authorized consecutive-phase batch,
validate focused predecessor tests at each boundary and run `mix precommit`
on the final batch. Each handoff records its acceptance evidence and the shared
gate. This does not waive any phase acceptance criterion.

## Validate the predecessor before implementing

Run the predecessor's focused acceptance commands and the specific regression
checks listed at the start of this phase. Inspect its migration/config changes
and unresolved blockers. Verify at least one externally visible behavior, not
merely module existence. Record results under this phase's entry validation.

If a predecessor invariant fails, repair the narrow defect with a regression
test before proceeding and record the correction. If the predecessor is
incomplete or requires an unresolved design decision, mark this phase blocked;
do not construct new behavior on a false assumption. Missing dependency approval
blocks only work that requires that dependency. Prepare its precise proposed
change and continue independent in-scope work where useful.

The explicit exception in phases 10–13 permits development with a verified fake
provider while live-provider evidence is pending. Carry that gate forward by
name; neither phase completion nor release readiness may be claimed until it
is satisfied. This does not waive failed deterministic or authorization tests.

## Red–green–refactor, one behavior at a time

1. Choose one numbered slice from the phase. Write a test stating its observable
   result or invariant; run it and capture the expected failure. Compile errors
   from a missing module are only an initial step: get to a meaningful failing
   behavior assertion before considering the test proven.
2. Implement the smallest working change. Keep rules in pure modules and IO in
   the shell. Avoid placeholder frameworks, unused public APIs, and speculative
   dependencies for later phases.
3. Run the focused test, then refactor while green. Add edge cases that can
   actually fail: invalid input, authorization, duplicate work, stale state,
   interrupted transactions, and disconnected consumers as relevant.
4. Run affected integration tests. Move to the next slice only when its behavior
   and its new contract are understood.

Use `mix help <task>` and installed dependency documentation before unfamiliar
Mix tasks or APIs. Prefer `mix test path:line`, then the affected file. After a
failure use the appropriate focused retry; do not rerun the whole gate after
every edit. Do not change quality gates or suppress warnings to make them pass.

## Testing conventions

- Pure tests use `ExUnit.Case, async: true`, supplied clocks/draws/IDs, and
  assertions on exact results. Enumerate bounded dice outcomes and transitions
  to check invariants without statistical or wall-clock tests. Add a property
  testing dependency only if approved and materially useful.
- OTP tests use `start_supervised!`, unique registries/child IDs, monitors,
  messages, and explicit barriers. Avoid sleeps and `Process.alive?` checks.
  Use `async: false` only for justified shared global state.
- Use Tempo.Clock.Test for the selected wall-clock boundary and separate explicit
  monotonic readings. Select and pin in the reading process; supervised children
  do not inherit test-process pins. Pass clock dependencies explicitly and test
  that child reads use them. Real, monotonic and fictional time move independently;
  no core clock reads or per-test global clock configuration. Carry precision,
  calendar/version and bounded-recurrence regressions after their owning phases.
- Persistence tests use `Genesis.DataCase` and real Postgres. Give spawned
  processes explicit Sandbox access. Rollbacks, restarts, and competing writes
  need observable state/log assertions, not only mocked Repo calls. SQL Sandbox
  ownership alone does not prove races between independent connections: use a
  separately isolated integration setup for the races that require it.
- Oban remains manual by default. Use `assert_enqueued`; execute workers
  explicitly or within `Oban.Testing.with_testing_mode(:inline, ...)` when
  behavior needs it. Test duplicate delivery even when jobs use uniqueness.
- Transport tests drive the public Session contract. LiveView tests use stable
  IDs and selectors; terminal tests use the chosen release's test backend.
  Also perform real SSH checks: a headless renderer cannot prove SSH auth.
  Player screens belong to one shared TUI. Test headless rendering/input,
  LiveView auth/cell payloads, actual browser JS/focus/resize and actual SSH.
  Compare shared semantics rather than pixel identity; capability changes must
  clear old secrets from both hosts' buffers before safe deltas resume.
- Inference integration tests run actual Lemieux sessions using its Scripted
  provider with Genesis's real tool/store/environment adapters. Adapter mocks
  alone are insufficient. Exercise rejection, fallback, implicit file-reference
  denial, resume and shared budget paths; never require a paid API key for
  `mix precommit`. Live checks separately record model, cost, date and upstream SHA.
- Security tests inspect unauthorized payload absence in state, messages,
  history, cache keys, and model context; hiding a DOM element is insufficient.
- Grow the two-campaign Ashfall fixture from [product/personas](product-and-personas.md):
  one published world truth, labelled experience-local outcomes, different private
  knowledge, player-driven consequences and explicit rehearsal isolation. Include
  completion/incorporation, off-suggested-path actions, changed
  prerequisites and replay without re-inference. “Canon” is not “public.”
- Add paired-context tests: same situation/draws with one changed character,
  prior deed or present companion; assert a specified mechanical difference.
  Also assert an irrelevant change makes no difference. Persist context versions
  and causal source references; fixture text differences alone are insufficient.
- Test lasting legacy separately from reminder frequency: player action →
  completion/incorporation → approved-time consequences → restart/new campaign → relevant callback, with
  negative tests for unauthorized, unrelated and repeated references. A later
  repair changes current state without erasing history. Run small deterministic
  generation/live-continuation equivalence tests; measure long history separately.
- Subsystem tests assert stock/balance/recipe accounting, atomic trade under
  races/retry, scoped belief/standing and a connected player-visible consequence.
  Record-only/disabled actions must fail explicitly. Run religious/currency and
  secular/barter presets; test migrations refusing to orphan live obligations.
  Scheduled/history versions must reuse the laws tested under explicit actions.
- Test the primary GM journey before optional player polish: curate without a
  player, pause across gatherings, inspect pending outcomes/duration, incorporate
  and understand consequences. A finished solo run may wait for the group's
  window. Verify max end-time, no idle drift, stable claims, stale confirmation
  and no double publication. Quality evidence follows experience-quality.md.

Suggested regression suites, added when the behavior first exists, live under
`test/genesis/{core,systems,engine,persistence,content,llm,transport}` and
`test/genesis_web/live`. Keep one readable end-to-end fixture journey growing
across phases instead of duplicating the engine in test helpers.

## Finish and hand off

1. Demonstrate the phase's acceptance scenario and preserve reproducible fixture
   setup. Document migrations, config, APIs, behavior changes, and limitations.
2. Run `mix precommit` after the implementation stabilizes. It includes the full
   suite and **writes** formatter/rule output. Inspect the resulting diff. If
   it fails, fix/retry the specific failing check, then rerun the final gate.
3. Record Dialyzer and remote CI separately; neither is implied by local
   precommit. Run additional checks required by changed CI or deployment files.
4. Fill in this phase's `handoff.md`: status, validated revision/diff, entry
   validation, implementation, public contracts, exact acceptance commands and
   results, real-service evidence, known limitations, and next validation steps.
   Include the persona journey advanced, world/campaign/continuity scope,
   definition-versus-event distinction, and AI/upstream gates where applicable.
   Every changed contract needs a named regression command for the next agent.
   For time work, include the Tempo pin/API, child-process clock setup, supported
   calendar capabilities, serialization precision and endpoint/recurrence rules.
   Include context sources/versions, companion ownership, causal consequences
   and legacy/callback evidence where applicable; do not hide these in a recap.
   From 05 include the actual native GM workflow; from 11 include shared-TUI
   regressions for both hosts; from 06 include each
   subsystem's actual playable/record-only/deferred status, schema/capability
   versions, conservation rules and next extension owner. Stubs are not features.
5. Ensure links resolve and `git diff --check` is clean. A complete phase has
   every required acceptance criterion satisfied and no hidden TODO behind a
   default-enabled feature. Explicitly deferred work stays outside its claims.

Do not commit/push/deploy merely because a phase is complete; follow the user's
publication instruction for that run. If publishing is authorized, stage exact
paths and report remote checks separately. Stop at the selected phase boundary.

## If the run ends before the phase does

Set handoff status to `in progress` or `blocked`, never `complete`. Record the
last green slice, uncommitted paths, exact failing test/error, pending approvals,
and the next small action. Update the existing handoff when resuming; retain
important prior verification provenance. This handoff is the continuation
context, not a substitute for passing the phase's exit gate.
