# Handoff: 06 — Local world-subsystem foundations

Status: implemented and locally validated in the batch following published `083a563a0c6dedaca4474cd30eac6b160eed87ce`;
**not fully qualified**. Actual browser visual/keyboard/narrow-layout
QA remains open for both 05 and 06. No later phase was started. This is a bounded
local-settlement slice, not completion of the entire subsystem roadmap.

## Entry validation and publication

The preceding 04–05 batch was committed and pushed to `main` as `083a563`;
remote HEAD matched. [GitHub Actions 33951975847](https://github.com/houllette/genesis/actions/runs/33951975847)
completed successfully, including tests, security, Dialyzer and workflow lint.
Its green result does not cover this subsequent phase-06 batch.

Read the historical report and current architecture/time/action/context/subsystem
contracts before extending the existing writer and storage seams. The exact
05 entry command passed **37 tests**, seed 879585:

```sh
mix test test/genesis/persistence test/genesis/core/curation_test.exs test/genesis_web/live/world_library_live_test.exs test/genesis_web/live/workspace_live_test.exs --warnings-as-errors
```

Supported Browser setup was retried on 2026-09-05: "No browser is available";
supported discovery returned `[]`. The user was asked to connect a browser.
Independent deterministic work continued under the requested next-phase execution,
but this is not a waiver of the predecessor acceptance gate. No actual browser,
keyboard, viewport or human-play result is claimed.

No new dependency, migration, service, AI process or timer was added. Existing
Postgres, Registry/World/Zone/Session, Tempo UTC boundary and transactional Oban
outbox remain the runtime. Erlang 29.0.6 / Elixir 1.20.4-otp-29 are pinned.

## Rules, records and durable compatibility

- `Systems.load/1` adds `fantasy_local` and `cyberpunk_local` as new validated
  bundle IDs. Original demo bundles and digests remain unchanged. New-world forms
  offer both generations; existing worlds never auto-upgrade.
- `Systems.LocalRules` validates a closed version-1 contract. Enabled playable
  capabilities are economy, commerce, production, institutions and survival.
  Unsupported, missing-dependency and record-only actions fail closed. Rules
  cannot mint recipe currency, mismatch the recovery resource maximum, omit
  waste accounting or accept a nonzero completion delay.
- `Systems.WorldProfile.preset/1` supplies `temple_market` (religious/currency)
  and `mutual_aid` (secular/barter). The versioned preset is pinned in the local
  settlement; the ruleset owns the capability manifest. The world's descriptive
  profile metadata is not mechanical authority. No world-name branch or campaign
  override changes these rules.
- `Core.Settlement.configure/3` stores one market/institution per Zone linked to
  that place and two real NPCs with stable version-1 dormant personas. Their
  inventory is their treasury/store. A tradition label and lore claim do not
  create a fact. Positive holdings or any local institutional record block
  profile/owner/disable changes without a migration policy.
- `Content.curate/7` adds typed `settlement` and `stock` edits through the
  existing Zone. `Settlement.stock/3` requires a reason and records an explicit
  source/sink delta through the existing authoring event. It cannot repurpose an
  ordinary item or change a lot's commodity/owner. Generic item editing cannot
  bypass stock controls. Window edits become Drafts, leaving Published and
  Working snapshots unchanged.
- State adds optional `local_rules`/`settlement`; Item adds optional
  `commodity`. Codec keeps format 1 with strictly whitelisted additive fields,
  omitted when nil. The captured pre-06 `test/fixtures/phase05_snapshot.json`
  round-trips exactly in `codec_test.exs`; old checkpoint/transition digests are
  not rewritten. Restore checks lot labels, ownership, totals, disabled currency
  and institution references against pinned rules. No shipped migration changed.

## Actions, accounting and authority

`Core.LocalAction` enters existing `Scene.propose/4`, `revalidate/2` and
`confirm/3`. `Stock`, `Commerce`, `Economy` and `Institutions` are pure
values/reducers; none read clocks or own processes.

- Quantity intents: `buy`, `sell`, `barter`, `produce`, `offer`, `disrupt`;
  integers 1–100, with authored production capacity also checked. Other intents:
  `rest`, `affiliate`, `aid`, `trespass`, `report`, `adjudicate`.
  Reports require a known existing fact ID. Payloads cannot supply roles, costs,
  arbitrary commodity flows, draws or sources.
- `Stock.balance/3` derives balances from existing owned Item lots. `flows/3`
  records exact debited lots; outputs derive identity from the accepted event,
  and spent lots remain at zero. Transfers conserve each commodity. Opening
  issuance/correction, supply loss, consumption and recipe conversion record
  explicit version-1 accounting, not hidden rewards.
- The recipe is two grain → one ration + one chaff, zero delay: abstract bundle
  units, not physical or economic equivalence. Currency uses integer minor units;
  barter exchanges rations for grain. Scarcity changes the next buy quote at an
  authored threshold; sell bids round down from half the base price without
  scarcity inflation. Only the merchant can record its own supply loss; the GM
  operates that NPC through existing authority. No production runs on idle/restart.
- Rest consumes one ration and restores at most two effort, capped at ten; a full
  actor cannot pay for no recovery. The shipped duration is 3,600 fictional
  seconds. Positive-duration incorporation still returns
  `:time_reconciliation_unavailable`; phase 08 owns that implementation.
- `Engine.Session.propose/3` returns an **opaque content-bound local quote ID**.
  Pass that returned ID to `confirm/3` or `cancel/2`, not the proposal request ID.
  It binds principal/campaign, actor, scope, rules and exact terms/context.
  Reusing a proposal request ID for new terms cannot rebind an old confirmation.
  Confirmations separately use their stable request ID for receipt recovery.
- Quotes reserve nothing. The conservative digest includes local actors,
  inventories, knowledge and policy; unrelated local mechanical changes can
  require requoting. Lifecycle-only revisions and UTC are excluded. An unchanged
  quote survives pause/resume; it expires at `fictional cursor >= expiry`.
- The Zone retires confirmed/declined local quotes and prunes invalid local
  proposals within a 64-proposal bound. Legacy scene identity semantics are
  unchanged. After an uncommitted Zone crash, re-propose; after a committed lost
  acknowledgement, retry the same confirmation request/quote IDs for its receipt.
- Existing action transactions save snapshot, scoped event, receipt, outbox and
  job before reply. Replay uses recorded transitions, not recipes/latest prices.
  Claims exclude another Experience from the same place/stock. No cross-zone
  transfer shortcut was added.

## Institutions, context and privacy

Affiliation creates a private sourced relationship and pending offering obligation.
A voluntary offering transfers real rations and can fulfill the obligation;
giving without joining does not create membership. `Context.institution/3`
consults the representative's typed relationship, obligation and debt knowledge.
Aid transfers one real grain from that representative and redeems the obligation.
Refusal, false membership beliefs, unrelated representatives, missing stock and
repeating a redeemed obligation do not grant aid.

Restricted-store trespass establishes a scoped fact. Only an authored witness
policy plus actual actor visibility creates the representative's observation;
otherwise the act remains private. Reporting requires a known established fact,
not a belief or guessed hidden ID, and creates a sourced observation without
making the original private event public. Only the responsible representative
can adjudicate an observed/reported act, creating one restitution obligation and
restricted local standing that prevents aid. This is one bounded local response,
not a full court, restitution-discharge system or universal reputation score.

Player projections retain state-layer audiences. Public market availability
does not reveal private currency lots or witness policy. Actions retain real
principal/actor provenance and frozen historical audiences. No affiliation or
offering grants platform privileges or authors a PC's beliefs. GM operation of
NPCs does not authorize impersonating another account's PC.

## Native GM surface and reproducible journey

Two routes use the **existing** `:require_authenticated_user` live session with
`[:browser, :require_authenticated_user]`: authentication precedes current
membership/role checks.

- `/worlds/:world_id/places/:zone_id/resources`: builder/steward controls for
  society preset, real representatives, stock/treasury and bounded policy.
- `/worlds/:world_id/experiences/:experience_id/resources`: GM/steward previews
  and explicit confirm/decline for owned PCs or real NPCs.

`SettlementLive`/`SettlementComponents` use current_scope, existing contexts,
revision-bound forms, stable request IDs and streams. Reopening explicitly loads
the latest revision; background refresh does not rebase an open save. Recipe
controls show the immutable bundle recipe and execute a bounded batch; they do
not edit pinned rules. Reports select known facts, not raw IDs. Lost confirmation
transport retains the request ID for explicit retry. Published/Working/Draft and
fictional time are labelled.

The native acceptance test creates a place, Edda and Tess, a religious institution
and opening stock; starts an Experience without players; operates those NPCs to
trade, produce, affiliate, offer and receive aid; inspects history and verifies
Published is unchanged. A second native journey uses cyberpunk/secular data,
actually produces/barters finite stock and rejects currency. These are server-
driven form tests, not browser QA.

For browser qualification, use normal README setup/server and create a **local
systems** world at /worlds. Repeat at desktop and 390px width. Check selects,
report choices, advanced policy controls, tab/focus order, stale-editor reopening,
pause/resume confirmation, refusal errors, treasury privacy and no horizontal
overflow. Record results/screenshots and also close [05's browser journey](../05-gm-workspace/handoff.md).
No fixture SQL or raw JSON should be needed for ordinary GM authoring.

## Verification evidence — 2026-09-05

- Meaningful reds: a legacy bundle returned the wrong capability error; regression
  now guards it. The quote-rebinding test failed because old/replacement IDs
  were equal (seed 608777), then passed after content-bound identity. Native
  barter checks exact final holdings, not only successful rendering.
- `mix test test/genesis/persistence/settlement_test.exs test/genesis_web/live/settlement_live_test.exs test/genesis/engine --warnings-as-errors`:
  **31 passed**, seed 170258, after quote-identity repair.
- `core/settlement_test.exs`: connected disruption → requote → trade →
  production/waste → rest; expiry/pause; 72 bounded price/quantity cases;
  conservation; invalid input/delay; exhaustion; beliefs versus violations;
  scoped adjudication; restore and authoring-bypass rejection.
- `persistence/settlement_test.exs`: two buyers racing for the last item,
  rejection without charge, competing admission, before-commit/after-commit/
  after-install crashes, 70 declined quotes without capacity leakage, and
  source-linked incorporation/replay/World restart/new-campaign return for both
  presets. The cross-campaign deeds are naturally zero-duration; no time is erased.
- `bundle_test.exs` validates local dependencies/recipe/currency/recovery;
  `codec_test.exs` pins backward-compatible encoding.
- The first full gate found one legacy authoring error-contract regression:
  invalid ordinary items returned `:invalid_state` instead of `:invalid_record`
  (214/215 tests passed, seed 879926). The implementation restored that public
  error without weakening the existing test; the focused curation/settlement
  rerun passed 11 tests, seed 460319. Local capability/migration errors remain
  specific and actionable.
- Final `mix precommit`: **215 passed**, seed 602218. Warning-free compile,
  formatter, Credo, dependency/security audits, generated usage rules, xref,
  Sobelow, documentation and the full test suite all passed.
- Final `MIX_ENV=test mix dialyzer`: zero errors, skipped warnings or unnecessary
  skips. `mix assets.build` passed. `git diff --check` passed. No dependency,
  migration, generated AGENTS rule or CI configuration change was needed.
- Publication refresh after the computer restart: `mix precommit` again passed
  all **215 tests**, seed 478194, and its configured checks. The Git access error
  no longer reproduces; local and fetched remote main matched the base above.
  This handoff accompanies the phase-06 publication batch. Check remote HEAD and
  CI for that exact commit separately; the remote result above covers 04–05 only.
- Browser setup was retried after restart and still reported "No browser is
  available"; supported discovery returned `[]`. Actual browser QA remains the
  acceptance qualification for both native journeys and the entry gate for 07.

## Support levels and next boundaries

| Subsystem | Actual current level | Next owning phase/seam |
| --- | --- | --- |
| Economy/commerce | Playable local finite lots, currency/barter, price bands and receipts | 07 ownership/transfer; 08 due production; 14 regional supply |
| Production/survival | Playable one immediate recipe and supply-consuming recovery | 08 durable completion/approved time; 12 encounters |
| Religion/institutions/law | Playable one institution, obligation/aid and sourced local response; traditions are lore | 07 shared identity; 08 observances; 14 continuing history |
| Geography/logistics | Place records only; no routes, travel or deliveries | 07 routes/ownership; 08/14 supply propagation |
| Population/kinship/culture | Actors/personas and descriptive notes; specialized records deferred | 07 typed atlas; 14 demographic transitions |
| Environment/seasons | No simulator; manual merchant loss is not weather modeling | 08 condition/due-event inputs; 14 connected history |
| Knowledge/reputation | Facts/audiences/context and institution-specific standing; no rumor network | 13 scoped NPC memory; 14 remembrance |
| Magic/technology/research | Record-only lore and existing checks; no supernatural/research action | 07 references; 12 supported ruleset mechanic |

Local record/accounting version is 1. Extensions preserve owning scope, pinned
rules, typed reads/writes, sourced events and frozen audiences. Unsupported
cross-zone, delayed or supernatural intents fail; no empty service counts as
implemented. Limits remain: 500 records per collection, 200 working action events,
1,000,000 units per owner/commodity, 64 proposals. Spent lots are retained;
long-running operation needs an explicit compaction/version decision, not silent
deletion. No LLM, embeddings, shared TUI, scale or human-play qualification exists.

## Next agent: qualify and validate before phase 07

1. Inspect the exact base plus local diff and close both browser qualification
   gates. Do not label them complete from the tests below.
2. Run these focused entry checks:

   ```sh
   mix test test/genesis/core/settlement_test.exs test/genesis/systems/bundle_test.exs test/genesis/persistence test/genesis/engine test/genesis_web/live/settlement_live_test.exs test/genesis_web/live/workspace_live_test.exs --warnings-as-errors
   ```

3. Preserve original pins, format-1 golden encoding, source/sink accounting,
   quote/receipt identity, current actor authority and exclusive claims. Repeat
   the two-preset restart/cross-campaign proof after ownership edits.
4. Read [07's brief](../07-world-zones/README.md). Extend the existing World with
   linked identity and explicit transfers; do not add another global writer,
   reinterpret profile metadata, implement 08 timers early or erase elapsed time.

Completion requires the entire acceptance gate. Publication, remote CI, browser
qualification and local deterministic validation remain separate facts.
