# Evidence for a useful GM tool and a memorable world

Accepted quality and early-pilot decisions. These are acceptance methods, not
claims that experiments have run. Technical correctness and enjoyable/useful
experiences need different evidence. Preserve TDD and the functional core.

## First prove Ashfall, then scale it

Phase 05 makes a native GM workbench useful before a player joins: create a
world/campaign, curate people/places/notes, declare an experience and save/resume.
Phase 09 supplies reviewed beats, duration rules, dependency diagnostics and
player-context preview. Phase 10 proves the Lemieux host with its actual Scripted
provider before AI-assisted drafting; dependency approval and live evidence stay
explicit. Phase 11 proves the same small player TUI on real SSH and browser
hosts before adding elaborate gameplay screens.

Phase 12 is the first integrated **living-village pilot**: one village, two NPCs,
one companion, a grain shortage and a religious institution or secular relief
guild. A GM curates the situation, a player makes an unscripted choice, and one
thin Lemieux NPC interaction changes a real offer. Include a small encounter,
provider-free fallback, pause across gatherings, completion, incorporation and
later discovery by another campaign. Use sourced simple memory/callbacks here;
full vector retrieval and all-NPC lifecycle follow in 13. The 2,000-year scale
gate comes in 14, after the pilot, not before the first useful GM/player loop.

The GM must be able to understand what changed, approve the elapsed time and
inspect the resulting people, resources, obligations and next opportunities.
Measure preparation friction and reconciliation clarity, not only player action
latency. Reuse the same fixtures throughout; avoid a disposable parallel engine.

## Four evidence layers

1. **Engine invariants:** exact TDD tests for authority, quantities, knowledge,
   duration, scope claims, deduplication, world publication atomicity and recovery.
   Test generated bounded action sequences against the pure model using supplied
   seeds/IDs/draws; a property-testing dependency needs separate approval.
2. **Simulation behavior:** versioned profiles, development and held-out seeds,
   invalid-state counts, resource bounds, event diversity, wealth/power concentration,
   institutional collapse and available opportunities. A ruined-world profile may
   seek collapse; a prosperous one should not accidentally produce the same famine
   every time. Record declared sources/sinks, not imaginary universal conservation.
   Test chunk equivalence at the same level of detail; declare coarse-generation
   approximations instead of promising every micro-action is identical.
3. **NPC quality:** separately assess observation extraction, belief updates,
   retrieval, persona consistency/refusal, grounded dialogue and repetition. A
   witnessed deed may be remembered; an unknown secret may not. A companion must
   change an actual option, not merely a greeting. Validate experience/window scope
   before memory retrieval and again before committing a late model response.
4. **Human usefulness:** run the primary GM create → curate → preview → host →
   pause/resume → incorporate → inspect consequences journey, then solo discovery,
   remote party and async story journeys. Test both play hosts and accessible
   input/reading. Can the GM prepare without developer help? Can players explain
   one consequence and identify a meaningful next choice? Can the GM explain why
   an overlapping run is waiting without reading an event log?

Procedural-content evaluation distinguishes output range from player impact;
generated years alone demonstrate neither. Generative Agents motivates sourced
memory/planning/reflection in a small sandbox, not Genesis-scale performance.
HaluMem separately examines memory extraction, updating and answering errors.
These sources motivate the tests; their results are not our product evidence.
[Evaluating content generators](https://www.pcgbook.com/chapter12.pdf),
[Generative Agents](https://arxiv.org/abs/2304.03442),
[HaluMem](https://arxiv.org/abs/2511.03506).

## Gates and handoffs

At phase 12 require zero observed authority/visibility failures in the committed
corpus, the complete GM journey without developer intervention, and a player who
can identify the choice's concrete consequence after incorporation. Record written
human NPC/coherence review and failures, not only an attractive transcript.
Scripted tests run without paid credentials; actual provider behavior needs an
authorized capped trial with model, upstream revision, prompt versions, eligible
source IDs, sample size, latency and cost. No live evidence can be manufactured
from fixtures. Automated model grading, if used, goes through Lemieux and is not
the sole authority for knowledge safety or enjoyment.

Before a measured pilot/scale run, record hardware, fixtures, numeric latency/
spend/repetition thresholds and reviewer criteria. Distinguish observations from
universal guarantees. Repeat held-out scenarios after tuning; do not report only
the best seeds. Later phases validate the pilot's exact tests and observations
before expanding it. Release targets a GM and a small invited table, not dozens
of concurrent public campaigns; larger stress runs are optional measurements.
