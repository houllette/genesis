# Phase 13 — Every NPC has persona, memory and bounded agency

## Validate phase 12 first

Read [phase 12's handoff](../12-living-pilot/handoff.md). Run the complete GM/player pilot,
scoped NPC bargaining/fallback, meaningful encounter/awards, cross-gathering time and
incorporation/legacy evidence.
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

## Outcome and scope

Every NPC—not just a showcased quest giver—has a stable, evolving persona,
relationships, goals and bounded agency. On interaction or eligible agenda work,
that NPC becomes a unique Lemieux-backed agent grounded in its own state and
knowledge. It can respond, make plans and attempt authorized actions. Dormant
NPCs remain data; unavailable AI uses the same persona's deterministic fallback.

Proposed homes: `Genesis.Engine.NpcAgent`, pure persona/agency/proposal logic,
scoped memory storage, pgvector retrieval, Oban reflection/reaction workers and
dialogue/GM inspection views. All inference, including persona enrichment and
reflection, uses phase 10's Lemieux integration. Request concrete approval for
pgvector infrastructure/dependencies; no assumed embedding API or local-model
bypass. Keep slices independently checkpointable for fresh runs.

## TDD slices

1. **Universal persona lifecycle.** Extend the phase 07 defaults into a versioned
   profile: stable identity/seed, role/culture, speech traits, motivations, values,
   goals, beliefs, secrets, relationships, routines and capability limits.
   Inherit bounded defaults from archetype/world context, then permit Lemieux to
   propose missing detail on first activation. Persist validated enrichment once;
   repeat meetings/restarts do not reroll personality. Test all authored/import/
   generated/spawn paths, two distinct NPCs from one archetype, no-provider
   creation and concurrent first interaction. Pinned facts remain protected.
   Evolve mutable goals/beliefs/disposition through attributable accepted events,
   not an unrestricted model rewrite of character stats or biography.
2. **One owner, unique agents.** One scoped NpcAgent coordinates each hot NPC's
   conversation/agenda queue and Lemieux lifecycle. Bound queue length, player
   input/rate, active agents and concurrent inference. Test simultaneous activation
   from two campaigns, stable turn IDs, fairness and idle demotion. Preserve persona
   and pending-work evidence when the process stops. There is no process/model
   session per dormant NPC and no global conversation shared by different NPCs.
3. **Context and disclosure.** Build each turn from current authorized facts,
   persona version, eligible memory and conversation participants. Same NPC across
   campaigns has one identity but different relationship/knowledge projections.
   Do not carry a private transcript/compaction summary into a public audience;
   use a fresh scoped Lemieux context when needed. Test private → public → different
   campaign → sandbox transitions, membership revocation and hidden IDs/metadata.
   Private deliberation may know secrets, but player-visible narration is built
   only from releasable context and validated outcomes. An NPC belief/lie is not
   narrated as established world truth.
4. **Actions and plans.** Offer a minimal tool set for existing capabilities:
   dialogue, bargain, offer a valid opportunity, transfer an owned item, move,
   or propose a bounded relationship/agenda change. A new NPC/lore proposal needs
   the configured creation/review capability. Revalidate current ownership,
   scope, protected facts, world generation, actor life state, persona/policy
   revision and resources at each commit. Persist goals/plans as intentions and
   schedule bounded steps, not precommitted successes. Test rejected invented
   entities, excessive authority and stale plans; one action changes scoped working
   state and reaches shared canon only through incorporation.
   Merchant and institutional representatives use actual quote/settlement,
   offering and aid capabilities from phase 06–08. Test stale prices, exhausted
   stock, disabled mechanics, fabricated membership and claimed miracles.
   Bargaining can propose new terms, not skip player confirmation or mint goods.
   Religious values/beliefs belong to the NPC; they do not become world facts or
   overwrite a PC's convictions because the model says so.
5. **Interruptions and receipts.** Race response completion with travel, death,
   a second campaign's action, disconnect, restart, budget exhaustion and GM
   possession. Fence stale work; deterministic fallback remains playable. A
   repeated tool or recovered transcript cannot repeat a committed mutation.
   Prior valid local tool commits remain durable if later narration fails; show recorded
   engine results rather than pretending the whole conversation rolled back.
6. **Episodic memory and reflection.** Store NPC encounters, per-character
   relationships and source event/audience/provenance. Filter continuity,
   generation, NPC knowledge and recipient permission before vector retrieval.
   Use real pgvector queries with explicit dimensions/model versions and scoped
   indexes. Combine bounded recency/importance/relevance; reflection through
   Lemieux/Oban preserves source visibility and distinguishes inference/belief
   from fact. Test empty/denied retrieval, wrong vector dimensions, versioned
   re-embedding and exclusion of discarded-future memories after rewind.
   Long-lived player legacies remain discoverable through durable facts/chronicle
   even if NPC working memory is compacted or evicted. Test an old relevant rescue
   against many recent irrelevant events, witness versus rumor knowledge, a
   stranger who cannot know it, and repeat suppression. Awareness/reputation
   spreads through explicit observations/disclosures, not universal mind-reading.
7. **Bounded living-world reaction.** A world event triggers an eligible NPC or
   faction agent through phase 08 scheduling and phase 10 policy. Demonstrate
   negotiation → completion/incorporation → changed patrol plan → later courier discovery. Test causal
   deduplication, maximum fan-out/depth, cooldown, stale generation, retries and
   disabled/budget-exhausted policy. Ordinary preapproved actions need no online
   GM; out-of-policy changes go to review. Never tick or prompt all idle NPCs.
   Attribute autonomous jobs to bounded service principals and policy revisions;
   test that they cannot borrow player/GM authority or another campaign's budget.
8. **Player and GM experience.** The shared TUI on both hosts shows thinking/cancelled/fallback,
   visible consequences and bounded conversation history. GM tools inspect
   persona/goals/provenance and request permitted revisions without revealing
   secrets to players. Buffer/validate outputs; sanitize terminal controls.
   Demonstrate two unique NPCs and two campaigns, an evolving relationship,
   an accepted action, a rejected proposal and a cross-campaign reaction.
9. **Companions with continuing agency.** Connect the actual recruited NPC's
   goals, commitments, witnessed deeds and current party state to its Lemieux
   context. Test willingness/refusal, dissent under bounded policy, separation
   and return; a former companion recalls an eligible shared deed afterward.
   A newly recruited NPC's relevant faction ties can substantially change a beat,
   while its secret history stays out of unauthorized prompts and player views.
   Never replace the persistent NPC with a generic follower or let an LLM grant
   the player new control rights. Provider failure retains deterministic policy.

## Upstream and live evidence gates

Phase 10's verified Provider contract has no embedding callback. Verify a current
Lemieux-supported embedding path or obtain the narrow upstream extension and
pin it; do not add a direct ReqLLM/vendor/Bumblebee inference path in Genesis.
Structured episodic retrieval and deterministic test embeddings permit partial
development, but do not satisfy the real embedding/pgvector integration gate.
A real extension-backed vector query alone does not prove embedding generation.

With authorized provider spend, record persona enrichment, dialogue and one
bounded reaction through actual Lemieux sessions, including model, revision,
latency and costs. Test fallbacks with no provider. Missing real-service evidence
is explicitly pending, never replaced by plausible prose or generated fixtures.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md).

