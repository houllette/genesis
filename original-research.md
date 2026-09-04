# Architecting an Extensible, Star Wars-Themed Text Adventure in Elixir + Ratatouille

## TL;DR

- **Build a pure-functional game core (structs + reducer functions) wrapped in one GenServer per session, persist to Postgres via Ecto with a jsonb-hybrid schema and snapshot-on-scene-transition — and do NOT let Ratatouille's Elm loop own your game state.** Ratatouille (0.5.1, last released March 25, 2020, no releases since across 8 versions) is effectively unmaintained, and its runtime has no public way to inject external async messages (LLM tokens, another player's move) into `update/2`; you work around this with an interval-subscription that polls a GenServer, or you adopt a maintained successor (ExRatatui or Raxol) for the SSH/multiplayer future.
- **Treat the TUI as one disposable frontend over a transport-agnostic core.** The hardest-to-reverse decisions are the core/shell boundary, the content representation, and the persistence model — get those right now; the TUI library, the LLM vendor, and the parser-vs-menu input model are all cheap to swap later.
- **Use LLMs offline as a content compiler (generate → validate against an Ecto schema → commit as canon), and only at runtime for cosmetic NPC flavor lines constrained to a fixed action space.** The deterministic story spine stays hand-authored. Adopt Ink or Yarn Spinner's *authoring concepts* but implement your own runtime in Elixir; do not depend on their C#/JS engines.

## Key Findings

### The TUI library landscape has moved on from Ratatouille
Ratatouille is the best-documented Elixir TUI kit and implements The Elm Architecture (model/update/render via `Ratatouille.App`, plus `Runtime.Subscription` and `Runtime.Command`). But its last Hex release is **0.5.1 (March 25, 2020)** — the latest of 8 versions, with none since, and roughly 13,779 all-time downloads — and it is effectively unmaintained (17 open issues, 5 open PRs on GitHub). It builds on `ex_termbox`, whose NIF creates an OS thread for blocking event polling — a workable design, but it is a NIF, so a C-level crash can take down the BEAM. There is a keep-alive fork, `ratatouille_ok` (0.5.2, last updated June 28, 2025, publisher "karamo"), but it is a single-version compatibility fork, not active development.

Successors worth knowing, with status:
- **ExRatatui** (mcass19/ex_ratatui, ~v0.11.1, 2025): Elixir bindings to Rust's `ratatui` via Rustler NIFs, event polling on the DirtyIo scheduler, `ExRatatui.App` behaviour with LiveView-style callbacks, precompiled NIFs (Linux x86_64/aarch64/armv6/riscv64, macOS x86_64/aarch64, Windows x86_64), and — critically for this project — **built-in SSH transport (subsystem mode, `nerves_ssh` integration, auto host-key bootstrap) plus an Erlang-distribution attach transport** that can serve any `ExRatatui.App` to remote BEAM nodes. Young (0.x) but the most modern option and rides on ratatui, one of the most actively maintained TUI cores in any language.
- **Raxol** (v2.x, 2025–2026): an ambitious "multi-surface" runtime — one TEA module renders to terminal, Phoenix LiveView, SSH, and MCP/agent surfaces. It even advertises token-streaming and inter-agent messaging over a Registry. Feature-rich but sprawling (many sub-packages, some pre-release), with heavy marketing language; treat its performance superlatives with caution. Builds on `rrex_termbox` (the revived ExTermbox, now on the termbox2 NIF, v2.0.4).
- **Garnish** (ausimian/garnish, ~v0.2.0): a Ratatouille-derived TUI framework that runs over Erlang's `:ssh` as an `ssh_cli` server channel, renders directly to escape sequences (no termbox NIF), and copies Ratatouille's view/render layer verbatim. Early, xterm-256color only, but a very clean model for serving a TUI over SSH.
- **elixir_opentui** (v0.1.1): Zig-NIF backend, pre-alpha/experimental — mention only.

