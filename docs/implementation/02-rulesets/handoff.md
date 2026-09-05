# Handoff: 02 — Ruleset bundles and deterministic checks

Status: implemented in the 01–03 batch; final-gate evidence is recorded in the
[batch handoff](../03-zone-sessions/handoff.md). Date: 2026-09-04.
Base and preserved starting changes: [phase 01](../01-pure-core/handoff.md).

## Delivered behavior

Both original JSON bundles use format 1 and version 1:
`priv/systems/fantasy_demo.json` and `cyberpunk_demo.json`.
Their [rules reference](../../../priv/systems/README.md) documents actual
mechanics, reads/writes, draw use, limits and unsupported features.

- `Genesis.Systems.load/1` allowlists bundle IDs; fixed demo JSON assets are
  embedded as tracked build resources, decoded/validated at runtime, while
  `Systems.Bundle.validate/1` is pure. References include format, ID, version
  and SHA-256 of recursively key-sorted JSON. Changed content changes the pin.
  No runtime file path or module is loaded from a character/action. Editing a
  demo JSON resource recompiles its loader; authored/persisted bundle input
  will use the validator, not a network-controlled filesystem API.
- `Systems.GameSystem` callbacks are `metadata/1`,
  `validate_character/2`, and `resolve/4`. `Systems.Declarative` is their
  shared implementation. `Systems.character/2` creates and validates sheets
  through that same path; `actor/4` adapts a validated sheet into Core.
- `Systems.scene_rules/1` supplies pinned actions and context to the same
  Scene reducer. `Systems.capability/2` returns explicit unsupported errors
  for unavailable mechanics; capability dependencies and cycles are checked.
- `Core.Check.resolve/2` implements roll-over, 2d6 thresholds, success pools
  and four Fudge dice. `prepare/2` adds attributes to totals except for pools,
  where they add dice. Both standalone and scene resolution use this path.
- `Core.Formula.evaluate/2` and `derive/2` use a bounded integer AST;
  dependency cycles, missing names, unknown operators and division by zero fail.
  `Core.Modifiers.apply/2` provides deterministic ordered set/add/min/max.
  Context rules are the narrower data-driven scene integration, not an
  arbitrary modifier scripting interface.
- `Core.Progression.award/4` requires an actual true deed, creates one sourced
  award identity, and cannot farm it by reopening the scene. Award event sources
  point to prior deeds; award facts point to the new event (no source cycle).
  `defeat/5` defaults nonlethal; death requires matching trusted prior
  actor/scope/policy/risk/revision consent. `retire/5` transfers only selected
  owned item identities to a living successor, without copying inventory or
  private memories, and marks the retiree offstage.

No dependencies were added for phase 02. Tempo adoption belongs to 03; no parser,
commercial rulebook, economy, encounter loop or generic plugin framework was added.

## Evidence

Predecessor's core regressions remained green while extending them. Initial
bundle-load and check-resolution tests failed against their unimplemented APIs.
The final suite contains **13 ruleset tests**:

```sh
mix test test/genesis/core test/genesis/systems
```

`bundle_test.exs` validates both bundles, content pins, unsafe input, saved-sheet
bounds/slots, capability cycles, duration units, action references, shared context
and pool attribute integration. `check_test.exs` enumerates finite boundaries
rather than random frequencies; it asserts explosion draw/cap behavior.
`formula_test.exs` covers limits, dependency order and stacking.
`progression_test.exs` runs award, consent and retirement against both bundles.
Final batch validation is recorded in the 03 handoff.

## Carry-forward limits

The equipment schema validates definition/slot assignments; those definitions
are not spendable world item instances. Phase 04 must instantiate and persist
actual inventory identities once. Standalone sheet resolution is pure mechanics,
not a second live authority: player mutations go through Zone/Scene.

Progression and compounds are pure contracts, not Session endpoints yet. Durable
award uniqueness, persisted consent, recovery and source mappings belong to 04
and later consumers. Supported durations are nonnegative integer seconds only;
calendar-relative months/years remain unsupported until 08. No GM/SSH/browser
game surface or human play-quality evidence exists at this stage.

## Next entry checks

Phase 03 is completed in this batch; inspect its [handoff](../03-zone-sessions/handoff.md).
Rerun the command above before modifying engine integration. Preserve explicit
roll inputs, exact bundle pins, paid accepted failure versus free validation
rejection, and the distinction between known fact and actor belief.
