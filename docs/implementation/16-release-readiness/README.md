# Phase 16 — Integrated alpha and operational rehearsal

## Validate phase 15 first

Read [phase 15's handoff](../15-gm-tools/handoff.md). Run native advanced GM controls,
possession, pending-window checkpoint restore and all affected experience/claim/confirmation
fences.
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
Also read [coverage](../coverage.md) and each earlier phase's actual evidence summary; an
unmet service/quality gate is not passing evidence.

## Outcome and scope

A reproducible, measured personal-use GM tool for a small invited table on one node. This phase supplies
release tooling, operational documentation and evidence. It does not silently
provision hosting, invite third parties, spend on providers, or deploy publicly.
Prepare those steps completely; execute them only within the run's authority.

Proposed outputs: release/runtime configuration, migration and backup procedures,
`docs/operations/`, realistic integration fixtures and bounded load harness.
Use a supported single VM or one application replica with Postgres. A rolling
deployment that briefly runs two engine writers is not a safe single-node plan.

## Work and verification slices

1. **Reproducible release.** Build production assets/release, configure secrets
   at runtime, validate migrated database compatibility and host-key persistence.
   Document startup, shutdown/drain, scheduled-work recovery and a maintenance
   deployment that prevents overlapping world owners. Roll back code only when
   the database format is compatible; otherwise provide a forward repair path.
2. **Observability and limits.** Expose useful zone/session/NPC counts, mailbox
   pressure, intent latency, DB failures, due-work lag, catch-up backlog, provider
   latency/spend and rejected actions. Keep prompt/secret payloads out of metric
   labels and ordinary logs. Bound connections, queues, history query windows
   and working memory while preserving durable canon and source retrieval;
   operators can disable AI without disabling deterministic play.
3. **Product walkthrough.** First create/curate/preview in the native GM workbench
   without a connected player. Then rehearse one GM and two remote players with mixed
   SSH/browser clients in the three-zone world. Show both rulesets, travel,
   combat, private information, a dormant routine, disconnect/reconnect, shared
   NPC conversations, approved generated opportunities, solo campaign, synchronous
   party gathering and async wait/resume. Both rulesets are demonstrated in their
   own worlds; two campaigns share Ashfall's one ruleset/canon.
   Complete every persona journey: GM builds/publishes and logs off; the party
   negotiates instead of taking the suggested combat path; the courier discovers
   changed patrols and a follow-up hook without seeing the secret negotiation.
   Show linked atlas/journal/organisation/objective/calendar/history state, two
   NPCs' distinct persistent personas, a bounded autonomous reaction and explicit
   non-canon sandbox isolation. Record exact setup and observable outcomes.
   Add the contextual bridge-crisis journey: different PC history and allied/
   hostile companions change mechanics and beat direction. After a major player
   deed, advance time, restart and archive its campaign; another campaign sees
   lasting physical/economic and social changes plus an occasional eligible
   historical reference. Then repair/reconcile one consequence: current state
   changes but the original deed remains. Test negative callback cases as well.
   Use the same player TUI in the browser Play tab and SSH, including actual
   resize/focus/paste, tab reopen, clear-on-revoke and accessible action flow.
   Rehearse the supply/recipe/rest/trade/offering chain and later institutional
   response in religious/currency and secular/barter worlds. Verify quantities,
   receipts, disclosure and unsupported-capability errors, not only UI labels.
4. **Failure rehearsal.** Interrupt the app/zone during a mutation, transfer,
   catch-up, story consequence, provider request and rewind. Simulate temporary
   Postgres/provider loss. Verify no acknowledged-action loss, duplication,
   stale-generation mutation, unintended disclosure or unbounded retry/spend.
   Include two-campaign resource/quest conflicts, implicit file-reference attacks,
   private-to-public Lemieux context changes and reaction-cascade shutdown.
   Include competing last-stock purchases, timed production versus spending,
   stale quotes after rewind and interrupted subsystem profile migration.
5. **Backup and restore.** Restore database plus referenced content versions and
   host-key configuration into an isolated environment. Verify representative
   state/history, auth, campaigns/journals, sandboxes, NPC personas/relationships,
   vector memories, Lemieux transcripts/budget reservations and scheduler cursors. Record
   measured restore time and the backup's actual recovery-point limit. Verify restricted
   access to prompt/response records; no data-lifecycle workstream is required.
6. **Capacity experiment.** Fix hardware, BEAM version, data volume, actor
   distribution, action rate, time horizon and provider mode before a run.
   Measure the declared small-table target first; larger counts are optional,
   include one crowded zone, spread zones, reconnections and many dormant NPCs.
   Include multiple campaigns using the same NPC and concurrent authoring/dialogue/
   reaction workloads with predeclared budget and queue limits. Do not run paid
   inference in the load test unless spending is explicitly authorized.
   Distinguish synthetic sessions from real encrypted SSH/rendering connections.
   Record p50/p95/p99 latency, errors, memory, mailbox/backlog and DB utilization.
7. **Continuous-history scale rehearsal.** Reproduce phase 14's fixed 2,000-year
   profile, record semantic event/entity/lineage counts and resource use, then
   continue it with actual player actions and bounded off-screen simulation.
   Measure indexed context/history lookup and callback behavior after accumulated
   play, not just initial generation. Compare two supported world profiles and
   their mechanical consequences. List unsupported/deferred DF-scale subsystems
   and generation/live detail differences explicitly; no “endless” capacity claim.

## Performance acceptance policy

Before measuring, record an explicit invited-alpha capacity target and thresholds
in the handoff. Proposed starting target: one GM plus four player attachments, non-LLM intent
p95 below 250 ms on the chosen host, no lost/duplicate accepted actions, no
unbounded queue/memory growth during a 30-minute steady workload, and restart
recovery below 60 seconds for the demo world. These are engineering targets,
not research-backed measurements; adjust transparently before the experiment
if hardware or the intended audience requires a different target.

Report LLM latency/cost separately. Meeting a small-table target does not prove
hundreds of players. Missing hardware, credentials or spend authority leaves
that evidence gate pending. Do not report estimated performance as a benchmark.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md).

