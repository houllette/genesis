# Generic-world MVP subsystems and extension contracts

The MVP needs a small connected world, not only a narrative/encounter engine.
This contract adds economies, commerce and religion explicitly, alongside the
other basic systems that let places and institutions respond to player actions.
It builds on [living history/context](living-history-and-context.md), uses the
same scoped single-writer model. This page defines delivery targets, not a claim
that every subsystem exists; the [phase-06 handoff](06-world-subsystems/handoff.md)
records the implemented local mechanics and their remaining qualification gates.

The native GM workbench configures and inspects these mechanics first. Player TUI
controls follow in 11. During play, mutations belong to an Experience; only its
validated incorporation changes published world state. [Experience time](experience-time.md)
replaces real-time simulation: pauses do not consume stock or advance observances.

[Tempo/time domains](tempo-and-time.md) supplies the shared calendar foundation
in 08: supported market/observance windows, seasonal conditions and production/
travel spans use bounded interval operations with explicit fictional targets.
Subsystems do not invent separate clocks, convert fictional dates to Oban cron,
or infer Earth seasons for an arbitrary world. Temporal availability never
overrides claimed ownership or stock/resource validation.

## What a foundation or stub means

Distinguish three levels in content manifests, UI and handoffs:

- **Playable foundation:** a small real mechanic with state, validated intents,
  consequences, persistence and meaningful tests. Phase 06 must deliver this
  for local economies, commerce and religious/secular institutions.
- **Record-only foundation:** useful typed records/relationships that can be
  inspected and referenced, without claiming an autonomous simulator exists.
  Unsupported actions explicitly return an unavailable/unsupported result.
- **Deferred extension:** a documented contract and example future interaction,
  not empty GenServers, fake-success tools or a table of unused nullable fields.

Support may progress between levels. Each handoff records the actual level and
versions per mechanic. Disabled is distinct from broken or record-only. A world
can be non-monetary, secular or without supernatural mechanics; generic support
does not require enabling every subsystem in every setting.

## MVP coverage and boundaries

The table is the target coverage map. Consult phase handoffs for current support:
01–05 supply the core/persistence/workbench and 06 adds bounded local mechanics;
later scheduled, cross-zone and historical behavior remains deferred. The named
phases own these minimums; detailed simulation is not an implicit extra gate.

| Subsystem | Smallest useful MVP behavior/data | Delivery | Explicit later expansion |
| --- | --- | --- | --- |
| Economy and scarcity | Owned stockpiles, integer-denominated balances, bounded supply bands, declared production/consumption with source/sink receipts | 06 local explicit actions; 08 scheduled; 14 linked regional consequences | Banking, credit, currency exchange, macroeconomic equilibrium, automated labor markets |
| Commerce and exchange | Buy/sell and simple barter; versioned quote, capacity/stock/funds/access checks, atomic settlement, receipts | 06; 07 cross-zone ownership/trade links | Auctions, order books, complex contracts, merchant strategy and shipping markets |
| Religion and belief | Traditions, optional deities as lore claims, institutions/sites, voluntary affiliations, offerings and one observance/obligation affecting permitted aid/access | 06 local; 07 linked world identity; 08 calendar; 14 continuing institutional history | Theology generators, schisms, religious wars, detailed ritual systems; miracles require a ruleset mechanic |
| Institutions, governance and law | Organisation roles, local jurisdiction, one explicit access rule and a witnessed/reported violation or obligation; scoped standing and due process policy | 06 local; 07 World ownership; 08 delayed enforcement | Elections, courts, tax simulation, elaborate diplomacy and territorial wars |
| Resources, production and crafting | One versioned conversion recipe: available inputs → outputs/waste; capacity and explicit time/cost, with provenance and conservation | 06 manual bounded action; 08 durable timed work | Crafting trees, tool wear, factories, skill specialization and settlement construction |
| Geography, infrastructure and logistics | Connected places/routes, access/capacity/condition; damaged route changes delivery availability; no item teleportation | 07 travel; 08/14 supply propagation | Grid geography, vehicles, pathfinding optimization and detailed transport networks |
| Population, kinship and culture | Typed settlements/culture/language/kinship records and NPC affiliations; bounded demographics/lineage/succession in history | 07 records; 14 bounded transitions | Household labor, comprehensive migration, language generation and ethnographic simulation |
| Environment, seasons and hazards | Versioned seasonal condition/resource modifier and one bounded environmental disruption connected to supply or travel | 08 condition/due work; 14 connected history | Weather physics, ecology/food webs, geology, disease simulation and terrain erosion |
| Knowledge, reputation and communication | Witnessed/reported facts, uncertain claims, institution-specific standing, authorized chronicle and occasional callbacks | 01/04 facts; 06 institutional reactions; 14 remembrance; 13 NPC agents | Messenger networks, newspapers, detailed rumor diffusion and competing historiography |
| Survival and recovery | Ruleset-declared conditions/resources plus one supply-consuming rest/recovery action; no universal hunger or health formula | 02 vocabulary; 06 local action; 12 encounter integration | Nutrition, injury/medicine models, aging penalties and complex downtime |
| Magic, technology and research | Named, versioned capabilities, artifacts and prerequisites that only do what the selected ruleset implements; unsupported actions fail explicitly | 02 bundle contracts; 07 atlas references; 12 one supported resource action | Spell research, tech trees, hacking, divine intervention and automated invention |

