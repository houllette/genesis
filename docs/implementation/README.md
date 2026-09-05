# Genesis implementation plan

Genesis is a personal, GM-first world-building and story-curation tool on
Elixir/OTP, with interactive adventures inside the GM's persistent setting.
The primary workflow is create → connect lore → curate situations → preview →
run across gatherings → incorporate outcomes → inspect the changed world.
The native browser GM workbench is the main product surface. Players optionally
join through one shared TUI hosted over SSH or inside a LiveView Play tab.

Worlds contain multiple campaigns, but this is not an always-running multiplayer
world. A durable Experience can span several real-world gatherings. Its actions
are saved immediately in scoped working state; the shared world/calendar waits
until completed experiences are reconciled and incorporated. Narrative completion
defines elapsed fictional time under GM-approved rules. Player choices and actual
NPC companions can change outcomes; GM curation does not make suggested endings
inevitable. NPC personas and AI assistance use Lemieux behind engine validation.

## Status and authority

The latest user review is incorporated here: GM-first priorities, experience-based
time, acceptance of the other reviewed action/knowledge/quality/character decisions,
and removal of the proposed data-lifecycle workstream. The temporary decision brief
has been removed. These are the execution contracts, not pending recommendations.
Tempo is selected for testable clock reads and supported calendar/interval work;
[its contract](tempo-and-time.md) defines adoption and limits without changing
experience-based time. Phase 03 has now qualified and installed its clock boundary.

