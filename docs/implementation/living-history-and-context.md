# Contextual simulation and living history

This is a foundational product contract, beginning in phase 01. It incorporates
the user's character/companion and Dwarf Fortress requirements, including the
clarification that history keeps developing during play. Pre-play world generation
is one use of the simulation; player-caused history is an equally important use.

The GM-first [experience-time contract](experience-time.md) controls scheduling:
working outcomes persist during an adventure, while the published world waits for
completion/incorporation. Approved fictional time, not real-world absence, drives
continuing history. The small living pilot is in 12; long generation follows in 14.

## Inspiration and scope

Dwarf Fortress connects generated civilizations/history with a persistent world
that can be revisited across games. That continuity, including recruiting people
and encountering prior characters, is the relevant inspiration. See
[Bay 12's feature description](https://bay12games.com/dwarves/features.html).
Bay 12's July 7, 2014 development entry explicitly describes bringing processes
such as succession, invasions and site creation from generation into ongoing
play. This is historical design evidence, not a claim of current feature parity.
See the [world activation development log](https://www.bay12games.com/dwarves/dev_2014.html).

Genesis's interpretation: one connected world model explains both how things
became this way and how players change what happens next. A destroyed bridge
changes travel and supply; those changes affect factions, residents and stories.
The alpha proves a small connected set of mechanics. Thousands of years and
larger populations are configurable, measured workloads, not a claim that every
Dwarf Fortress subsystem is already planned or computationally free.
The [world-subsystem matrix](world-subsystems.md) makes the first economy,
commerce, religion/institutions and supporting mechanics explicit. Their local
forms arrive in phase 06 and evolve through the same causal laws in 07–08 and 14.

## Context changes situations, not just their wording

`ResolutionContext` is a proposed pure value assembled from authoritative state:

- Character's validated origins, abilities, conditions, affiliations and deeds.
- Prior choices, promises, crimes, rescues, debts and event-backed relationships.
- Actual present companions: identity, capabilities, loyalties, condition, knowledge
  and relationship to the people involved, not just a party-size modifier.
- Local conditions, available resources, routes, season/time, institutions and law.
- Relevant world/campaign history and currently unresolved consequences.
- Versioned rules, content, world policy and the revisions of consulted facts.

Use a small typed fact vocabulary with source IDs, scope and validity periods;
do not scan every historical event or feed the whole chronicle into a prompt.
Materialized facts accelerate lookup but retain provenance and one authoritative
owner. Character backstory supplied by a player is a proposal: claiming to be
the king's heir does not grant a title, property or invented historical deeds.
Bind approved backgrounds to real world people/places without rewriting history.

Keep authoritative resolution facts separate from actor-visible explanation and
LLM context. An observer can react to what they know/recognize; the whole world
does not instantly know a hidden crime or a companion's secret identity.
Filter before model retrieval. Client text cannot supply trusted context.

At beat/event activation, resolve eligible participants, stakes, approaches,
rewards/costs, opposition, obligations and follow-ups using that context. Small
variation might be a greeting or discount; large variation might replace an
escort with a trial or bypass a confrontation entirely. Variant composition has
declared precedence, compatibility and bounded tie-breaking, not arrival-order
accidents or arbitrary model decisions. Record the selected bindings/reasons,
inputs/draws and source versions. Before commitment, revalidate changed facts;
after commitment, persist the outcome instead of rerolling it when a page opens.

Curated beats retain the GM's stated constraints, but adapt around actual state.
If incompatible, explicitly bypass/invalidate/review them; never reset reality
to force a beat. The same context machinery applies to spontaneous events,
encounters, schedules and NPC plans—not only quests with a StoryRun.

## Companions are world actors

Recruit/dismiss/agree-to-follow are validated intents with durable relationships,
commitments and a single active party assignment. A companion remains the same
NPC in the world, with its own inventory, location, goals and limits. Recruitment
does not grant ownership of its mind or unrestricted player control. Start with
deterministic willingness and turn behavior; Lemieux deliberation adds nuance
through the same bounded capabilities in phase 13.

Test recruitment races across campaigns, refusal, separation, death, dismissal,
party travel and interrupted follow actions. An absent/dead companion cannot
contribute skills, act as a witness or open a route. A party cannot duplicate an
NPC to gain extra turns/resources. Witnessing, recognition and relationship
changes persist after departure, even when the companion becomes dormant data.

## One causal model before and after players arrive

```text
World recipe / initial conditions
  → historical simulation → launch checkpoint
  → scoped player + NPC actions → durable ExperienceEvents
  → completion + explicit elapsed time + reviewed incorporation → WorldEvents
  → approved-time consequences + evolving institutions/relationships
  → relevant future situations and occasional remembered references
  → further actions in the SAME continuing history
```

Generation and live play reuse pure transition laws, semantic event types,
fact ownership and consequence rules. They differ in scheduling and detail:
pre-play epochs advance in batches; active authorities serialize scoped commands,
then incorporation reconciles their consequences at approved fictional times. There must not
be a historical simulator whose
consequences stop working once the first campaign opens.

Events carry causal parent/root IDs, affected entities/places/groups, initiator
and participants, before/after facts, logical dates, versions, and observation/
disclosure provenance. Local invariants commit atomically with the experience action. Published world
changes require incorporation. Delayed consequences are durable, idempotent work
that rechecks scope/current state and runs only to an approved target.
Group a siege into a source-linked episode for navigation, without replacing
its underlying events or recording a summary as a second siege.

Off-screen simulation uses aggregates and bounded due work. Materializing a
named resident from a population must reconcile counts, lineage and dates;
it cannot invent a contradictory past. A historical person may be dead but
still have descendants, property claims and surviving artifacts. Keep tombstones
and source links. Reconstructing history never calls a provider or reruns actions.

## Lasting consequences and selective remembrance

A major player-caused event has several possible durable footprints:

| Layer | Example after players end a siege | Persistence and later use |
| --- | --- | --- |
| Physical/economic | Damaged gate, rerouted supplies, rebuilding costs | Route/resource/settlement state affects future actions until changed again |
| Political/social | New ruler, treaty, displaced residents, a debt | Institutions, membership and relationship state affect eligibility and agendas |
| Personal | A rescued child, a grieving guard, companion loyalty | Per-NPC witnessed/reported memories; not universal knowledge |
| Cultural | A named battle, memorial or annual observance | Explicit in-world creation/adoption events; later calendar/place/story references |
| Historical | Who acted, who suffered, what changed and why | Append-only chronicle with participant attribution and causal links |

These are consequences to implement as supported rules/policies, not effects
that every siege automatically receives. Memorials, titles and folklore must
be created through validated world actions; narration cannot invent them into
existence. A GM may authorize new traditions; bounded NPC/world policies may
also propose or adopt them within delegated powers.

Separate enduring state from mention frequency. A ruined gate does not repair
itself because its event becomes less salient. A reconstruction action changes
its current state, while the destruction remains history. Distinguish persistent,
expiring and explicitly reversible consequences; only declared rules expire them.
Player impact survives logout, campaign closure, NPC demotion and server restart.

Bound query windows, inboxes and working memory, not the existence of canonical
deeds. Pagination or archival must retain stable source links and authorized
retrieval of significant old events; transcript compaction cannot delete the
world facts or legacies those events established.

For occasional callbacks, use a deterministic, bounded relevance policy over
eligible facts: participant connection, location, unresolved consequences,
anniversary, importance, recency and a per-recipient mention cooldown. Record
which sources were referenced. Major deeds remain retrievable after ordinary
scrollback or NPC working memory ages out; relevance must not be recency-only.
Not every conversation should retell the player's greatest victory. A callback
is a presentation event, not re-execution of the original consequence.

Rumors have an origin, transmission path, claim/uncertainty and audience. What
an NPC believes can differ from canon; do not silently rewrite truth or award
omniscient reputation. An approved disclosure creates a new audience-scoped
record, not broader access to a private original. Lemieux can narrate eligible
material or propose reactions, but cannot choose to erase history or expand
its own knowledge. Use authored references when inference is unavailable.

## Extensible connected mechanics

Each new mechanic declares its reads, owned writes, emitted/consumed event
types, timing and conservation rules. Reuse existing authority/transactions;
do not build an unbounded event bus where every handler may mutate everything.
The initial connected slice is routes/infrastructure → supplies/production →
commerce → religious/secular institutions and faction pressure → NPC
commitments/relationships → contextual opportunities, with
knowledge/disclosure controlling what each actor understands about the chain.

`WorldProfile` is proposed versioned data separate from a ruleset: generation
seed/era, geography and society parameters, enabled simulation modules,
consequence intensities, pacing, content boundaries and automation budgets.
Worlds pin profile/module versions; campaign overrides may narrow policy only.
Safe declarative variants, traits, relationships and templates enable breadth;
new mechanics needing code use reviewed Elixir modules, never uploaded code.
Validate missing dependencies, contradictory overrides and removed mechanics.
Changing a profile does not reinterpret old canon; migrations are explicit.

Avoid implementing a framework before a second mechanic needs the seam. To
accept a new mechanic, require a meaningful test of interaction with an existing
one, persistence/recovery and an actor-visible consequence. “Customizable” must
mean tested configuration/composition, not hardcoded per-character story branches.

## Required evidence

- From phase 01: identical situation/action with different validated character,
  prior-choice or companion context can produce different exact results; irrelevant
  or unknown/forged facts cannot arbitrarily alter it.
- From phase 07: a recruited companion is the same conserved world actor, and
  departure removes only their current participation, not past relationships.
- From phases 08 and 14: the same connected laws work before and after world launch;
  a player-caused disruption persists and propagates through approved fictional
  time, including when nobody is connected to compute an authorized candidate.
- From phases 09–13: contextual variant selection changes mechanics and whole
  beat direction, and relevant old deeds occasionally resurface with source
  attribution, appropriate knowledge and repeat suppression.
- At release: return after time passes and a restart, then start another campaign.
  The changed place, relationship/institution and a permitted historical callback
  all derive from the original player event. A later repair updates current state
  without erasing the deed. Test this without a live provider as well.
