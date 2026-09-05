# Implementation architecture

These are the current execution contracts. Read the original
[architecture report](../../ttrpg-elixir.md) as research, then
[product/personas](product-and-personas.md), [experience time](experience-time.md),
[story/canon](story-and-canon.md), [actions/knowledge](play-and-knowledge.md) and
[Lemieux integration](lemieux-integration.md). The user's GM-first/session-time
clarification supersedes real-time progression and immediate shared-world writes.
Names below are proposed APIs, not implemented modules.

The [execution review](execution-review.md) clarifies phase boundaries and
command/knowledge edge cases. World claim authority starts in 03 and is extended
in 07. Until 04, accepted shell results are explicitly ephemeral, not durable
game acknowledgments; no player route may expose that intermediate shell.

The [Tempo/time contract](tempo-and-time.md) selects `:ex_tempo` for testable
system-clock reads and supported calendar/interval operations. Phase 03 qualifies
the dependency and shell clock; 08 consumes calendar adapters. Preserve UTC
DateTime persistence, OTP monotonic deadlines and explicit fictional coordinates.

## Boundaries

| Namespace | Owns | Must not own |
| --- | --- | --- |
| Genesis.Core | Serializable values, pure reducers, checks, knowledge and experience/encounter transitions | Repo, clock reads, processes, provider or UI calls |
| Genesis.Systems | Versioned bundles and reviewed pure mechanics | World writes or transport-specific sheets |
| Genesis.Content | Lore/beat definitions, validation, drafting and publication | Executing uploaded code or making suggested outcomes true |
| Genesis.Campaigns | Memberships, party bindings, notes, gatherings and scoped read models | Competing authoritative NPC/item fields |
| Genesis.Engine | Scoped Zone/World authority, Experience orchestration, claims and incorporation | A second implementation of game rules |
| Genesis.Persistence | Transactions, scoped snapshots, logs, receipts and queries | Calling back into running Zones to resolve rules |
| Genesis.Time | Small clock boundary and pure supported-calendar adapters | Deciding fictional advancement, durable scheduling or replacing every stdlib timestamp |
| Genesis.LLM | Lemieux host/store/environment, scoped context and budget admission | Another provider SDK, agent loop or direct world writer |
| GenesisWeb / TUI / Transport | GM workflows and shared player presentation/auth adapters | Rules or the sole knowledge/security boundary |

Keep one Mix application, pure core plus OTP/IO shell, Registry and
DynamicSupervisor. No ECS, graph database, full event-sourcing framework, Horde
or libcluster. Ecto validation stays at boundaries; do not add a behaviour around
every small function or create compile-time context dependency cycles.

## GM-first presentation

Native LiveView world/campaign library, linked records, authoring, experience
management and incorporation review are the primary workflow, beginning in 05.
Use the existing authenticated live_session/pipeline and current_scope conventions.
Exact routes and rationale belong in each implementing handoff.

One shared player TUI arrives in 11 over SSH and browser cell rendering. Both
hosts delegate to the same player model; Engine Session imports no widgets or
sockets. Full GM management need not be reproduced in a terminal. Scope output
before rendering, clear stale cells on permission changes, and prove real-host
input/reconnect plus an accessible reading/action path. A painted grid alone is
not accessibility evidence.

## Identity, state scopes and command contract

A World has one published checkpoint/calendar and at most one open advancement
window. An Experience pins that base, rules/content/profile, local timeline,
participants and bounded footprint. PlaySession is a real-world gathering;
Engine Session is an attachment; neither owns an adventure's game state.

Use a StateScope value: published world, experience working state, preparation
candidate, or explicit rehearsal, each with world/generation and the relevant
window/experience identity. A Zone process is the sole writer per
(world, scope, zone). A campaign ID supplies provenance/permission, not another
canonical Zone. Experience overlays are a deliberate new staging scope, not
independent canonical copies or spendable duplicate inventories.

World owns global facts, scope claims and incorporation. Experience/StoryRun/
NpcAgent orchestrators submit intents to the appropriate Zone/World. No one may
write published state via an experience-scoped command. A unique actor/item
has one canonical identity and one active experience assignment; derived working
representation cannot be admitted into another experience for duplicate use.
Conservative writable-zone/global-resource claims prevent ordinary overlap.
Long-lived domain claims are not held database locks.

- Use stable string content IDs and binary persisted IDs; never atomize user input.
- Derive principal, world/campaign/experience, role, generation and capabilities
  from trusted server scope. Client fields and model arguments cannot grant them.
