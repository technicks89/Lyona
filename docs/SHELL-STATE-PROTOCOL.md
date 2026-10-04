# Shell State Protocol

How dwm and the managed Quickshell shell share state, beyond standard EWMH:
dwm's own root-window properties, and the DPI state file Settings writes.
Changing any of these is a change to both sides; keep this document, `dwm.c`,
`scripts/dwm-quickshell-state` and the QML that reads them in step (Sync
Sprint 16 R16-51).

## X root-window properties

dwm sets these on the root window. `dwm-quickshell-state watch` follows them,
and each client's title, class and tag, through one `dwm-xwatch` process
(`PREFIX/lib/lyona/dwm-xwatch`, which prints `root PROPERTY` or `window 0xID`
for each change), re-reads only what changed, and prints the shell's state
lines; QML never reads X itself. Without `dwm-xwatch` it falls back to one
`xprop -spy` per window (`DWM_STATE_WATCHER=spies` forces that).
The standard EWMH properties (`_NET_CURRENT_DESKTOP`, `_NET_CLIENT_LIST`,
`_NET_ACTIVE_WINDOW`, `_NET_WM_DESKTOP` and the others) are read the same way
and are not repeated here.

"Logical monitor index" is the monitor's position in dwm's monitor order, the
order the shell's panels use. A tag index is 0 to 8.

| Property | Type | Written by dwm when | Value |
| --- | --- | --- | --- |
| `_DWM_MONITOR_DESKTOPS` | `INTEGER`, 5 per monitor | the selected tag changes on any monitor, or monitors change | for each monitor, by logical index: x, y, width, height, and its first selected tag |
| `_DWM_SELECTED_MONITOR` | `CARDINAL`, 1 | the selected monitor changes | the selected monitor's logical index |
| `_DWM_LAYOUT` | `CARDINAL`, 1 | the selected monitor's layout changes | an index into dwm's `layouts[]` |
| `_DWM_FULLSCREEN_MONITORS` | `CARDINAL`, 0 or more | a window enters or leaves fullscreen | the logical indexes of the monitors showing a fullscreen window; empty when none |
| `DWM_TAG_UPDATE` | `CARDINAL`, 1 | any window's tags change | a sequence number, increased each time; its value means nothing, a change means "read `_NET_WM_DESKTOP` again" |

A write does not always mean a change: dwm writes `_DWM_LAYOUT` and
`_DWM_FULLSCREEN_MONITORS` only when they change, but may write the others again
with the same value, so a reader compares before acting.

### Requests from the shell

| Property | Type | Set by | Effect |
| --- | --- | --- | --- |
| `_DWM_SET_LAYOUT` | `CARDINAL`, 1 | `dwm-quickshell-state layout INDEX` (the panel's layout switcher) | dwm reads it, deletes it, and applies `layouts[INDEX]` to the selected monitor, as the layout key would. An index out of range, or a value of another type or length, is ignored. |

Any X client can set a root property; that is the same trust as the EWMH
client messages dwm already accepts.

## DPI state file

`dwm-settings-display` publishes the session's DPI whenever it applies one
(start-up, a change in Settings, a reset), and the shell scales to it
(`shell.qml`, `Theme.applyDisplayDpi`). The shell watches the file; it never
calls the helper for this.

- **Path:** `$XDG_RUNTIME_DIR/dwm-settings-display/dpi.current`. The directory
  is the user's, mode 0700; the file is mode 0600, replaced whole (written
  beside it, then renamed), so a reader never sees half of it.
- **Format:** tab-separated lines:

  ```text
  dpi-state-protocol	1
  dpi	DPI
  ```

  `DPI` is an integer from 72 to 384; a value outside that range means 96.
  With no file the shell uses 96, and a file without the version 1 header is
  ignored, leaving the scale as it was.