### Ratatouille cannot be driven from external events without a workaround
This is the single most important architectural finding for this project. Reading `Ratatouille.Runtime`'s source: the runtime is a plain `Task` (not a GenServer), and its `receive` loop matches exactly three inbound shapes — `{:event, ...}` (terminal key/resize/mouse), `{:command_result, ...}` (the result of a `Command` the app itself started), and an `after state.interval` timeout that fires interval subscriptions. The default loop interval is **500 ms** (`@default_interval_ms 500`). There is no public/documented API for an arbitrary external process (an LLM streaming tokens, a co-op peer's action broadcast over PubSub) to push a message into `update/2`; a message that doesn't match those shapes just sits unhandled in the mailbox. Subscriptions are interval/timer-only — `Ratatouille.Runtime.Subscription` offers `interval/2` and `batch/1` and nothing resembling subscribe-to-a-pid or PubSub.

The idiomatic workarounds:
1. **Interval-subscription-as-poll.** Run a separate GenServer/Agent/ETS "inbox" that external producers write to. Use `Subscription.interval(ms, :poll)` so every tick `update/2` receives `:poll`, drains the inbox, and folds items into the model. Latency is bounded by the loop interval — lower `:interval` (e.g., 50–100 ms) for streaming responsiveness at the cost of more wakeups.
2. **Command for one-shot async you own.** `Runtime.Command` legitimately runs a function in a Task and sends `{:command_result, msg}` back — correct for "call the LLM once, get the whole reply." Not suited to a long-lived external stream.
3. **Custom runtime.** The "Under the Hood" guide documents building your own loop with `Ratatouille.Window` + `Ratatouille.EventManager` + a manual `receive`, where you can add your own clauses to accept external messages. This is the real escape hatch — and it's essentially what Garnish/ExRatatui already did by reimplementing the runtime.

The strategic implication: if streaming LLM dialogue and co-op are first-class goals, either (a) accept the poll-the-inbox pattern on Ratatouille for the vertical slice, or (b) start on ExRatatui/Raxol, whose runtimes already contemplate external/streamed messages and SSH. Because your game core is transport-agnostic (see architecture), this is a **cheap-to-reverse** decision — build the slice on Ratatouille if you like its ergonomics, and swap the shell later.

### There is strong Elixir prior art for text-game architecture
**ExVenture** (Eric Oestrich) and its extracted framework **Kalevala** are the reference designs. Kalevala's model maps almost directly onto your needs: a `Character.Foreman` process per connected player handles incoming text and orchestrates output; a `Conn` context token (à la `Plug.Conn`) accumulates renders and events to fire together; `Command.Router` uses a small parser DSL to pattern-match input; `View` modules render iodata/EEx; and `World.Zone`/`World.Room` processes act as local PubSub for events. Oestrich's ElixirConf 2020 talk "Writing Game Servers With Elixir" frames both ExVenture and Kalevala as event-driven systems built to be "full of state" and to handle thousands of users, with Kalevala being "a rewrite of ExVenture's internals" that treats events as the foundational structure (and behavior trees for AI). This is the "functional core, imperative shell" pattern realized for a text MUD — steal it.

### Ink and Yarn Spinner: adopt the concepts, write your own runtime
Both are mature, well-documented narrative formats. **Ink** (inkle; open-sourced under MIT on March 11, 2016, by Jon Ingold and Joseph Humfrey) compiles `.ink` to a JSON runtime format via the `inklecate` compiler; its durable abstractions are knots/stitches, diverts (`->`), weave, and variable state, with a C#/JS runtime. **Yarn Spinner** uses plain-text `.yarn` files of nodes (`title:` header, `---`/`===` body markers) containing lines, options, commands, and `jump`s. Neither has an Elixir runtime, so adopting either means writing a parser (NimbleParsec is the right tool) or the JSON interpreter. Yarn's node/option/jump model is simpler and closer to a menu-driven TUI; Ink is more expressive. For **LLM-assisted authoring**, Yarn's flat, forgiving syntax is easier for an LLM to emit validly than Ink's denser weave syntax — but the most robust path is neither: have the LLM emit **structured JSON validated by an Ecto schema** (via `instructor_ex`/`instructor_lite`) and compile that into your own scene structs.

