# Getting Started

> lyona is an Arch Linux-only X11 desktop. These instructions assume a
> supported Arch installation completed through the Arch install medium or
> `install.sh`.

After installing, the first thing to know: **Super** = the Windows key.

Press <kbd>Super</kbd> + <kbd>/</kbd> at any time to open the interactive keybind viewer.

## Essential Actions

| Action | Keys |
|--------|------|
| Open Alacritty terminal | `Super` + `X` |
| App launcher (Quickshell) | `Super` + `R` |
| Close window | `Super` + `Q` |
| Power menu | `Super` + `Ctrl` + `Q` |
| Control Center | `Super` + `F1` |
| Keybind viewer | `Super` + `/` |

## Switching Tags (Workspaces)

Tags 1-9 act as workspaces. Use `Super` + a number from `1` through `9` to switch.
`Super` + `0` shows windows from all nine tags at once; `0` is not a tenth tag.

| Action | Keys |
|--------|------|
| Switch to tag | `Super` + `1`–`9` |
| Move window to tag | `Super` + `Shift` + `1`–`9` |
| Show all tags | `Super` + `0` |

## Layouts

Three layouts are available — switch between them instantly.

| Layout | Keys |
|--------|------|
| Tiling (master + stack) | `Super` + `T` |
| Floating | `Super` + `F` |
| Monocle (one window at a time) | the Control Center; no default key |

The Control Center (`Super` + `F1`) has a **Window layout** row with all three:
the current layout is highlighted, and each tag keeps its own.

For one window rather than the whole layout: `Super` + `M` makes the focused
window fullscreen, and `Super` + `Shift` + `M` floats it, or tiles it again.

### The window overview

`Super` + `O` shows every open window, on every tag and monitor, as a card with
a preview. Type to narrow the cards by title or class; `Up`, `Down`, `Home` and
`End` move the selection; `Enter` or a click goes to that window, on its tag;
`Ctrl` + `W` or a card's close button asks the window to close, as `Super` +
`Q` would; `Escape` closes the overview. With more than one monitor, each card
says which monitor its window is on.

See [Keybindings](./keybinds.md) for the full reference.
