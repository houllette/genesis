# Living-World, System-Agnostic RPG Engine on Elixir/OTP + ExRatatui — Architecture Report

## TL;DR (key decisions)
1. **Reverse the "no per-entity processes" call — partially.** Make **zones/locations processes** (single-writer authority per zone), keep **NPCs, items, factions as data inside their zone** by default, and promote an NPC to its own process only when it has an active LLM conversation or an autonomous agenda. Zone = the consistency boundary, à la Kalevala Zone/Room and Nakama's "one node owns the match" (Heroic Labs docs: "A single node is responsible for this to ensure the highest level of consistency accessing and updating the state").
2. **Living world = lazy simulation, not global ticks.** Keep the prior "event-driven" instinct but add a coarse world clock. Zones hibernate when empty and **catch up on wake** by fast-forwarding their schedule; only a small global scheduler runs while nobody's home. Don't tick thousands of idle NPCs.
3. **Persistence: snapshot + command log now, event sourcing selectively.** Postgres (jsonb + embedded schemas) for entity state; an append-only **event/command log per world** for "what happened while I was gone," GM audit, and replay. Do **not** adopt full Commanded/CQRS for the whole world — use it (or a hand-rolled event table) only for the shared canonical world timeline.
4. **Single node + Postgres for the stated scale (dozens–low hundreds of players).** Design process lookups through a `Registry`/`DynamicSupervisor` seam so you *can* swap in Horde later, but do **not** pay the CRDT/libcluster complexity tax on day one.
5. **Ruleset-as-data via a `GameSystem` behaviour + declarative content.** A game system is a plugin module implementing a behaviour, plus data (attributes, resources, dice/check grammar, item slots, actions) loaded/validated at boot. One dice/check abstraction expresses d20, 2d6 PbtA, dice pools, and Fudge dice. Fantasy and cyberpunk are two config bundles, not two codebases — the Foundry VTT "system-agnostic core + system module / DataModel" pattern.
6. **Narrative = storylet/QBN state machine authored by the GM; LLM fills validated content.** Story skeleton is data (beats + predicates over world/quality state); the LLM emits JSON validated by Ecto schemas and reviewed before it becomes canon. Runtime NPC dialogue is constrained to a fixed action space with hand-authored fallbacks.
7. **NPC agents: Generative-Agents memory model, but cheap.** Behavior tree / scheduler drives routine action; LLM only for dialogue and occasional decisions; per-player relationship + episodic memory; tool-calling into engine intents with strict output validation and prompt-injection isolation.
8. **ExRatatui is confirmed fit-for-purpose.** v0.11.x has the LiveView-style `App` behaviour with `handle_info/2` (the Ratatouille external-message problem is solved), built-in SSH subsystem transport, and Erlang-distribution attach. One `App` instance per connected player over SSH, shared backend state via PubSub.

---

## 1. What changes from the single-player conclusions (explicit)

| Prior conclusion (single-player) | New verdict (living multiplayer world) | Why |
|---|---|---|
| Don't make rooms/NPCs/items processes | **Zones become processes**; NPCs/items stay data until "hot" | Need a single-writer authority per spatial partition to serialize concurrent player actions |
| Campaign GenServer is sole authority | **Per-zone authority**, campaign/world process owns only global state (clock, factions, cross-zone) | One global writer becomes a bottleneck and a single failure domain with many players |
| Event-driven, not tick-driven | **Mostly event-driven + coarse lazy world clock**; hibernation + catch-up | A living world needs time to pass when unobserved, but ticking idle entities is waste |
| Event sourcing overkill | **Selective event log for the shared world timeline** | "What happened while I was gone," GM audit, and replay are now real requirements |
| ECS wrong for narrative game | **Still wrong** as the core; entity-as-data + reducers stays | Turn/narrative logic doesn't benefit from ECS system-iteration; keep functional core |
| Multi-node deferred | **Still deferred**, but keep the Registry seam | Scale doesn't justify Horde/CRDT yet |

---

## 2. Revised architecture

