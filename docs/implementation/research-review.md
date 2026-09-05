# Research interpretation and accepted revisions

The [original research](../../original-research.md) and
[extended report](../../ttrpg-elixir.md) remain preserved source material.
The user's latest review establishes a GM-first personal tool with session-based
time. Current [architecture](architecture.md), [experience time](experience-time.md)
and [product/personas](product-and-personas.md) are the execution authority when
historical recommendations conflict. This document does not claim game features
are implemented or re-certify dated dependency comparisons.

## What remains load-bearing

The pure functional core, scoped single-writer Zones, plain-data dormant NPCs,
Registry/DynamicSupervisor seam, one node, Postgres snapshot-plus-log persistence,
ruleset-as-data and state-level knowledge boundaries remain. Lemieux is the only
inference foundation. AI proposes content/actions; the engine and authorized GM
workflow determine accepted changes. GM curation means control over setting,
constraints and opportunities, not forced player outcomes.

## What the latest review changes

| Earlier direction | Current contract |
| --- | --- |
| Primarily a player-facing shared-world engine | Native GM world-building and curation first; optional shared player TUI |
| Continuous real-time calendar with skips | Explicit Experience duration, multi-gathering pause and GM-managed advancement windows |
| Every action immediately becomes shared-world canon | Every action is durable in its Experience; completion/reconciliation incorporates shared canon |
| Campaigns cannot pause the shared world | Published state intentionally waits while the window's experiences are unfinished |
| No long-lived story claims | Durable conservative footprint/actor/item claims prevent collisions; these are not long DB locks |
| Only sandbox overlays exist | Ordinary experiences have bounded working state intended for incorporation; rehearsals remain explicitly non-canon |
| World time based on absence | Only admitted local or approved incorporation/downtime targets drive simulation |
| NPCs appear late, large history comes first | Early GM workbench, Lemieux preflight and small pilot precede full NPC/history expansion |
| Dedicated later story-instance phase | Experience scope begins in 01–04; time/run orchestration is completed in 08–09 |
| All GM editing needs terminal parity | Native GM editing is primary; only player flows share mandatory TUI parity |
| Proposed data lifecycle | Removed from this personal-use implementation plan |

An Experience is the durable adventure, a PlaySession is an evening/gathering,
Engine Session is a transport attachment, and Lemieux.Session is inference.
These are not interchangeable. A two-hour solo errand may finish while a
three-day group story remains paused; both can await a single consistent world
incorporation. See the mandatory day-100 fixture in the time contract.

The decision brief's other accepted recommendations now live in
[actions/knowledge](play-and-knowledge.md) and [quality](experience-quality.md):
freeform bounded intent, confirmation/partial success, cooperative consent,
typed provenance/knowledge, milestone/legacy growth and empirical quality gates.
The temporary review brief was removed, not left as a competing specification.

## Tempo adoption

The user's selected [Tempo library](https://github.com/elixir-tempo/tempo) is
incorporated through [the time contract](tempo-and-time.md), with immutable source
references and phase-specific tests. Use its testable clock and interval/calendar
tools where useful; keep standard UTC timestamps, OTP monotonic timing and Oban
durability. This does not reinstate a real-time world clock. Phase 03 qualifies
`:ex_tempo`; 08 supplies supported calendar mechanics; 14 extends historical
periods and qualified dates. Arbitrary fantasy-calendar support needs evidence.

## Historical technical assumptions that are still superseded

- Session owns attachment/delivery only; it never writes game state.
- Keep the existing Mix application, not eight speculative umbrella apps.
- Real Supervisors own process trees; worker diagrams do not make GenServers supervisors.
- Save every acknowledged scoped mutation with its event/receipt before reply;
  debounced snapshots alone do not meet the crash contract.
- Record versions, draws, ordering, visibility and source mappings. Replay does
  not reroll or invoke providers. Restore is a coordinated new generation.
- Ecto.Multi gives DB atomicity, not synchronized GenServer caches. Cross-zone
  operations and publication require reservation/fencing/install/recovery.
- Lore/wiki fields cannot independently edit a second copy of runtime state.
- Start with bounded declarative formulas/predicates, never uploaded Elixir.
- Buffer/validate model output; raw token streaming is not safe player narration.
- Publishing a story creates opportunities, not victories or historical events.
- World/campaign/experience are separate identities. GM campaign control does not
  imply world-wide security, incorporation or restore authority.
- All NPCs have stable persona/agency defaults; a showcase agent alone is not universal support.
- Direct ReqLLM/instructor_lite/Bumblebee inference is replaced by the Lemieux host.
- Registry isolates lookup, not distributed ownership safety. Single-node is deliberate.

## Delivery sequence and evidence

The current index has 17 folders: 00 baseline; 01–04 core/authority/durability;
05 native GM workbench; 06–07 subsystems/atlas; 08 time/incorporation; 09 authored
experiences; 10 Lemieux; 11 combined player TUI; 12 living pilot; 13 NPCs; 14
history/genesis; 15 advanced GM control; 16 personal-table release.
All unstarted handoffs use that predecessor chain. The original baseline's
historical validation counts and test results remain historical, not proof of
new features.

## Repository and upstream evidence boundaries

Baseline f46f5bd is one Phoenix application with generated auth, Ecto/Postgres,
PubSub, Oban Basic/default queue and manual-mode job tests; it had no game
modules. That was the documentation-review baseline, not the current working
tree. The subsequent [01–03 batch](03-zone-sessions/handoff.md) implements the
first game foundations and qualifies Tempo. Tool/dependency pins come from
.tool-versions and mix.lock; neither the baseline nor this review proves later
product capabilities.

The earlier review inspected Lemieux's remote host/provider/environment contracts
at the SHA recorded in [Lemieux integration](lemieux-integration.md). Its public
embedding capability remains a named gate, not an invented API. Phase 10 rechecks
a tested pin; 13 must verify the supported embedding path. Prior ExRatatui cell/
SSH documentation supports a candidate design, not compatibility evidence:
[the shared-TUI contract](tui-first-play.md) requires actual-host qualification in 11.
Dependency selection requires current primary-source checks and AGENTS approval.

Oban transactional enqueue and idempotent domain work remain appropriate;
unique jobs alone do not prove exactly-once outcomes.
[Oban insertion](https://oban.hexdocs.pm/Oban.html#insert/3),
[job uniqueness](https://oban.hexdocs.pm/unique_jobs.html),
[Ecto.Multi](https://ecto.hexdocs.pm/Ecto.Multi.html).

mix precommit is the local final gate and writes formatter/generated-rule output.
CI additionally runs checks such as Dialyzer. A local pass is not remote-CI evidence.
The plan requires real-service, human usability and measured scale evidence where
named; fake providers and plausible prose cannot satisfy those gates.
