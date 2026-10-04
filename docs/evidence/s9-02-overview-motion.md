# S9-02 -- overview motion and visual polish

Plan: `docs/sprints/SYNC-SPRINT-9-OVERVIEW-POLISH.md#s9-02-motion-and-visual-polish`. Issue `#350`.

## Change

- `OverviewCard.qml`: every colour is a `Theme` token. The fill and border come from
  `menuSelectedBackground`, `controlHoverFill`, `controlNormalFill` and the border tokens; the title and class text use
  the matching text roles (`menuSelectedText`, `controlHoverText`, `controlNormalText`, added in S11-01) so a light
  palette stays readable. The close button's glyph uses `Theme.readableText(Theme.textStrong, Theme.danger)` on hover.
  `Behavior on color` and `Behavior on border.color` use `ColorAnimation { duration: Theme.animationFast }`.
- `WindowOverview.qml`: the popup content fades in and out with `Behavior on opacity`, `Theme.animationNormal`,
  and `Easing.OutCubic`. The window stays mapped until the fade-out finishes; input is disabled and its focus grab
  released as closing starts. Reopening during the fade reverses it. Reduced motion hides the popup immediately.
  Scrolling a keyboard selection into view uses a `NumberAnimation` on `contentY` with the same token.
- `Theme.animationFast` and `animationNormal` are `0` under `reducedMotion`, so the change is instant, not skipped.

## Verification

- `tests/test-quickshell-overview.sh`: no literal hex colour in the overview, the three text roles, both
  `Behavior` lines, `duration: Theme.animationNormal`, and no fixed `duration: <number>`.
- `tests/qml/OverviewInteraction.qml`: a card in a real `FloatingWindow` changes from the normal to the selected
  fill; a positive control checks the colour is mid-transition shortly after the change, and with `reducedMotion` set
  the colour is already final on the next frame.
- Mutation check: replacing `Theme.animationFast` with `0` in the card makes the motion case fail; the unmutated
  card showed a mid-transition colour (`#544756`) as the positive control expects.
- Not verified: how it looks or feels by eye, and the fade under a real display server frame rate.

## Close-transition regression coverage

`tests/qml/OverviewInteraction.qml` checks that closing keeps the popup visible during the fade, hides it at
completion, passes through an intermediate opacity, survives reopening during the fade, and closes immediately
with reduced motion. Passed all 55 interaction assertions under Xvfb with Arch Quickshell 0.3.1 and Qt 6.11.2
via `scripts/ci-local.sh --each --targets 'check-quickshell-overview-xvfb check-overview-load-xvfb check-quickshell-qml'`.
The sandbox's Docker build/run commands used host networking because its default bridge is unavailable.
