# Sync Sprint 6 — Theme consistency and a cross-tag window overview

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Upstream re-surveyed at
`6258133` (2026-09-21), `d155edc..6258133`: 4 non-merge commits (2 dependabot,
excluded — not Chris's), and 7 new issues Chris opened the same day, `#344`
to `#350`.

**Goal:** the small, real part of that range that applies to Lyona, and the
record of why the rest does not. Unlike Sprints 1–5, most of this range has
**no upstream fix yet** — these are freshly opened issues, not merged PRs, so
S6-02 through S6-04 below are tracking items (implement Lyona's own fix; there
is nothing to port) rather than ports.

| Item | Upstream | Kind | Size |
| --- | --- | --- | --- |
| [S6-01](#s6-01-live-panel-tooltip-position-on-window-resize) | `2461027` (`#343`) | Port, small | ~+5 code |
| [S6-02](#s6-02-thunar-and-other-gtk-apps-stay-light-under-dark-themes) | issue `#348` | Lyona's own fix (no upstream code) | unscoped until reproduced |
| [S6-03](#s6-03-hover-states-that-hide-text-in-light-themes) | issue `#349` | Lyona's own fix (no upstream code) | unscoped until reproduced |
| [S6-04](#s6-04-cross-tag-window-overview) | issue `#350` | Lyona's own feature (no upstream code) | large; needs its own design pass |

Not taken: see [Declined](#declined-from-this-survey).

---

## S6-01: Live panel tooltip position on window resize

Upstream `2461027` (`#343`, "restore Fedora Quickshell lint and validation
gates" — the commit is mostly Fedora-only `qmllint` pragma comments for
warnings Lyona already tolerates as non-fatal, and one QML component
extraction Lyona has no reason to need; see Declined). One hunk in that commit
is a real, small, portable fix:

`config/quickshell/core/PanelTooltip.qml` binds `anchor.rect.x` once, as a
plain value (`anchor.rect.x: 0`), and only recomputes it from inside
`anchor.onAnchoring`, an event handler that fires when Quickshell decides to
re-anchor — not on every geometry-relevant change. Upstream turns it into a
live property binding instead, so it tracks `root.anchorWindow.width`,
`root.width` and `root.anchorX` directly:

```qml
anchor.rect.x: Math.round(Math.max(0, Math.min(root.anchorWindow.width - root.width,
                                             root.rightAligned ? root.anchorX - root.width : root.anchorX))) | 0
```

with the old imperative assignment removed from `anchor.onAnchoring` (which
keeps only the `anchorX`-computing lines).

**Why this matters for Lyona:** `PanelTooltip.qml` is unchanged from the
pre-fork baseline and has the identical structure, so the same staleness is
possible here: a tooltip anchored near a screen edge could clip if the
anchor window resizes (a DPI change, a monitor hot-plug) between anchoring
events, since the x position would not be recomputed until the next
`onAnchoring` fires.

**How to confirm nothing breaks:** a `tests/test-quickshell-*.sh` or `.inc`
case that anchors a `PanelTooltip` near the right edge, resizes/rescales the
anchor window without a fresh `onAnchoring` event, and asserts
`anchor.rect.x` (or the tooltip's rendered `x`) updates to stay clamped
inside the window — something the current test suite has no coverage for
either way, so this needs new coverage, not just a port. `make
check-quickshell-qml check-quickshell-design-system` and whichever panel
test ends up covering it.

## S6-02: Thunar and other GTK apps stay light under dark themes

Issue `#348`. Reported against Dracula and "a few other dark presets"; no
upstream fix exists yet (issue is open, unassigned). **Not started**: needs
reproduction on a real or nested X11 session with Lyona's actual shipped
theme presets (`scripts/lyona-gtk-theme` and friends) before any fix is
designed, since the issue itself says the affected preset list is still being
narrowed. Likely area: `scripts/lyona-gtk-theme` / `scripts/theme-apply.sh`'s
GTK3/GTK4 mapping for Dracula-family presets, and whether Thunar's own
`gsettings`/`xfconf` schema picks up the applied `gtk-theme-name` the same way
other GTK apps do.

**How to confirm nothing breaks:** reproduce first (screenshot evidence, per
the issue's own acceptance criteria), then a test that applies each shipped
dark preset and asserts the GTK/Thunar-visible setting matches, plus a
regression case for whichever preset(s) turn out affected.

## S6-03: Hover states that hide text in light themes

Issue `#349`. Same shape as S6-02: reported, not yet reproduced against
Lyona's presets, no upstream fix to port. Likely area: `Theme.qml`'s
light-preset hover color tokens (`Theme.controlHoverFill` or equivalent) and
whatever text-color token is expected to stay legible over it; Lyona's own
Quickshell theme system is independent of upstream's GTK-only theming, so
this may not even reproduce the same way here — reproduction decides that.

**How to confirm nothing breaks:** reproduce across the shipped light presets
first; a `tests/test-quickshell-design-system.sh`-style contrast check (Lyona
already has precedent for contrast assertions from the accessibility work)
for hover-state foreground/background pairs would give this permanent
coverage instead of a one-off visual check.

## S6-04: Cross-tag window overview

Issue `#350`, a genuinely new feature (a "Mission Control"-style overview of
windows across every tag, click to switch and focus). No upstream code exists
to port — Chris opened this the same day as `#348`/`#349` with no PR yet.
This is the largest item in this survey by far and needs its own design pass
(a new Quickshell surface, dwm-side IPC or root-property exposure of
cross-tag window state, keyboard navigation, multi-monitor handling) before
any implementation estimate is meaningful. **Not started; recommend scoping
as its own follow-up document (`design/CROSS-TAG-OVERVIEW.md` or similar)
once someone picks it up, rather than folding a large new-surface design into
this sprint doc.**

---

## Declined from this survey

- **Dependabot commits** `58d10b82d` (`github/codeql-action` bump),
  `513d4103e` (`withastro/action` bump): not Chris's; Lyona's own CI already
  manages its own action pins independently.
- **`62581338` "chore: test update delivery"**: zero file changes (an empty
  commit exercising upstream's own release/update delivery mechanism). N/A.
- **The rest of `2461027` (`#343`)**: Fedora-only `qmllint` pragma comments
  (`// qmllint disable signal-handler-parameters`, `// qmllint disable
  missing-type`) for warnings Lyona's own `check-quickshell-qml` already
  treats as non-fatal (seen throughout this repo's own lint output, e.g.
  `QProcess::ExitStatus ... [signal-handler-parameters]`), so silencing them
  buys nothing Lyona's CI does not already tolerate. The `RunningAppsArea.qml`
  `state` → `desktopState` rename avoids a Fedora-Quickshell-specific
  shadowing warning Lyona's toolchain does not raise. The
  `SystemRegionalControls.qml` `Repeater { delegate: Rectangle {...} } ` →
  `component CatalogCard: Rectangle {...}` extraction exists only so a
  Fedora-strict `qmllint` can type-check `catalogRepeater.itemAt(index) as
  CatalogCard`; Lyona's own file is structurally identical to upstream's
  *pre*-fix version and works today. The one substantive-looking line
  (`installed.length` → `String(matched).length` in a font-matching helper)
  does not apply: Lyona has no such function (`Qt.fontFamilies()` font
  matching is not present in `AppearanceModel.qml`).
- **`#344`–`#347`**: Fedora `DNF`/kickstart installer items (post-install
  updates, `fastfetch` seeding, default-Yes update prompts, mirror
  optimization). N/A — Arch/CachyOS has no DNF or kickstart, and Lyona's own
  `install.sh`/`lyona-cachyos` already cover the equivalent groundwork with
  `pacman`.

---

## Verification

Same gates as every sprint (see [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#verification)):
`scripts/run-tests make clean all`, `check-shell`, `check-format`,
`check-quickshell-qml`, then `scripts/run-tests make check` before the sprint
closes, and the manual **Full suite (manual)** workflow on the sprint branch
and on `main`.
