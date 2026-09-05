# Phase 10 — Lemieux host integration and adaptive authoring

## Validate phase 09 first

Read [phase 09's handoff](../09-authored-stories/handoff.md). Run native authoring/context
preview, provider-free solo/group decisions, duration/terminal completion and
incorporation/rehearsal isolation.
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

## Outcome and scope

Genesis embeds Lemieux as its only agent/inference foundation. A GM requests
help designing beats, stakes, contextual variants and possible follow-ups,
reviews the draft and publishes an immutable opportunity. The GM can preview
it in a sandbox, log off and let players discover it. Actual outcomes remain
engine-owned and unscripted. A thin NPC pilot follows in 12; full lifecycle/reactions expand in 13.

Proposed homes: `Genesis.LLM` host/gateway adapters, Ecto transcript/run/audit/
budget storage, Genesis tools, Oban authoring worker and existing review views.
The user has selected Lemieux; verify the exact pin, compatibility and dependency
change under AGENTS. No independent ReqLLM/instructor_lite/HTTP inference client.
Do not patch a neighboring repository without explicit upstream-change authority.

## TDD slices

1. **Actual harness contract.** Pin and mount Lemieux under a named supervisor.
   Run its Scripted provider with Genesis's explicit tools, immutable profile,
   scoped Store and deny-all Environment. Test prompt → structured tool proposal
   → validated tool result → finished, malformed arguments, cancellation and
   bounded turns/deadlines. Test implicit `@path` reads, unknown tools, MCP/code/
   filesystem defaults and restored capabilities are denied. This is a real
   Lemieux integration test, not a mock of Genesis's own gateway.
2. **Shared hard budgets.** Persist and atomically reserve a run envelope against
   world/campaign/principal limits, then configure Lemieux's session cost/turn/
   token bounds inside it. Follow-up, compaction and correction calls share the
   envelope. Test concurrent NPC/compiler-style runs, cache hits, duplicate jobs,
   cancellation, crash/resume and unknown usage/prices. Retain ambiguous spend;
   a retry cannot replenish a cap. Document accounting periods and reconciliation.
3. **Durable transcript and audit.** Implement ordered scoped Store append/read/
   list and host-controlled resume. Correlate run, transcript, provider attempts,
   request context revisions and tool/engine receipt IDs. Persist prompt/response,
   model, versions, timing, validation and usage outcomes, including failures.
   Test resume after a commit with a missing tool-result append; no action repeats.
   Recheck current authority and audience before restoring context or capabilities.
   Raw model events stay inside the adapter, never in player PubSub topics.
4. **Context, schema and compiler.** Use scoped world facts, relationships and
   canonical event references to generate beat drafts through Lemieux tools.
   Distinguish trusted engine constraints from untrusted player/draft/retrieved
   text. Reject invented references, injected commands, excessive output and
   violations of pinned facts. New entities require explicit validated proposals,
   not unnoticed additions inside prose. Oban retries are bounded and idempotent;
   never wrap an unbounded second loop around Lemieux's retries.
   Supply actual capability versions and support levels. Reject drafts requiring
   disabled/deferred mechanics or fabricated stock, money, membership or divine
   facts. Test religious/currency and secular/barter worlds without hardcoded
   setting branches. Models cannot upgrade a record-only stub into an action.
5. **Review and publish opportunity.** Extend phase 09 authoring with provenance,
   proposed beats/variants, validation errors, current-context diff, cost and
   preview. Revalidate references and revisions at approval. A builder can revise
   narrative situations, not retroactively set outcomes. Published definitions
   pin versions for active runs; material world changes since drafting cause
   revalidation/review rather than overwriting live facts. Separate explicit
   world-fact edit commands from content approval. Test retire and republish.
6. **Automation policy seam.** Extend phase 08 policy data with steward-approved
   model purposes, action classes, territories, protected facts and budgets.
   Campaign settings may narrow, not widen, world policy. Test authorization,
   disabled inference, policy revisions and required review for major lore or
   destructive changes. Prepare the bounded world-reaction consumer for 13;
   no default-enabled unvalidated automation in this phase.
7. **Grounded contextual adaptation.** Generate within a declared variation
   envelope: permitted role/stake/approach/follow-up changes and fixed facts.
   Test minor and major proposals against the same context matrix as phase 09.
   Lemieux receives only eligible character/deed/companion facts and selected
   historical sources; validate output references and current revisions. It
   cannot invent a past rescue, erase a crime or choose success for the player.
   Add a small sourced relevance/cooldown selector for old deeds needed by the
   pilot; full history expansion follows in 14. Use its eligible sources, not an
   unrestricted prompt to mine all history. Optional
   generated chronicles summarize actual events without executing them again.

## Integration and evidence

Review routes extend the existing authenticated browser/live_session scope;
world/campaign builder authorization is enforced in contexts and at publication.
Native review is required; compact terminal administration is optional later. Cache keys
include continuity/generation, campaign/audience, persona where relevant,
context revisions, model/settings and prompt/content versions. Cached text never
bypasses current authorization or replays a cached mutation.

All inference purposes use Lemieux. Inspect its embedding support and record
any gap for phase 13 without inventing an API or adding a direct-provider path.
Use configured credentials and an explicitly authorized cap for an actual
Lemieux generate → review → publish → discover → differently resolve journey.
Record SHA/model/date/latency/cost. Missing live access remains an unmet gate;
ordinary tests run offline with Scripted and do not prove live quality.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md). This contract is required in this phase.

Run the actual Scripted host/store/environment/budget preflight before rich editor work.
Context/cache/transcript keys include StateScope, window, Experience and publication status.
Test free text → typed goal proposal, clarification, confirmed commitment, stale revision,
unsupported mechanic and partial success. No mutation precedes authorization; no model tool
grants time or completion authority. Duration suggestions are reviewed inputs. Preserve
explicit live compatibility/spend and embedding gates.

## Handoff criteria

- [ ] Actual Lemieux sessions preserve experience scope and translate free text without
  gaining mutation/time/completion authority.

- [ ] Actual Lemieux sessions prove tool/store/environment/lifecycle integration;
  coding tools, implicit file reads and raw player-facing model streams are denied.
- [ ] Concurrent runs and nested provider requests stay within reserved budgets;
  resume/cancellation/retries cannot erase uncertain spend or duplicate actions.
- [ ] Restricted audit and current-context reconstruction preserve all scopes.
- [ ] Reviewed definitions become discoverable, not predetermined historical
  facts; stale lore/invalid references cannot silently change the live world.
- [ ] Contextual variants and historical references stay within the validated
  envelope; all referenced deeds have eligible sources and mention limits.
- [ ] Native authoring/preview and policy boundaries are tested; `mix precommit`
  passes without paid credentials.
- [ ] [handoff.md](handoff.md) records tested Lemieux SHA/APIs, exact harness tests,
  upstream embedding gap/status, and live journey evidence or its unmet gate.

Phase 11 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../11-tui-play/README.md).