Reproduce day 100: a three-day group experience across three gatherings plus an independent
two-hour ready solo run. With no idle drift, incorporation ends at day 103. Exercise claims,
causal review, partial failure, stale confirmation, paused deadlines and one atomic
publication. Demonstrate native curation/reconciliation usability before optional player
polish. Preserve secrets, authority, spending and recovery safeguards; do not add
public-platform scale or the removed data-lifecycle proposal as gates.

## Handoff criteria

- [ ] GM-first usability and overlap/incorporation recovery are proven at personal-table scale.

- [ ] Every product acceptance item in [the plan](../README.md) is demonstrated
  on actual transports; live provider evidence includes cost/model/provenance.
- [ ] Isolation, crash, duplicate-work, revoke and rewind scenarios pass.
- [ ] Cross-campaign consequences, GM-offline discovery, divergent player outcomes,
  universal personas and bounded autonomous change are demonstrated end to end.
- [ ] Character/deed/companion variation, continuous generated-to-live history,
  lasting player legacies and selective later references have actual evidence.
- [ ] One shared player TUI is proven in browser and SSH; no deferred second
  transport or separate browser gameplay implementation hides behind parity claims.
- [ ] Economy, commerce and religious/secular institutions have connected,
  persistent mechanics. The subsystem matrix accurately labels basic, record-only
  and deferred support; conservation, disabled-action and migration tests pass.
- [ ] All inference uses the pinned Lemieux path; transcript/tool/environment/
  budget gates and real embedding integration are verified, not bypassed.
- [ ] Release restart and an isolated backup restore have recorded outcomes.
- [ ] Predeclared capacity targets are met by a reproducible measured run;
  supported limits and failed experiments are documented.
- [ ] `mix precommit` passes; Dialyzer and applicable workflow/release checks
  pass. Report remote CI separately if a publication was authorized.
- [ ] [handoff.md](handoff.md) links operational runbooks, exact demo/restore/load
  commands, evidence artifacts, known limits and any unmet release gates.

The next run begins by validating this release's version, migrations, smoke
journey and recovery evidence before extending the engine. Unmet evidence gates
mean the alpha is not yet fully validated, even if implementation tests pass.
