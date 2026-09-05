# Final execution review — 2026-09-04

Reviewed the shared contracts and phases 00–16 against the historical report and
the actual Phoenix baseline. These clarifications resolve implementation
ambiguities; they do not qualify historical library or performance claims.

## Ownership and phase boundaries

- Phase 03 introduces the minimal World authority for in-memory admission and
  claims. Phase 07 extends that owner with global facts and transfers; it must
  not start a second World process or move claims to a competing context.
- Phase 01 is pure and phase 03 is ephemeral. Their successful results are not
  crash-durable acknowledgments. Phase 04 supplies snapshot/event/receipt/outbox
  persistence before game routes arrive in 05. Do not expose the ephemeral
  shell for real adventures.
- Phase 04's incorporation is a single-zone zero-duration storage proof.
  Through 07, nonzero-duration actions can be staged and inspected but cannot
  be incorporated. Earlier cross-campaign demonstrations use an explicitly
  zero-duration fixture, never erased action time. Phase 08 reconciles time.
- An authorized batch may span consecutive phases. Validate focused predecessor
  regressions at each boundary and run the final gate on the completed batch.
  Each included handoff records its own acceptance evidence and that shared gate.

## Admission, completion and exclusion

Claim keys use canonical world/generation and resource identity, not campaign
identity. Read-only lore access grants no interaction right. Preparation
candidates are not live actor assignments; rehearsal assets cannot be exported.

`ready` retains claims until publication or explicit exclusion. Pause, connection
loss and process restart cannot release them. Before exclusion, verify no included
experience depends on its provisional outcomes. Quarantine excluded assets and
release only that experience's claims using expected owner/generation checks.
Reconcile already admitted dependents instead of leaving unexplained missing assets.

A nonzero start offset cannot import another ready run's rewards. All experiences
still pin the common base; sequential use of changed assets waits for incorporation.
Before an offset experience acts, phase 08 catches its footprint up to its
authorized start and checks due effects/dependencies. Day-102 play cannot use
stale day-100 stock. Earlier phases reject nonzero start offsets.

## Commands, confirmation and replay

Separate the trusted server envelope from allowlisted client action fields.
Principal, actor, role, scope, policy, context, IDs and draws come from authority.
A pure API accepts explicit trusted values for testing; it is not a network
authorization boundary. No whole authority state goes to a client.

A proposal is not a reservation or a resolved roll. Bind its exact action,
principal/actor, scope, policy and consulted revisions; retain it server-side
and return only disclosable terms. Confirmation revalidates before consuming
draws/resources. Hidden and absent targets share a public error. Missing targets
request clarification without charging an action.

Compound work stops at its first rejection, retaining accepted earlier steps.
Phase 04 gives each step a stable `(plan_id, step_index)` receipt linked to the
parent request. Resume the first unresolved step after timeout. An atomic
exchange remains one step. A resolved unsuccessful check is an accepted outcome
and may pay declared costs; validation rejection consumes nothing.

Replay applies recorded transitions with precondition checks, not historical
intents under the latest rules. Never reroll or replace a candidate zone with
an experience's terminal snapshot: interleave changed fields/ownership and due
effects, reporting conflicts. At equal coordinates, causal parents precede
children; remaining ties use pinned policy and stable event IDs. Canonical
commit order is a separate cursor.

## Knowledge and disclosure

Resolve event audiences to eligible identities at occurrence. Historical `party`
or `occupants` cannot mean whoever belongs now. Current access is also required.
Present state and historical event projection are distinct: acquiring an item
may reveal its name without granting the private conversation that promised it.

Restricted source IDs, relationship endpoints, counts, diagnostics and variant
reasons can leak secrets too. Omit them or emit a safe summary. Resolving an NPC
response may use its knowledge; explaining it to a player cannot disclose all
consulted facts. Belief/reflection never satisfies a fact predicate unless the
mechanic explicitly asks what an actor believes.

Source compatibility includes scope, calendar and generation. Incorporation
maps sources without widening audiences. Restore fences discarded-future context;
it cannot revoke something a human already read.

## Bounds and evidence

The 04–05 implementation review adds these concrete translation guards:

- Commit order is allocated under a world-row lock, not a sequence reservation
  or UTC timestamp; a late commit cannot fall behind a delivered history cursor.
- Receipt replay is still an authorization boundary. Stable metadata retries
  acknowledge the earlier command without reapplying it over a newer role or
  character assignment. Browser forms refresh the current read model afterward.
- Public preview is a state-layer projection, not a GM DTO with hidden controls.
  Notes linked to invisible entities are hidden too. NPC persona, an authored
  belief and an established engine fact remain distinct records and meanings.
- New authoring during a window is a Draft, not an edit to its pinned canonical
  base or a back door into Working state. Future draft promotion needs a fresh
  conflict review; saving a draft does not imply it has been incorporated.
