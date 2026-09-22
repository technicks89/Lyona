# lyona Patch Ownership and Invariants

This document records the major patched subsystems in `dwm.c` before Phase 4
refactoring. "Owner" means the source area that owns the behavior and must stay
authoritative when code is regrouped or extracted.

## EWMH

Owner: root-window and client property handling in `dwm.c`, including atom
setup, desktop metadata, active-window state, client lists, and fullscreen
messages.

Invariants:

- `_NET_SUPPORTED`, `_NET_CLIENT_LIST`, `_NET_NUMBER_OF_DESKTOPS`,
  `_NET_CURRENT_DESKTOP`, `_NET_DESKTOP_NAMES`, `_NET_DESKTOP_VIEWPORT`, and
  `_NET_ACTIVE_WINDOW` must reflect the current monitor/tag state after setup,
  client management changes, focus changes, and tag switches.
- `_DWM_MONITOR_DESKTOPS` must expose `x`, `y`, `width`, `height`, and current
  desktop tuples in the same logical order used by monitor tag ownership.
- Cross-monitor tag changes must update selected monitor state, focus, cursor
  placement, and EWMH current desktop together.
- Property updates must be synchronous with state changes and must not add
  blocking work to the X event loop.
- External bars must be able to reconstruct tag and client state from root
  properties without relying on dwm internals.

Regression coverage:

- `make check-xvfb-runtime` validates startup EWMH state, focus, tag switching,
  fullscreen requests, and client-list behavior.
- `make check-monitor-tags` validates the cross-monitor source path for EWMH
  tag handoff.

## Pertag

Owner: monitor state, tag selection, layout selection, and view/toggle-view
paths in `dwm.c`.

Invariants:

- Each monitor owns independent per-tag layout, master count, master factor,
  selected layout, and visibility state.
- Switching tags must restore the target tag state before arranging windows.
- The all-tags view must not corrupt the remembered current or previous tag.
- Pertag state must stay attached to its monitor and must not be shared across
  monitor instances.

Regression coverage:

- `make check-xvfb-runtime` validates tag switching in a live Xvfb session.
- `make check-monitor-tags` validates the cross-monitor tag-switching source
  path.

## Swallowing

Owner: client process tracking and swallow/unswallow paths in `dwm.c`.

Invariants:

- Only terminal clients with process ancestry to the launched client may swallow.
- Rules with `noswallow` must prevent swallowing for matching clients.
- Floating swallow behavior must respect the `swallowfloating` setting.
- Unswallowing must restore the terminal client without losing monitor, tag,
  layout, or focus consistency.
- Missing process information must skip swallowing rather than guessing.

Regression coverage:

- No direct automated swallowing regression exists yet. Refactors that touch
  this path need either a focused process-tree test or manual X11 validation.

## Systray

Owner: systray window management, tray icon reparenting, bar geometry, and
Rofi-era bar-facing monitor behavior in `dwm.c` plus Rofi-era bar launch configuration.

Invariants:

- The tray belongs to the primary bar path and must not duplicate across
  secondary monitors.
- Missing tray-capable desktop components must not prevent dwm startup.
- Tray icon mapping, unmapping, and geometry changes must keep bar layout
  stable.
- Systray code must stay optional and must not become a dependency for core dwm
  behavior.

Regression coverage:

- `make check-session-guards` validates optional startup behavior.
- Rofi-era bar capability checks cover missing desktop components, but live tray icon
  behavior still requires runtime validation.

## Fullscreen

Owner: fullscreen state transitions in `dwm.c`, including EWMH fullscreen
messages, fake fullscreen, layout interaction, and focus rules.

Invariants:

- EWMH fullscreen requests must update client state and X properties together.
- Fake fullscreen must preserve tiling state while making the client appear
  fullscreen according to the configured mode.
- Focus locking for fullscreen clients must respect the configured
  `lockfullscreen` behavior.
- Fullscreen transitions must not strand border, geometry, monitor, or tag
  state when toggled repeatedly.

Regression coverage:

- `make check-xvfb-runtime` validates EWMH fullscreen handling in a live Xvfb
  session.

