# GM-first product, personas and world workspace

The latest user clarification is the product priority: Genesis should be an
exceptional personal GM world-building and curation tool that also supports
interactive experiences. It is not principally a multiplayer game service.
Native browser management is primary; [shared TUI play](tui-first-play.md) is the
secondary player surface. All capabilities below are planned, not implemented.

## Design inspiration

Borrow Foundry's separation of users, actors, items, scenes and encounters for
running a table, and Kanka's navigable people/places/organisations, relationships,
notes and timeline for building a setting. Do not require battlemap graphics or
feature/import compatibility.
[Foundry GM tutorial](https://foundryvtt.com/article/tutorial-two/),
[actors](https://foundryvtt.com/article/actors/),
[Kanka overview](https://docs.kanka.io/en/latest/overview.html).

Genesis distinguishes a persistent world from its several campaigns, unlike
using “campaign” interchangeably for both. The GM can curate a world without any
active play. AI drafts remain editable proposals; authored constraints guide
situations without automatically establishing their outcomes.

## Domain hierarchy

```text
World: published setting, ruleset/profile, calendar, canon and GM stewardship
├── People, places, institutions, resources, lore, relationships and history
├── Campaigns: rosters, objectives, notes and adventure organisation
│   └── Experiences: durable adventures, optionally driven by a StoryRun
│       └── PlaySessions: any number of real-world gatherings
├── Open advancement window: common checkpoint + admitted experiences
│   └── Scoped working states, claims, completion manifests and impact preview
└── Explicit rehearsal: non-canon preview, never an automatic reward source
```

- World owns published truth and calendar. Campaign identity is membership/
  organisation, not a separate copy of world canon.
- Experience owns durable progress, local elapsed time and provisional outcomes.
  Its scoped Zone owns actual mutation; the Experience orchestrator is not a
  competing writer. One character/companion has one active experience assignment.
- PlaySession is a meeting record, not the adventure's lifetime. Engine Session
  is a client attachment; Lemieux.Session is an inference loop.
- StoryDefinition is a pinned opportunity structure; StoryRun tracks it within
  an Experience. A live GM can instead run an unstructured experience and enter
  validated off-platform outcomes. Closing a meeting does not publish either.
- An advancement window coordinates independent adventures based on the same
  world checkpoint. The [time contract](experience-time.md) defines claims,
  completion, collision review and atomic incorporation into shared history.
- A rehearsal is explicitly non-canon. It may use the same scoped machinery,
  but cannot be mistaken for an ordinary experience awaiting incorporation.

A world pins one ruleset and profile version; its campaigns are compatible with
them. Fantasy and cyberpunk demonstrate separate worlds on one engine. One party
per campaign is sufficient initially. Archiving a campaign does not erase its
published consequences or silently discard an unfinished experience.

## Persona priorities and complete journeys

| Priority/persona | Journey | First useful delivery |
| --- | --- | --- |
| Primary: GM/world builder | Create world → connect people/places/institutions → write notes → curate hooks → preview context and dependencies | 05–07, 09–10 |
| Primary: GM running a table | Prepare experience → run/adjudicate → pause across gatherings → complete with duration → review impacts → incorporate | 05, 08–12; advanced controls 15 |
| Primary: async story curator | Publish bounded opportunities/duration rules → log off → players resolve → review ready outcomes and next story possibilities | 09–10, 12 |
| Supporting: solo player | Accept invite → choose character → discover/play → pause/finish → see incorporation status → discover later consequences | 11–13 |
| Supporting: remote party | Join common experience → external call → act together → save gathering → return to the same fictional moment | 11–12 |
| Supporting: async party | Submit choices → see waiting reason → resume under the authored policy → narrative completion | 09, 11–12 |
| Occasional: co-GM/steward | Delegate bounded control → inspect dependencies/claims → resolve overlap → approve shared history | 05, 08–10, 15 |

Voice/video remains external. Meeting links are displayed safely, never fetched,
joined, transcribed or recorded by Genesis. Spoken outcomes enter game state only
through explicit authorized commands. No Discord bot or meeting integration is
a prerequisite.

## Native GM workbench

The default signed-in destination is the world/campaign workspace, not Play.
Organise it around the GM's tasks: World library, Atlas/People, Campaigns,
Experiences, Stories, and Review/History. The selected world and Published versus
Working status must remain visible. Keep the next useful action obvious.

Phase 05 delivers manual creation/editing, notes, rosters, experience start/pause/
resume and a minimal pending-outcome view. Phase 07 adds linked hierarchy,
relationships, search/backlinks and companions. Phase 08 makes completion/time/
incorporation review operational. Phase 09 adds beat authoring, duration policy,
broken-dependency diagnostics and character/companion preview. Phase 10 adds AI
drafting through the same forms and review queues. Advanced controls in 15 extend
this workspace; they are not when the GM first receives a useful product.

Canonical edits use World/Zone commands. During an open window, ordinary saves
create drafts; changing its base is a deliberate gated amendment, not a second
writer. Clearly distinguish an NPC prototype, an instantiated person, an
experience-local change, a proposed future beat, a belief and a published fact.

Controls show concrete consequences before technical details: affected NPCs,
resource changes, elapsed days, waiting adventures and invalidated hooks. A GM
should not need to read raw JSON, operate a terminal or act as a fake player to
build a world. Reuse linked typed records and progressive forms; defer a universal
schema designer and graphical VTT.

## Interactive surface remains unified

Player navigation, sheets, actions, commerce, conversations, journal and gathering
flows share one TUI on SSH and the browser Play tab. Native GM editing/search/
timeline/AI review has no requirement for full TUI parity. A small set of live
GM terminal commands may complement it. Personal use does not waive state-level
knowledge isolation, role checks or bounded provider spending.

## Required Ashfall demonstration

A GM creates the village, bridge, grain market, relief institution and two NPCs;
curates a negotiable dispute; previews an ordinary visitor, a prior rescuer and
an allied/hostile companion. The same facts change actual approaches and costs.
The GM can do this before inviting players.

The Dock Crew's three-day experience takes three weekly gatherings. An independent
courier finishes a two-hour errand while it is paused. The published world does
not advance between gatherings; scope claims stop the courier duplicating the
crew's NPC/item. After completion, the GM sees the actual choices and a three-day
target, incorporates once and inspects changed stock, bridge and relationships.
A later campaign discovers a permitted legacy without receiving the crew's secrets.
A reconstruction changes current state while the original deed remains history.

Repeat with religious/currency and secular/barter presets. Include GM-authored
async completion, failure/abandonment after a real expenditure, one NPC refusal,
restart and duplicate confirmation. Use the [quality contract](experience-quality.md)
to assess GM effort and narrative clarity, not just screen availability.
