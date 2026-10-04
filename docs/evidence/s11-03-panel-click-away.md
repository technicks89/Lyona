# S11-03 -- clicking the empty panel closes open popups

Plan: `docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md#s11-03-clicking-the-empty-panel-closes-open-popups`. Issue `#154`.

## What it actually changes

The plan said an outside click on the bar does nothing. Reading `tests/test-panel-popup.py`
showed that a click on the bar already dismisses a `ClickAwayPopup`, because those popups
hold an input grab. What does not close on a bar click is everything that is a plain
floating window: the launcher, the command menu, notification history and the control
center's utility windows. `selectPanelPopup(panel, "")` already closes all four for an
empty popup id; nothing asked for it from the bar background. The change is the
`MouseArea` (upstream's hunk from `ebe57c6`, which applied unchanged):

```qml
        MouseArea {
            anchors.fill: parent
            onClicked: root.popupRequested(root, "")
        }
```

## Results (2026-09-26, CachyOS, working tree, nothing committed)

- `check-quickshell-panel-menus`: PASS, now also pinning the `MouseArea` and the four
  closers in `selectPanelPopup()`. Removing the `MouseArea` makes the pin fail.
- `tests/test-panel-popup.py` (real clicks under Xvfb, with a stub panel): PASS.
- `check-quickshell-command-menu`, `check-quickshell-qml`: pass.

## Not verified

No test drives the real `DwmPanel` (it takes eleven models). By hand: open the launcher
and click an empty part of the bar (it should close); click a bar button such as the
control center (it should still open); open notification history and click the bar.
