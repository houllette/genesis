# Handoff: 07 — Linked world atlas, multiple zones and global ownership

Status: **Phase 07 complete within its documented bounds; ready for Phase 08 entry validation**. Published
07A remains `10c54f6`; the existing 07B/07C1/07C2 work and new 07D changes are
uncommitted. This top section is the current handoff. Earlier restrictions and the
historical remaining-work list below describe their own slice, not current gaps.
No Phase 08 feature, dependency, provider or timer started. No commit or push was
requested or performed in this turn. Browser QA remains explicitly user-deferred.

## 07D — Companions, delivery, sourced global state and continuity — 2026-09-05

Entry validation reran the preceding 07C2 handoff command: **154 tests passed**,
seed **893359**. Existing uncommitted work was preserved. Companion tests first
failed with `:unsupported_action`; focused reducer, persistence, native journey
and independent-connection tests were added before the final gate. The Elixir
validation funnel governed targeted red/green work, narrow repairs and closeout.

### Delivered behavior and precise boundaries

- **Existing-actor companions.** `Core.Companions` implements `recruit`, `agree`
  and `dismiss` through the existing `Session.propose/3` / `confirm/3` path.
  The current bound PC invites a present visible NPC; invitation alone does not
  bind it. Only that inviter resolves the deterministic response from explicit
  `companion_policy` (`willing`, `max_trips`, version 1). Default willingness is
  false. No GM impersonation, inference, player control of NPC inventory or
  persona-prose authorization is introduced. Institution operators are anchored.
- A successful agreement creates one current binding for **1–8 connected trips**.
  Travel moves the whole eligible party (PC plus at most seven NPCs) atomically;
  it never silently leaves a bound follower behind. Dead, retired or legacy
  unsupported bindings block travel until dismissed. Each committed trip consumes
  one trip, including delivery; failed attempts and exact retries consume none.
  Exhaustion ends the binding at arrival. Dismissal preserves actor/items and past
  relationship records. The agreement/change source stays on the commitment;
  travel transitions are the evidence of subsequent trip consumption/completion.
- Present, living, currently bound companions participate in the existing
  resolution context. Tests make an allied companion secure admission where a
  hostile one triggers confrontation; dismissal/death removes current benefits.
  Historical `companionship` knowledge is not itself a present-companion modifier.
- **Identity-only remote objects.** `State.actor_refs` is an optional, exact,
  sorted set (maximum 500) for absent objects of retained subject-owned knowledge.
  Snapshot compatibility requires each reference to name an existing actor in
  this World's published identity index. A knowledge subject remains an actual
  local actor. Transfers partition knowledge by subject and rebuild the needed
  reference set at each place. References confer no presence, attributes, stock,
  mechanics or remote write rights. Conservative player projections do not expose
  records whose remote object is not locally visible. Future working-only spawned
  identities require an explicit Phase 13 extension to this index contract.
- **Real courier delivery.** `Travel.preview/6` adds an optional closed exchange
  map: `type` in `buy/sell/barter/offer`, `target_id`, and quantity 1–100.
  `Travel.move/6` keeps the existing exact token/request protocol. A preview checks
  the route's whole-party capacity, destination and local quote without expansion
  or mutation. Execution moves the party and performs one arrival exchange as one
  candidate and SQL decision. It advances each Zone one revision, records departure
  and arrival plus an optional exchange event, and returns those 2/3 event IDs in
  one receipt. Failed stock/quote/admission checks move nothing. A return requires
  its own directed journey. There is no remote stock editor or delayed shipment.
- Pure `Scene` now supports ordinary-item `drop` through a bundle's existing `take`
  capability, preserving old bundle digests. Dropping returns that same item to
  its Zone; commodity lots still require their validated owner/store. Independent
  take/drop/buy commits race against delivery reservations without double spending.
- **Scoped World standing and flags.** `WorldStandings.report/5` routes to World;
  its internal persistence boundary authenticates current GM access and frozen
  source audience. Only an accepted positive `offer` to the actual representative
  of a registered institution is eligible. One institution/actor resource receives
  +1 standing per distinct accepted source, with `relief_supported = true` after
  its first report. Non-contributions are rejected. There are at most 200 sources
  per resource and 200 scoped records per Experience. This is not general free-form
  global editing, universal reputation, affiliation, aid rights or local stock.
- Before the first report, `global_dependencies` acquires an exclusive World/
  generation/resource write claim pinned to the published data digest and network
  revision. It is separate from the local entity-backed `experience_claims` table;
  no fake entity or duplicate institutional owner was added. Reports are idempotent
  by source and request, survive recovery, and remain Working until incorporation.
  Visibility is the intersection of source audiences, never their union. A later
  Experience extends the existing published standing and preserves earlier sources.
- **One publication decision.** Completion format 2 conditionally adds the global
  row identities/digests/base/revision and dependency metadata. Empty legacy seals
  remain byte-compatible. `GlobalPublication` validates claims/base, replays recorded
  transitions, maps accepted sources and includes global candidate digests in the
  existing publication manifest. Global data, WorldEvents, Zone snapshots, identity
  relocation and claim release commit together. The same World-wide publication
  fence protects global reads until all published caches install or become cold.
  Global replay never reruns a contribution or invents an accepted event.

### Transfer recovery and ownership

The original coordinator remains the only cross-Zone process path. No new Zone
to Zone calls, global inventory writer, NPC process or transaction-held callback
was introduced. Domain claims survive pauses/return/abort; short reservations do
not. Unrelated claimed Zones can read and commit while another transfer waits on
its participants. Short commits still lock the World row for durable cursor/order
consistency; this is not a claim of concurrent lock-free SQL writes.

| Durable operation state | Exposed state and recovery |
| --- | --- |
| `prepared` | Both participants are fenced at original revisions. New prepares also pin both snapshot digests. Stop affected caches, verify evidence, then abort/release. No exchange or trip is consumed. |
| `committed` | Both snapshots and 2/3 events exist atomically; reads stay fenced. Verify generation, reservations, revisions, event/result identities and committed digests, install both caches or stop them for cold recovery, then release. Never rerun the exchange. |
| `installed` | Exact authorized retry returns the original receipt, without another trip or contribution. |
| `aborted` | Original request/token can revalidate and prepare again; changed payload conflicts or stale revisions reject. Admitted footprint claims remain held. |
| Inconsistent evidence | `:corrupt_transfer`; keep both fences. Repair/restore durable evidence under an operator recovery procedure, never clear reservations over live unresolved caches. |

