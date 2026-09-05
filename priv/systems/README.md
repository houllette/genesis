# Original demo rules — format 1, bundle version 1

These are small original games, not implementations of licensed fantasy or
cyberpunk rulebooks. Both use `Genesis.Systems.Declarative` and the same Scene
reducer. Load with `Genesis.Systems.load("fantasy_demo")` or `"cyberpunk_demo"`.
Fixed JSON assets are embedded using tracked build resources: editing them
recompiles the loader, and decoding/validation still happen at runtime.
There is no runtime filesystem path input. Arbitrary bundle filenames/modules
are not accepted. References pin format,
ID, version and canonical-content SHA-256; do not silently repin saved sheets.

## Playable rules

| Rule | fantasy_demo | cyberpunk_demo |
| --- | --- | --- |
| Attributes | might, insight (0–5) | reflex, tech (0–5) |
| Resources | effort; focus maximum is 2 + insight | effort; charge maximum is 2 + tech |
| Equipment slots | hand, body | implant, rig |
| Equipment definitions | staff, coat | interface, jacket |
| Check action `attempt` | d20 + might >= 12; 1 effort, 30 seconds | d10 + reflex >= 8; 1 charge, 20 seconds |
| Trait access discount | riverborn: cost becomes 1 | guild-trained: cost becomes 0 |

Both bundles also declare:

- `take`: an available visible zone item changes owner; no cost/time. There is
  no implicit stack splitting or cloning. Equipment definitions are not item
  instances: validation assigns definitions to sheet slots; later persistence
  creates actual inventory identities exactly once.
- `help`: costs 1 effort and 60 fictional seconds; creates a sourced `helped`
  fact for the actor and target. A false belief that help occurred does not count.
- `access`: baseline costs 2 effort with `confrontation` result. Context applies
  in ascending priority then rule ID. A qualifying trait changes cost; a true
  prior `helped` deed known to the target or a living, present, diplomatically
  skilled allied companion changes the outcome to `admitted`. Irrelevant,
  absent, retired or dead companions do not qualify. These are actual result
  and cost differences, not generated prose or a full social encounter engine.
- `bridge-service`: qualifying helped deeds grant the uniquely identified
  `village-access` award through the pure Progression API. Repeated awards fail.
- Defeat defaults to an `injured` fact. Matching prior actor/scope/policy/risk/
  revision consent can permit exceptional permadeath; the fixture does not
  implement a full encounter or consent UI. Retirement marks offstage and moves
  selected owned item instances without transferring private memories.

Scene resolution owns actor resource/revision changes, item ownership, local
fictional time and sourced action/deed events. Context only reads current traits,
knowledge, companion presence/skills and relationships; it owns no independent
state. Progression uses the same facts/events, not a second advancement ledger.
Actions return effects; only the Zone may install their resulting live state.
The standalone character/check API is not an alternative live player writer.

All action durations are explicit `{unit: "second", value: integer}` JSON
objects, normalized to integer seconds at the Scene boundary. Calendar-relative
months/years are rejected until phase 08. A failed resolved check still spends
the declared resource/time; malformed, unauthorized or stale actions spend none.
Confirmation consumes draws only after revalidation, not during preview.

## Deterministic check and formula vocabulary

`Core.Check` additionally supports independently tested primitives; this does
not mean either bundle implements a complete game using every mode:

- `roll_over`: one die with 2–100 sides, plus modifier, succeeds at `>= target`.
  Optional explosions consume another die only on the maximum face, up to
  `max_explosions` (0–20 extra draws). A maximum at the cap is included and
  recorded with `capped: true`; no hidden draw is discarded.
- `pbta`: exactly two d6; `>= full` succeeds, `>= partial` is partial, else fails.
- `pool`: exactly `count` dice, count successes `>= success_at`, then compare
  to target. An action attribute adds dice, not successes. Prepared count is
  revalidated and never exceeds 100.
- `fudge`: exactly four draws in -1..1, plus modifier, compared to target.

Draw lists must match exactly; unused, missing and out-of-range values fail.
Numeric modifiers are bounded. The shell generates draws; Core never calls RNG.

Formula AST supports integer literals, `["ref", name]`, and binary
add/sub/mul/div/min/max. Division truncates toward zero. Limits are depth 16,
128 nodes, 32 derived formulas and absolute intermediate values <= 1,000,000,000.
Unknown operators, missing dependencies, cycles and division by zero fail.
Standalone modifiers sort by priority then unique ID and apply set/add/min/max;
intermediate magnitudes above 1,000 fail. This is not executable Elixir or a
user-supplied module/expression evaluator.

## Capability and delivery limits

`scene` and `checks` are enabled/playable; `lore` is record-only and `commerce`
deferred. Required disabled/absent mechanics and dependency cycles fail bundle
validation; querying an unavailable capability returns an explicit error.
There is no fake commerce success, calendar adapter, full WorldProfile, NPC
agency, transport or persistent award/consent implementation.

Reproduce the two-system journey and finite checks with:

```sh
mix test test/genesis/systems test/genesis/core
```

The [phase 02 handoff](../../docs/implementation/02-rulesets/handoff.md) records
acceptance and the [phase 03 handoff](../../docs/implementation/03-zone-sessions/handoff.md)
records the batch gate. Phase 04 adds durable serialization, uniqueness and
membership before these mechanics can support real adventures.