Extend the thin NPC implementation from 12, not a competing host seam. Two campaigns cannot
independently use the same claimed NPC; authorized shared participation joins one queue.
Memory/reflection keys and eligible sources include scope, window and publication status;
map sources at incorporation before later-campaign recall. Agendas run only within admitted
local/approved world targets, never because Oban's wall date changed.

Evaluate observation, belief updates, retrieval, grounding, refusal and repetition
separately under the quality corpus. Race sealing/completion with late replies: reject stale
local writes and other-experience provisional-future disclosure.

## Handoff criteria

- [ ] The pilot remains green; scoped NPC memory/agency obeys completion fences and separate
  quality checks without idle-world advancement.

- [ ] Every NPC path produces stable persona/agency data; distinct agents preserve
  identity and event-driven evolution across campaigns, demotion and restart.
- [ ] One bounded queue per hot NPC; no per-idle-NPC processes or model ticks.
- [ ] Tools, plans and autonomous reactions pass current engine authorization;
  cascade limits, protected facts, costs and generation fences hold.
- [ ] Private transcripts, vector retrieval and reflections never cross forbidden
  audiences/continuities; current-scope reconstruction has regression coverage.
- [ ] Companion-specific agency and old player legacies shape later encounters;
  references are relevant, source-linked and occasional rather than omniscient.
- [ ] Real pgvector and Lemieux-backed embedding generation are verified, or
  explicitly remain unmet upstream/external gates; no inference bypass exists.
- [ ] Both clients support persona-grounded dialogue/fallback; `mix precommit`
  passes using actual scripted Lemieux sessions.
- [ ] [handoff.md](handoff.md) records persona/policy/memory versions, adapter APIs,
  adversarial tests, bounded reaction evidence and any live/provider gates.

Phase 14 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../14-living-history/README.md).