`TransferRecovery.verify/2` now guards both `Transfers.finish/1` and cold/interrupted
`recover/2`. Older pre-07D prepares with an empty result have no before-digest seal;
they still require their original reserved revisions and valid digest-checked
snapshots. New prepares record both before digests. Existing installed receipts,
plain-travel tokens and golden snapshot encoding are unchanged. Nullable Actor
`companion_policy`/`commitment` and State `actor_refs` are omitted from legacy codec
output; no old snapshot or persona seed is mass-rewritten.

### Native workflow, visibility and source navigation

The NPC editor's collapsed background controls hold explicit willingness/trip
limits separately from descriptive persona. Experience resource controls reuse
the existing proposal/confirmation form for invitation, response and dismissal,
including non-settlement worlds. Travel adds a collapsed optional arrival exchange
and shows party count and the actual terms before confirmation. No broad UI redesign.

`/worlds/:world_id/history` is in the existing `[:browser,
:require_authenticated_user]` pipeline and `:require_authenticated_user`
live_session because history and report controls require an authenticated scope.
`History.page/3`, `get/3` and `source/4` enforce current membership/Experience access
and frozen audiences in the context, not just the UI. Source traversal rechecks
each origin; a published event never grants access to its private source Experience.
The streamed timeline, accepted-event detail, report button and review's standing
panel have native LiveView tests. Reports use deterministic per-source request IDs,
not an unbounded socket map of client-provided IDs.

Atlas Knowledge entries are read-only runtime projections, with accepted-source
links for authorized inspection. Authored baseline sources without an accepted
event are explicitly unavailable as history; no false provenance is manufactured.
Authored references/prototypes and live entities remain labelled separately. The
native annotation editor accepts up to eight namespaced `note:` text/integer/boolean
values, rejects duplicate keys/malformed input, and preserves typed values. It
does not grant mechanical meaning to a note. Existing route/resource typed forms
stay distinct. Two campaign viewers see the same incorporated NPC/bridge state
but only their own campaign notes and no private global/source details.

### Acceptance evidence and validation closeout

New evidence lives in `core/companions_test.exs`, `core/standing_test.exs`,
`persistence/phase07_continuity_test.exs`, `persistence/phase07_race_test.exs` and
`live/phase07_journey_live_test.exs` under `test/genesis{,_web}`. It covers the
three-place companion/contribution/incorporation journey, two campaigns, later
standing extension, secular barter, refusal/hostility/dismissal, native policy/
annotation editing, and accepted-source privacy. Fault tests cover delivery-worker
loss at four boundaries, either participant Zone loss before/after commit, global
publication loss at five boundaries, fenced global reads and damaged recovery/seals.
Independent PostgreSQL-backend barriers verify take/drop/commerce versus delivery,
opposing movement, competing campaign admission and duplicate reports. A blocked
delivery allows a third Zone's separate Experience to accept an unrelated action.
These are bounded correctness rehearsals, not a throughput or browser benchmark.

Final validation:

- `mix precommit` passed **342 tests**, seed **130436**, with all configured
  dependency audits, warning checks, formatter, strict Credo, usage-rule sync,
  compile-connected check, Sobelow and generated documentation gates passing.
- Separate `MIX_ENV=test mix dialyzer` passed with **0 errors, 0 skipped warnings,
  0 unnecessary skips**. `mix assets.build`, `mix format --check-formatted` and
  `git diff --check` passed. No check was narrowed and no suppression was added.
- The final 33-test native/continuity/race family passed seed 827227 before the
  additional later-Experience regression. That regression initially reused a
  World-scoped publication request ID, correctly got `:request_conflict`, then
  passed with a fresh request (seed 548356). An early full-gate run was interrupted
  on noticing that known fixture failure; it is not counted as validation. The
  complete successful 342-test gate above includes the corrected regression.
- `mix ecto.migrate` applied the new 07D migration to local development; tests also
  migrated successfully. The already-running development server was left running.
  **Restart it before manual use** so long-lived World processes initialize the
  updated state; hot-reloading modules does not migrate process state.
- Browser QA was deliberately not run, per the user's deferral. Native LiveView
  tests are not browser/viewport/accessibility acceptance. Remote CI covers the
  published 07A commit only, not this uncommitted working tree. Nothing was pushed.

The only new 07D SQL migration is
`20260905202855_add_scoped_world_standings.exs` (scoped standing and global claims).
Keep it alongside the existing uncommitted network, transfer and publication
migrations. No installed migration, dependency, version pin, CI pipeline or
generated usage-rule block was hand-edited. Backups/restores in Phase 15 must cover
these tables and their manifests, source mappings and operation fences together.

### Phase 08 entry — current, supersedes historical remaining-work list

Run this focused predecessor command before starting the next phase:

```sh
mix test test/genesis/core/companions_test.exs test/genesis/core/standing_test.exs test/genesis/core/transfer_test.exs test/genesis/core/incorporation_test.exs test/genesis/core/network_test.exs test/genesis/core/atlas_record_test.exs test/genesis/core/persona_test.exs test/genesis/core/settlement_test.exs test/genesis/persistence test/genesis/engine test/genesis_web/live/phase07_journey_live_test.exs test/genesis_web/live/review_live_test.exs test/genesis_web/live/travel_live_test.exs test/genesis_web/live/network_live_test.exs test/genesis_web/live/atlas_live_test.exs test/genesis_web/live/workspace_live_test.exs test/genesis_web/live/settlement_live_test.exs --warnings-as-errors
```

Phase 07 remains intentionally **one zero-duration Experience per publication,
up to eight admitted Zones, at most 200 actor events** (delivery uses three), and
up to 2,048 sealed total events. Transfer admission conservatively reserves capacity
for three events even for plain travel. Phase 08 must add coherent elapsed cursors,
parallel Experience timelines, explicit approved targets, due effects, candidate
preparation and conflict/review policies—not merely remove the current guards.
General remote policy enforcement, arbitrary cross-place mechanical dependency
graphs, autonomous NPC movement and delayed shipments are not implied by identity
references or a reported standing flag. No wall-clock catch-up, LLM, new player host
or positive-time simulation was enabled. See the [Phase 08 brief](../08-living-time/README.md).