Currency here is fictional game state, not a payment integration. Religious
belief, affiliation, reported miracles and engine-established supernatural facts
are distinct. Do not require a pantheon, assign beliefs from player demographics,
or have a model silently change a PC's convictions. A secular mutual-aid guild
can exercise the same institution/offerings/obligations contracts without a god.

## Economy is not the shop screen

Economy tracks resources, availability and declared flows. Commerce is the
transaction protocol by which actors exchange them. Reuse inventory identity
and ownership; a shop listing or treasury view is not a second balance store.
Start with one configured settlement unit and bounded stock-based price bands,
or barter where money is disabled. Use integer minor units and quantities,
explicit rounding and bundle policies; never floats or model-guessed totals.

A quote binds items/quantities, counterparties, unit, price-policy version,
inventory/balance revisions and expiry to a proposed exchange. Revalidate it
before atomic settlement; the player confirms any changed price. Expiry uses
the supplied experience cursor or approved world target, never a hidden wall-clock
read in the pure core. Pausing play does not expire a fictional quote.
Concurrent buyers, repeated requests and crash recovery cannot buy the last
item twice or charge without delivery. A rejection consumes nothing.

Transfers preserve quantities and balances. Production, consumption, authorized
currency issuance or destruction are explicit source/sink events; recipes
declare units, conversion/waste and capacity rather than pretending different
resources are identical. Start with finite fixtures and manual lawful actions
in 06. Scheduled production/consumption arrives in 08, cross-zone operations
in 07, and historical/regional evolution in 14. No per-market price timer or
per-merchant process is required. Quotes cannot reserve stock indefinitely.

## Religion, institutions and agency

Traditions define teachings/observances as versioned content; a live institution
owns membership, relationships, obligations and resources within its authority.
Religious sites and relics reference existing places/items. Offering a ration
actually transfers it to an owned store; it does not merely add a journal line.
A supported affiliation or fulfilled obligation can unlock shelter, alter an
NPC's willingness to help or affect a local dispute through ResolutionContext.

The engine records observable actions; opinions and rumors have an audience and
source. Theft does not create instant world-wide infamy. Institutional access
policy is not a player authorization role: joining a temple never grants GM or
world-steward rights. Covert affiliations remain private until a valid reveal.
Donation cannot forge membership, force affection or reroll an NPC's identity.
Lemieux may later suggest approved actions or dialogue within these contracts;
it cannot mint goods, invent gods into canon or bypass transaction authority.

## Ownership and safe extension

Each supported mechanic declares a version, required capabilities, typed reads,
owned writes, intents/events, visibility, timing and conservation invariants.
Use plain data and pure functions with the existing Engine/Persistence seams;
introduce a behaviour only where two real implementations need it. Do not add
a universal plugin runtime, dynamic atom names or uploaded executable rules.

Phase 06 is deliberately one-zone: local inventories, institutions and policies
have that Zone as owner. World-wide definitions are pinned content, not an
unimplemented second writer. Phase 07 explicitly establishes global institution
identity, standings and cross-zone transfer ownership while preserving IDs,
receipts and history; document any migration and reject unsupported transfers
until the coordination protocol exists.

WorldProfile declares supported/enabled/record-only capabilities and versions;
campaign overrides cannot broaden world policy. Content requiring an absent
mechanic fails validation or uses an explicitly authored alternative, never
silent success. Minimal pins/capability checks start in 02/06; 14 expands these
into generation parameters without replacing the manifest. Disabling a live
mechanic with balances, affiliations or pending work requires an explicit
migration/settlement policy, not deleting those records or reinterpreting canon.

In the phase-06 implementation this contract is split explicitly: the immutable
ruleset bundle declares the supported capability manifest and local rules;
`Systems.WorldProfile` supplies a versioned society preset pinned inside the
Zone's settlement. The existing world's descriptive `profile` metadata is not
mechanical authority. Campaigns cannot override either rules or the settlement
preset. Phase 07 may promote shared definitions to World ownership only with an
explicit identity/pin migration; do not start reading an unversioned metadata
label as policy.

## Connected acceptance journey

Grow Ashfall's existing bridge story instead of inventing a parallel demo:

1. A lawful disruption or player deed changes available grain. A bounded recipe
   converts remaining grain to rations with declared costs; rest consumes a ration.
2. Reduced stock changes the next quote under a deterministic policy. A player
   buys or barters; money and items settle once, including after retry/restart.
3. The player offers supplies to a religious institution or secular relief guild.
   Inventory changes, a sourced obligation/standing changes, and aid/access or
   an NPC's later response differs. An unrelated or unaware NPC does not react.
4. From 07–08 and 14, damaged routes and seasonal conditions affect supply, institutions
   schedule bounded relief/observances, and other campaigns inherit the changed
   world after incorporation. Restoration creates new history. From 09–13, those facts influence
   beats and NPC choices; AI remains optional for the underlying mechanics.

Deliver the single-zone explicit-action form in 06 and extend it only when each
later phase's authority/time contracts exist. Phase 06 uses native GM controls
and engine tests; from 11, browser-hosted and SSH TUI use the same player shop/
offer/inspect/decline flow and source-linked history views.
Record exact outcome, privacy, conservation, disabled-capability and recovery
tests—not just successful rendering of an Economy or Religion tab.
