# S9-03 -- overview accessibility and keyboard operability

Plan: `docs/sprints/SYNC-SPRINT-9-OVERVIEW-POLISH.md#s9-03-accessibility-pass`. Issue `#350`.

## Findings from the audit

- The monitor label on a card had never rendered since S8-02: the card read a `monitorCount` that nothing provided.
  `OverviewModel` now has `monitorCount` (from `dwmState.monitorCount()`) and the card gets it, with `tagLabel`.
- The close button is shown only on hover or selection, so a keyboard user had no way to close a card. Ctrl+W now
  calls `OverviewModel.closeSelected()`, from both the popup and the search box (the search box holds focus, so it has
  its own handler); the hint line reads "Up/Down move, Enter switch, Ctrl+W close, Esc dismiss".
- A keyboard selection could move out of the visible part of the list. `revealCard()` scrolls it into view, including
  the tag heading when the selection is the first card of a group.

## Change

- Card: `Accessible.role: ListItem`, name = the window title, description "Tag N, <class>[, monitor M]", `selected`,
  and a press action that focuses the window. Close button: role Button, name "Close <title>", press action closes.
  Popup content: role Dialog, name "Window overview"; search: name "Search windows".

## Verification

- `tests/test-quickshell-accessibility.sh` pins the roles, names, description, press actions and exactly two Ctrl+W
  branches. `tests/qml/OverviewInteraction.qml` (45 assertions) reads the real `Accessible.*` values, the monitor label
  with one and two monitors, and the close button's visibility and glyph colour.
- `tests/test-overview-keyboard-xvfb.py` (`make check-overview-keyboard-xvfb`): real dwm and Quickshell, real key events
  from `xdotool`, no mouse event. Down, End, Home, typing "kit" into the search box, Down, Ctrl+W (closes `0x3`, the
  popup stays open), Return (focuses `0x1`, closes), reopen, Escape.
- The pins in `test-quickshell-overview.sh` and `test-quickshell-accessibility.sh` cover the Ctrl+W branches, the
  `monitorCount` binding and the `revealCard` call; the load test's Home/End checks fail without the scrolling.
- Not verified: a screen reader (Orca) announcing the items, multi-monitor labels on two real monitors, and the
  high-contrast palette by eye.
