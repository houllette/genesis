# Actions, knowledge, consent and character growth

Accepted implementation contracts from the decision review, adapted to a
GM-first personal-use product. Read [experience time](experience-time.md) for
the distinction between durable in-experience outcomes and published world canon.
The rejected data-lifecycle proposal is not an implementation workstream.

## Flexible action, bounded authority

Players express goals freely within the GM's curated setting and declared
capabilities. Suggested choices are shortcuts. Blades separates goal/approach
from risk and effect and represents obstacles without prescribing a single
solution; borrow that interaction pattern, not its complete ruleset.
[Action rolls](https://bladesinthedark.com/action-roll),
[progress clocks](https://bladesinthedark.com/progress-clocks).

Free text goes through Lemieux to a typed proposal, never directly to a mutation.
Clarify missing targets/intent without spending game resources. Preview material
commitments, known costs and permitted risks; the controlling player confirms.
Do not expose hidden difficulties/witnesses or require another confirmation for
every look or explicit harmless command. Revalidate current experience revisions
before execution; changed costs/stakes require renewed confirmation. Fallback
structured commands work without inference.

Compound plans are bounded, independently resolved steps. A successful distraction
followed by failed theft remains those two outcomes. Retry cannot repeat the
distraction's cost or steal twice. An atomic exchange is still one transaction.
Other PCs authorize their own contributions; companions can refuse. No generic
`set_fact` tool, uploaded code or invented mechanic bridges an unsupported request.

Each compound step has stable parent-plan/step identity. Stop at the first
rejection and retain earlier accepted steps; phase 04 retries from receipts.
A resolved unsuccessful check may pay declared costs, whereas a validation
rejection consumes nothing. Proposals carry no speculative roll result and
reserve nothing; retain their full binding server-side until confirmation.
Offer a supported approximation or a scoped, audited GM adjudication. Reusable
mechanics require a reviewed ruleset extension and tests.

The GM curates tone, lore, scope, hooks, stakes and possible directions. They can
enter off-platform resolutions through validated commands and review deviations.
AI assists preparation and adjudication; it does not enforce a predetermined
ending by resurrecting NPCs, minting rewards or overwriting a player's decision.
Structured claims/source IDs ground significant narration; fluent prose alone
is not verification. Publish actual experience outcomes through incorporation.

## Minimal knowledge vocabulary

| Record | Meaning | Example |
| --- | --- | --- |
| Event | Accepted occurrence, with scope/status, causes and participants | Mara opens the granary during an experience |
| Fact | Engine-established current or time-bounded state | Grain stock is twelve |
| Observation | Information acquired by a particular eligible observer | A guard witnesses the opening |
| Belief | Attributed interpretation that can be false or uncertain | A merchant suspects the priest ordered it |
| Relationship | Directed typed connection with evidence | The merchant trusts Mara |
| Obligation | Parties, terms, due condition and resolution status | The village owes Mara shelter until winter |
| Memory | Sourced episode or explicitly derived recollection | The guard recalls the rescue during a later famine |

Use stable scoped IDs, versions, provenance and visibility conventions. Distinguish
fictional occurrence, server recording/commit order and observer learning time.
Experience-local facts and published facts are labelled; publication maps sources
without granting every NPC knowledge of them. Reflection is interpretation, not
automatic fact promotion. A rumor can be false without creating another canon.

Borrow provenance and temporal distinctions without adopting RDF, a graph database
or a complete bitemporal framework. Start with typed Elixir values, indexed
relational ownership and validated ruleset-specific jsonb.
[W3C PROV primer](https://www.w3.org/TR/prov-primer/),
[Bitemporal History](https://martinfowler.com/articles/bitemporal-history.html).

Filter by actor knowledge and intended audience before retrieval, then rank by
relevance, causal importance, relationships and mention cooldown. Memories from
another experience's unincorporated future cannot enter a prompt. Persistent
consequences outlive working-context compaction and infrequent mentions.

## Cooperative defaults and GM control

World policy sets content and exceptional-risk boundaries; campaign/experience
agreements may tighten them. Default to no nonconsensual PC attacks/theft, forced
control or permadeath. Exceptional consent is scoped to participants, risk and
policy version, never inferred from a party vote or a GM login.

Provide a short session-zero agreement and pause/report control in both play
hosts. Pausing stops new scene actions/output and configured decision deadlines.
It does not require explaining private personal reasons. Revocation prevents
new exceptional actions; repairing existing fiction is an explicit GM process.
[Consent in Gaming](https://www.montecookgames.com/consent-in-gaming/),
[TTRPG Safety Toolkit](https://ttrpgsafetytoolkit.com/).

Use GM-declared risk tiers for shared NPCs, property and world-defining assets.
Ordinary NPC losses may stand and reshape stories; not every NPC needs universal
campaign approval to die. Protected holdings and major structural damage require
the agreed authority. Check indirect resource attacks where impact is knowable;
ambiguous abuse needs GM judgment, not a claim of perfect automated intent detection.
AI obeys the same rules. Fictional warrants/restitution are gameplay, not substitutes
for restricting a disruptive participant. Keep this appropriate to an invited
personal table, not a public-platform moderation product.

## Progression, failure and retirement

Advancement is ruleset data plus reviewed pure resolution. The two original
starter bundles favor goal/milestone awards and social/world progress: capabilities,
relationships, titles, access, projects and obligations. Do not hardcode universal
kill XP. Awards have unique identities, party/individual eligibility and published
source events; no farming through retries or multiple campaigns. Experience-local
awards are usable only there until incorporation validates their canonical transfer.

Failure can mean injury, loss, debt, retreat or a permanently missed opportunity;
it need not funnel back to the same reward. Default PC defeat is nonlethal, with
permadeath opt-in before the risk. Supported revival has actual rules/costs.
Fate provides useful examples of story-linked advancement and meaningful concession,
not a requirement for every Genesis bundle.
[Advancement](https://fate-srd.com/fate-core/advancement-change),
[concession](https://fate-srd.com/fate-core/conceding-conflict).

Retirement preserves accomplishments and relationships. Offstage retirement is
the default; autonomous NPC portrayal requires the player's explicit agreement.
A successor gains only explicitly transferred assets/rights, never a cloned
inventory or automatically inherited private memories. The same milestone cannot
be claimed twice because an experience was reopened or a narrative ended twice.

## Required evidence

From 01–04 test typed facts/beliefs, exact contextual changes, clarification versus
mutation, confirmation revisions, compound partial success, private knowledge and
durable provisional outcomes. Phase 02 defines milestone/defeat data; 06 exercises
confirmed commerce and institutional obligations; 09 implements flexible authored
actions and group decisions; 10 supplies the Lemieux interpretation boundary.
Phases 11–13 prove both player hosts, refusal, consent, progression and persona
memory against those same contracts. Phase 15 adds advanced adjudication, not the
first GM authority. Each owning phase records runnable tests in its handoff.