Phases 01–03 are implemented as the first bounded batch: pure scene/knowledge/time,
two original rulesets, and ephemeral World/Zone/Session authority. See the
[batch handoff](03-zone-sessions/handoff.md) for exact verification and remaining
limits. Phase 00's [historical handoff](00-baseline/handoff.md) remains historical;
its account/auth/page regressions were refreshed. Published commit `083a563` implements
[04 persistence](04-persistence/handoff.md) and [05 native GM authoring](05-gm-workspace/handoff.md).
Its [GitHub Actions run](https://github.com/houllette/genesis/actions/runs/33951975847)
passed; that result covers 04–05, not later uncommitted work.
[06 local settlement systems](06-world-subsystems/handoff.md) is published as
`9e4c8cf` with successful remote CI. The user reported the existing interface
looked fine after the manual checklist and approved proceeding; the handoffs
distinguish that acceptance from unavailable agent-observed browser evidence.
[07A linked atlas/persona](07-world-zones/handoff.md) is published as `10c54f6`
with [successful remote CI](https://github.com/houllette/genesis/actions/runs/33982428350).
The uncommitted 07B batch adds World-owned directed connections and institution
identity/jurisdiction curation. Bounded 07C1 adds footprint expansion, PC/inventory/
self-contained-knowledge travel, durable reservations/recovery and Session rebinding.
The user accepted 07A/07B manually and explicitly deferred further Browser QA.
07C2 adds whole-footprint sealing, replay/conservation checks, atomic multi-zone
publication with canonical ownership relocation, durable cache fences/recovery
and a native review page. It remains bounded to one zero-duration Experience and
eight places. **Phase 07 is complete within its documented bounds**: 07D adds voluntary companions,
party delivery/exchange, identity-only cross-place knowledge references, scoped
World standing/flags and native accepted-source navigation and typed annotations.
The final `mix precommit` passed 342 tests; separate Dialyzer and asset checks passed.
See the current handoff's closeout for the explicit Phase 08 entry checks and
Browser QA deferral. Phases 08–16 are not started. The 07B/07C1/07C2/07D working tree has not
been committed or pushed.
The user's complexity concern is retained: defer broad UI refinement, keep new
controls progressive, and fix workflow/authority problems when they arise.
All 17 folders have briefs;
unstarted handoffs remain explicit templates. The phase order places GM workspace
in 05, Lemieux authoring in 10,
combined player play is 11, the living pilot is 12, and long history is 14.
Experience/run semantics formerly isolated in a later story-instance phase now
begin in the core and persistence and are completed in 08–09.

The original research/report remain historical source material. When they disagree,
the current shared contracts below take precedence; do not implement real-time
progression, immediate cross-campaign publication or a player-first product from
an older paragraph.

## Read before starting

Read [workflow](workflow.md), [product/personas](product-and-personas.md),
[final execution review](execution-review.md),
[architecture](architecture.md), [experience time](experience-time.md),
[Tempo/time domains](tempo-and-time.md),
[story/canon](story-and-canon.md), [actions and knowledge](play-and-knowledge.md),
and [experience quality](experience-quality.md). The
[research review](research-review.md) explains superseded assumptions.

From phase 01 read [living history/context](living-history-and-context.md);
from 02 read the [subsystem matrix](world-subsystems.md). Before phase 10 read
the complete [Lemieux contract](lemieux-integration.md); before 11 read
[TUI-first play](tui-first-play.md). Each phase begins by validating its actual
predecessor and ends with exact handoff evidence for the next fresh agent.

## Phase map

| Phase | Useful result | Predecessor |
| --- | --- | --- |
| [00 — Baseline](00-baseline/README.md) | Verify boilerplate without game code | None |
| [01 — Pure core](01-pure-core/README.md) | Scoped actions, knowledge, context and experience-time values | 00 |
| [02 — Rulesets](02-rulesets/README.md) | Two original bundles, checks, advancement and defeat contracts | 01 |
| [03 — Zone authority](03-zone-sessions/README.md) | One writer per scope; attachments and qualified Tempo clock boundary | 02 |
| [04 — Persistence](04-persistence/README.md) | Durable experience staging, scope claims, published state and recovery | 03 |
| [05 — GM workbench](05-gm-workspace/README.md) | Create/manage a world and campaigns; prepare, pause and inspect experiences | 04 |
| [06 — World subsystems](06-world-subsystems/README.md) | Real local economy, commerce and religious/secular institutions | 05 |
| [07 — Connected atlas](07-world-zones/README.md) | Linked world records, companions and cross-zone ownership | 06 |
| [08 — Experience time](08-living-time/README.md) | Completion, overlap review, fictional-time simulation and atomic incorporation | 07 |
| [09 — Authored stories](09-authored-stories/README.md) | GM beat editor, context previews, sync/async runs and narrative completion | 08 |
| [10 — Lemieux authoring](10-llm-authoring/README.md) | Proven host boundary and AI-assisted GM drafts/review | 09 |
| [11 — Unified player TUI](11-tui-play/README.md) | Optional invited play over SSH and browser, built and tested together | 10 |
| [12 — Living-village pilot](12-living-pilot/README.md) | Complete GM/player loop with a small encounter and thin NPC interaction | 11 |
| [13 — NPC agency](13-npc-agents/README.md) | Universal personas, scoped memory and bounded evolving agents | 12 |
| [14 — Living history](14-living-history/README.md) | Connected legacies, seeded genesis and measured 2,000-year continuity | 13 |
| [15 — Advanced GM control](15-gm-tools/README.md) | Possession, deep history tools and coordinated checkpoint restore | 14 |
| [16 — Personal-use release](16-release-readiness/README.md) | Useful, recovered and measured single-node tool for an invited table | 15 |

Run in this order, not by following a historical phase number. Each phase has
bounded TDD slices; checkpoint long phases across independent runs. Later agents
preserve earlier public contracts and regression tests. Dependency approval,
real-service evidence and publication authority remain separate gates.

## Product acceptance

- A GM can create a world, connect places/people/institutions, manage multiple
  campaigns and curate an experience without first inviting or impersonating a
  player. Native authoring, search, notes and impact review are the primary UX.
- GM-authored beats preserve setting constraints while allowing negotiation,
  refusal, departure and genuine failure. Context from deeds and companions
  changes actual options and consequences, not only prose.
- An Experience pauses across several gatherings with no wall-time advancement
  or expired-game-turn storm. A two-hour solo errand and three-day group adventure
  share a window; incorporation advances three days, not the sum or wall elapsed.
- Claimed shared NPCs/items cannot be used in conflicting adventures. Cross-scope
  dependencies are checked during preparation; conflicts receive actionable GM
  review. Completed stories do not silently overwrite one another.
- Ready outcomes, preview, elapsed time, confirmation, canonical publication and
  resulting chronicle are visible and recoverable. Retry creates one history;
  abandoned/failed play preserves its actual outcomes for reconciliation.
- One small Ashfall pilot proves GM prepare/run/incorporate/return, player agency,
  an NPC's relevant memory and cross-campaign discovery before long-history work.
- Both original rulesets use the same engine. Economy, commerce, obligations and
  religious/secular settings have real small mechanics and honest support levels.
- Every NPC has stable evolving persona/agency data. All inference uses Lemieux;
  actual host/store/environment/budget tests and explicit embedding/live gates
  prevent assumed integration or an alternate provider path.
- The same player TUI runs in SSH and the browser Play tab. Real mixed-client,
  authorization, reconnect, input and accessible-action evidence is required;
  full GM editing does not need terminal parity.
- Major player events persist through incorporation, approved downtime, restart
  and campaign closure. Places, resources and relationships change; later eligible
  references are sourced and occasional. Repair adds history instead of erasing it.
- A bounded measured 2,000-year generated world continues under the same causal
  laws through completed experiences, not automatic passage of real time.
- Native GM and player knowledge remain separate at the state/model boundary.
  Restricted credentials, inference caps, audit, backup/recovery and a small-table
  capacity rehearsal remain engineering basics; no public hosting platform is required.

See [coverage](coverage.md) for ownership and evidence. Full VTT graphics, voice/
video hosting, arbitrary sandbox merging, multi-node ownership and public-server
scale are not first-delivery requirements.

## Assigning a fresh agent

> Begin phase 08 from `docs/implementation/08-living-time/README.md`,
> validating the current Phase 07 handoff, including 07D, before extending time or
> multi-Experience reconciliation. Follow `AGENTS.md`
> and the current shared contracts. Validate the predecessor's actual handoff
> and regression commands first. Work through this phase using red–green–refactor,
> run `mix precommit`, and record exact evidence and next-agent entry checks in
> its handoff. Stop at the phase boundary. Do not infer dependency installation,
> provider spending, upstream edits, publication or deployment authority.
