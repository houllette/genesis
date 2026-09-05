# Handoff: 07 — Linked world atlas, multiple zones and global ownership

Status: **in progress**. 07A implements a bounded linked atlas and NPC-persona
slice; final gate results are recorded below. The full phase is not complete.
07B must implement actual cross-zone/global ownership, transfers and companions
before phase 08 begins. No later phase, new dependency, provider or timer started.

## Entry validation and scope decision — 2026-09-05

Base: published main `9e4c8cfd436aeb69cdd8f710d51c7b1cd543b3a1`, clean on
entry. Phase-06 remote CI succeeded (run 33977526863, verified at publication).
New 07A changes are uncommitted and are not covered by that remote result.

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
remain unchanged. 07B must explicitly preserve/map this reference when promoting
global identity or moving a site's authority.

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
- No commit/push performed for 07A; remote CI does not cover this diff.

## Remaining 07B work and next entry

No transfer state machine or recovery table is supplied because **no transfer
protocol has been implemented**. Follow brief slices 1–5 and 8, then finish
their linked-record/continuity acceptance cases:

1. Validated mechanical zone-neighbor graph, global institution/standing and
   jurisdiction ownership with explicit migrations preserving local identities.
2. Destination/global footprint claims, stable-order reservations and revision
   fences; atomic actor + all inventory/delivery transitions; cache installation
   and release; durable operation status and recovery at every crash boundary.
3. Actual independent-connection conservation/race checks, client resubscription
   and old-zone effect fencing. No synchronous Zone A → B → A chains.
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
mix test test/genesis/core/atlas_record_test.exs test/genesis/core/persona_test.exs test/genesis/core/curation_test.exs test/genesis/persistence test/genesis/engine test/genesis_web/live/atlas_live_test.exs test/genesis_web/live/workspace_live_test.exs test/genesis_web/live/settlement_live_test.exs --warnings-as-errors
```

Reproduce the native atlas journey above, preserve the golden snapshot, v1/v2
persona semantics, local accounting and claim invariants, and keep the user's
complexity concern in scope without starting a broad redesign. Run final
`mix precommit` at the next bounded handoff. **Continue 07; do not start 08 yet.**
