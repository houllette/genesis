# Handoff: 05 — Native GM world-building workbench

Status: implementation and server-driven acceptance tests pass; **not fully
qualified**. Actual browser visual/keyboard/narrow-layout QA is outstanding
because the available Browser runtime returned no browser connections on
2026-09-05. Do not substitute LiveView tests for that gate. Shared final
precommit evidence is recorded below.

## Entry validation

Base: `a0d3d826044ac0fcf1c4d1822cb44c7e4259ab08` plus the phase-04/05 local
diff. The published foundation commit passed GitHub Actions run 33946082052.
The phase-04 entry command `mix test test/genesis/persistence
test/genesis/engine --warnings-as-errors` passed 39 tests, seed 453909.
Read its [handoff](../04-persistence/handoff.md) for crash, time, claim,
provenance, format and independent-connection cursor evidence.

No new dependencies or remote service setup. Existing Postgres, Phoenix,
LiveView, Oban and the qualified Tempo clock remain the boundaries.

## Routes and real APIs

All six routes are inside the existing `:require_authenticated_user`
live session with `[:browser, :require_authenticated_user]`. Login precedes
membership checks; every context/command rechecks current world/campaign
authority. Every template passes current_scope to Layouts.app.

| Route | Purpose |
| --- | --- |
| `/worlds` | Create/select a world and original ruleset/profile |
| `/worlds/:world_id` | Places, campaigns, Experiences and authoring drafts |
| `/worlds/:world_id/places/:zone_id` | Typed people/items, place edits, linked notes and public preview |
| `/worlds/:world_id/campaigns/:campaign_id` | Invitations, role delegation, roster, character assignment and preparation |
| `/worlds/:world_id/experiences/:experience_id` | Start/pause/resume, local versus published time, gatherings and audit |
| `/invitations/:token` | Explicit acceptance by the named authenticated account |

Authenticated visits to / redirect to /worlds; public auth routes remain
unchanged. The home page now explains the actual product and limitations.

- `Content.create_zone/4` and `curate/7` enter Runtime → existing World.
  Initial admission creates a new zone only; edits to an existing zone are
  delegated to its owning Zone. `Core.Curation` is a pure, closed typed reducer.
- `Content.view/3`, `preview/3`, `list_notes/3` return authorized projections.
  Preview grants no identity or access and cannot reveal private persona,
  items, notes or even a public note linked to an invisible entity.
- `Content.save_note/6` stores linked author-only/private or public notes,
  plans and beliefs. None satisfy engine fact predicates. Detailed atlas,
  prototypes, cross-zone linking and story beats remain later work.
- `Campaigns`, `Worlds`, `Invitations`, `Workspace` implement roster,
  separate campaign/world roles and real gathering metadata. Invitation links
  are email-bound, expire after seven days and are explicitly shared by the GM;
  no email is sent and no world stewardship is implied. Meeting URLs accept
  only HTTP(S) without embedded credentials. Meeting dates are explicitly UTC.
- Actor persona is versioned data with a stable temperament, goal and dormant
  agency. It creates no LLM process. PCs use validated ruleset defaults, and
  items keep a single typed owner.
- Forms carry stable request IDs and scene/note revisions. Background refreshes
  do not silently rebase an open edit form. Reopening shows committed state.
  Metadata role/binding receipts return the earlier acknowledgement without
  restoring an old decision; the UI then refreshes current state.
- The durable outbox emits only safe world/cursor invalidations. Both open
  workspaces and live World grants reauthorize after delivery. Detached sessions
  release grant capacity; a 260-reconnect regression guards against exhaustion.

## Published, Working and Draft

An open advancement window preserves its canonical base. New ordinary authoring
saves create Draft rows without mutating Published or Working state. Drafts
show their pinned base revision; promotion requires a fresh conflict review
and is deliberately unavailable here, not a successful placeholder.

