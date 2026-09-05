# Handoff: 04 — Durable state, audit and recovery

Status: implemented and locally validated. The shared final precommit gate with
phase 05 passed. Do not infer production or full-time readiness.

## Entry and delivered contracts

Base: `a0d3d826044ac0fcf1c4d1822cb44c7e4259ab08`, followed by the local
phase-04 diff. Phase-03/core/rules predecessors passed 41 focused tests before
implementation. No dependency changes. Existing auth IDs are UUIDs.

- `Engine.Runtime.call/3` and `attach/4` enter the existing World owner in
  `:postgres` mode. Ephemeral fixtures remain separate; persistent mode refuses
  bootstrap grants. Every binding/receipt replay rechecks database membership.
- Registry zone identity is `{:zone, {Scope.key(scope), zone_id}}`, not a
  flattened tuple. World restart fences sessions, not durable claims; reattach
  reloads snapshots. Zone loss retains acknowledged receipts.
- `Persistence.Actions`, `Control`, `Tx` atomically store snapshot, event,
  payload-bound receipt, outbox and Oban work before acknowledgement. A short
  world-row lock serializes commit cursors across zones. No lock spans OTP calls.
- Migrations `20260905050623` and `20260905052850` add scoped storage, composite
  world/campaign/entity foreign keys, exclusive claims, source uniqueness and
  revocable memberships. Archived campaigns retain canonical assets and history.
- `Codec` format 1 is bounded tagged JSON with closed atoms/structs; it rejects
  unknown formats and never decodes executable terms. UTC timestamps retain
  microseconds. Fictional coordinates/calendar pins remain explicit. `Deadline`
  saves remaining milliseconds and UTC, never a persisted monotonic counter;
  restart caps backward wall jumps and rebuilds process-local deadlines.
- `Replay` validates checkpoints and recorded transitions/digests, not a reroll.
  History freezes eligible user audiences and filters before pagination. Later
  membership grants do not reveal old private events; revoked membership cannot
  replay receipts or attach.
- `Session.submit_step/4` and `confirm_step/4` use stable plan/index receipts:
  a failed later step does not refund earlier elapsed time or permit skipping it.
- `Persistence.Incorporation` proves only one ready Experience, one zone and
  **zero elapsed time**. A server-retained preview binds the checked base, claims,
  replay, rules and source mapping. Publication is atomic and source-linked;
  retries across crash boundaries apply once. Positive elapsed time returns
  `:time_reconciliation_unavailable` and retains claims. Phase 08 owns broader
  time windows, multiple experiences and scheduling.

## Evidence and limits

On 2026-09-05, `mix test test/genesis/persistence test/genesis/engine
--warnings-as-errors` passed **39 tests**, seed 453909. `mix credo --strict`
passed. Meaningful red tests preceded codec/storage/authority implementation.
Tests cover action and incorporation crashes before commit, after commit and
after cache install; pause across weeks/restart; private whispers, late joins
and revocation; independent committed connections racing claims and cursors;
source-linked lasting deeds affecting resolution after campaign archive.

`test/support/fixtures/world_fixtures.ex` builds original demo scenes. Only the
incorporation fixture explicitly selects a validated zero-duration help action;
normal actions retain their real duration. It is not a UI time-reconciliation
workaround. No live LLM, embeddings, player TUI or human play evidence is claimed.

Current bounds: 200 action events per working Experience, 2000 retained core
events, 500 entities per core collection, 256 live grants, eight incorporation
previews per World process. No silent receipt eviction. These limits need an
explicit compaction/version decision before large-world deployment.
The supervisor additionally caps 32 live World trees and 80 Zone/Session workers
per tree. Detached sessions release grants; reconnects do not consume a lifetime
quota. Durable snapshots currently support Published and Experience scopes;
the incorporation candidate is a checked in-memory projection, not an independently
editable published copy. Other durable scope kinds require later contracts.

Current snapshots are saved on every accepted action/control/authoring command.
Historical checkpoints are taken at zone admission, Experience start, canonical
authoring and incorporation; between checkpoints, replay applies recorded deltas.
Metadata role/binding/revocation commands accept an optional stable request ID;
network forms always supply it. Omitting it in a trusted context call declares a
new command. Start/archive derive a stable ID from target and expected revision.
No delayed receipt replays an earlier role or assignment over a newer decision.

## Phase 05 entry check

Re-read current architecture/time/knowledge contracts, then rerun the exact
39-test command above, especially `history_lifecycle_test.exs`,
`committed_race_test.exs`, `durable_authority_test.exs` and
`incorporation_test.exs`. This command passed before phase-05 work began.
Browser authoring must use the persistent authority seam; no raw JSON workflow,
canonical edits during an open window, idle advancement or full-incorporation
placeholder is permitted. Final whole-tree gate evidence follows.

## Final shared verification — 2026-09-05

- `mix precommit`: **190 passed**, seed 234906. Includes warning-free compile,
  formatting, Credo, dependency/security audits, generated usage rules, xref,
  Sobelow, documentation and the entire test suite.
- `MIX_ENV=test mix dialyzer`: zero errors, zero skipped warnings.
- `mix assets.build`: passed. Erlang 29.0.6 / Elixir 1.20.4-otp-29 as pinned.
- Both new migrations passed in test and local development (`mix ecto.migrate`);
  shipped auth/Oban migrations and existing development accounts were untouched.
  Postgres truncates the generated claim/receipt index names to
  `experience_claims_world_id_generation_resource_kind_resource_id` and
  `request_receipts_world_id_scope_key_principal_id_request_id_ind` respectively.
  Use the actual catalog names if later adding changeset constraint translation.
- The first full gate caught three auth tests expecting the historical landing
  page. Targeted auth tests were updated to verify the new library redirect and
  authenticated account menu before the successful final gate.
- Code remains an uncommitted local diff on the base SHA above. Remote main and
  its successful CI still contain the earlier 01–03 foundation, not this batch.
- Phase 05's browser visual/keyboard/narrow-layout gate remains open; no external
  service, actual player play or production recovery qualification is inferred.