## 07C2 — Whole-footprint review and publication — 2026-09-05

This was the 07C2 boundary; 07D above is current. The 07C1 publication gate below
was superseded. Browser QA remains explicitly deferred by the user. No browser tool
was attempted and no visual/viewport/accessibility acceptance is fabricated.
Existing 07B/07C1 changes were preserved; this turn does not commit or push them.

Entry: the preceding handoff's exact focused regression command passed **128
tests**, seed 982866. Core red showed the absent multi-zone projection; storage
red showed the old `:multi_zone_incorporation_unavailable` guard. A separate
meaningful deadlock regression timed out querying World identity while a sealing
command waited for a suspended Zone; it passes after asynchronous delegation.

### What is now supported

- One Experience in its open advancement window, at most eight visited places,
  **zero elapsed fictional time in every place**, and at most 200 actor events
  (travel consumes departure plus arrival). Completion seals at most 2,048 total
  scoped events including status/metadata. These are bounded correctness limits,
  not a throughput benchmark or a full advancement-window scheduler.
- `Seals` format 2 binds all working snapshot IDs/digests/base checkpoint IDs,
  claims and immutable event identities plus payload/audience digests. The seal
  is captured after its own status transition is recorded in the same transaction.
  The original format-1 single-zone seal remains readable; it is not rewritten or
  represented as having the newer event-payload seal. Ready experiences do not
  resume in this slice. Sealing retains all claims and **does not publish**.
- `IncorporationPlan` revalidates the sealed footprint, each published base,
  working checkpoint/replay, exact claims, generation/window revision and the
  canonical ownership index. Even an unchanged destination from aborted travel
  remains part of the admitted footprint; returning home does not remove it.
- `Core.Incorporation.project_many/2` is pure. It checks base equality and fixed
  metadata, duplicate/missing typed identities and all local candidate states.
  An original actor, item or knowledge record must occur once somewhere in the
  footprint. No per-zone removal is allowed without whole-footprint conservation.
  Recorded commerce may legitimately change quantities; replay and the original
  reducer validate that accounting, not an invalid blanket quantity-equality rule.
- Source mapping spans the whole footprint, including transfer events absent
  from `State.events`. Portable knowledge can retain a source from its previous
  place. WorldEvents retain frozen audiences and one unique source-row link.
  Existing published history stays in place. Per-zone recorded publication
  transitions replay from old checkpoints; no original action is rerun.
- All candidate snapshots, relocation of existing `world_entities` rows,
  source-linked events, checkpoints, receipt, Experience/window status, World
  revision and claim release commit in one short World-row transaction.
  `snapshot_id` remains the origin for compatibility; results also contain
  `snapshot_ids` and `zone_ids`. The Published index is never moved during play.

### Coordination, fences and recovery

The new `incorporation_operations` ledger records stable principal/request and
preview identity, generation, manifest and prepared/committed/installed/aborted
status. A partial unique index admits one active publication per World. Its fence
blocks ordinary World transactions and native canonical reads, including history,
atlas/network reads, place summaries and notes. Only trusted coordinator/replay
calls carry the internal operation exemption; no client grants itself one.

World starts a temporary publication coordinator and returns to its mailbox.
Affected Zones independently validate candidates in deterministic order, the
coordinator commits the SQL batch, installs every published cache, and releases
the fence only after installation. No transaction spans a process callback.
The older sealing/curation paths also now use bounded temporary command workers
(maximum 16), with caller/Zone capability checks, so they cannot block World's
authorization mailbox. An interrupted command returns an unknown-outcome error;
retry its exact request to recover the durable receipt, not a newly rebased action.

Before commit, recovery verifies the original published digests and aborts the
operation. After commit, it verifies generation/revision, candidate snapshots,
ownership index, lifecycle/claim release and receipt; it never republishes effects.
World stops all affected caches before recovery, or recovers during `rest_for_one`
cold startup after old workers are gone. Corrupt committed evidence retains the
fence and fails closed. Receipt lookup returns busy until installation/cold recovery
completes. A durable post-install invalidation prevents consumers that fetched
during the fence from missing the final state. An interrupted confirmation keeps
its exact preview/request identity; before-commit retries revalidate the same
plan, while committed retries return the original result.

The additive migration `20260905193053_add_incorporation_operations.exs` is part
of this slice. Include this ledger, manifests and status in future backup/restore
work; never clear a pending fence over live unresolved caches. Current publication
uses a short world-wide fence deliberately; do not stretch it into phase 08's
long-running simulation/review without a separate staged protocol.

### Native workflow and verification

`/worlds/:world_id/experiences/:experience_id/review` sits in the existing
authenticated browser pipeline and `:require_authenticated_user` live_session.
The Experience links to **Review all outcomes**. Its GM-only, streamed per-place
diff shows both departure and arrival, separates sealing from preview/confirmation,
states the irreversible seal and time/multi-Experience limits, and requires current
stewardship for publication. Canceling a preview does not unseal or publish.
Core/persistence source links are tested; richer cross-campaign source-navigation
UX is still in the remaining work below.

Focused evidence covers exact retries, non-origin snapshot and source-audience
tampering, aggregate conservation/private knowledge, portable source remapping,
per-zone replay and later admission at the incorporated destination. Fault tests
cover coordinator loss at preparation, before/after commit, first cache install
and final install; Zone and World loss are tested before commit and after partial
installation. A distinct-PostgreSQL-backend race proves one publication winner
and one fenced loser, independently of shared SQL-sandbox process tests. Native
tests cover review/seal/cancel/confirm, positive-time ineligibility and outsiders.

Final validation:

- `mix precommit` passed **302 tests**, seed **18429**, including the configured
  dependency audits, warning checks, formatter, strict Credo, usage-rule sync,
  compile-connected dependency check, Sobelow and generated documentation.
