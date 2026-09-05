# Lemieux is the only inference foundation

Required by the user on 2026-09-04: all Genesis LLM interactions build on
[Lemieux](https://github.com/houllette/lemieux). `Genesis.LLM` is the game-specific
host adapter/policy boundary, not another provider SDK or agent loop. This
replaces the research's direct ReqLLM/instructor_lite selection. No dependency
is installed in this documentation pass.

The [world-subsystem contract](world-subsystems.md) also governs model tools:
use real engine commerce, resource and institution actions with current versions,
ownership and confirmation requirements. Disabled/record-only mechanics cannot
be promoted by a prompt; no fabricated stock, money, membership or divine facts.
The player interface remains Genesis's shared TUI, not Lemieux's coding-agent UI.

## Verified upstream contract

Inspected remote `main` at `e427221bc6b6c2b70909256d048174b986910fbd` on
2026-09-04 using authenticated read-only GitHub access. The local Lemieux checkout
was older (`534c75a`); it was not changed. Recheck and pin a tested upstream
revision at phase 10; this observation is not a compatibility test or a mandate
to follow a moving branch. Anonymous browser access returned 404.

Lemieux provides host-mounted supervision, start/resume APIs, asynchronous
sessions, subscribers, host-supplied tools, durable transcript storage and
session cost limits. Sessions are temporary workers: recovery explicitly resumes
a transcript, not an empty automatic restart. One prompt can cause multiple
provider calls. Host capabilities must be supplied again on resume. Its shipped
Scripted provider supports deterministic integration testing. See the pinned
[embedding
contract](https://github.com/houllette/lemieux/blob/e427221bc6b6c2b70909256d048174b986910fbd/docs/embedding.md).

The public `Lemieux.Provider` seam runs requests and exposes estimates/model
metadata. Its production implementation is `Lemieux.Providers.ReqLLM`; upstream
explicitly rejects adding parallel vendor transports there. Do not implement
direct vendor HTTP calls in Genesis. See the pinned
[Provider
source](https://github.com/houllette/lemieux/blob/e427221bc6b6c2b70909256d048174b986910fbd/lib/lemieux/provider.ex).

Prompt file-reference expansion occurs independently of giving the agent a
read tool. Files and commands go through the supplied Environment; the default
is local access. Genesis therefore supplies a deny-all environment, including
reads/listings, for all game agents. See the pinned
[Environment
source](https://github.com/houllette/lemieux/blob/e427221bc6b6c2b70909256d048174b986910fbd/lib/lemieux/environment.ex)
and the embedding contract's file-reference section. Test `@config/runtime.exs`
as hostile player text, not as an intentionally granted attachment.

## Responsibility split

| Genesis owns | Lemieux supplies |
| --- | --- |
| Authenticated world/campaign/actor scope and current capabilities | Bounded session/tool loop and policy hooks |
| Zone/World commands, rules, revisions and canonical commits | Tool invocation and provider response handling, not game authority |
| Persona construction, authorized memory/context, content schema validation | Host-supplied prompts/tools and conversation management |
| Durable shared budgets, admission policy, cancellation/recovery decisions | Session-level request estimates/caps, usage and lifecycle events |
| Ecto transcript adapter and restricted audit access | `Lemieux.Store` append/read/list contract |
| Safe player projections and UI lifecycle | Internal session events, never a player authorization boundary |

Use Genesis's own LiveView/ExRatatui game UI, not the `lmx` coding-agent terminal.
`Lemieux.Session` is neither an Engine Session nor an authoritative NPC record.

## Required host configuration

Scope every run/cache/context to published state, Experience or preparation
candidate, including window/generation and source publication status. An unrelated
experience's provisional future is not eligible NPC knowledge. Late results cannot
write a sealed experience, incorporate outcomes, or invent elapsed time. Background
agency runs only within an admitted local or approved advancement target. Native
GM authoring/review is primary; all phases consume the same host boundary.

- Mount an explicitly named Lemieux supervisor with test-local names in tests.
  One active NPC owner controls at most one admitted deliberation at a time;
  offline compiler/reaction jobs have separately bounded sessions.
- Pass an explicit game system prompt and a minimal allowlist of Genesis tools.
  Do not call `Lemieux.Tools.default/0`. No bash, code evaluation, file editing,
  arbitrary web requests, MCP, CLI workspace discovery, executable plugins or
  delegation. Optional features stay disabled on fresh **and resumed** sessions.
- Host tools receive trusted run identity/capabilities from server construction,
  not model arguments. Use immutable `tool_profile` caps and pre-tool policy;
  the final engine check still decides permission and resource/revision validity.
- Supply a deny-all `Lemieux.Environment`, no credentials in `cwd` or persona
  text, and no filesystem-based transcript store. Test attachments and resume
  against this boundary as well as the visible tool catalogue.
- Store transcripts via a scoped Ecto implementation of `Lemieux.Store` with
  ordered durable append, read and list. Correlate inference run, transcript,
  provider attempts, tool call IDs and WorldEvents. A transcript tool success
  is not proof of a game commit; use domain receipts to recover that ambiguity.
- Only an internal Genesis adapter subscribes to raw Lemieux events. Buffer
  deltas, validate final structured results, and deliver authorized game effects.
  Never forward reasoning, system prompts, raw tool arguments or secret memory
  to a player LiveView/TUI. Credentials stay in runtime provider configuration.

## Every purpose uses the same boundary

Story/beat drafting, NPC persona enrichment, dialogue, agenda planning, world
reactions, reflection and optional generated recaps all use the adapter. Initial
structured output can use a bounded `submit_draft`/`propose_action` tool with
Ecto validation and bounded correction feedback inside Lemieux. It does not
require an independent structured-output client.

Contextual variants and optional chronicle/legacy narration use this same path.
The pure world generator and continuing simulation do not need inference;
Lemieux may enrich only validated, eligible facts. A recall prompt receives a
bounded selection of sourced events after knowledge/relevance/cooldown checks,
not all of world history. Generated references cannot grant past deeds, create
memorials or re-execute consequences merely by mentioning them.

Embedding generation is a specific upstream gate: the inspected public Provider
contract has no embedding callback. Phase 13 must verify a supported Lemieux
embedding path or request the narrow upstream extension and pin/test it. Do not
invent a `Lemieux.embed` API, call a vendor/Bumblebee/ReqLLM directly as a silent
bypass, or label fake vectors real integration. Scoped episodic/structured
retrieval can support development while that gate is explicitly pending.

## Budget and recovery contract

Reserve a durable aggregate **run envelope** in Genesis before starting a
session, atomically against world, campaign and initiating-principal limits.
Autonomous jobs use an explicit service allocation and policy attribution;
they do not inherit another campaign's player credentials or spending identity.
Assign the corresponding Lemieux session cap plus bounded turns/output/deadline;
all compaction, correction and tool-follow-up calls consume that same envelope.
No model-selectable children or separately funded hidden sessions. This keeps
shared concurrency admission in Genesis and provider-call estimation in Lemieux,
without duplicating the agent loop. If a proven path needs per-request host
admission, add a tested delegating policy seam, not another provider transport.

On cancellation/crash, fence game capabilities immediately, but retain uncertain
cost reservations until reconciled. Resume/retry must account for earlier spend;
it cannot start with a newly replenished cap. Missing prices/usage are unknown,
not zero. Embeddings and any separately billed service must join the same ledger
when its supported path exists. Local inference still has resource/concurrency
limits even if configured monetary cost is zero.

Lemieux handles in-session tool follow-ups; Genesis/Oban handles durable job
retries with stable run IDs. Bound the combined attempt budget. A retried tool
uses a stable engine receipt key and returns the recorded outcome after current
authorization checks. Transcript replay never re-executes canonical mutations.

Reconstruct current host authority on resume. A stored prompt/transcript may
contain now-forbidden campaign knowledge or a discarded generation. Do not
resume it into a newly broadened audience: create a fresh, scoped session from
eligible memory while retaining restricted transcripts for audit. NPC identity
and persona survive independently of the model conversation's context window.

## Phase 10/13 contract tests

Run real Lemieux sessions with `Lemieux.Providers.Scripted` and the actual Genesis
tool/store/environment adapters. Test tool → receipt → result → finish; malformed
arguments; forbidden tools; file-reference denial; cancellation; compaction;
unknown costs; concurrent envelopes; restart/resume; duplicate tool IDs; and
current-scope reconstruction. Adapter-only mocks do not prove the host contract.

Record the tested Lemieux SHA, lockfile, adapter APIs, policy options, schema
support and unresolved upstream gaps in each handoff. Live generation/dialogue
requires configured credentials and authorized spend; never infer these from
the choice of library. Keep ordinary `mix precommit` offline and deterministic.