Starting a draft pins a checkpoint and claims its place, actors and items.
Conflicting claims show a useful route back to unfinished Experiences. Pause
and subsequent gathering records retain those claims and the same fictional
point. Local action history is separate from published audit. The UI offers
no full completion/incorporation shortcut. Positive-duration publication,
multi-Experience reconciliation and calendar simulation remain phase 08.

## Observed acceptance evidence

- Meaningful red tests preceded the pure authoring reducer and content APIs.
  LiveView tests caught missing stream-child IDs and a note whose default link
  pointed at a different place; both were fixed with regression coverage.
- `test/genesis_web/live/workspace_live_test.exs` passes the complete native
  form sequence: create Lantern Quay, Edda and Tess, a brass lantern, private
  and public notes, a campaign and Experience, start, first gathering, pause,
  reopen, second gathering, resume at the same coordinate, and author a Draft.
  No player session, JSON or developer mutation is used for that journey.
- The same file tests stale concurrent editors, role revocation, wrong-world
  and tampered IDs, claim conflict guidance, and actual Oban outbox delivery
  refreshing a formerly privileged view. Duplicate delivery is harmless.
- A durable help action produces a native comparison against the starting
  checkpoint: the changed effort balance and a new established fact are visible,
  while an earlier belief is not misreported as an already-established deed.
  The published snapshot and world coordinate remain unchanged.
- `workspace_metadata_test.exs` covers invitation expiry/email binding,
  role limits, delayed role/binding retries, reassignment without duplication,
  repeated archive acknowledgement and real/fictional date separation.
- `content_test.exs` covers idempotent creation, stale saves, unchanged
  published snapshots during windows, note references and preview privacy.
- Asset build, compiler, Credo and an intermediate Dialyzer run passed.
  Final whole-tree results belong in the verification section below.

## Remaining acceptance gate and next run

The browser skill was followed: connection setup failed with "No browser is
available"; supported discovery returned []. No screenshots, viewport, keyboard,
focus or human usability success is claimed. The CSS includes narrow layouts,
visible focus, reduced-motion support and a skip link, but source inspection is
not rendered-browser evidence.

With a browser connected, run `mix setup` and `mix phx.server`, register/sign
in through the local dev mailbox, open /worlds and repeat the native journey
above at desktop and 390px widths. Check tab order, select changes, validation,
focus, no horizontal overflow, private/public preview and reopening a paused
Experience. Record screenshots and observed results; repair issues and rerun
the affected checks plus precommit before closing phase 05.

## Final shared verification — 2026-09-05

`mix precommit` passed **190 tests** (seed 234906) plus all configured compile,
format, lint, dependency/security, generated-rule, xref and documentation checks.
`MIX_ENV=test mix dialyzer` passed with zero errors/skips. `mix assets.build`
passed. Publication update: the 04–05 batch is committed and pushed to `main` as
`083a563a0c6dedaca4474cd30eac6b160eed87ce`; remote HEAD was verified and
[GitHub Actions 33951975847](https://github.com/houllette/genesis/actions/runs/33951975847)
completed successfully. This result does not cover subsequent uncommitted code.
The two new migrations are also applied to the local development database.

The browser gate is the only remaining phase-05 acceptance qualification; it
must be closed before marking the whole phase complete. Native templates and
styles are not claimed to have passed visual or keyboard QA.

Before phase 06, read this handoff and run:
`mix test test/genesis/persistence test/genesis/core/curation_test.exs
test/genesis_web/live/world_library_live_test.exs
test/genesis_web/live/workspace_live_test.exs --warnings-as-errors`.
Then close the browser gate. Do not infer playable economy, LLM, embeddings,
player TUI, scale or human play qualification from this batch.

Phase-06 entry repeated the focused command above: **37 passed**, seed 879585.
Supported Browser setup was retried on 2026-09-05 and still reported
"No browser is available"; discovery returned `[]`. The user was asked to
connect a browser. Independent deterministic phase-06 implementation continued
under the user's request, with this predecessor gate explicitly carried forward,
not waived or represented as a completed phase. Close both native journeys
before starting phase 07 or declaring 05–06 fully qualified.