- The Elixir validation funnel was used: predecessor checks, focused red/green
  regressions, narrow lint fixes and one final full gate. The final focused
  core/publication-race/native-review batch passed 10 tests, seed 978632, before
  that gate. No full-suite rerun was used as a substitute for targeted debugging.
- Separate `MIX_ENV=test mix dialyzer` passed: zero errors, skipped warnings or
  unnecessary skips. `mix assets.build` and `git diff --check` passed.
- The new migration is applied to both test and local development. No dependency,
  generated usage-rule, CI or version-pin change. The existing development server
  on port 4000 was left running; restart it before manual acceptance so new World
  coordinator state is initialized rather than relying on hot-reloading old
  process state. This turn did not stop the user's server.
- Browser QA is user-deferred. Remote CI does not cover this uncommitted slice;
  the last published `10c54f6` / 07A CI result is historical, not evidence for 07C2.

Next logical batch: sourced global standing and explicit cross-place dependency /
delivery ownership. Companion mechanics remain a separate bounded extension;
none of this begins phase 08 or approves broad UI refinement.

## 07C1 — Bounded travel and recovery — 2026-09-05

Historical slice: its multi-place publication gate and synchronous-owner-command
note are superseded by 07C2 above. Its travel limits and recovery evidence remain.

The user explicitly accepted manual validation of the preceding 07A/07B interface
and asked to continue without Browser QA. No browser tool was attempted in this
slice; no screenshot, viewport, accessibility measurement or agent-observed visual
acceptance is claimed. This supersedes the earlier browser blocker below, not
the distinction between user acceptance and automated LiveView evidence. Broad
UI refinement remains deferred.

Entry regressions: **106 passed**, seed 149869, using the previous handoff's exact
command. Selected scope: footprint expansion + bounded movement + reservation /
commit / installation / recovery + Session rebinding. Meaningful core red returned
`:unsupported_transfer` instead of moved state (seed 989942); implementation then
passed the core transfer/local-system batch (11 tests, seed 790229).

### Contract and ownership

- `Travel.preview/5(scope, world, experience, actor, destination)` is read-only.
  `Travel.move/6(scope, world, experience, actor, token, request)` enters the World
  owner. The closed token pins generation, network revision, both zone IDs and
  both scoped snapshot revisions. Retry the exact token/request after an unknown
  outcome; changed payloads conflict, stale revisions require a new preview.
  Current campaign/world access and the user's own PC binding are rechecked even
  for receipt retrieval. A GM cannot use travel to impersonate someone else's PC.
- The Experience footprint is bounded at eight working places. Each place keeps
  its own immutable published base checkpoint and working checkpoint. Extension
  validates the open window/base, claims the destination and its original actors
  and items, then creates short transfer reservations. Initial admission and
  expansion share the same resource-claim helper. Preview acquires nothing.
- Long claims **survive failed travel, return trips, pause and restart**. They
  are not leases and do not expire from idleness. An aborted preparation can
  therefore leave an additional, unchanged working place; that is intentional,
  visible in the travel screen, and not a successful move or a released claim.
- `Core.Transfer.move/3` is pure and preserves IDs, actor/persona revisions,
  quantities, ownership, beliefs, visibility, provenance and fictional coordinates.
  Every carried item and knowledge whose subject is the traveler and object is
  nil/self moves. Incoming/outgoing cross-actor knowledge, local obligations,
  companions and institution anchors reject movement rather than being dropped.
  Persistent admission currently accepts active, bound participating PCs only.
- Every visited place must have zero elapsed time; source and destination must
  have exactly equal fictional coordinates and pinned rules. No inferred journey
  duration, catch-up, deadline consumption or wall-time progression is introduced.
- A place without a market can contain valid carried commodities. The previous
  blanket state invariant incorrectly conflated possession with permission to
  issue or exchange goods. State validation now checks pinned commodity definitions
  and actor ownership; market/profile validation still gates issuance and exchange.
  Regression tests reject minting/trading at a marketless destination.
- The canonical `world_entities` index remains **Published**, not an additional
  working-state authority. Working actor location is resolved from the bounded
  footprint's validated snapshots. Atomic future incorporation must relocate the
  published index together with every affected candidate, never during play.

### Durable protocol and failure recovery

World preparation runs a short transaction, never a transaction across OTP calls.
The World then returns to its mailbox while a supervised temporary coordinator
obtains both reserved Zone states in stable snapshot-ID order, asks each Zone to
validate its local candidate, atomically commits both snapshots/events/receipt,
installs both caches and only then releases reservations. At most four coordinators
run per World. Source and destination never synchronously call each other.
Ordinary Zone commands continue through the World authorization mailbox; legacy
owner operations that synchronously call a Zone return busy during coordination.
Database ordering retains the existing short World-row transaction lock, not a
long-lived World mailbox lock or a claimed guarantee of lock-free concurrency.

| Durable status | Affected reads/writes | Recovery |
| --- | --- | --- |
| `prepared` | Both snapshots fenced; no actor move committed | Stop affected caches; mark aborted; release short reservations, retain footprint claims |
| `committed` | Both snapshots changed atomically; reservations remain | Stop affected caches; rebuild from committed snapshots; mark installed and release reservations |
| `installed` | Both caches installed or cold; same-ID result available | Never replay movement or reissue inventory; return original result |
| `aborted` | Original actor location retained; extension may remain | Same request can retry unchanged terms, subject to fresh validation |

World `rest_for_one` startup recovers only after old workers/caches are gone.
A live coordinator/participant failure terminates affected caches before clearing
their durable fences. Snapshot reads check reservation and state under one short
transaction so they cannot straddle commit/installation. Zone actions recheck the
fence, principal location and snapshot digest inside their commit transaction.
No unresolved cache serves a successful read/mutation merely because its process
survived. Recovery conserves one actor and its inventory; reconnect after a Zone
failure is explicit, while normal travel rebinds an existing Session.

The additive migration `20260905182730_add_scoped_transfers.exs` adds
`zone_transfers`, `zone_reservations` and nullable `zone_snapshots.base_checkpoint_id`,
backfilling existing origin bases. Applied to test and local development databases.
It does not rewrite snapshot JSON, old event/receipt payloads or entity identities.
Future whole-world restore must include/fence this ledger and its generation;
do not resurrect old reservations or lose per-place base references.

