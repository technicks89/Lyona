# Sync Sprint 9 — Cross-tag window overview: visual richness, accessibility, performance

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Continues
[Sprint 8](SYNC-SPRINT-8-OVERVIEW-INTERACTION.md), which finished the
overview's interaction model. Everything here is explicitly **beyond** the
design doc's first version — real per-window previews, motion, an
accessibility pass, and formal performance validation, none of which
upstream issue `#350` requires but all of which a "Mission Control"-style
surface is expected to have once it is more than a proof of concept.

**Depends on Sprint 8 (S8-01 through S8-04) being merged.** S9-01 is a
research spike: land it only if the spike confirms it is worth the
complexity, and say so plainly if it is not, the same honest-when-something-
does-not-pan-out standard the rest of this project's issue investigations
already hold to (see Sprint 6 S6-02/S6-03's own record of a dead end and a
fix).

| Item | Kind | Size |
| --- | --- | --- |
| [S9-01](#s9-01-live-per-window-thumbnails-a-spike) | New, research-first | spike, then ~+60 script/QML if it pans out |
| [S9-02](#s9-02-motion-and-visual-polish) | New | ~+30 QML |
| [S9-03](#s9-03-accessibility-pass) | New | ~+30 QML, ~+30 tests |
| [S9-04](#s9-04-idle-cpu-and-many-window-performance) | New | ~+40 tests |

---

## S9-01: live per-window thumbnails (a spike)

The design doc's Sprint 6 pass called this infeasible ("Quickshell/Lyona
does not have [a compositing capture path] today"). Re-checked while writing
this sprint, and it deserves a real spike rather than staying a closed
question:

- `dwm.c`'s `showhide()` moves an off-tag client far off-screen
  (`XMoveWindow(dpy, c->win, WIDTH(c) * -2, c->y)`); it does **not** unmap
  it. A window on another tag stays mapped, just positioned outside the
  visible screen area.
- A mapped window under a compositor (Lyona ships and configures Picom)
  keeps a live backing pixmap even while positioned off-screen, since
  compositing works per-window, not per-visible-region.
- `scripts/dwm-screenshot` already shells out to `maim`, which supports
  `maim --window <id>`-style capture of a specific window by id, not only a
  screen region — the exact capability this needs, already a dependency,
  already proven to work in this codebase for a different purpose.

Put together, per-window thumbnail capture for an off-tag window may
already work with the tools Lyona has, **without** the "second capture
protocol" the earlier assessment assumed was necessary. The spike is to
actually try it, not to reason about it further:

1. With Picom running, move a test window off-screen the way `showhide()`
   does, and confirm `maim --window <id>` (or the equivalent lower-level
   call, e.g. `import -window <id>` if `maim` itself does not resolve an
   off-screen window's pixmap in practice) still produces a real image, not
   a blank/black one.
2. If it works: a `dwm-quickshell-state thumbnail WINDOWID OUTFILE`-shaped
   action (or a small dedicated helper if the capture call needs different
   privileges/timing than the other actions), called on demand when a card
   scrolls into view or on an interval while the overview is open — not a
   thumbnail for every window all the time, to keep the idle-cost promise
   (S9-04) intact. Cache the last capture per window between overview opens
   so re-opening it is instant, and use a placeholder (today's icon+title
   card) as the first frame while a capture is in flight.
3. If it does not work (a black/stale image, permission trouble, or a
   compositor timing issue that makes it unreliable): document exactly what
   was tried and why it failed here, close this item as decided-against, and
   the icon+title card stays the permanent design — that is a legitimate,
   documented outcome, not a failure to finish the sprint.

**Verification, if it lands:** an xvfb+Picom case capturing a known test
window's thumbnail and asserting the result is a real image (non-uniform
pixel content, not blank) of roughly the right dimensions; a case confirming
an off-tag window's thumbnail still resolves (the actual scenario this
whole item exists for); the idle-cost check from S9-04 re-run with the
overview open and several thumbnails cached, to catch a spike's `maim`/
capture calls turning out more expensive than assumed.

## S9-02: motion and visual polish

- Open/close transitions and hover/selection state changes consistent with
  the motion language Lyona already uses elsewhere (the launcher, panel
  popups), gated behind `Theme.reducedMotion` the same way every other
  animation in this app already is — not a new opt-out mechanism, the
  existing one.
- Card hover/selection visuals should reuse `Theme.controlHoverFill`/
  `Theme.controlFocusBorder`/etc. (the same tokens every other control in
  this app uses), not introduce new one-off colours for the overview alone.

**Verification:** a `tests/test-quickshell-design-system.sh`-style static
check that the new QML references `Theme.*` tokens for its interactive
states rather than literal colours (the pattern that test already enforces
elsewhere), and a case confirming `Theme.reducedMotion: true` disables the
transitions (an instant state change, not a skipped one — the same contract
`Theme.applyAccessibility()`'s existing consumers already have to meet).

## S9-03: accessibility pass

Lyona already has an established accessibility convention — `Accessible.role`/
`Accessible.name`/`Accessible.description` on `PanelToggleSwitch.qml`,
`ShellButton.qml`, and others, plus `Theme.highContrast`. This item is
applying that existing convention to the overview's new components, not
inventing a new one:

- Every card gets `Accessible.role: Accessible.ListItem` (or the closest
  fit for a "cell in a grid" semantic Qt Quick Accessible offers),
  `Accessible.name` set to the window's title, and a description including
  its tag ("Tag 3, Firefox — reddit.com" shape) so a screen reader
  announces enough to distinguish two windows of the same app.
- `Theme.highContrast` support: confirm the card/selection borders already
  route through `Theme.controlNormalBorder`/`controlFocusBorder` (S9-02
  should already have made this true, so this item's job here is auditing
  and fixing gaps, not building it from zero).
- A full keyboard-only operability audit: open the overview, filter (S8-03),
  navigate (S8-01), activate, close a card (S8-04), and dismiss — all
  without a mouse — confirming nothing added since Sprint 7 quietly requires
  one (the most likely gap: the close affordance from S8-04, added as a
  hover-revealed button, needs a keyboard-reachable equivalent here if S8-04
  itself did not already add one).

**Verification:** extend whatever static accessibility check this codebase
already runs (the same style of test that presumably checks
`PanelToggleSwitch.qml`'s `Accessible.*` properties today) to the new
overview components; a keyboard-only xvfb walkthrough of the full
open-filter-navigate-activate/close-dismiss sequence with no mouse events
sent at all.

## S9-04: idle-CPU and many-window performance

The design doc already flagged the idle-CPU requirement and a closed-popup
baseline as something to check once built (Sprint 7 took one manual
measurement). This item formalizes it into a standing, repeatable test
rather than a one-time manual check, and adds the scale dimension no earlier
sprint exercised:

- A closed-CPU baseline test: 30 s with the overview never opened vs. 30 s
  after opening and closing it several times, per `docs/UPSTREAM-SYNC.md`'s
  existing manual-qualification checklist item 4's own methodology, turned
  into an automated comparison rather than a manual one-off.
- A many-window, many-tag stress case: open enough `xclient`-style test
  windows across every tag to exceed what a normal desktop session would
  realistically have (dozens, not the 2-4 every earlier sprint's tests used),
  open the overview, and assert it still renders and responds to
  navigation/filtering within a reasonable time budget — this is where a
  naive (non-virtualized) `GridView`/`Flow` of cards would first show real
  cost, so this is also the point at which "does the card list need
  virtualization" gets answered with data instead of guessed at.
- If S9-01 (thumbnails) landed: confirm the on-demand/cached capture
  strategy actually keeps idle cost flat with many windows present but the
  overview closed (thumbnails are captured, if at all, only while the
  popup is open — this test is what proves that promise holds under load,
  not just in the small-scale case S9-01's own verification already checked).

**Verification:** the two automated tests described above, both new; no
existing target covers "the overview under load" today since no earlier
sprint had enough of the feature built to exercise it meaningfully.

---

## Verification (whole sprint)

Same gates as every sprint: `scripts/run-tests make clean all`,
`check-shell`, `check-format`, `check-quickshell-qml`, then `make check`
before the sprint closes, plus the **Full suite (manual)** workflow on the
sprint branch and on `main`. This is the sprint that closes out the cross-tag
window overview feature (issue `#350`) as a whole — its own closing note
should update `docs/UPSTREAM-SYNC.md`'s issue table to close `#350` locally
(upstream itself may still show it open, since there is no upstream fix for
Lyona to track against).