### Supervision tree (single node)
```
Engine.Application
├─ Repo (Postgres; jsonb + embedded schemas + pgvector)
├─ Phoenix.PubSub                      # fan-out to sessions
├─ Registry (:zones, :sessions, :npcs) # via-tuple lookups (Horde-swappable seam)
├─ World.Clock                         # coarse global tick + scheduler of due events
├─ WorldSupervisor (DynamicSupervisor)
│   └─ World (GenServer)               # per active world: global state, factions, clock cursor
│       ├─ ZoneSupervisor (DynamicSupervisor)
│       │   └─ Zone (GenServer)        # single-writer authority; holds entities/items as data
│       │       └─ NpcAgentSupervisor  # NPCs promoted to processes only when "hot"
│       │           └─ NpcAgent (GenServer)  # LLM dialogue / autonomous agenda
│       └─ StoryInstanceSupervisor (DynamicSupervisor)
│           └─ StoryInstance (gen_statem / Finitomata)  # curated story run (solo or group)
├─ SessionSupervisor (DynamicSupervisor)
│   └─ Session (GenServer)             # one per connected player/GM; client of Zone/World
├─ LLM.Supervisor
│   ├─ LLM.Gateway (rate limits, cost caps, caching, provider routing)
│   └─ LLM.OfflineCompiler (content generation → validation → review queue)
└─ Transport.Supervisor
    └─ ExRatatui SSH daemon (subsystem mode)  # 1 App per connection
```

**Session vs. Zone split (keep functional core):** `Session` owns the ExRatatui `App` state (the Elm-ish TUI model) and the player's `Conn`-style context token (borrow Kalevala's `Conn`). Game state lives in `Zone`/`World`. Sessions send intents to the authoritative Zone; Zone applies pure reducers `(state, intent) -> {state, effects}` and broadcasts effects over PubSub. This is Nakama's authoritative-match model mapped onto per-zone GenServers.

### Umbrella / app layout (evolve `saga_*` → neutral `realm_*`)
- `realm_core` — pure: structs + reducers, dice/check engine, modifier resolution. No processes.
- `realm_systems` — `GameSystem` behaviour + bundled rulesets (fantasy, cyberpunk) as data + plugin modules.
- `realm_content` — narrative DSL (storylets/beats), compile-time validation of diverts/refs.
- `realm_engine` — OTP: World, Zone, Session, StoryInstance, NpcAgent, clock/scheduler.
- `realm_persistence` — Ecto schemas, snapshots, world event log, replay.
- `realm_llm` — gateway, structured-output validation, RAG grounding, NPC memory.
- `realm_tui` — ExRatatui apps: player app, GM app, shared widgets.
- `realm_transport` — SSH daemon, auth, invite tokens, session wiring.

### Data model (sketch)
- **World**: id, ruleset ref, clock cursor, global flags. **Zone/Location**: id, world_id, neighbors (graph edges), embedded entities/items, hibernation state, `last_simulated_at`.
- **Entity/Character**: id, kind (pc/npc), system-specific `attributes` jsonb validated against the active system schema, resources, inventory, faction memberships, location_id. **Item**: def_id + instance state; equipment slots per system.
- **Faction**: id, standings graph, agenda state.
- **Story / StoryInstance**: story = skeleton (beats + predicates); instance = live cursor + quality state + participant set + branch/merge policy.
- **Session / Player / Role**: player identity (SSH key), role (gm/co_gm/player/spectator), per-world invite, per-actor visibility set (fog of knowledge).
- **NPC memory**: episodic stream rows (embedding via pgvector), reflections, per-player relationship scores.
- **WorldEvent log**: append-only (actor, intent, effects, timestamp, zone) for audit/replay/"catch-up."

---

## 3. Game-system plugin design (ruleset-as-data)

### The `GameSystem` behaviour
A system is a **plugin module + data bundle**. The behaviour surfaces the parts that genuinely need code; everything declarative is data validated at boot.

