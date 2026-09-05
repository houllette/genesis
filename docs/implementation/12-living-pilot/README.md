# Phase 12 — A useful GM loop and memorable living-village pilot

## Validate phase 11 first

Read [phase 11's handoff](../11-tui-play/handoff.md). Run real mixed-host and
headless regressions, key/role revocation, experience labels and pause/reconnect.
Recheck 08's incorporation crash/conflict tests, 09's terminal duration/authoring,
and 10's actual Scripted Lemieux adapters/budgets/resume. Read
[workflow](../workflow.md), [architecture](../architecture.md),
[quality](../experience-quality.md), [actions/knowledge](../play-and-knowledge.md),
[experience time](../experience-time.md) and the full Lemieux contract.

## Outcome and scope

Prove the GM-first end-to-end experience in a small village before extending all
NPCs or generating thousands of years. Add one small durable encounter and a thin
Lemieux-backed NPC interaction using the established engine/host. This is real
production-path vertical work, not a throwaway chatbot or a second engine.
Full NPC enrichment/vector memory and generation are explicitly left to 13–14.

Build these bounded slices across fresh runs and checkpoint evidence. Proposed
homes: pure Encounter, a small scoped NpcAgent, existing Session/Zone/LLM adapters,
native GM panels and shared TUI views. No new provider or framework is authorized.

## TDD slices

1. **Small encounter.** Both original bundles resolve start, supplied initiative,
   legal turn, attack/check, defend/concede, defeat and return to exploration.
   Apply action economy, actual stock/resources and companion willingness. No
   player obtains turn control merely through campaign membership. Claim shared
   actors before admission; participants meeting share one Experience/Zone.
2. **Duration and recovery.** Persist turn/resources/local elapsed time atomically.
   Retry a lost reply without new dice or damage. Timeout jobs bind turn/scope/
   generation and obey pause/resume: next week's gathering resumes that turn,
   not an expired-turn avalanche. Defend/pass defaults apply only to an actively
   running encounter under its disclosed policy. Both player hosts take turns.
3. **Progress and stakes.** Exercise cooperative/exceptional-risk checks, default
   nonlethal defeat, one real setback, a scoped milestone and party award identity.
   Reopen/complete/incorporate twice without duplicate awards. Retirement preserves
   a sourced legacy; a successor cannot clone assets or private knowledge.
4. **Thin NPC interaction.** Use 07's stable data and 10's actual Lemieux host for
   one named NPC's serial turn queue, eligible sourced context and one real bargain
   proposal. Test companion-sensitive terms/refusal, explicit confirmation, unknown
   tool/file denial, stale turn/experience status, budget exhaustion and fallback.
   A second distinct NPC supplies a control case; no global shared conversation.
   Use structured episodic retrieval; do not claim embeddings or full 13 complete.
5. **Small lasting memory.** Persist one witnessed deed and directed relationship;
   select a later relevant sourced callback with repetition suppression. Test
   unknown/private/provisional-other-experience facts are absent. Changing dialogue
   alone is insufficient: the deed changes an actual option or offer.
6. **GM-first full journey.** Create/curate Ashfall in the native workspace, use
   AI-assisted drafting where enabled, preview two contexts, invite play, pause
   across gatherings, finish with duration, inspect/approve impacts and incorporate.
   Show changed grain stock, relief obligation and bridge/relationship. The next
   campaign discovers a permitted legacy. Also complete a GM-authored async story
   while the GM is offline; an independent ready courier waits for the paused group.
7. **Quality review.** Execute the committed scenario matrix from the quality
   contract. Record GM preparation friction, incorporation comprehension and NPC
   grounding/refusal/repetition observations. Both real play hosts and the native
   GM workbench need actual usability evidence. Set latency/spend targets before
   any authorized live trial; scripted passing tests do not establish live quality.

## Handoff criteria

- [ ] Both bundles complete the bounded encounter with exact resource/turn results.
- [ ] Pause/restart/timeout/duplicate-action races preserve local fictional time.
- [ ] A real Lemieux tool proposal changes a validated offer; rejection/fallback
  preserves agency, authority and budgets.
- [ ] The GM prepares/runs/incorporates/inspects without developer intervention.
- [ ] A later campaign discovers a source-linked mechanical consequence and an
  eligible occasional reference; no provisional/secret future leaks.
- [ ] Milestone, loss and retirement/transfer tests preserve actual ownership.
- [ ] Human observations and actual-host evidence satisfy the small pilot gate;
  required live-provider evidence is recorded or explicitly remains unmet.
- [ ] mix precommit passes; [handoff.md](handoff.md) names exact fixture, tests,
  observed failures/limits and the APIs 13 will extend.

Phase 13 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../13-npc-agents/README.md).
