# Phase 07 — Linked world atlas, multiple zones and global ownership

## Bounded execution slices

The current run selects **07A: linked atlas and persona identity**, chiefly the
record-only portion of slice 6 and existing-creation-path portion of slice 7.
The user accepted the existing 05–06 interface and chose to defer a broad UI
redesign. See the [actual handoff](handoff.md) for evidence and remaining limits.
**07B** still owns the mechanical World graph/global-state migration, claims,
transfers, race/crash recovery, client resubscription and companion behavior.
Describing a route or affiliation in the atlas never implements those mechanics.
Do not mark the full phase complete or start 08 from the 07A subset.

## Validate phase 06 first

Read [phase 06's handoff](../06-world-subsystems/handoff.md). Run native GM resource
controls, quote/trade/recipe accounting, institutional knowledge, scope claims and restart
tests.
Use exact existing commands from that handoff, inspect the implemented APIs and
repair any predecessor defect with a regression test before extending it.
Read [workflow](../workflow.md), [architecture](../architecture.md),
[product/personas](../product-and-personas.md), [experience time](../experience-time.md)
and [actions/knowledge](../play-and-knowledge.md). Read the full extended report
before structural changes; the current GM-first/session-time contracts supersede
its real-time and immediate shared-canon assumptions.
Read [world subsystems](../world-subsystems.md) and [living context](../living-history-and-context.md).

## Outcome and scope

A small world has three connected zones. Characters and their inventories can
travel without duplication or loss; a local action can trigger a controlled
global faction change. Unrelated claimed scopes can continue serving their experiences. The atlas
links people, places, organisations, lore and history across campaigns without
creating independent editable copies of canonical state.

Proposed homes: `Genesis.Engine.World`, transfer coordination, zone/global
reducers, persistence transactions and engine integration tests.

## TDD slices

1. **World ownership.** Validate the zone-neighbor graph. Extend phase 03's World process
   for global flags, faction standings and cross-zone operations, supervised as
   a worker. Keep local faction entities in their zone. Test world/StateScope
   identity collisions, invalid edges and duplicate zone activation.
   Extend phase 06 institutions/markets with global identities and explicitly
   owned world standings/jurisdictions. Preserve local balances/stock, event
   IDs and prior affiliations; document migrations and prohibit dual writers.
2. **Transfer contract.** Start with a test that an actor and all carried item
   identities are owned by exactly one zone after travel. Implement reservation
   at known revisions in a fixed zone order, zone-local candidate validation,
   atomic persistence, cache installation, and release as specified in the
   architecture. Reject inaccessible destinations and unsupported transitions.
3. **Races.** Race take/drop against travel, simultaneous travel by one actor,
   and opposite-direction transfers. Define retry/busy errors. Assert no double
   spend, stale reply, or observable dual occupancy. Do not permit synchronous
   Zone A → Zone B → Zone A call chains.
4. **Recovery.** Persist operation identity/status and fence revisions. Crash
   source, destination or coordinator before commit and after commit before
   both caches install. Recover from durable evidence; unresolved participants
   must not serve stale state or mutations. Verify retry completes once and
   unrelated zones keep accepting work.
   Extend goods transfer to bounded inter-zone delivery/exchange only through
   this protocol; no remote quote directly edits another zone's stock. Test
   commerce against travel and interrupted delivery without item teleportation.
5. **Global and client effects.** Route one faction-standing update to the World
   owner with deduplication. Resubscribe clients after travel, fence old-zone
   messages, and verify public/secret effects across both locations. Extend the
   fixture journey through engine APIs and native GM inspection; player hosts follow in 11.
6. **Linked world workspace.** Add typed region/location, organisation/family,
   lore/article and directional relationship records with tags and backlinks.
   Bind runtime characters/NPCs/items to their world records. Test nested
   locations/cycles, dangling references, archive/tombstone behavior and validated
   custom fields. Public/party/GM notes and beliefs remain distinct from facts.
   Extend existing institution/religious-site records instead of duplicating
   them; add culture/language/kinship, route condition/capacity and resource
   site references as scoped typed records. Record-only fields imply no ecology
   or language simulator. Test broken dependencies and hidden affiliations.
   Add native permission-filtered search and a scoped player read API; test hidden
   titles, counts, snippets and links, not just detail-page denial.
   Use Ecto/Postgres, not a new graph/search engine. Canonical edits go through
   current owners; snapshot/wiki fields cannot diverge.
7. **Persona data and campaign continuity.** Give every NPC creation path a
   stable persona seed, role/culture, motivation, goals, constraints and bounded
   agency defaults as data. No inference yet. Test authored, spawned and minimal
   fallback NPCs, including protected facts. Grow Ashfall: two campaigns see the
   same published NPC/faction/bridge state after incorporation, labelled working
   changes, and only their own notes. Link facts to
   their accepted event and distinguish prototype definitions from live entities.
8. **Companions as existing actors.** Implement recruit/agree/dismiss with
   deterministic willingness, bounded commitments and one active party binding.
   Test competing campaigns, refusal, inventory conservation, separation and
   departure without deleting past relationships. Support bounded party travel
   through the coordinator; declare whether an action moves the whole eligible
   party atomically or schedules explicit follow steps. Never teleport or clone
   a follower. Read current presence/condition/relationship into phase 01 context;
   the same gatekeeper reacts differently to an allied versus hostile companion.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md). This contract is required in this phase.

Acquire destination/global footprint claims before travel or scope expansion. A claimed
merchant in another experience is not a simultaneously interactable copy; offer authorized
join/wait/reschedule. Domain claims survive nights of pause; short transfer reservations end
with transaction/recovery. Ordinary GM saves during a window are drafts; a base amendment
invalidates/revalidates affected work.

## Handoff criteria

- [ ] Cross-zone movement stays within StateScope and preserves one active companion/item
  assignment and a stable base.

- [ ] Three zones run with single writers and one explicit global-state owner.
- [ ] Travel preserves actor/item conservation across races and every recovery
  boundary; DB atomicity is paired with process-cache coordination.
- [ ] Actor location, receipts and history agree; stale-zone events cannot leak
  after travel. No global serialization of ordinary unrelated zone actions.
- [ ] Linked atlas/organisation/lore/relationship records and safe search work
  in native workspace/scoped read APIs; no competing writer or cross-campaign secret leak.
- [ ] Every NPC has validated persona/agency defaults, without activating models.
- [ ] Local economy/institution IDs and receipts survive cross-zone expansion;
  markets, cultures/sites and route records share one authoritative ownership
  model, and resource/delivery races preserve phase 06's accounting invariants.
- [ ] Recruitment/travel conserves one NPC identity and resources; companion
  presence changes actual resolution and departure removes only current benefits.
- [ ] `mix precommit` passes; [handoff.md](handoff.md) records the transfer state
  diagram/table, recovery procedure, actual transaction APIs and race tests.

Phase 08 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../08-living-time/README.md).
