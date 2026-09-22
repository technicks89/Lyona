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
upstream fix exists yet (issue is open, unassigned).

**Investigated (2026-09-22), not reproduced.** Ran `scripts/theme-apply.sh` for
real (not stubbed) under an isolated `HOME`/XDG set, for every one of the 10
shipped dark presets (`nord`, `dracula`, `gruvbox`, `catppuccin`, `tokyonight`,
`onedark`, `solarized`, `rosepine`, `everforest`, `monochrome`), after
generating their GTK themes with `lyona-gtk-theme generate-all`:

- Every preset's `[theme.<id>]` section has both `dark_mode = true` and a
  matching `gtk_theme = "Lyona-<id>"` — no missing or misspelled key for any
  of them.
- `lyona-gtk-theme generate-all` produced a `gtk-3.0/` and `gtk-4.0/` directory
  for every one of the 10 (`gtk_theme_available()` finds all of them).
- `theme-apply.sh` wrote `gtk-theme-name=Lyona-<id>` and
  `gtk-application-prefer-dark-theme=1` into both
  `~/.config/gtk-3.0/settings.ini` and `~/.config/gtk-4.0/settings.ini`, and
  also set `org.gnome.desktop.interface gtk-theme`/`color-scheme` via
  `gsettings` and `/Net/ThemeName` via `xfconf-query`, for all 10 presets — no
  outlier.
- The generated `Lyona-<id>/gtk-3.0/gtk.css` imports Adwaita's own
  `gtk-contained-dark.css` as its base and only recolours named custom
  properties on top, so it inherits Adwaita-dark's full widget coverage
  (including whatever Thunar-specific styling Adwaita-dark already has)
  rather than being a partial theme with gaps.

In other words: every mechanism Lyona has for telling a GTK app "use this dark
theme" is wired correctly and fires for every dark preset, confirmed by
reading the actual files/settings a fresh GTK3/4 process reads at startup.
Launching a real `thunar` process under Xvfb to visually confirm the render
was attempted but blocked on getting an unconfigured `dwm` (no `hotkeys.toml`/
window rules in the sandbox) to actually map and size Thunar's window for a
screenshot — an artifact of the throwaway test rig, not evidence about the
theme code. **Given the config-writing side is now verified correct**, the
two remaining explanations worth checking on a real desktop are:

1. **An already-running Thunar doesn't live-reload.** GTK3/4 apps pick up
   `gtk-theme-name` from `settings.ini` at startup and from `gsettings` live
   *if* they're watching that schema; Thunar's own behaviour here is unverified.
   The issue's own acceptance criteria already anticipates this
   ("with any required application restart clearly explained"), which is a
   strong hint upstream expects this to be at least part of the answer.
2. **Something specific to the reporter's real environment** (a stale user
   `~/.config` from before a preset switch, a distro Thunar build with its own
   theme override, GVFS/xfconfd differences) that this isolated reproduction
   cannot surface.

**Next step, and how to confirm nothing breaks:** a maintainer with a real
session should select Dracula, restart Thunar, and screenshot it — much
faster there than continuing to fight a throwaway Xvfb+dwm rig here for the
same answer. If it turns out to be (1), the fix is documentation (surface the
"restart to apply" note somewhere in Settings > Appearance) plus, optionally,
a `pkill -HUP thunar`-style nudge in `theme-apply.sh` if XFCE session tooling
makes that safe. If a real screenshot instead shows an actual rendering gap,
narrow it to the specific preset(s) and widget(s) first, then a test that
applies that preset and asserts the GTK/Thunar-visible setting (already
proven correct here) *and* the process's rendered pixels.

## S6-03: Hover states that hide text in light themes

Issue `#349`. Same shape as S6-02.

**Investigated (2026-09-22), not reproduced, one candidate found.** Checked
the generated GTK CSS for all 5 shipped light presets (`catppuccin-latte`,
`gruvbox-light`, `solarized-light`, `rosepine-dawn`, `tokyonight-day`):

- Every light preset correctly imports Adwaita's *light* `gtk-contained.css`
  (not the dark variant) as its base.
- The explicit `button:hover`/`menuitem:hover` rules the generator writes use
  palette-derived colours (`@lyona_overlay`, `@lyona_accent`) for every
  preset, not a hardcoded dark value — nothing obviously wrong there.
- None of the 5 presets define their own `row:hover`/`treeview:hover` rule at
  all, so list/icon-view hover (what a file manager's own listing mostly
  uses) falls through entirely to Adwaita's own light-mode hover, which
  computes a low-opacity tint from `@theme_fg_color` — a colour every one of
  these presets *does* override (`normfgcolor`, all reasonably muted dark
  tones, `#3C3836`-`#657B83`-ish; no outlier that stands out as too saturated
  or too dark relative to the others).

Nothing here points at an obvious bug in what Lyona generates; the remaining,
unverified possibility is that Adwaita's own light-mode row-hover alpha,
combined with a *specific* preset's fg/bg pairing, crosses a contrast
threshold that a plain colour-token read doesn't catch (this needs a real
render, not just CSS values, to settle) or that the issue is really about
Quickshell's own panel/pane hover states (`Theme.qml`) rather than GTK apps at
all — the issue doesn't say which.

**Next step, and how to confirm nothing breaks:** a maintainer reproduction
(screenshot, which preset(s) and which specific control) is what actually
unblocks a fix here, the same as S6-02. Once narrowed: for the GTK side, a
computed-contrast check across `row:hover`/`button:hover` pairs added to
`tests/test-lyona-gtk-theme.sh`; for the Quickshell side, a
`tests/test-quickshell-design-system.sh`-style contrast check (Lyona already
has precedent for contrast assertions from the accessibility work) for
hover-state foreground/background pairs would give this permanent
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