- Pin bundles/definitions/profile versions. Publishing a new definition never
  overwrites instantiated people or reinterprets accepted outcomes.
- Inject time, IDs and draws into pure resolution. Distinguish world calendar,
  experience elapsed time, server audit timestamps and transport/provider deadlines.
  A Tempo interval is not an audit instant or an advancement authorization.
  Pure calendar functions take explicit values; clock reads stay in the shell.
- A valid action commits new scoped state, event, receipt and effects; an invalid
  request consumes no game resources and returns a non-leaking error.
- Deduplicate by principal/world/state scope/generation and request ID; bind
  campaign/experience/action payload and reject ID reuse with different content.
  Reauthorize before returning a stored result. Timeouts mean unknown outcome:
  retry/query the same ID, not a fresh roll or action.
- Multiple attachments to one actor serialize at the same authority. Last detach
  records disconnected status; it never seals the Experience or advances time.
  Safe-checkpoint/danger behavior is explicit. Pause/resume preserves the exact
  fictional point and configured remaining decision deadlines.
- Confirmation binds proposal, scope and revisions; changed costs, stakes or
  incorporation manifests require renewed authorization.

## Context, knowledge and effects

ResolutionContext includes validated origins, prior deeds, present companions,
owned resources, relationships, relevant conditions and consulted revisions.
Materialize it from the appropriate authority. Separate resolution facts from
disclosable explanation and model context. Record selected variants and sources;
revalidate pending choices, not already resolved outcomes.

The [knowledge vocabulary](play-and-knowledge.md) distinguishes event, fact,
observation, belief, relationship, obligation and memory. Track occurrence,
commit/recording and learned time separately. Reflection cannot promote belief
to fact. Companions have one identity, location, resources, assignment and agency;
recruitment does not grant control of their mind or a copied character.

Effects carry source IDs, publication status and visibility audiences. Project
before delivery; raw state/private notes never enter player transports. PubSub
is not authorization or durable storage: deliver safe invalidations or already
scoped payloads. Recheck revocation and clear stale presentation state.
Current access plus the event's recorded audience governs historical disclosure;
new access does not automatically reveal old whispers. Explicit reveal creates
an audience-scoped event.

Resolve historical party/occupant audiences to identities at occurrence. Filter
source IDs, endpoints and diagnostic metadata as well as prose. Present-state
visibility does not retroactively grant access to the events that produced it.

For group narration, use only context permitted for every recipient or produce
separate scoped replies. Knowing a private fact does not authorize broadcasting
it. Published knowledge and local experience memories remain separate until
incorporation maps their sources; an unrelated experience never sees a provisional
future. Preparation/wiki views are read models and validated edit surfaces, not
alternate mutable copies of runtime fields.

## Durable state and replay

Persist a current snapshot on every accepted mutation with its append-only event,
receipt and transactional outbox/Oban work before acknowledgment. Experience
actions use ExperienceEvents; incorporation produces canonical WorldEvents linked
to those original sources. Direct authorized world editing outside an open window
can produce WorldEvents through the canonical authority. Historical checkpoints
are additional recovery/preview anchors, not the only save points.

Keep one mutable representation per state scope. Relational ownership/index
columns and validated jsonb snapshots update together. Window bases are immutable;
bounded overlays/candidate snapshots retain base references, not full world copies
for each character. Rehearsal must be separately labelled and cannot export rewards.

Processing order: authorize → pure resolve → atomic scoped persistence →
install committed cache → acknowledge/deliver. On failure before commit, no success
is visible. On crash after commit, recover from Postgres and receipts. Resync
repairs missed notifications. Record request/correlation and causal IDs, scope/
generation, campaign/experience/gathering, acting character and real principal,
revisions, times, versions, draws, resulting changes and audiences.

Replay recorded transitions against checkpoints without new rolls, live effects
or inference. Unsupported versions fail with migration diagnostics. Event APIs
are append-only; authorized corrections create new records. The event log is
audit/replay evidence, not the sole source of state.

A generated database ID does not ensure commit order. Define durable allocation/
pagination discipline separately for experience history and published world history
in 04. Canonical commit order differs from fictional chronological order; keep both
queryable and never skip late commits. A published source-event mapping has a unique
constraint so retry cannot reincorporate an outcome.

## Cross-zone and incorporation coordination

Phase 07 implements bounded transfers within a StateScope: reserve participants
at known revisions in stable order, obtain pure candidate transitions, atomically
commit affected states/ownership/receipts/events, install or reload all caches, then
release short operation reservations. Avoid circular synchronous Zone calls.
Crashes have durable operation IDs/status and revision/generation fences.
Unrelated scopes/zones can proceed; no item is spendable in two locations.