```elixir
defmodule Realm.GameSystem do
  @callback attributes() :: [AttrSpec.t]          # STR, REF, humanity...
  @callback derived() :: [DerivedSpec.t]          # HP = f(attrs), dependency graph
  @callback resources() :: [ResourceSpec.t]       # hp, stress, essence, humanity
  @callback check(Check.t, Actor.t, Ctx.t) :: Check.Result.t   # resolution mechanic
  @callback character_schema() :: Ecto.Schema     # for TUI form-gen + validation
  @callback item_slots() :: [SlotSpec.t]
  @callback actions() :: [ActionSpec.t]           # turn economy / intents
  @callback subsystems() :: [module]              # magic, netrunning, vehicles
end
```
Attributes, derived values, resources, item slots, actions, and the character sheet schema are **data** (TOML/JSON loaded at boot, or an Elixir DSL compiled). Resolution mechanics and subsystem logic that need branching are **code**. This mirrors Foundry VTT: a system-agnostic core plus a per-system DataModel declaring the schema (Foundry v10+ makes `DataModel` "a framework to define a structured data schema from which document objects can be constructed, validated, updated, and serialized"; system-specific data lives under a document's `system` property). Evennia's typeclass + Attributes approach is the same lesson from the MUD world — arbitrary attributes attached to objects rather than a schema per entity type, and the framework is deliberately "game-agnostic... does not prescribe a genre, game rules, skills, classes, combat system."

### Dice / check expression language
Build a small expression layer. **Do not** adopt an abandoned dice lib; the maintained math-expression evaluator **abacus (v2.2.0, updated Mar 2026, narrowtux)** parses expressions into valid Elixir AST that can be compiled to BEAM bytecode — use it for derived-stat formulas and modifier math, and add a thin dice grammar (via NimbleParsec, already in your stack) for the random part. A `Check` is a struct, not a string, so it can express radically different mechanics:

```elixir
%Check{
  dice: "1d20",  modifiers: [{:attr, :str}, {:prof}],
  vs: {:dc, 15}, mode: :roll_over        # d20 / 5e
}
%Check{ dice: "2d6", modifiers: [{:stat, :cool}], thresholds: [{:>=,10,:full},{:>=,7,:partial}], mode: :pbta }
%Check{ dice: "Nd6", pool: {:attr_plus_skill}, count_successes: {:>=,5}, mode: :pool }  # Shadowrun-ish
%Check{ dice: "4dF", modifiers: [{:skill}], vs: {:opposed}, mode: :fudge }              # Fate
```
One `check/3` dispatch per `mode`; adding a system = adding data + at most a resolution clause. **Modifier stacking / derived stats**: model as a dependency graph recomputed on change (spreadsheet-style), evaluated with abacus; ordered rulebooks (Inform 7 before/instead/after — your prior conceptual model) handle conditional application.

### Same engine, two rulesets (illustrative bundle)
```toml
# fantasy.toml
attributes = ["str","dex","con","int","wis","cha"]
resources  = [{name="hp", formula="con_mod*level + roll(hit_die)"}]
check      = {default="1d20", mode="roll_over", proficiency=true}
slots      = ["head","body","main_hand","off_hand"]
subsystems = ["magic_vancian"]

# cyberpunk.toml
attributes = ["int","ref","dex","tech","cool","will","luck","move","body","emp"]
resources  = [{name="hp", formula="10 + 5*ceil((body+will)/2)"}, {name="humanity", formula="emp*10"}]
check      = {default="1d10", mode="roll_over", exploding=true}
slots      = ["cyberware_neural","cyberware_body","weapon"]
subsystems = ["netrunning","cyberware"]
```
For fantasy content, Open5e / 5e-SRD JSON is a ready source of monsters, items, and spells you can ingest into this shape; cyberpunk/Shadowrun data models add resources like humanity/essence and subsystems (netrunning) — both fit the same schema with system-specific extensions.

---

## 4. Narrative DSL + LLM story pipeline

### Story skeleton shape (storylet / QBN + state machine)
Adopt **quality-based narrative** (Fallen London / StoryNexus). Per Emily Short (2016), QBN is "the term invented by Failbetter Games to refer to interactive narratives structured around storylets unlocked by qualities... Qualities are numerical variables that can go up or down during play, and represent absolutely everything from inventory... to skills... to story progress." The core loop, in her words (2017): "the world state determines what the player is currently allowed to do; everything the player does then updates the world state again."

A GM authors a story as **beats (storylets)** with **prerequisite predicates** over world + quality + roster, plus a coarse spine (act/beat ordering) so it degrades gracefully:

```elixir
defstory "The Ashfall Contract" do
  requires entities: [:fixer_moll, :the_docks]
  quality  :heat, 0..10
  beat :meet_fixer, when: at(:the_docks) and quality(:heat) < 3 do
    on_enter llm_generate(:scene, constraints: [tone: :noir, must_reference: [:fixer_moll]])
    choices [ ... ]
    effects [set_quality(:heat, +1)]
  end
  failure_state when: quality(:heat) >= 10, into: :heat_crackdown
end
```
Beats reference the world's canonical factions/locations/NPC roster so generation stays world-consistent. For *auto-suggesting* beat skeletons, use Doran & Parberry's quest grammar — from their analysis of 750+ quests across EVE Online, World of Warcraft, EverQuest and Vanguard (*A Prototype Quest Generator Based on a Structural Analysis of Quests from Four MMORPGs*, 2011, UNT LARC), they derived nine NPC-motivation categories, each mapped to a set of verb-noun strategies (e.g. "kill pests," "steal supplies," "rescue NPC") that decompose into ordered atomic actions with prerequisites. Model the runtime as **gen_statem** or **Finitomata (v0.41.0, actively maintained, Jun 2026, am-kantox)** — Finitomata gives you a declarative FSM DSL with compile-time validation, which fits "GM defines states/transitions." Avoid **machinery** here: it's **unmaintained (last release v1.1.0, Apr 2023)**.

### LLM authoring pipeline
Two-stage, matching your prior "offline compiler vs runtime flavor" split:
1. **Offline content compiler** (`LLM.OfflineCompiler`): GM triggers generation for a beat; LLM emits **structured JSON** → validated against Ecto schemas → grounded in world lore via RAG (pgvector + Bumblebee embeddings, or just structured context injection of the roster/factions) → lands in a **review queue** → GM approves → promoted to canon (same struct shape as hand-authored content). Consistency across many stories is enforced by (a) injecting canonical entities and (b) validating that referenced entities/items already exist.
2. **Runtime**: constrained flavor only (see §5).

**Structured-output tooling, verified Sept 2026:** prefer **instructor_lite (v1.3.0, actively maintained, Jul 2026, martosaur)** over the original **instructor / instructor_ex (v0.1.0, stale since Feb 2025)**. **req_llm (ReqLLM) has reached and passed 1.0 — now v1.21.1 (Aug 2026, agentjido/mikehostetler)** — the cleanest Req-native path for `generate_object`/structured output and multi-provider routing (Anthropic/OpenAI/Gemini/Groq/Ollama/Bedrock). **langchain (brainlid) is at v0.13.1 (Aug 2026, active)** if you want the heavier agent/tool framework. Recommendation: **ReqLLM as the transport + instructor_lite for schema-validated extraction**. (Prior art worth studying, not depending on: CALYPSO as an LLM co-DM assistant; MUDGPT/Holodeck and the current crop of self-hostable AI-TTRPG projects with COC/DND rule systems, most of which are early and thinly maintained.)

---

## 5. NPC agent design + guardrails + cost model

### Agent architecture (Generative Agents, made cheap)
The reference is Park, O'Brien, Cai, Morris, Liang & Bernstein, *Generative Agents: Interactive Simulacra of Human Behavior*, UIST '23, pp. 1–22 (arXiv:2304.03442) — memory stream + reflection + planning. Make it affordable:
- **Memory**: episodic rows in Postgres, embedded via pgvector. Retrieval scoring follows Park et al.: recency ("a higher score to memory objects that were recently accessed, based on an exponential decay function"), importance (an LLM-output integer distinguishing mundane from core memories), and relevance ("cosine similarity between the memory's embedding vector and the query memory's embedding vector") — the three normalized and combined with equal weighting. Periodic **reflection** synthesizes higher-order memories.
- **Per-player relationship state**: separate small record per (npc, player) — the shared NPC has many relationships.
- **Routine behavior via behavior tree + scheduler** (Kalevala/ExVenture NPC pattern); the LLM is called **only** for dialogue and the occasional "decision," not every tick.
- **Group conversation** (many players → one NPC): the NpcAgent process **serializes** inbound utterances into a single turn queue; batches concurrent utterances into one prompt turn where possible; broadcasts the reply to all present via PubSub. This is exactly why the NPC is a process when hot.
- **NPC-to-NPC / world events**: NPCs subscribe to zone/faction events; reactions are scheduled, not real-time.

### Guardrails (security-grade — the point of your background)
- **Fixed action space / tool-calling into engine intents.** The LLM never mutates state directly; it emits a tool call (`give_item`, `set_relationship`, `offer_quest`) that is **validated by the engine** against the ruleset and world (item must exist, quest must be real). Hallucinated items/quests are rejected — the engine, not the model, is the source of truth.
- **Prompt-injection isolation.** Treat all player chat as untrusted. Structurally separate player text from instructions (delimited, never concatenated into the system prompt); keep canonical facts in a privileged channel the player text can't overwrite; output validation rejects out-of-schema or out-of-canon responses; per-player and per-session **rate limits and hard cost caps** at `LLM.Gateway`. Log every prompt/response for audit and GM review. Players *will* try to jailbreak NPCs — assume it and validate outputs, don't trust the model to "refuse."
- **GM override / puppeteer.** GM can seize any NPC ("possess") and speak as it, or pin/rewrite an NPC's canonical facts.

### Cost & latency
- **Tiering**: small/local model (Ollama or Bumblebee/Nx/EXLA) for routine flavor lines; frontier API model for key story beats. Cache aggressively (identical prompt+context → cached line); hand-authored fallbacks when the LLM is slow, over budget, or fails validation.
- **Streaming over SSH**: stream tokens into the ExRatatui view via `handle_info/2`; each Session renders its own frame, so many terminals stream independently. Local models remove per-token API cost for the bulk of lines; a realistic self-hosted 2026 setup = Ollama for routine lines + an API model for climaxes.

---

## 6. Play modes & GM tooling

### Three modes over one world state
All three are **the same `Zone`/`World` authority** with different **session/instance wrappers**:
- **(a) Invited solo curated story** → a `StoryInstance` bound to one Session, running in a **forked/branched copy** of the relevant zones (copy-on-write) so the solo player doesn't perturb the shared world. Merge-back policy: usually **no merge** (instanced dungeon model).
- **(b) Group curated story, no GM, sync or async** → one `StoryInstance` with multiple Sessions; async play works because the story is a persistent state machine + quality state — players advance beats at different times; "waiting for X" states are explicit FSM states. This is the MMO **instance** concept.
- **(c) Live GM session** → Sessions attach to the **shared open world** (not a fork); a GM Session has elevated intents (spawn, narrate, adjudicate, secret roll, possess NPC, pause/rewind time via the event log).

**Branching/forking world state**: copy-on-write snapshot of the affected zones at instance creation; the fork carries its own event log. "Shards"/"instances" = named forks. Merge-back (if ever) is a manual GM-reviewed diff, not automatic — treat it like a git branch you cherry-pick from.

### GM terminal (multi-pane ExRatatui)
Borrow Foundry/Roll20 GM affordances (fog, secret rolls, whisper, token spawn, macros) and MUSH/MOO builder commands (in-world building, `@dig`/`@create`-style). Layout:
```
┌ World Map / Zone list ─────┬ Player roster (loc, hp, status) ┐
│ (jump, spawn, edit)        │ + connection state              │
├ Story-state-machine view ──┼ Hidden/GM-only info (fog) ──────┤
│ (current beat, predicates) │ secret notes, upcoming beats    │
├ Adjudication console ──────┴─────────────────────────────────┤
│ >  spawn npc moll at docks   |  roll secret 1d20+3           │
│ >  possess moll              |  whisper @alice ...           │
├ Live event log / narration feed (append-only, rewindable) ───┤
└──────────────────────────────────────────────────────────────┘
```
Multi-pane is directly supported by ExRatatui's constraint layout + the `Focus` primitive for multi-panel apps. **Per-actor views (fog of knowledge)** are first-class: each effect carries a visibility set; the Session only renders what its role/actor may see, so "what the GM sees vs. what players see" is enforced at the state layer, not the UI.

### Turn / time model
- **Real-time by default** for exploration/chat (event-driven).
- **Turn-based when combat starts**: the Zone enters a combat sub-mode (gen_statem) with an initiative order; it becomes the turn arbiter ("whose turn"), time-boxing turns so one slow/absent player can't stall the group (auto-default or GM adjudication on timeout). This is how ExVenture/Kalevala and Evennia's turn-based contribs reconcile it.
- **Async group play**: because state is persistent, players in different zones act independently; combat only synchronizes the participants in that Zone.

### Drop-in/drop-out
On disconnect: character is **parked** (save-and-freeze) by default; optional **AI autopilot** (behavior tree, or LLM-lite) for co-op continuity; in combat, auto-defend/dodge default or NPC takeover. Reconnect over SSH resyncs by replaying the Session's current authoritative Zone snapshot into a fresh ExRatatui `App`. The event log gives a "here's what happened while you were gone" digest.

---

## 7. Transport & security

### ExRatatui — verified findings (Sept 2026)
- Package `ex_ratatui` (mcass19), Rustler bindings to Rust ratatui, precompiled NIFs (Linux x86_64/aarch64/armv6/riscv64, macOS, Windows) — no Rust toolchain needed. Runs on the BEAM **DirtyIo** scheduler so event polling never blocks. Docs/forum cite the current line as **v0.11.1** (repo actively updated Mar 2026; Hex has historically also carried a 0.5.x line — pin explicitly).
- **`ExRatatui.App` behaviour exposes `mount/1`, `render/2`, `handle_event/2`, and `handle_info/2`.** The `handle_info/2` callback means **the Ratatouille "can't push external async messages into update" problem is solved** — your backend pushes state (NPC lines, world events, other players' actions) straight into a player's App via ordinary process messages. There's also an Elm-style reducer runtime (update/2 + commands + subscriptions) if you prefer it.
- **SSH transport**: subsystem mode with nerves_ssh integration and auto host-key bootstrap; drop the daemon into your supervision tree. Public-key auth, custom host keys, idle timeouts, and user/password options are supported. **Distribution-attach transport** serves an App to remote BEAM nodes over Erlang distribution.
- **Multi-session**: ExRatatui handles session isolation and terminal management per transport; each connection gets its own terminal reference (Rust `ResourceArc`) and its own App instance — exactly the "one App per connected player, shared backend state" model you need (the `ash_tui` explorer demonstrates the same App running unchanged across local/SSH/distributed transports). Widgets include Paragraph/Block/List/Table/Gauge/Chart/Canvas/Calendar/Sparkline/BarChart, a `Widget` protocol for composites, `Focus` for multi-pane, and rich text (Span/Line). Resize is delivered as an event.

### Recommended hosting topology (homelab / k8s)
- **Single VM or single k8s pod** for the engine + Postgres (managed or sidecar) at this scale. SSH daemon exposed; **Erlang distribution never exposed to the internet.**
- **NAT/remote access**: put the SSH endpoint behind **Tailscale/WireGuard** (or a Cloudflare tunnel) for a homelab; invited players join the tailnet or connect to the tunneled SSH port. This avoids opening raw SSH to the world while keeping latency low for live GM sessions.
- Full-screen TUI redraws over SSH: ratatui does frame diffing; keep frames modest and rely on partial updates. Latency for live sessions is fine on a LAN/tailnet; the real bottleneck is LLM calls, not rendering.
- k8s buys you rolling deploys and restarts here, not scale — a single well-backed-up VM is honestly sufficient until you exceed low hundreds of concurrent players.

### Security checklist
- Per-player **SSH keys**; **one-time invite tokens** map a key → world + role at onboarding.
- **Never** expose EPMD / Erlang distribution publicly; bind dist to localhost/tailnet; set a strong cookie.
- Treat all player input as untrusted: typed command grammar (NimbleParsec) rejects malformed input; free text only reaches the LLM through the isolated, validated path (§5).
- **World isolation**: a Session's role/world scoping is enforced at the Zone/World authority, not the UI; spectators get read-only visibility sets.
- **Audit logging**: the WorldEvent log doubles as a security/GM audit trail; log all LLM prompts/responses and GM impersonation actions.
- **GM impersonation risk**: "possess NPC" and "speak as" actions must be logged and visibly attributed in the audit log even if hidden from players.
- **LLM API keys**: keep in env/secret store injected at runtime; never in world data; enforce per-world cost caps so a compromised or abusive session can't run up spend.

---

## 8. Persistence decision (reasoned)

**Recommendation: snapshot + per-world append-only event log; reserve full event sourcing for the shared world timeline only.**

- **Entity/zone state** → Postgres relational skeleton + **jsonb / Ecto embedded schemas** for system-specific attributes (flexible across rulesets). Snapshot on scene/zone transitions + debounced autosave (your prior cadence still holds).
- **Shared world timeline** → append-only **WorldEvent** table (actor, intent, effects, zone, timestamp). This is what makes "what happened while I was gone," GM audit, rewind, and replay cheap. You can hand-roll this on Postgres, or use **commanded/eventstore (v1.4.x, maintained)** if you want the CQRS machinery — but full Commanded across the whole world is overkill and couples you to aggregate/projection ceremony you don't need at this scale.
- **ETS** → hot, per-zone transient indexes (who's in the room, cooldowns) — rebuildable, not persisted. **Mnesia** → skip; Postgres + PubSub covers it without Mnesia's operational sharp edges. **pgvector (v0.4.0, maintained, Jun 2026)** → NPC memory embeddings.
- **Thousands of NPCs cheaply**: store NPC state as rows with jsonb attributes; only "hot" NPCs are processes. Dormant NPCs are pure data, simulated lazily on zone wake.
- **Concurrency**: single-writer per Zone removes most contention; for cross-zone/global writes use `Ecto.Multi` + optimistic locking on the World row (your prior instinct, now scoped to global state).

---

## 9. Named libraries — versions & maintenance (verified Sept 2026)

| Library | Version | Status | Use |
|---|---|---|---|
| **ex_ratatui** | 0.11.1 (docs); 0.5.x line also on Hex | **Active** (updated Mar 2026) | THE interface |
| kino_ex_ratatui / phoenix_ex_ratatui | current | Active | Livebook dev / browser dev-render |
| Raxol | v2.x | Heavy multi-surface alt | Not recommended as primary |
| Garnish | — | :ssh ssh_cli TUI | Fallback transport only |
| Kalevala | v0.1.0 (Hex) | Reference, low activity | Borrow Conn/Foreman/Router patterns |
| ExVenture | **archived** | Dead as a dep | Study only |
| **instructor_lite** | **1.3.0** | **Active (Jul 2026, martosaur)** | Schema-validated LLM output |
| instructor (instructor_ex) | 0.1.0 | **Stale (Feb 2025)** | Prefer instructor_lite |
| **req_llm (ReqLLM)** | **1.21.1** | **Active, past 1.0 (Aug 2026)** | Primary LLM transport |
| **langchain (brainlid)** | **0.13.1** | **Active (Aug 2026)** | Optional heavier agent framework |
| NimbleParsec | current | Active | Command grammar + dice grammar |
| **Finitomata** | **0.41.0** | **Active (Jun 2026)** | Story/combat FSM |
| Machinery | 1.1.0 | **Unmaintained (Apr 2023)** | Avoid |
| gen_statem (OTP) | — | Core | FSM without a dep |
| Horde | current | Active | Only if/when multi-node |
| libcluster | current | Active | Only if/when multi-node |
| **abacus** | **2.2.0** | **Active (Mar 2026, narrowtux)** | Formula/derived-stat eval (AST→BEAM) |
| **pgvector** | **0.4.0** | **Active (Jun 2026)** | NPC memory embeddings |
| **Bumblebee** | **0.7.1** | **Active (Jul 2026, elixir-nx)** | Local embeddings / local inference |
| commanded / eventstore | 1.4.x | Active | Only if adopting CQRS for world log |
| ecsx / ecspanse | 0.5.2 / 0.10.1 | Semi-stale / stale | Not used (ECS rejected) |

---

## 10. Hardest-to-reverse vs. cheap-to-reverse

**Hard to reverse (decide carefully now):**
- Zone-as-authority boundary & the Session↔Zone intent protocol (touches everything).
- The `GameSystem` behaviour + check-abstraction shape (all rulesets depend on it).
- The WorldEvent log schema (audit/replay/rewind depend on its fidelity).
- Per-actor visibility ("fog of knowledge") as a first-class state concept — retrofitting it later is painful.
- Functional-core purity (reducers return effects) — keeps everything else testable.

**Cheap to reverse:**
- Which LLM provider/model (Gateway abstracts it).
- Local vs. API inference mix (tiering is config).
- Finitomata vs. raw gen_statem for stories.
- Single-node vs. Horde (if the Registry seam is respected).
- TOML vs. JSON vs. DSL for ruleset data.

---

## 11. Vertical-slice build order (each step independently testable)

1. **Functional core**: `realm_core` structs + reducers + `Check` engine; property-test d20 and 2d6 resolution. No processes.
2. **One Zone, one Session, local**: Zone GenServer as authority; a bare ExRatatui `App` connects locally; player issues an intent, sees the effect. Prove the Session↔Zone protocol + `handle_info/2` push.
3. **SSH multiplayer**: ExRatatui SSH subsystem daemon; two terminals connect as two players into one Zone; PubSub fan-out; both see each other's actions. Invite-token → key auth.
4. **Persistence**: Postgres snapshots + WorldEvent log; reconnect resync + "what happened while gone" digest.
5. **Living world**: World.Clock + zone hibernation + catch-up-on-wake; one scheduled NPC routine with no player present.
6. **Second ruleset**: load `cyberpunk.toml` alongside `fantasy.toml`; same engine renders both character sheets via schema-driven TUI forms. Proves ruleset-as-data.
7. **One LLM NPC**: NpcAgent promoted when talked to; tool-calling into engine intents; output validation + injection isolation + cost cap; hand-authored fallback. Two players talk to the same NPC (serialized turns).
8. **One LLM-generated story**: GM authors a 3-beat storylet skeleton; OfflineCompiler generates + validates beat prose; GM reviews/approves; solo player plays it in a forked instance.
9. **GM live session**: GM terminal multi-pane; spawn NPC, secret roll, possess NPC, rewind via event log; per-actor fog enforced.
10. **Target reached**: one GM + two remote players, one small living world over SSH, one LLM NPC, one LLM story, two rulesets loadable.

---

## 12. Caveats & open questions
- **ExRatatui is young.** v0.11.x is feature-rich but the versioning is early and the Hex line has been inconsistent (0.5.x vs 0.11.x) — pin versions and keep the `Transport`/`App` surface behind your own thin adapter so a breaking release doesn't ripple. Load-test many concurrent SSH sessions early — published evidence of "hundreds of concurrent SSH TUI sessions" is thin; you will be an early validator.
- **LLM latency for live combat narration** may exceed acceptable turn time; keep the frontier model for out-of-combat beats and use cached/local lines in fast exchanges.
- **Copy-on-write world forks** are conceptually clean but can get memory-heavy if a solo instance touches many zones; bound fork scope to the zones the story actually references.
- **Merge-back semantics** for instanced stories are genuinely hard; recommend "no automatic merge" until you have a concrete need.
- **Group-conversation serialization** with one NPC can feel laggy if many players spam it; consider a GM-tunable turn cadence and per-player rate limits.
- **Reflection/memory cost** for many NPCs adds up; cap memory depth and reflection frequency per NPC, and only run reflection for NPCs that have been "hot."
- **Multi-node** will eventually matter if you exceed a single box; the Registry seam is your insurance, but Horde's CRDT netsplit behavior needs real testing before you rely on it for authoritative world state.