### Delivery, inspection and deliberate publication gate

Movement emits one departure and one arrival ExperienceEvent with scoped field
transitions. They freeze recipient users at occurrence; departure does not expose
the destination, and neither event includes private inventory/knowledge contents.
These metadata events are not appended to the Core action-event list. Replay
uses their recorded transitions; future incorporation must map their source IDs
along with ordinary actions. The 200 actor-event limit is now Experience-wide,
and both preparation and commit require capacity for the two movement events.

World grants revalidate current working location. Sessions locate/rebind before
commands, discard old quotes and ignore invalidations from their old Zone PID.
After reservation release, a fresh invalidation prompts the consumer to refetch.
An acknowledged move never makes a Session a state writer. Pause/resume remains
Experience-wide; persisted Experience status gates every Zone. The origin status
snapshot remains the control revision, with status projected onto visited places.

The authenticated GM route `/worlds/:world_id/experiences/:experience_id/travel`
uses the existing required-user live_session and browser/auth pipeline. It offers
preview/cancel/confirm and streamed links to per-place working resources via the
authorized `?zone=` selector. All backend authority remains in contexts. Comparison
now represents departures as 'Not present at this place', rather than silently
omitting removed records. A lost OTP reply retains the exact confirmation identity.
The visited-place cards show people and quantities from one atomic, GM-authorized
whole-footprint projection, not separate reads that could straddle a move.

**Multi-place Experiences are test-only at this boundary.** Sealing and
incorporation return `:multi_zone_incorporation_unavailable` instead of attempting
single-zone publication. Returning home does not reduce the footprint or bypass
this guard. Single-zone review retains its existing behavior. Extend review and
atomic canonical reindexing next; do not start phase 08 to hide this phase-07 gap.

### 07C1 validation and closeout

Focused tests cover inventory/belief conservation and visibility, stale previews,
exact retry/conflicting payloads, portable commodities, replay from both working
checkpoints, old-zone grant/quote fencing, pause/resume, native confirm/inspection,
and access redirects. Fault injection covers preparation, pre-commit rollback,
commit-before-install and partial installation, plus source/destination and World
failure on both sides of commit. An independent-connection race verifies two
distinct PostgreSQL backends, one prepared winner, one busy loser and rejection of
a precomputed take while reserved. Opposing directions return busy/stale and
require re-preview; the World remains responsive during coordination. These are
bounded correctness tests, not throughput or deployment readiness evidence.

The affected 82-test batch passed (seed 876345); the later focused native/travel
batch passed 17 tests (seed 353039). Initial `mix precommit` passed 276 tests
(seed 165048). The separate type check then identified an unreachable fallback
in the atomic snapshot reader; it was removed without a suppression, and the
narrow `MIX_ENV=test mix dialyzer` rerun passed with **0 errors, 0 skipped and 0
unnecessary skips**. The refreshed final **`mix precommit` passed 276 tests**, seed
912043, with all configured warning-free compile, format, Credo, dependency audits,
usage-rule sync, xref, Sobelow and documentation checks green. Final
`mix assets.build` and `git diff --check` passed. No dependencies, generated usage
rules, CI configuration or running development server were changed/stopped.
The final documentation-only closeout records these results without altering code.
07B and 07C1 remain
uncommitted on published `10c54f6`; remote CI for that SHA does not validate this
diff. No publication was requested in this continuation.

## 07B entry, publication and selected boundary — 2026-09-05