### LLM tooling in Elixir is now solid
- **instructor_ex** / **instructor_lite**: structured outputs coerced into Ecto schemas. You define an `@llm_doc` description plus a `validate_changeset/1` (via `use Instructor.Validator`); combined with `max_retries: 3`, Instructor "iteratively go[es] back and forth with the LLM up to n times with any validation errors so that it has a chance to fix them" — ideal for the offline content pipeline ("LLM writes content, engine validates it"). Note `max_retries` is disabled in streaming mode, so use it for authoring, not runtime streaming.
- **LangChain (Elixir, brainlid/langchain, ~v0.13):** full chains, tool-use, streaming callbacks, multi-provider (Anthropic/OpenAI/etc.). Heaviest but most complete.
- **ReqLLM (~v1.0):** composable Req-plugin client, `generate_text/stream_text/generate_object`, per-model cost metadata; lighter and idiomatic.
- Streaming into a TUI: tokens arrive on a Task/stream, get written to the GenServer inbox, and the Ratatouille interval-poll drains them — implement a typewriter effect and an "NPC is thinking…" state to hide latency.

### ECS is the wrong abstraction here
`ecsx` (ETS-backed components, GenServer systems, tick-based) and `ecspanse` exist and are real, but ECS is built for real-time simulation with many entities updated every tick. A narrative, turn-based text game has few entities and event-driven (not tick-driven) state changes. ECS would add a per-tick loop and component-query machinery you don't need. Skip it.

## Details

### A. Functional core, imperative shell — and avoiding two nested state machines
The trap with Ratatouille is that TEA *is itself* a model/update/render state machine, so it's tempting to put game state in the Ratatouille model. Don't. Keep two clearly separated layers:

- **Game core (pure):** plain modules and structs. `GameState`, `Character`, `Scene`, `Quest`. Functions like `Core.resolve_command(state, command) :: {new_state, [effect]}`. No processes, no IO, fully unit-testable and reproducible. This is where the deterministic story spine lives.
- **Ratatouille model (thin):** holds only *view/session* concerns — the current input buffer, scroll position, "thinking" flags, a cached projection of the game state for rendering, and a reference (via the inbox) to the session process. When a key is pressed, `update/2` sends the parsed command to the session GenServer and updates only presentational state; the authoritative game state transition happens in the core, and the new projection flows back through the inbox.

This avoids duplicating state: the core is the single source of truth; the Ratatouille model is a render cache.

### B. Process topology
Concrete recommendation for the current scope and its growth path:

- **One `Session` GenServer per player** (drop-in/drop-out unit), registered in a `Registry`, started under a `DynamicSupervisor`. It owns the player's authoritative `GameState` in memory and calls the pure core for transitions.
- **One `Campaign`/`Instance` GenServer** when co-op begins: it owns the *shared* canonical state for a co-op session; player Sessions become clients that send commands to it and receive broadcasts. This is the host-authoritative model.
- **`Phoenix.PubSub`** for event fan-out (room/say, quest-updated, player-joined). You get this "for free" and it's the same primitive Kalevala's rooms use as local PubSub.
- **Do NOT make rooms, NPCs, or items processes yet.** In a single-player, story-driven game they are plain data inside the session's state. Per-entity processes pay off only when entities have independent concurrent lifecycles (autonomous NPCs acting on timers, rooms with many simultaneous actors) — i.e., a real MUD. Adding them prematurely buys you distributed-state headaches (the "two players mutate the same object" problem) with no benefit. Your story-driven, turn-based design sidesteps the hard real-time concurrency problems by construction: commands to a shared Campaign are serialized through its GenServer mailbox, giving you a total order with zero locking.
- **Distribution:** defer. When you need multi-node, `Registry` → `Horde.Registry`/`Horde.DynamicSupervisor` (or `syn`) is the swap; `Phoenix.PubSub` already clusters. Don't build for this now.