These short transfer reservations are distinct from a window's long-lived
experience footprint claims. Expanding a footprint first acquires domain claims.
Canonical changes during an open window are drafts or explicit base amendments
that invalidate/revalidate dependent experiences, never an unchecked wiki write.

Phase 08's incorporation is a World-owned operation. Seal all admitted experiences,
prepare a candidate from the pinned checkpoint with accepted local transitions
and due effects ordered in fictional time, validate dependencies, then show an
impact preview. Conflicting recorded outcomes require GM adjudication, not LLM
merging. The target is the maximum declared experience end, not summed concurrent
durations. Only explicitly approved following downtime adds to it.

Preparation uses durable bounded batches/cursors and does not expose a partial
world. Confirmation binds its base, manifest and target. Final publication commits
the bounded affected snapshots, WorldEvents/source mappings, calendar, receipt,
claims release/status and outbox atomically. Fence actions/admission during sealing
and publication; install caches before exposing the new checkpoint. Scope/event
caps keep the MVP transaction bounded. Oversized or inconsistent candidates fail
with an actionable review state, not silent partial commits.

Closing a gathering, idleness or restarting the server does not advance any
fictional clock. Oban resumes only authorized local/candidate work, keyed to its
scope, target, generation and policy. Due events use stable identities across
local resolution and incorporation. Canonical catch-up runs only to an approved
target and uses the same pure laws; no idle entity timers or unbounded wake storms.

## Connected systems and living history

Phase 06 implements local resources, atomic exchange, production and religious/
secular obligations. Phase 07 extends cross-zone ownership; 08 schedules those
same laws over explicit local/approved time. Each mechanic declares owned fields,
read dependencies, inputs/outputs, timing and accounting invariants.
WorldProfile is versioned data separate from the ruleset. Supported, enabled,
record-only and deferred capabilities are distinct. Disabled actions do not
succeed; changes cannot orphan stock or obligations without a migration decision.

Phase 12 proves the small living-village journey and basic sourced remembrance.
Phase 13 expands NPC agency. Phase 14 extends these laws to connected legacies
and pre-play history generation. A generation coordinator owns an unpublished
world; activation publishes a validated checkpoint before live ownership starts.
It never overwrites an existing world's past.

Player and generated events retain causes, participants and lasting effects.
Old obligations, ruins, people and relationships continue through incorporated
experiences and approved downtime. Mention cooldown governs narration, not whether
a bridge remains ruined. Repair creates new history. Bounded working context
cannot erase established deeds or grant omniscient reputation.

## Lemieux and human control

Every inference purpose uses the Genesis Lemieux host with scoped Store, deny-all
Environment, explicit minimal game tools and immutable capability profiles.
No coding defaults, file expansion, arbitrary HTTP tools, delegation or second
SDK. Reserve durable world/campaign/principal run envelopes before admission;
nested requests, retries, compaction and ambiguous usage cannot replenish spend.
Prompts/responses and operator actions are restricted audit records; secrets
remain runtime configuration. Provider failure preserves deterministic play.

NPCs have stable versioned personas/goals/beliefs and bounded agency as data.
Only active conversations or eligible deliberations create hot processes.
One NpcAgent per scoped hot NPC serializes turns; context/audience changes require
fresh eligible history. Revalidate scope, window/experience status, ownership,
turn, persona/policy and generation before a late result can commit.
A valid local tool commit remains durable if later narration fails; it is not
published globally until incorporation.

Ordinary delegated reactions may run within an authorized local/advancement
target. New major lore or out-of-policy damage requires review. Causal root/
parent IDs, depth/fan-out, cooldowns and budgets limit chains. A model cannot
approve its own proposal, bypass consent or manufacture a completion duration.

The native GM workbench owns preparation and incorporation from early phases.
Phase 15 adds possession, advanced adjudication and checkpoint restore. Possession
fences pending AI; audit distinguishes the real operator from the speaking NPC.
Whole-world restore requires steward authority, a complete paused checkpoint,
an explicit affected-campaign/window preview and a new generation. Include
published state and open experience/claim/cursor state coherently; fence old jobs,
confirmations, clients and model output. Security grants and provider spending
are not rewound. Exclude discarded-future memories from new context while retaining
audit history. Arbitrary single-event undo and automatic rehearsal merging remain
outside this first delivery.