Published 07A as `10c54f614d7b54a06cb1ccf9922ae1a31166ba68`; origin/main
matched exactly after push. Publication refresh: `mix precommit` passed **235
tests**, seed 653853, plus every configured gate. Remote
[CI run 33982428350](https://github.com/houllette/genesis/actions/runs/33982428350)
completed successfully. That result covers 07A, not the new uncommitted 07B diff.

Re-read current architecture, time, workflow, knowledge, persona/context,
subsystem contracts and the historical report; inspected actual single-zone
authority, curation, receipts, snapshots and local institution code. The complete
publication gate on the unchanged predecessor covered all 07A entry regressions.
Selected the graph and institution-identity/jurisdiction part of brief slice 1.
No claim that global standings or any transfer acceptance criteria are complete.

### 07B public workflow and ownership

- Open a world's **Connect places & institutions** link. The new native route
  `/worlds/:world_id/connections` uses the existing `:require_authenticated_user`
  live_session and `[:browser, :require_authenticated_user]` pipeline. Context
  authorization still requires current world membership and builder/steward
  authority for writes. Controls are closed until requested; no broad redesign.
- Connect two existing published places. Links are **directed**; author the return
  direction separately. Edit condition/capacity/visibility without silently
  retargeting an existing edge. Check a group size without moving or reserving
  anything. Damaged and closed connections both reject passage; capacity is an
  integer 1–1,000. No duration, inferred speed, pathfinding or delivery simulation.
- Register an existing local institution, keeping its home in its declared
  jurisdiction set. Inspect the original home's resource controls. Registration
  is an explicit, auditable identity extension, **not a migration of balances,
  beliefs, affiliations or standing**. These remain owned by the original Zone.
  The identity helper `Content.NetworkCatalog.institution_id/3` preserves 07A's
  exact UUID and atlas reference. Names are read through, never copied to globals.
- Jurisdiction is presently **record-only**, not remote enforcement or a claim
  on every listed place. It grants no membership, GM access, omniscience or
  ability to spend a remote merchant's goods. Global-standing propagation remains
  07C, requiring sourced transitions and separate footprint claims.
- `WorldNetwork.save/5(scope, world, %{generation: g, revision: r}, command, id)`
  routes through the existing World/DurableWorld; `persist/5` is its internal
  transaction boundary. Closed commands are string-key maps:
  `connection` with `from`, `to`, `condition`, `capacity`, `visibility`; or
  `jurisdiction` with `institution_id`, `zones`, `visibility`.
  `view/3` returns permission-filtered published projections; `assess/5` is a
  read-only geography check, **never a travel permission token**.
- `Core.Network` format 1 carries world/generation, up to 160 unique directed
  links and 80 institution bindings. Self links, dangling/foreign endpoints,
  duplicate links/jurisdictions, missing home, forged local IDs and unknown keys
  fail closed. Directed cycles are valid geography, unlike containment cycles.
  Catalog materialization is capped at 80 current published zones; exceeding a
  bound fails the whole operation, not a truncated graph. Bounds are not scale QA.

### 07B persistence, privacy and recovery

Additive migration `20260905175758_add_world_networks.exs` was generated with
`mix ecto.gen.migration add_world_networks`. It adds one snapshot row per
world/generation, unique in Postgres, with positive revision and versioned JSON.
Legacy worlds read as an empty global network until the first explicit save;
the migration rewrites no Zone snapshots, old events, receipts or atlas rows.
New global state must be included in future whole-world restore/checkpoints.
Applied successfully to both test and local development databases. No existing
migration or development world data was changed or removed.

The existing short World-row transaction reauthorizes, fences generation and
revision, applies the pure reducer, and commits the global snapshot, World
revision, before/after audit, receipt, outbox and Oban delivery before replying.
Receipts bind generation/revision/command/principal/request. Retry after a lost
reply returns the original result; changed payloads conflict, and revoked users
cannot retrieve an old privileged receipt. No second GenServer/global cache,
new dependency or synchronous call to a Zone is added.

| Boundary | Durable result and recovery |
| --- | --- |
| Rejected or rolled-back edit | No snapshot/revision/receipt/audit/outbox change; retry the same request |
| Committed edit, reply or notification missed | Read-through reload and same-ID retry recover once from Postgres |
| World process restart | Registry/supervision restarts the existing owner; no network cache to install |
| Open advancement window | Save a `network` Draft, not a global mutation; original base and working state remain unchanged |
| Transfer boundary | **Not implemented**; this is not the cross-Zone recovery proof required by the phase |

Network drafts use `zone_id: "@network"` (not a Zone or claim target), world
base revision, generation, network revision and the closed command. They remain
unpromoted; future review must revalidate all those bindings. Ordinary saves do
not amend an open window. Future sealing states must extend the existing window
admission fence consistently, not only guard a status called `open`.

GM/public visibility is filtered before returning edge or institution DTOs.
An institution also requires both local representatives to be visible, regardless
of its global record's audience. No local source IDs or private stock enter the
network projection. Native preview/revocation clears hidden cards and editors;
invalidation marks existing editors stale without rebasing their generation or
revision. Delayed editor tokens cannot bind to a newer editor.

### 07B validation

Meaningful entry red: the existing World returned `:unsupported_operation`
instead of a published connection (seed 815415); first green seed 561278.
Core/persistence subset: **12 passed**, seed 809420. Native workflow/privacy/
stale-editor/draft/auth tests: **5 passed**, seed 790179. Independent committed
connection race: **1 passed**, seed 443944; two distinct Postgres backend PIDs,
one revision-zero winner, one stale loser, one audit and one receipt. This is
global-authoring concurrency evidence, **not transfer conservation evidence**.
Additional acceptance tests cover local registration after real incorporated
membership/offering actions, snapshot/receipt/source identity preservation,
transaction rollback, exact retry, World restart, malformed formats and live names.

The browser skill's
supported connection attempt returned “No browser is available”; discovery was
empty. Automated LiveView assertions are green but real-browser visual,
responsive and accessibility QA of 07A/07B remains unobserved. The user's prior
05–06 manual acceptance does not certify these new screens. No browser workaround
or broad UI polish was attempted.

### 07B closeout

The selected bounded slice is implemented and **uncommitted** on top of
`10c54f6`; full phase 07 remains in progress. Final affected batch passed
**47 tests**, seed 345569:

```sh
mix test test/genesis/core/network_test.exs test/genesis/persistence/network_test.exs test/genesis/persistence/network_race_test.exs test/genesis/persistence/atlas_test.exs test/genesis/persistence/settlement_test.exs test/genesis_web/live/network_live_test.exs test/genesis_web/live/atlas_live_test.exs test/genesis_web/live/workspace_live_test.exs --warnings-as-errors
```

Final `mix precommit`: **254 tests passed**, seed 561851 (19 added tests), with
all configured compile/format/Credo/audit/usage-rule/xref/Sobelow/docs checks green.
Separate `MIX_ENV=test mix dialyzer`: **0 errors, 0 skipped, 0 unnecessary skips**.
`mix assets.build` and `git diff --check` passed. No dependency, generated usage
rule or CI configuration changes; the running development server was not stopped.
The final handoff update records these results without changing implementation.

For manual browser verification, open **Connect places & institutions** from a
world with at least two places. Add an outward link, check an oversized group,
mark the link damaged and verify it blocks the check, register an institution
including its home, then try public preview. Open a second editor and save a
concurrent change to verify the first is stale. During an active Experience,
verify saves are explicitly Drafts. Do not treat any of these checks as travel.

## Historical 07A handoff (published above)

## Entry validation and scope decision — 2026-09-05

Base: published main `9e4c8cfd436aeb69cdd8f710d51c7b1cd543b3a1`, clean on
entry. Phase-06 remote CI succeeded (run 33977526863, verified at publication).
At that entry, 07A was uncommitted; its later publication/CI is recorded above.

The user reported “Everything looks fine” after receiving the manual 05–06
checklist and authorized proceeding. That closes the entry blocker as
user-reported acceptance. No browser name/version, measured widths, per-item
results or screenshots were supplied. This is not agent-observed browser or
accessibility evidence, nor acceptance of the subsequently added atlas screen.
The user explicitly raised UI complexity and deferred broad refinement while
the remaining phases develop.

Read the historical report and current architecture, workflow, product, time,
knowledge, context, subsystem and execution-review contracts before structural
work. Inspected actual World/Zone authoring, snapshots/indexes/receipts, local
settlements, notes and native workspace code. The exact predecessor command
passed **82 tests**, seed 480551:

```sh
mix test test/genesis/core/settlement_test.exs test/genesis/systems/bundle_test.exs test/genesis/persistence test/genesis/engine test/genesis_web/live/settlement_live_test.exs test/genesis_web/live/workspace_live_test.exs --warnings-as-errors
```

Selected mainly the descriptive-record portion of brief slice 6 and current
creation-path persona portion of slice 7. Do not count the entirety of slices
1, 6 or 7 as completed. The mechanical transfer/recovery work is a following
coherent batch, not a successful placeholder.

## Delivered ownership, persistence and public APIs

- `Genesis.Content.Atlas.save/6` sends `{:atlas_save, ...}` through
  `Engine.Runtime` to the **existing World** and `DurableWorld`.
  The internal `Atlas.persist/6` boundary rechecks current world/build and
  relevant campaign-GM permissions, including before receipt replay.
- `Tx.run/2` supplies the existing short world-row transaction. Descriptive
  row, world revision, versioned before/after audit, stable receipt, outbox and
  Oban delivery job commit together before acknowledgement. There is no second
  process/cache owner or DB transaction held across an OTP callback.
- New additive migration:
  `20260905165350_add_world_atlas_records.exs`, generated using
  `mix ecto.gen.migration add_world_atlas_records`. Applied to test and local
  development DBs. No shipped migration changed. It adds one table with world,
  generation, campaign/audience, revision, archive and validated JSON data.
  Test setup initially recorded the generated empty migration; after verifying
  the table did not exist, only that exact test migration marker was removed
  and the completed migration applied. No world data was deleted.
- `Core.AtlasRecord` defines stored format **1**. Unknown formats, mismatched
  indexed audience/type fields, unsupported keys, invalid typed fields,
  references, cycles and stale revisions fail closed. Stable new IDs derive
  from world/generation/principal/request. Kind is immutable after creation.
  Archive retains the row, identity, revision and audit; no delete operation.
- At an open window, an ordinary save creates a `Content.Draft` with
  `kind: "atlas"`, `zone_id: "@atlas"`, logical record identity, pinned world
  and record revisions. **@atlas is not a Zone or claim target.** Published
  atlas rows and Experience snapshots remain unchanged. The general workspace
  draft list enforces the draft's campaign audience. Draft promotion remains
  unavailable; future review must preserve these audience and base bindings.
- Bounds: 500 descriptive records per world/generation, including tombstones;
  80 published snapshots per atlas read; 50 search results with a visible-only
  total and explicit “narrow your search” behavior. No silently freed archive
  capacity, unbounded graph walk, search daemon or new database technology.
  Reads take the same short world-row lock to materialize a coherent authorized
  catalog; this is bounded MVP querying, not a scale/performance qualification.

## Identity, linked records and privacy

Runtime keys are `zone:<id>`, `actor:<id>`, `item:<id>` and
`institution:<derived-uuid>`; descriptive keys are `record:<uuid>`.
Institution UUID derives from the world, existing place and local institution
ID, avoiding ambiguous string concatenation. This is a **read-through identity**,
not a second institution balance/policy writer or completed global migration.
Existing local IDs, receipts, affiliation knowledge, holdings and pinned profiles
remain unchanged. 07B preserves this reference on registration; future movement
of a site's authority must still explicitly preserve/map it.

`AtlasCatalog` reads validated scoped snapshots and `State.view/2`.
Names/locations follow the real owner; a wiki field cannot independently rename
an NPC, edit stock, replace persona or create a duplicate spendable actor.
The institution's projection uses its existing representative-visibility check.

Descriptive kinds: region, location, organisation, family, article, culture,
language, route, resource_site and relationship. Location parents reject cycles
and non-place parents. Directed links require existing, active endpoints;
relationship labels are located_in, affiliated_with, kin_of, speaks, documents
and connected_to. They never automatically add inverse relationships.
Routes require two distinct places, described condition and bounded capacity.
Resource sites name a resource; **neither creates stock, travel or simulation**.
Other custom fields require the `note:` namespace and bounded scalar values;
there is no universal schema designer or arbitrary mechanical field editor.

Authored text/relationships are references or claims, not engine-established
facts, real institutional membership, a PC's convictions or prototype instances.
Existing author-only/public notes and typed engine knowledge remain separate.
Persona culture is a descriptive label; an atlas link supplies a real record
reference, not a new culture/language simulation.

- `Atlas.search/4` and `get/4` reauthorize against current DB membership.
  World-visible means authorized world members, not anonymous Internet access.
  GM-only requires world stewardship/build access. Party records require current
  access to their own campaign. Public preview never inherits GM/party visibility.
- Filter hidden rows and relationship/route endpoints **before** matching,
  snippets, counting, limiting and backlinks. Hidden/archived parents are omitted
  from projections; retained stored links do not disclose their IDs. Missing and
  inaccessible detail requests share `:unavailable`.
- `Atlas.player_search/5` derives campaign and StateScope from
  `Authority.principal/4` and projects the selected actor's authorized Working
  snapshot, even for a GM caller. It includes permitted global descriptive rows,
  not another Experience's runtime overlay or campaign secrets. Published atlas
  edits stay frozen during the window. This is a scoped Elixir read API, not a
  public HTTP endpoint or phase-11 player host.

## NPC persona and native workflow

`Core.Persona` format **2** supplies a stable actor-ID seed, temperament,
current goal, role, culture label, motivation, bounded constraint list and
dormant agency. Fresh/fallback NPC materialization through `State.new/1` and
manual curation use it. Partial edits and renames preserve unspecified persona
fields and the seed. Clients cannot set seed/version/agency or inject facts/
inventory. No inference or hot process is activated.

Legacy empty/v1 personas remain valid **on restore** without rewriting bytes,
digests, rules pins or accepted transitions. Explicit editing/materialization
upgrades that actor to v2 with preserved authored goals/temperament. This is not
a background migration of all old residents. Future generated/hot NPC paths
must use the same constructor; those systems do not exist yet.
Settlements accept validated v1 and v2 representatives. The pre-06 format-1
golden checkpoint still round-trips exactly.

`/worlds/:world_id/atlas` is in the **existing**
`:require_authenticated_user` live_session and
`[:browser, :require_authenticated_user]` pipeline: login comes first, then
current world/campaign authority. The world workspace links to it.
`AtlasLive` offers search → select → follow links/open owning place; editing is
explicit, with tags/archive controls collapsed. Selected endpoints remain in
the editor even when filtered out of search, but are reauthorized. Stale saves
require reopening; background invalidations do not rebase the editor.
Permission downgrades clear private results, details and open editors.
NPC background/motivation fields extend the existing place form behind details.
No new dashboard framework, player transport or broad UI redesign was added.
Each form change/save binds the opened editor's request token; delayed events
from a replaced editor cannot rebind an old payload to the newly selected record.
The final review also repaired a predecessor privacy defect: omitted visibility
on an NPC/item edit now preserves the prior audience. Native existing-record
editors default to `unchanged`, retaining even actor-scoped audiences rather than
coercing them to public or GM-only. Changing visibility remains an explicit choice.

Native server-driven acceptance creates lore and a directed link, follows a
real person to its owning place, preserves filtered editor endpoints, checks
public preview and window drafts, and clears an editor after revocation.
For actual browser follow-up: open the atlas from a world, repeat that flow,
edit from a narrowed search, inspect tab/select behavior and narrow layout.
New atlas visual/keyboard QA remains unobserved; do not apply the user's earlier
acceptance to it automatically.

## Verification evidence

- Persona meaningful red: new NPC still returned version 1 instead of 2
  (seed 237814); after implementation the curation/settlement/codec subset passed
  15 tests (seed 376107).
- Atlas meaningful red: save returned unsupported rather than a durable result
  (seed 765957). Implemented real World/transaction persistence, not a mock.
- Native meaningful red: filtered relationship editor lost its selected source
  option (seed 957662). Source/target choices now retain authorized selected
  records; all three initial native tests passed (seed 375705).
- Focused batch: **39 passed**, seed 822569, covering atlas/persona/curation,
  codec, settlement persistence and all affected native workspace journeys.
  Later focused core-atlas/persistence checks: **10 passed**, seed 846902.
  Native atlas including permission downgrade: **4 passed**, seed 512186.
- Persistence regressions cover idempotency/payload conflict, audit/outbox,
  live rename, private endpoints, campaign access and revocation, cycle/dangling
  rejection, tombstones, window isolation, cross-workspace draft privacy,
  World restart/receipt recovery, two queued stale authors and filtering before
  the first 50-result page. The queued-writer test is a World-serialization
  check under SQL Sandbox, not independent-connection cross-zone race evidence.
- Final-review meaningful reds: a delayed old-editor payload changed the current
  record (seed 831289); partial authoring changed a hidden NPC's audience to
  public (seed 666607). Both have regression tests, including native preservation
  of an actor-scoped item's visibility.
- Earlier full gates passed 232 tests (seed 2227), then 233 (seed 517148)
  after editor-token binding. Final post-privacy-fix `mix precommit` passed
  **235 tests**, seed 657530, and all configured warning-free compile,
  formatter, Credo, audits, generated-rule, xref, security and documentation
  checks. The affected curation/workspace/atlas subset passed 15 tests,
  seed 767108, before that final gate.
- Initial separate Dialyzer found an opaque-type inference error in the recursive
  visited-set argument. Using a plain visited-ID map resolved it without a
  suppression; the focused rerun passed with zero errors/skips. Final post-fix
  `MIX_ENV=test mix dialyzer` passed with zero errors, skipped warnings or
  unnecessary skips. `mix assets.build` and `git diff --check` passed.
- Environment: Elixir 1.20.4 / OTP 29.0.6, Postgres, Oban manual testing.
  The user's running development server was not stopped.
- Publication and its refreshed gate/remote CI are now recorded above.

## Historical remaining phase-07 work after 07C2 (superseded by 07D above)

The 07C1 protocol and its recovery table are above. Preserve that bounded
implementation while completing the remaining mechanics and continuity cases:

1. Extend the implemented graph/identity/jurisdiction owner with sourced global
   standing and scoped read/write dependencies. Do not promote local private
   standing into universal reputation or interpret jurisdiction as enforcement.
2. **Completed bounded slice: 07C2 multi-zone sealing/incorporation**, documented
   above. Preserve whole-footprint replay, conservation, atomic reindexing and
   asynchronous coordination. Do not relax its one-Experience/zero-time limits
   to imply phase-08 reconciliation. Richer cross-campaign source navigation is
   still needed alongside the later continuity scenarios.
3. Extend the transfer protocol to explicitly modeled cross-place obligations,
   global write dependencies and deliveries. Preserve privacy and original local
   stock/accounting; an expanded jurisdiction still grants no remote spend rights.
   Add independent multi-actor/commerce/delivery races and an unrelated third-Zone
   workload rehearsal. Current take/transfer and opposing-direction tests are not
   evidence for remote commerce or every unsupported dependency. No synchronous
   Zone A → B → A chains.
4. Companion willingness/refusal/recruitment, one party binding, inventory
   conservation, bounded travel and sourced context effects. Do not treat
   descriptive kinship/affiliation links as those mechanics.
5. Two-campaign post-incorporation atlas/fact-source navigation and full companion
   continuity. Existing phase-06 tests preserve local cross-campaign accounting;
   they do not complete this larger scenario.
6. Native custom-field editing and richer campaign note/relationship authoring
   may extend the bounded read model as needed. Current custom annotations are
   validated through the context API and displayed, not a general native designer.
   Full atlas reconstruction/version-copy during generation restore requires a
   phase-15 schema/identity decision; current world restore is not implemented.
   Do not silently drop atlas rows when adding that feature.

Before extending, inspect main plus this exact diff and run:

```sh
mix test test/genesis/core/incorporation_test.exs test/genesis/core/transfer_test.exs test/genesis/core/network_test.exs test/genesis/core/atlas_record_test.exs test/genesis/core/persona_test.exs test/genesis/core/curation_test.exs test/genesis/persistence test/genesis/engine test/genesis_web/live/review_live_test.exs test/genesis_web/live/travel_live_test.exs test/genesis_web/live/network_live_test.exs test/genesis_web/live/atlas_live_test.exs test/genesis_web/live/workspace_live_test.exs test/genesis_web/live/settlement_live_test.exs --warnings-as-errors
```

Respect the user's manual acceptance and Browser QA deferral. Preserve the golden snapshot, v1/v2
persona semantics, local accounting and claim invariants, and keep the user's
complexity concern in scope without starting a broad redesign. Run final
`mix precommit` at the next bounded handoff. **Continue 07; do not start 08 yet.**
