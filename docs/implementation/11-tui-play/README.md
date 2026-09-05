# Phase 11 — Unified TUI play over SSH and LiveView

## Validate phase 10 first

Read [phase 10's handoff](../10-llm-authoring/handoff.md). Run actual Scripted Lemieux
tool/store/environment, confirmed freeform intent, budget/resume and native draft/publish
tests; carry live/embedding gates explicitly.
Use exact existing commands from that handoff, inspect the implemented APIs and
repair any predecessor defect with a regression test before extending it.
Read [workflow](../workflow.md), [architecture](../architecture.md),
[product/personas](../product-and-personas.md), [experience time](../experience-time.md)
and [actions/knowledge](../play-and-knowledge.md). Read the full extended report
before structural changes; the current GM-first/session-time contracts supersede
its real-time and immediate shared-canon assumptions.
Read [world subsystems](../world-subsystems.md) and [living context](../living-history-and-context.md).
Read [story/canon](../story-and-canon.md); verify completed outcomes are incorporated, not
immediately published.
Read the complete [Lemieux contract](../lemieux-integration.md) and carry actual
upstream/live gates forward.
Read [TUI-first play](../tui-first-play.md) and [quality](../experience-quality.md); native
GM management stays primary.

## Outcome and scope

One player TUI is usable through SSH and as the default Play tab in the website.
An invited player selects a campaign, creates/resumes a character, explores,
acts and reconnects to the same durable world through either host. The existing native GM
workbench remains the primary surface;
this optional player interface does not replace its management workflows. This phase
replaces both former transport
phases and must prove both paths before handing off.

Proposed homes: shared `Genesis.TUI` model/widgets, `Genesis.Transport` adapters,
world/invite/key contexts, a `GenesisWeb.PlayLive` host and workspace LiveViews.
ExRatatui and its Phoenix integration are not installed at baseline. Work through
these bounded slices across fresh runs if necessary; checkpoint actual evidence.

## TDD slices

1. **Shared-application spike.** Inspect official source/docs for compatible
   ExRatatui and browser cell-rendering integration versions, supported OTP/NIF
   targets, runtime callbacks, input/resize, SSH identity and cleanup. Prepare
   exact dependency changes and obtain approval under AGENTS before installing;
   pin tested versions and sync usage rules. Run one shared model/rendering
   implementation in a browser cell surface and SSH. Verify backend push plus
   two simultaneous runtimes with no module-name collision before adding screens.
2. **Account, campaign and key onboarding.** Reuse phase 05's world/campaign
   setup and delegation workflows. Test scoped high-entropy one-time
   invites stored as digests, atomic consumption, expiry/revoke and denied entry.
   Resolve browser and SSH to the same principal and world/campaign grants.
   Key enrollment verifies possession with an expiring one-time challenge through
   the authenticated account flow; reject unknown/revoked keys, replay, forged
   roles and trusted-username shortcuts. Account setup may be web-native.
3. **Shared character and play flow.** Build campaign/character selection,
   ruleset-metadata-driven creation, location, roster, inventory, choices/checks
   and source-linked history in the TUI. Normalize keys/paste and structured
   selections through bounded input parsing; Session submits authenticated
   intents. Background affiliations reference approved world facts; free-form
   claims cannot mint ancestry, titles or rewards. Resume never resets state.
4. **LiveView Play host.** Embed that TUI in the authenticated site shell using
   the verified cell bridge, without SSH/shell access from the browser. Share
   screen callbacks rather than recreating HEEx gameplay forms. Use native
   components for shell/status/help and account/workspace forms. Test authorized
   mount, bounded cell/input payloads, full snapshot then revisioned deltas,
   browser tab hiding/showing, resize/refit, focus escape and reconnect.
5. **SSH host.** Serve the same player flow with durable configured host keys,
   invited binding/port, connection/idle limits and authenticated key mapping.
   Verify unnecessary shell/exec/forwarding/SFTP capabilities are unavailable;
   never expose Erlang distribution. Test quit/cleanup without stopping the VM.
   Bound and sanitize input/output, including malicious OSC/clipboard sequences.
6. **Concurrency, knowledge and recovery.** Use headless/input-injection tests
   plus LiveView auth/payload tests. Exercise different users and two attachments
   of one actor, contested actions, private knowledge, stale frames/commands,
   duplicate submit, app crash, logout and last-attachment parking. Revocation
   and actor/campaign changes must clear previously visible cells and buffers.
   Reconnect takes a fresh authorized snapshot; lost deltas cannot leave secrets
   visible or cause missed/duplicated mutations. Compare exact contextual
   outcomes across hosts; no client-local deed or companion history.
7. **Campaign workspace and usable input.** Support player/party journal notes,
   objectives and durable gatherings with roster, agenda, external meeting link
   and recap in the TUI; native web preparation may complement these. Links are
   displayed safely, never fetched automatically. Recaps reference accepted events,
   not new world edits. Test solo return, party gathering, private notes, switching
   and archive without discarding pending outcomes. Test narrow layouts, Unicode, paste/IME, keyboard
   focus, copy and a labelled accessible text/action alternative using the same
   presentation model; a painted grid alone is not accessibility evidence.
8. **Actual mixed-client proof.** Run two real SSH terminals plus a browser Play
   tab, and separately two browser tabs. Perform the shared fixture journey,
   contested action, contextual choice and permission-safe history lookup.
   Disconnect/revoke/reconnect, resize, navigate away/back and exercise actual
   browser keyboard/JS behavior. Record versions/OS, exact commands and visual/
   manual evidence. Headless tests cannot satisfy either actual-host gate.

## Route and presentation contract

Place the Play host, world/campaign selection, journals/gatherings, invitation/
key management and character workspace LiveViews in the existing
`live_session :require_authenticated_user` inside the scope using
`[:browser, :require_authenticated_user]`: verified account authentication must
precede game authorization and cell delivery. Keep public auth routes in their
existing `:current_user` session. Preserve invite destinations only as validated
local paths. Pass `current_scope` to `Layouts.app` and contexts; record exact
routes and why each scope is used.

Use the existing JS/CSS asset bundles. A hook-managed grid needs a unique ID and
`phx-update="ignore"`; external controls retain proper labels/focus behavior.
Never insert raw cell text as HTML or follow arbitrary content navigation.
Inspect actual embedded/full-size/narrow presentation. Native shell components
follow AGENTS forms/icons/Tailwind rules. A required embedded TUI LiveComponent
is a bounded integration choice, not a second player application.

## Current experience and GM-first contract

Read [experience time](../experience-time.md), [actions/knowledge](../play-and-knowledge.md)
and [quality](../experience-quality.md). This contract is required in this phase.

Show current Experience, local fictional time, paused/active/ready status and pending
incorporation. Join only GM-approved scope; ready rewards cannot be spent elsewhere. An
evening's pause saves the adventure and remaining deadlines, not a world-time jump. A ready
courier visibly waits for the longer group's window. Test confirmation/context semantics in
both hosts; full native GM editor/reconciliation parity in the TUI is not required.

## Handoff criteria

- [ ] Both hosts show local versus published outcomes and resume across gatherings without
  time drift or resource duplication.

- [ ] One shared TUI application delivers character creation, scene actions,
  journals/gatherings and authorized return history over both SSH and LiveView.
- [ ] Approved, pinned dependencies pass shared-render/push/concurrent-instance
  evidence; supported NIF targets and integration limits are documented.
- [ ] Scoped invite/key possession, replay/revoke, tampered ownership and stale
  submissions fail at the authentication/context/engine boundary.
- [ ] Mixed attachments preserve one actor state, last-attachment semantics and
  exact contextual results; stale frames and permission changes leak no secrets.
- [ ] Browser markup and terminal control injection, resize/focus/paste and slow
  consumers have regression coverage. Actual browser and SSH journeys pass.
- [ ] TUI-first play and an accessible reading/action path were manually checked;
  no unverified mobile or assistive-technology support is claimed.
- [ ] `mix precommit` passes and [handoff.md](handoff.md) records actual routes,
  host/daemon setup, versions, fixture commands, tests and manual evidence.

Phase 12 first validates this phase's actual handoff and focused
regressions before extending it. Follow [the next brief](../12-living-pilot/README.md).
