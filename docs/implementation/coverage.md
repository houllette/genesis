# Requirements-to-delivery coverage

The current [plan](README.md), [GM product](product-and-personas.md) and
[experience-time contract](experience-time.md) supersede historical player-first,
real-time and immediate-canon assumptions. Phases 01–03 now have implemented
foundations; their [batch handoff](03-zone-sessions/handoff.md) carries actual
evidence. The rows below are end-to-end requirements, not a claim that a whole
row is delivered because its earliest phase is complete. Phases 04–16 remain unstarted.

| Requirement | Owning phases | Required evidence |
| --- | --- | --- |
| Pure rules, scoped authority and thin clients | 01–04 | Exact outcomes; one writer; no process/IO inside Core |
| Distinct published and experience state | 01, 03–04, 08 | Durable local actions do not publish world state early |
| GM-first world/campaign management | 05, 07–10 | Useful native create/curate/preview/incorporate workflow without a player |
| Foundry/Kanka-inspired connected records | 05, 07 | Linked people, places, institutions, relationships, notes and safe search |
| Experience spans multiple gatherings | 01, 04–05, 08 | Pause/resume at the same fictional point; no idle/restart drift |
| Tempo and separated time domains | 01–02 values, 03 clock/dependency, 04 persistence, 08 intervals, 14 eras | Verified `:ex_tempo` pin; child clock isolation; UTC precision; monotonic restart safety; supported calendar bounds and no real-time fictional drift |
| Session-based completion and elapsed time | 08–09 | GM or validated terminal predicate seals coherent duration and actual outcomes |
| Overlapping solo/group adventures | 04, 07–09, 12 | Claims prevent shared-NPC/item collisions; ready runs can wait; max end not summed durations |
| Atomic world incorporation | 04 zero-duration; 08 complete | Source mapping, candidate/review, stale confirmation and crash/retry tests |
| Snapshot plus log, not full event sourcing | 04, 08, 15 | Scoped recovery/replay without rerolls, re-inference or partial publication |
| Typed facts, observations, beliefs and memories | 01–04, 13 | Provenance and learned/occurred/recorded distinctions; no false fact promotion |
| Character/prior-choice/companion context | 01–02, 07, 09, 12–13 | Exact minor/major changes and irrelevant/forged-context negative tests |
| Flexible actions and confirmation | 01–02, 06, 09–12 | Clarify/preview/confirm/revalidate; partial success; unsupported actions fail |
| Consent, protected assets and bounded GM authority | 01–05, 08–09, 12, 15 | Cooperative defaults, scoped risk and audited intervention; no forced PC control |
| Rulesets, checks, advancement and defeat | 02, 12 | Two original bundles; exact dice boundaries, milestones, losses and transfer rules |
| Connected economy/commerce/institutions | 06–08, 12, 14 | Real balances/stock/recipes/obligations; religious/currency and secular/barter presets |
| Generic subsystem extension contracts | 02, 06–08, 14 | Playable/record-only/deferred states, owned fields, dependencies and safe migration |
| Cross-zone travel and companions | 07 | Claim expansion, one owner, transfer races/recovery, willingness/refusal |
| Lazy scheduled consequences | 08, 13–14 | Same laws to approved targets only; bounded/deduplicated work and zero idle ticking |
| Curated beats with actual outcomes | 09 | Native authoring, variants, unscripted paths, failure/abandonment and terminal duration |
| Solo/sync/async experiences | 08–09, 11–12 | Scope, waits, pause/deadline rules, outcome persistence and eventual incorporation |
| AI-assisted GM drafting | 10 | Actual Lemieux host preflight; editable reviewed drafts are not future canon |
| Lemieux for all inference | 10, 12–13 | Real Scripted tool/store/environment/resume/budget tests; explicit pin/live/embedding gates |
| Combined SSH/browser player TUI | 11 onward | Same application; actual hosts, key/auth, input, reconnect, knowledge and accessible actions |
| Early living-village pilot | 12 before 14 | GM prepare/run/incorporate/inspect and player choice remembered across campaigns |
| Universal NPC personas and agency | 05/07 data, 12 thin, 13 full | Stable agents, separate knowledge/audiences, scoped memory and approved-target reactions |
| Quality beyond TDD | 05, 10–14, 16 | GM usability, human NPC review, development/held-out scenarios and measured limits |
| Lasting player legacies | 01/04 sources, 12 small, 14 expansion | Durable effects, relevant occasional callbacks, repair without erasing the deed |
| Dwarf Fortress-inspired continuity | 14, 16 | Bounded measured 2,000-year run plus continued experience-driven causal laws |
| Advanced live GM tools and restore | 15 | Possession, secret rolls, full pending/published checkpoint and generation fences |
| Personal-table operations | 16 | Actual small-table target, restricted secrets/budgets, release restart and backup restore |

## Explicit scope limits

- Native GM management is primary. Player TUI parity does not require terminal
  copies of the full editor, atlas management or reconciliation workspace.
- The world deliberately waits for completed experiences. Continuous wall-time
  simulation, independent campaign time-skips and public-MMO availability are not goals.
- Conservative scope claims and GM-reviewed incorporation are required. Automatic
  arbitrary branch/sandbox merging, inconsistent backdating and last-writer-wins
  conflict resolution are not acceptable shortcuts.
- Personal use removes the proposed data-lifecycle workstream, not basic role/
  knowledge isolation, secret handling, provider cost caps or backup recovery.
- Sample rulesets are original and bounded, not full commercial rulebook support.
  Full VTT graphics, imported catalogues, voice/video hosting and bots are deferred.
- No new graph database, ECS, full event sourcing, Horde/libcluster or second
  inference SDK. Boilerplate DNSCluster does not authorize distributed game writers.
- The existing subsystem matrix defines honest small mechanics and record-only
  boundaries. No fake-success stub or empty supervisor counts as a capability.
- Capacity, model quality and long-history richness need actual evidence. A few
  scripted tests or a year counter do not establish those claims. Test the useful
  GM/player village before scaling its historical population.