## Icons

Owner: `_NET_WM_ICON` parsing, client icon storage, and draw paths in `dwm.c`
and `drw.c`.

Invariants:

- `_NET_WM_ICON` data must be bounds checked before reading width, height, or
  pixel data.
- Missing, empty, or truncated icon properties must leave the client managed and
  must not terminate dwm.
- Icon allocation failures must fall back to no icon without corrupting client
  state.
- Drawing code must tolerate clients without icons.

Regression coverage:

- `make check-xvfb-runtime` validates missing hints and malformed
  `_NET_WM_ICON` data.

## Runtime TOML

Owner: runtime configuration loading, inotify reload, and applied hotkey, theme,
and rule state in `dwm.c` plus `tomlparser.c`.

Invariants:

- User runtime files live under
  `${XDG_CONFIG_HOME:-$HOME/.config}/lyona/`.
- `hotkeys.toml`, `themes.toml`, and `window-rules.toml` reload independently
  when changed.
- A failed reload must report the invalid file and keep the last valid runtime
  state.
- Defaults may seed missing files, but reloads must not overwrite user-owned
  configuration.
- Theme application may spawn helper work asynchronously; config parsing itself
  must not block the event loop for long-running operations.

Regression coverage:

- `make check-xvfb-runtime` validates hotkey TOML reload and invalid reload
  preservation.
- `make check-install-preservation` validates user runtime TOML preservation
  during repeated installs.

## Stacking and floating geometry

Owner: `restack()` and `restackprioritywindows()` (with `raisefloatingclients`,
`raiseselectedclient`, `raisealwaysontopclients`, `raisefullscreenclients` and
`restackraisesselected`), and, for geometry, `setfloating()`,
`shrinkfloating()` and `setlayoutshrink()` in `dwm.c`.

Invariants:

- `restackprioritywindows()` raises in a fixed order, later steps ending up on
  top: floating clients (except always-on-top, `_NET_WM_STATE_ABOVE` and visible
  fullscreen ones), the selected client where `restack()` raises it, always-on-top
  and EWMH-above clients, the bar and tray of every monitor without a visible
  fullscreen client, override windows flagged to raise, and visible fullscreen
  clients last.
- "`restack()` raises the selected client" is one predicate,
  `restackraisesselected()`: the client is floating, or the layout is the
  floating one. `restack()` and `raiseselectedclient()` both use it, so they
  cannot disagree. A tiled selected client stays below floating clients and
  below popups an application raised itself.
- The mechanism and the policy of going floating are separate:
  `setfloating(c, shrink)` toggles the client, and `shrink` alone decides whether
  a tiled client pops out smaller. Keys and buttons (`togglefloating`) pass 1;
  the mouse-drag paths pass 0 and keep the geometry the drag started from. No
  caller signals the policy through a NULL `Arg`.
- A tiled client that pops out (explicitly, or when the floating layout is chosen
  from an arranged one) is scaled to `FLOATSHRINKPCT` percent (85 by default,
  `config.def.h`; `dwm.c` falls back to 85 for an older `config.h`), kept
  inside the work area and within its size hints, and centred on the tile it had.
  Fixed-size and fullscreen clients are not shrunk, and choosing the floating
  layout again does not shrink the windows a second time.

Regression coverage:

- `make check-xvfb-runtime` validates the pop-out size and centring, retiling,
  the floating-layout shrink, and the stacking order in a live Xvfb session.
- `make check-dwm-roundtrips` pins that the selected client is raised after the
  floating pass.
- `make check-dwm-floating-guards` pins the structure above: the shared
  predicate, `setfloating` and its callers, the named constant and its default,
  and that a `config.h` without the constant still builds.

## Phase 4 Refactor Rules

- Preserve the existing test coverage before extracting code.
- Add direct tests or Xvfb coverage for any subsystem whose invariants are
  changed.
- Keep X event-loop paths nonblocking.
- Keep extracted interfaces narrow: the caller should request an EWMH update,
  TOML reload, or client-state transition without exposing unrelated globals.
- Do not increase the default runtime dependency footprint.