### C. Persistence with Ecto/Postgres
Recommended model — **relational skeleton + jsonb for flexible entity attributes**, with snapshotting:
- Normalized tables for the things you query and index: `accounts`, `characters`, `saves`, `sessions`.
- A `jsonb` column on the save/character for the flexible, fast-evolving bag (inventory, flags, quest progress, kyber crystal choice). This lets you add species traits and quest state without a migration per content change — which also means LLM-authored content that introduces new attributes doesn't require schema churn.
- **Write frequency:** never per keystroke, and not per command. Snapshot the game state **on scene transitions and other natural save points** (entering the Gathering, choosing a crystal), plus a debounced autosave (e.g., write at most every N seconds if dirty). Keep the hot state in the Session GenServer; Postgres is the durable checkpoint, not the working store.
- Use **`Ecto.Multi`** for transactional multi-table state transitions (advance quest + update inventory + write snapshot atomically). Add **optimistic locking** (`Ecto.Changeset.optimistic_lock` on a `lock_version`) on the shared Campaign state so two co-op writers can't silently clobber each other.
- **Event sourcing (`commanded`, `eventstore`) is overkill at this scale.** It's a serious commitment (CQRS, eventual consistency, projections) justified by audit/replay requirements you don't have. You can get 80% of the replay/debugging benefit cheaply by logging the *command stream* per session to a table alongside snapshots — deterministic core + recorded commands = reproducible replays, without adopting a framework. Revisit `commanded` only if audit/time-travel becomes a product requirement.

### D. Static content vs. dynamic state — build a compile-time DSL
This is a place to invest. Author content as an **Elixir DSL using macros** (`defscene`, `defquest`, `defspecies`) that expands to validated structs at compile time. Benefits:
- **Compile-time validation:** a divert to a nonexistent scene, or a quest prerequisite referencing an unknown flag, becomes a *compile error*, not a runtime surprise — exactly the guardrail you want when an LLM is generating content.
- **Zero-cost loading:** content is compiled data, no runtime parse.
- **Hot reload in dev:** `mix`/`recompile` picks up changes; `Code.eval` or Phoenix-style code reloading works for iteration.

Pair the DSL with a **data-driven ingestion path** for LLM output: the LLM emits JSON → validated by an Ecto/`instructor` schema → codegen'd or loaded into the same struct shape the DSL produces. So hand-authored canon uses the ergonomic macro DSL; machine-authored drafts come in as data and get promoted to canon after human review. Both converge on one internal representation. NimbleParsec is available if you later want to accept an external text format (Ink/Yarn) but you don't need it for the DSL itself (macros operate on Elixir AST).