- An Experience's real gathering date is labelled UTC and never advances its
  fictional coordinate. Profiles and dormant NPC agency imply no simulation or
  active AI. No complete-incorporation button disguises the phase-04 proof.
- LiveView acceptance tests exercise server-rendered forms, not browser layout,
  keyboard focus or human usability. Phase 05 retains that explicit browser gate.

Use integer fictional seconds initially; calendar-relative expressions wait for
08. Zero-duration events stay points. Due occurrence keys include schedule
identity/version and coordinate, independently of execution scope or batch.
Bound event counts as well as target dates. A due event at the starting cursor
must already be accounted for in the checkpoint; initialization cannot skip it.

Bundles reject unknown keys/operators, missing references, cycles, unsafe numeric
sizes and incompatible pins. Digest canonical key ordering with a format version.
Document draw consumption, rounding, stacking and explosion caps. Two roll-over
bundles alone cannot establish 2d6/pool/Fudge support: test every supported mode.

`mix precommit` includes tests, audits and generated outputs, but not Dialyzer,
workflow lint, remote CI, human usability or live providers. A pass cannot imply
a green PR/release. The explicit live-provider development exception in 10–13
does not waive deterministic authorization or human pilot evidence.

## Selected batch

Phases **01–03**, after refreshing 00's regressions: pure scoped actions,
knowledge and time; original rulesets/checks; ephemeral World/Zone/Session
authority and qualified Tempo. Persistence and native GM management (04–05)
form the next natural batch. Later phase ownership and evidence gates remain.

## Executed result

Phases 01–03 are complete within their pure/in-memory boundaries. Their real
handoffs replace the templates, and the [03 batch record](03-zone-sessions/handoff.md)
names APIs, restart/data-loss behavior, trust boundaries, rules/clock versions,
meaningful failed regressions and final verification: 153 tests through
`mix precommit`, plus a clean Dialyzer run. The static demo bundles ship as tracked
build resources; authored/persisted bundle validation is not a runtime file loader.
No game route, migration, provider call, commit or publication was added.

That paragraph records the original 01–03 execution, not current repository
status. The 04–05 follow-up is now published as `083a563`, with successful remote
CI. Phase 06 is the next local slice; 07 is deliberately a separate ownership
and cross-zone recovery change. See its [handoff](06-world-subsystems/handoff.md)
for validation and browser gates.

## Phase-06 implementation translation guards — 2026-09-05

- Stock and treasury are views over existing owned Item lots, not a second
  ledger. Transfers preserve commodity quantities; every authorized opening or
  correction records a reason and source/sink delta. Production records each
  consumed source lot and declared output/waste. Spent identities remain at zero;
  they are not transferable rewards, and collection bounds still apply.
- The first recipe exchanges abstract, bundle-declared units (two grain into
  one ration and one chaff). This is a game accounting invariant, not a claim
  of physical mass or monetary value equivalence. A sell bid rounds down from
  the base price and does not receive the scarcity multiplier, preventing a
  buy/sell loop from creating currency at a stock-band boundary.
- A local quote ID returned by the Zone is opaque and content-bound to the
  principal, actor, scope, rules, exact terms and consulted state. Confirm/cancel
  that returned ID, not the proposal request ID. Retiring or pruning a quote
  must never allow a delayed confirmation to authorize different terms. A
  stable confirmation request ID still recovers its committed receipt first.
- Quotes reserve nothing. The conservative consulted-state digest covers local
  actors, inventories, knowledge and policy, but excludes lifecycle-only revision
  changes and UTC. Pause/resume alone preserves a quote; fictional expiry is
  half-open (`cursor >= expiry` is expired). After uncommitted process loss,
  re-propose against current state; never infer success from a lost connection.
- Rest declares 3,600 fictional seconds in the shipped local bundles. The
  cross-campaign test uses naturally zero-duration trade/production/institutional
  deeds; it does not delete rest time to fit 04's incorporation proof. Delayed
  recipes and positive-duration incorporation remain unavailable until 08.
- Affiliation is a private sourced relationship, not a belief predicate or
  platform role. An offering moves real rations but does not imply membership;
  aid consumes actual institution stock and redeems one fulfilled obligation.
  Claims about deities remain lore. Only a witnessed or legitimately reported
  violation permits the authorized representative's one scoped debt response;
  there is no omniscient reputation update or full court simulator.
- The GM may operate these real NPCs without a player account. Existing actor
  authorization still forbids impersonating another account's PC. Native world
  editing, Experience actions and player knowledge keep separate scopes.
- Original bundle pins and format-1 checkpoint digests are durable contracts.
  New optional fields encode only when present; a captured pre-06 JSON snapshot
  round-trips exactly. Reject unknown fields and inconsistent restored stock;
  do not rewrite shipped checkpoints or silently enable mechanics in old worlds.
- Browser-hosted LiveView tests are server-driven acceptance evidence, not
  actual browser visual/keyboard QA. The unavailable Browser connection is an
  open qualification gate for both 05 and 06, not a reason to mark either done.
