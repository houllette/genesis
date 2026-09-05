# One player TUI, hosted over SSH and in the browser

This user clarification supersedes the earlier browser-first implementation
followed by a separate SSH interface. [Phase 11](11-tui-play/README.md) delivers
both together. The primary player experience is the TUI, including when opened
as a Play tab in a LiveView page. This is a plan, not installed functionality.

The native GM world-building/curation workspace is the primary product, delivered
before this player surface. Full editor, atlas management and incorporation-review
parity in the TUI is not required. Play shows its Experience/local time, pause and
pending-incorporation status; closing a tab or gathering never advances world time.

## Shared experience, separate connections

```text
SSH connection ── terminal input / ANSI output ──────┐
                                                  ├─ shared Genesis.TUI application
LiveView Play tab ── browser input / cell output ────┘    (one instance per attachment)
                                                       ↓ authenticated intents
                                                  Engine Session → World / Zone
                                                       ↑ permitted state / effects
```

Share player navigation, input semantics, action selection, character sheets,
inventory, conversations, journals, history and contextual explanations. Each
attachment has its own dimensions, focus, scrollback and rendering process;
do not share a mutable terminal buffer between players or between browser tabs.
The shared application may adapt layout to dimensions and input capabilities,
but it must not become separate browser and terminal gameplay implementations.

Engine Session stays independent of widgets and LiveView sockets. Both hosts
derive the same principal, campaign, character and capabilities; the Zone remains
the authoritative writer. Multiple attachments to one actor cannot gain extra
turns, duplicate inventory or maintain competing local histories. Parking uses
last-attachment semantics under checkpoint/danger policy, not closing any one
browser tab. Experience pause is a separate domain operation.

## Browser integration and upstream evidence

The preferred browser path is structured cell rendering, not an SSH connection
from the browser or a shell-backed terminal. ExRatatui documents a `CellSession`
surface that uses the same application/draw contract as its terminal transports.
See the [official non-terminal rendering guide](https://ex-ratatui.hexdocs.pm/cell_session.html).

`phoenix_ex_ratatui` documents cell-diff delivery over LiveView and both full-page
and embedded TUI components. Evaluate that existing integration before writing
a new bridge. See its [official repository](https://github.com/mcass19/phoenix_ex_ratatui).
ExRatatui's App options document a module-name registration default and `name: nil`
for unregistered instances; explicitly test concurrent attachments. See
[App options](https://ex-ratatui.hexdocs.pm/ExRatatui.App.html#module-options).

These sources were checked on 2026-09-04; they establish a candidate design, not
a compatible dependency pin or a production qualification. Phase 11 must verify
the exact ExRatatui/Phoenix integration versions, NIF targets, input/resize APIs,
lifecycle and shared-app delegation before dependency approval/installation.
If a unified LiveView macro generates an adapter runtime, delegate its callbacks
to the same Genesis TUI model/rendering functions used by SSH. Do not copy screens
into a Phoenix-only application. Use a thin CellSession host adapter only if the
selected integration cannot preserve that contract; record the reason and tests.

## What remains native web UI

Native HEEx is appropriate for account/login/settings, invitation/key management,
world/campaign library, builder forms, linked atlas browsing and extensive GM
preparation. The default Play action opens the TUI inside the authenticated site
shell. Keep essential player actions, character creation/selection, journal,
party gathering, commerce and discovery available inside that TUI over SSH too.
Initial account/key enrollment may use the website; ordinary play must not
require bouncing through web-only screens.

Use the existing authenticated live_session and browser authentication pipeline
for the shell and play mount. Pass `current_scope` to `Layouts.app` and contexts;
authorize before starting a renderer or sending a cell snapshot. An embedded
LiveComponent is justified here only when the chosen integration requires its
lifecycle; it is not a reason to split every screen into LiveComponents.

The browser hook lives in the existing app.js/app.css bundles. Give a hook-owned
grid a unique DOM ID and `phx-update="ignore"`. Preserve server-rendered controls
outside it for help, focus/escape and connection status. Implement only the
verified integration contract; do not assume native wrapper components handle
Genesis authentication or revocation for us.

## Input, safety and accessibility

- Normalize keyboard, paste, mouse/touch selection and resize into one bounded
  TUI input vocabulary. Document minimum dimensions and small-screen layout.
  Restrict hotkeys to a focused Play surface; tab switching must not submit or
  repeat game actions. Support browser text entry/IME and visible focus escape.
- Reuse authenticated attachment tokens/capabilities; never trust a client PID,
  actor ID, role, terminal size or navigation destination. Bound input length,
  frames, dimensions and update frequency; coalesce output for slow consumers
  without dropping committed world events or inventing successful actions.
- Escape user/NPC text for its destination. The browser must never treat cell
  contents as raw HTML. SSH must reject embedded terminal controls, including
  OSC clipboard operations. Do not execute URLs, shell commands or arbitrary
  browser navigation emitted in content. No shell/exec/forwarding/SFTP access is
  needed for the game; Erlang distribution is not a player transport.
- Check membership/key/session revocation on live attachments and reconnect.
  Clear stale visible cells on role/actor changes before re-rendering; a reduced
  projection must not leave old secret text in a diff buffer. Reconnect uses a
  full authorized snapshot before deltas resume, with stale-frame fencing.
- A painted character grid is not automatically accessible. Provide labelled
  help, controls and an authorized linear text/action alternative driven by the
  same presentation model and intents, not a second rules/UI workflow. Test
  keyboard-only play, zoom/narrow layouts, copy/paste and an actual assistive
  reading path. Do not claim mobile/screen-reader usability from headless tests.

## Evidence before handoff

Phase 11 requires real mixed-client play: two SSH terminals plus a browser Play
tab, as well as two independent browser tabs. Test contested actions, different
knowledge, identical contextual outcomes, identity/permission changes and
disconnect/reconnect. Reproduce resize, focus loss, paste, tab hiding/showing,
missed deltas and terminal cleanup without leaking or duplicating state.

Headless TUI tests prove shared rendering/input; LiveView tests prove authenticated
mounts and socket payloads; actual browser interaction proves the JS bridge and
layout; real SSH tests prove daemon auth and terminal behavior. None substitutes
for the others. Record versions, commands, operating systems and visual/manual
evidence. All later player-facing phases extend this one TUI and rerun both hosts.