### E. Parser design — go hybrid
Full verb-noun IF parsers (Inform 7's `VERB NOUN PREPOSITION NOUN`, scope rules, disambiguation, "you can't see any such thing") are a lot of work and, in a TUI, a worse UX than what you can offer. Inform 7's durable ideas worth stealing conceptually are **rulebooks with ordered before/instead/after resolution and a most-specific-rule-wins ordering** — that's a clean mental model for command resolution and quest triggers, and you can implement a small version in the pure core (a list of rules tried in order, each returning `:handled | :continue`).

For input itself, a **hybrid: typed commands with autocomplete/suggestions** fits a TUI beautifully and is very achievable. Offer a menu/choice model for the character-creation and dialogue flows (species selection, backstory, crystal choice are naturally menu-driven), and a small typed-command grammar for exploration ("look", "take", "talk to yoda"). Use **NimbleParsec** (v1.4.x, actively maintained by Dashbit) for the command grammar (compile-time, fast, composable) with a synonym-normalization pass. Kalevala's `Command.Router` `parse(...)` DSL is a working example of exactly this scale of parser.

### F. Quest/mission modeling
Model quests as **explicit state machines with a dependency graph of prerequisites**, not a general rule engine. Each quest is a struct with states (`:unavailable → :available → :active → :complete/:failed`), a set of prerequisite predicates (functions of `GameState`), and completion triggers. Track completion as flags in the jsonb bag. A dependency graph lets you compute "what's now available" after each state change. This is simpler to reason about and to test deterministically than a forward-chaining rule engine, and it's what you want for reproducibility. This also maps cleanly onto quality-based narrative ideas (StoryNexus/Fallen London): quests gate on numeric/boolean "qualities" (Force sensitivity, alignment, reputation) held in the jsonb bag.

### G. LLM integration — the two roles, concretely
**Authoring pipeline (offline):**
- Define the content contract as Ecto schemas (`Scene`, `DialogueLine`, `Quest`) with `@llm_doc` descriptions and `validate_changeset` rules (e.g., "every `divert_to` must be an existing scene id"; "speaker must be in the known NPC roster").
- Generate with `instructor_ex`/`instructor_lite` using structured output + `max_retries` so validation failures are auto-corrected by the model.
- Human-in-the-loop: generated content lands in a "draft" state (a table or a `content/drafts/` dir); a reviewer promotes it to canon (into the DSL modules or a canon table). This keeps everything reproducible and canon-consistent.
- Canon consistency: keep a curated **lore pack** (species facts, timeline, Ilum/Gathering/kyber details) and inject it as context (a lightweight RAG or just a system prompt with the relevant facts) so generated lines stay in-universe.

**Runtime NPC dialogue (sprinkled):**
- Constrain the LLM to a **fixed action space**: it may only return a flavor *string* plus an optional choice from an enumerated set of engine-known intents. It cannot invent items, quests, or diverts — those come from the deterministic core. Validate the returned structure before display; on any violation, fall back to a hand-authored line.
- **Latency hiding:** show an "NPC is thinking…" state immediately, then a typewriter reveal as tokens stream into the inbox and drain via the interval-poll.
- **Caching/determinism:** memoize generated lines keyed by (npc, scene, player-state-hash); in test mode, use a deterministic stub adapter so the game is fully reproducible. This also controls cost.
- Client libs: `instructor_*` for structured calls, `ReqLLM` or `LangChain` for streaming chat; all use `Req`/`Finch` under the hood.

### H. Keeping the TUI as one of several frontends
Because the game core is pure and the Session GenServer exposes a transport-agnostic API (`send_command/2`, subscribe to updates via PubSub), the TUI is just one adapter. The same core can be driven by:
- **Ratatouille/ExRatatui TUI** (local).
- **Phoenix LiveView** (browser) — Raxol and `phoenix_ex_ratatui` even let you share the TEA module; or just render the projection in HEEx.
- **SSH:** Erlang's built-in `:ssh` daemon with a custom `ssh_cli`/`ssh_server_channel` gives you auth (keys/passwords), is reasonably NAT/firewall-friendly (one well-known port), and negotiates terminal size/resize and raw key input as part of the protocol. Garnish and ExRatatui both already serve TUIs this way; `esshd` is a helper. This is the most promising remote-play transport and is more secure out-of-the-box than raw TCP (`:ranch`), which you'd have to secure yourself. WebSockets to Phoenix is the other good option if the client is a browser.

### I. Multiplayer / co-op
The OTP-native version of drop-in/drop-out co-op: a **Campaign GenServer owns canonical shared state**; each player's Session is a connected client; commands flow to the Campaign (serialized by its mailbox → total order, no locks); results broadcast via `Phoenix.PubSub`. Session ownership/host-authority is natural (the Campaign *is* the authority; it can outlive any one player, or hand off). Guest state reconciliation on leave is trivial because the guest holds no authoritative state — it just unsubscribes. This is the ExVenture/Kalevala pattern scaled down. Because the game is turn-based and story-driven, you avoid the ordering/conflict problems real-time games face; the only concurrency concern (two players acting on one object) is resolved by the single-writer GenServer and, at the persistence layer, optimistic locking.

## Recommended architecture (umbrella layout)

```
star_saga_umbrella/
├── apps/
│   ├── saga_core/          # PURE. no processes, no IO.
│   │   ├── game_state.ex   #   structs: GameState, Character, Scene, Quest
│   │   ├── rules.ex        #   before/instead/after-style ordered resolution
│   │   ├── command.ex      #   command structs + resolve/2 -> {state, effects}
│   │   └── quests.ex       #   quest state machine + prereq graph
│   ├── saga_content/       # authored content: the DSL + compiled canon
│   │   ├── dsl.ex          #   defscene / defquest / defspecies macros
│   │   ├── scenes/         #   the Gathering, character creation, etc.
│   │   └── validation.ex   #   compile-time checks (diverts, refs)
│   ├── saga_engine/        # OTP layer (imperative shell)
│   │   ├── session.ex      #   GenServer per player; owns state; calls core
│   │   ├── campaign.ex     #   GenServer per co-op instance (shared state)
│   │   ├── registry.ex     #   Registry + DynamicSupervisor
│   │   └── inbox.ex        #   external-event inbox for TUI poll pattern
│   ├── saga_persistence/   # Ecto/Postgres
│   │   ├── repo.ex
│   │   ├── schemas/        #   accounts, characters, saves (+ jsonb)
│   │   └── snapshots.ex    #   Ecto.Multi transitions, optimistic lock
│   ├── saga_llm/           # LLM boundary
│   │   ├── authoring.ex    #   offline: instructor schemas + validation
│   │   ├── dialogue.ex     #   runtime: constrained NPC flavor + cache
│   │   └── lore.ex         #   canon context / RAG for consistency
│   └── saga_tui/           # frontend adapter (swappable)
│       ├── app.ex          #   Ratatouille.App: model/update/render
│       ├── views/          #   panels, ASCII-art blocks, dialogue box
│       └── art.ex          #   figlet banners, sprite blocks
```
Boundaries: `saga_tui`, `saga_llm`, and `saga_persistence` all depend on `saga_core` and `saga_engine`, never the reverse. `saga_core` depends on nothing. This is what keeps the TUI (and the LLM vendor, and even Postgres) swappable.

### ASCII art in the TUI
Use the **`figlet`** Elixir package for banner text ("STAR SAGA", chapter titles), and store multi-line art as heredoc string blocks rendered in Ratatouille `label`/`panel` elements with box-drawing panels. For a shimmering-crystal or hyperspace effect, drive a simple animation with `Subscription.interval` ticks that cycle frames. `bc_utils` offers themed banners if you want color themes. Keep art in `saga_tui/art.ex` so it's a pure presentational concern.

## Recommended build order (vertical slice first)
The intro sequence is a perfect vertical slice that exercises every layer. Build it in this order:

1. **Core + one scene, no processes, no TUI.** `GameState`, `Character`, and the character-creation → species → backstory → Gathering → crystal flow as pure functions with a scripted test that plays the whole intro. This proves the deterministic spine and is your regression harness forever.
2. **The content DSL** for those scenes, with compile-time validation. Rewrite step 1's scenes in `defscene`.
3. **Session GenServer + Registry/DynamicSupervisor** wrapping the core. Still no UI — drive it from `iex`.
4. **Persistence:** save/load the intro's result (species, backstory, crystal) via Ecto with the jsonb hybrid; snapshot on scene transition. Add the command-log table.
5. **Ratatouille TUI** rendering the projection, with the interval-poll inbox pattern wired up (even before LLM, use it for animations). ASCII art + figlet banners. This is the first playable build.
6. **LLM authoring pipeline** offline: generate one new side-conversation as JSON → validate → promote to canon. Proves the content-compiler workflow.
7. **Runtime NPC flavor** on Yoda: one constrained, cached, streamed flavor line with a hand-authored fallback. Proves latency hiding and guardrails.
8. **Co-op scaffold:** extract a Campaign GenServer + PubSub so a second player can observe/join. Evaluate migrating the shell to ExRatatui for its SSH transport at this point.

Each step is independently testable and leaves you with a working game.

## Hardest-to-reverse decisions (get these right now)
- **The core/shell boundary (pure core vs. OTP/IO shell).** If game logic leaks into GenServers or the TUI model, everything downstream (testing, multiplayer, alternate frontends) gets harder. Highest-value invariant.
- **Content representation (the DSL + internal struct shape).** Everything authored — by hand and by LLM — targets this. Changing it later means rewriting content. Design the scene/quest structs carefully.
- **Persistence model (relational + jsonb, snapshot cadence, command log).** Migrating a live save format is painful; decide the jsonb boundary and save-point strategy up front.
- **Identity/ID scheme** for scenes, quests, species, items (stable string ids). Diverts and save data reference these forever.

Cheap-to-reverse (don't over-invest now):
- **The TUI library** (Ratatouille ↔ ExRatatui ↔ Raxol) — it's an adapter behind the core.
- **The LLM vendor/client** (`instructor`/`ReqLLM`/`LangChain`) — behind the `saga_llm` boundary.
- **Parser sophistication** — start menu+simple-verb, deepen later.
- **Transport** (local TTY → SSH → WebSocket) — the core doesn't care.

## Named library recommendations (with status)
- **Ratatouille 0.5.1** (Mar 25, 2020, unmaintained) — fine for a local prototype; know its limits. Consider **ratatouille_ok 0.5.2** (Jun 28, 2025) only as a patched drop-in.
- **ExRatatui ~0.11.1** (2025, active, Rust/ratatui NIF, SSH + distribution transports) — best forward-looking choice, especially given SSH/co-op goals; young.
- **Raxol v2.x** (2025–26, active, multi-surface incl. LiveView/SSH/MCP) — powerful but heavy and partly pre-release; evaluate if you want one TEA module across terminal + browser.
- **Garnish ~0.2.0** — cleanest reference for TUI-over-SSH via `ssh_cli`; early.
- **Kalevala** / **ExVenture** — study for architecture (Foreman/Conn/Command.Router/Zone-Room PubSub); not a dependency you'd necessarily adopt, but the canonical Elixir text-game design.
- **instructor_ex** / **instructor_lite** — structured LLM output validated by Ecto; core of the authoring pipeline.
- **LangChain (Elixir) ~0.13** / **ReqLLM ~1.0** — runtime LLM clients with streaming; pick ReqLLM for lightness, LangChain for features.
- **NimbleParsec 1.4.x** (Dashbit, maintained) — the command grammar.
- **figlet** / **bc_utils** — ASCII banner/art helpers.
- **Ecto/Postgrex** — persistence (given).
- **Phoenix.PubSub** — event fan-out; **Horde**/**syn** — only when you go multi-node.
- **ecsx / ecspanse** — real ECS frameworks, but **not recommended** for a narrative text game.

## Star Wars IP note (brief)
Star Wars is owned by Lucasfilm/Disney and they actively enforce it. They have shut down fan games — *Galaxy in Turmoil* received a Lucasfilm letter on **June 22, 2016** demanding it "halt production… with any Star Wars related IP at once" (the studio, Frontwire, then pivoted to an original universe), a decision driven by EA's exclusive Star Wars license. Disney has also issued DMCA takedowns over trivial fan uses and pressured KOTOR-related mod/remake efforts. There is no formal fan-game license. Lucasfilm has tolerated *non-commercial* fan works that follow their (informal) rules — no crowdfunding, no ads, no monetization — but tolerance is discretionary, not a right, and "fair use/parody" is a legal defense, not permission. Practical guidance for an open-source project: keep it strictly non-commercial, don't ship copyrighted assets, make it easy to rename/reskin (which your species/lore-as-data design already enables), and be prepared to comply with a takedown. Consider designing the engine so the Star Wars canon lives entirely in the swappable `saga_content`/`saga_llm` lore layer, letting the core engine stand on its own as a generic, publishable IF engine.

## Caveats
- Ratatouille's external-event limitation and 500 ms default loop interval are established from its source and docs; the poll-the-inbox workaround is the idiom implied by the API, not a single blessed tutorial — validate the responsiveness for your streaming UX and lower `:interval` as needed.
- Version/status details for the fast-moving successors (ExRatatui, Raxol) are current as of retrieval in 2026 and are 0.x/early-2.x — verify latest before committing.
- The IP section flags obvious risk only; it is not legal advice, and enforcement posture can change.
- Raxol's marketed performance/feature claims come from the project's own materials; treat superlatives with appropriate skepticism until benchmarked for your use.