# Sync Sprint 11 -- Shell text contrast, live theme broadcast, and the gaps a re-survey found

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Independent of Sprints 7 to 10.
It comes from a re-survey of `ChrisTitusTech/dwm-titus` (2026-09-26, upstream
`e5bbddc`, tag `v0.7.2`), plus a full-range check of every upstream commit,
issue and PR since the fork against what our docs account for. **Nothing in
this document has been started.** It waits for maintainer review. All three
design decisions are made (D-10 square popups and a 1 px focus ring, D-11 Qt
and GTK 2 theming, D-12 a layout switcher and a Picom corner-radius slider), so
no item is gated. Code in this document that says "validated" was run in a
scratch copy of the repository or in a throwaway worktree; none of it has been
applied to the repository.

| Item | Kind | Gate |
| --- | --- | --- |
| [S11-01](#s11-01-shell-text-stays-readable-on-hover-and-selected-surfaces) | Bug, completes S6-03 (`#116`) | none |
| [S11-02](#s11-02-broadcast-the-gtk-and-icon-theme-over-xsettings) | Port (`#351`, live half) | none |
| [S11-03](#s11-03-clicking-the-empty-panel-closes-open-popups) | Port (`#340`, click-away half) | none |
| [S11-04](#s11-04-keep-a-tests-bad-config-notification-off-the-real-desktop) | Test hygiene (`#354`, test half) | none |
| [S11-05](#s11-05-document-desktop-dependencies-and-install-profiles-for-arch) | Docs (`2a0e9b3`) | none |
| [S11-06](#s11-06-qt-palettes-for-qt5ctqt6ct-and-a-gtk-2-theme) | Bug plus port (`#352`, app-theme half) | none (D-11 decided) |
| [S11-07](#s11-07-square-popups-and-a-1-px-focus-ring) | Port (`#340`, geometry half) | none (D-10 decided) |
| [S11-08](#s11-08-a-layout-switcher-in-the-control-center) | New feature (issue `#297`) | none (D-12 decided) |
| [S11-09](#s11-09-a-picom-window-corner-radius-slider) | New feature (issue `#297`) | none (D-12 decided) |

Every item can start as soon as this is approved, and they are independent. If
you want an order: S11-04 (a test that leaks notifications) and S11-01 (the
contrast bug) first, S11-06 (Qt theming is broken for `qt6ct` users today) next,
then the rest. S11-08 is the only item that changes the dwm C core.

---

## What the re-survey found

Range surveyed: `d155edc..e5bbddc`, 10 non-merge commits (6 after our last
survey point `6258133`). Full-range check: all 183 upstream non-merge commits
since 2026-08-27 compared with every SHA and PR number in our docs and their
git history. 177 were already referenced. The 6 that were not:

| Commit | Upstream | Finding |
| --- | --- | --- |
| `37600c1` | test(quickshell): isolate missing nwg-look case | **Already solved.** `tests/test-quickshell-controlcenter.sh` restricts `PATH` to a `safe-bin` for that case. No work. |
| `498ebf5` | `#351` dark GTK themes and xsettings broadcast | Half superseded by our generated `Lyona-<theme>` themes (S6-02); the live broadcast half is **S11-02** |
| `b3c8f3d` | `#352` light theme hover contrast, GTK/Qt palettes | Quickshell half is **S11-01** (and is the real S6-03 root cause); app-theme half is **S11-06**, gated |
| `cb96c25` | `#354` unblock desktop updates, capture test notifications | Updater half N/A (D-8); test half is **S11-04** |
| `2a0e9b3` | docs: desktop dependencies and install profiles | **S11-05** |
| `e5bbddc` | `#355` Prepare 0.7.2 | N/A. Fedora DNF defaults, initial-update service, kickstarts (upstream issues `#344` to `#347`, already N/A) |

One more was found only by reading, not by the mechanical check: `#340`
(`ebe57c6`) is cited once in our CHANGELOG as "ported in part" (the launcher's
`OnlyShowIn`/`NotShowIn` filter, done as `#104`), but no sprint tracks its other
two halves. They are **S11-03** and **S11-07**.

Method limits, stated plainly: "referenced" means a SHA or PR number appears in
our docs or their history, which proves a decision was recorded somewhere, not
that it was a good one. The check covers the fork window (2026-08-27 onward);
older upstream history predates Lyona.

### Contributor work was never audited

`UPSTREAM-SYNC.md` said every issue and PR "opened by `ChrisTitusTech`" was
accounted for. Upstream has 286 PRs and 71 issues from 59 distinct authors (57 excluding bots). Since the
fork, non-maintainer items missing from our tables:

| Item | State | Disposition |
| --- | --- | --- |
| PRs `#340`, `#351` (contributor `Abs313a`) | merged | See above: S11-03, S11-07, S11-02 |
| PR `#353` DNF confirmations default to yes | closed | N/A (Fedora `dnf`) |
| PR `#357` / issue `#356` NetworkManager Wi-Fi plugin | open | **N/A for Arch, verified.** Fedora splits `NetworkManager-wifi`; Arch's `networkmanager` 1.58.1 hard-depends on `wpa_supplicant` and ships Wi-Fi support built in (`pacman -Si networkmanager`). Not tested on real Wi-Fi hardware. |
| Issue `#192` Wifi issues | closed | Same as `#356`; N/A |
| Issue `#187` 2K 200Hz monitor not working | closed, no fix | N/A: a hardware report against an upstream install, no code |
| Issue `#297` layout and scale settings in Quickshell | open | Feature request, no code: **D-12**, Future Evaluation |
| Issue `#298` AI agent skills for configuration | open | Declined. Upstream is pulling skills from a separate repo; Lyona has `AGENTS.md` |
| The maintainer's own pre-fork upstream items (`#90`, `#126`, `#127`, `#131` to `#133`) | closed | N/A (Debian, pre-fork) |

### Something that affects the person running the tests

`tests/test-xvfb-runtime.sh` writes a deliberately invalid `hotkeys.toml`
(line 692) and signals dwm, which runs `notify-send -u critical "dwm: bad
config"` (`dwm.c:3502`). The test uses a separate X display but inherits the
caller's D-Bus session, so **each run pops a critical notification on the real
desktop.** Upstream fixed the same problem in `#354`. See S11-04. Runs of
`make check` on a live desktop, including several during the Sprint 10 audit,
will have shown it.

---

## Decisions (all made 2026-09-26)

| ID | Decision | Item |
| --- | --- | --- |
| **D-10** | Square popups, and the keyboard focus ring goes to 1 px (same as the idle border). | S11-07 |
| **D-11** | Theme Qt apps and GTK 2 apps too, through our generator (option C), not upstream's 105 checked-in files. `gtk-dark.css` is dropped as unneeded. | S11-06 |
| **D-12** | A layout switcher in the Quickshell control center, and a Picom window corner-radius slider. **Not** gaps (dwm has none; a large C feature against `AGENTS.md`'s small-core rule) and not a border-width slider (it would have to write the user's own TOML). The "scale" half of issue `#297` already exists (DPI scaling in Settings). | S11-08, S11-09 |

The facts behind D-11 and D-12 are recorded in the items themselves, with what
was verified and what was not.

---

## S11-01: Shell text stays readable on hover and selected surfaces

Completes S6-03 (issue `#116`). Upstream fixed `#349` in `#352` and found the
root cause our own investigation (2026-09-22, Sprint 6) suspected but could not
confirm without a render: it is in the **Quickshell shell**, not GTK apps.

**Root cause, reproduced here on Lyona's own data.** `Theme.surfaceHover` is
`colors["surface-hover"]`, which `scripts/dwm-settings-appearance` maps to the
palette's `term_color8` (`'surface-hover|term_color8|selbgcolor'`, line 1673).
`term_color8` is ANSI bright-black, a terminal foreground colour, not a light UI
surface. Hover text is `Theme.text` / `Theme.textStrong` (`normfgcolor` /
`selfgcolor`). Computed with the WCAG formula from `config/themes.toml` and the
mappings the shell actually reads (calculated, not rendered):

| Preset | Mode | Hover surface | Text | Text on hover | Strong text on hover |
| --- | --- | --- | --- | --- | --- |
| catppuccin-latte | light | `#6C6F85` | `#4C4F69` | **1.62** | **1.62** |
| solarized-light | light | `#002B36` | `#657B83` | **3.37** | **1.00** |
| rosepine-dawn | light | `#9893A5` | `#575279` | **2.44** | **2.44** |
| tokyonight-day | light | `#A1A6C5` | `#3760BF` | **2.45** | 5.11 |
| gruvbox-light | light | `#928374` | `#3C3836` | **3.16** | **4.02** |
| gruvbox | dark | `#928374` | `#EBDBB2` | **2.68** | **3.24** |
| onedark | dark | `#5C6370` | `#ABB2BF` | **2.84** | 5.24 |
| monochrome | dark | `#555555` | `#AAAAAA` | **3.21** | 7.46 |
| rosepine | dark | `#6E6A86` | `#E0DEF4` | **3.91** | **3.91** |
| tokyonight | dark | `#414868` | `#A9B1D6` | **4.23** | 5.53 |
| dracula | dark | `#6272A4` | `#F8F8F2` | **4.41** | **4.41** |

Below 4.5:1 in bold. Passing (not listed): nord, catppuccin, solarized,
everforest. **All 5 light presets and 6 of the 10 dark presets fail.**
Solarized Light's strong text on hover is 1.00:1, the same 1:1 upstream reported
(hovered label and background both `#002B36`).

**The fix (upstream `b3c8f3d`, `config/quickshell/core/Theme.qml`).** Derive
a light hover surface from the light background instead of bright-black, and
pick each hover/selected text colour with a contrast check that falls back to
black or white. Add to `Theme.qml`:

```diff
     property string accentText: "#2E3440"
+    readonly property string accentHoverText: readableText(accentText, accentSecondary)
     property string success: "#A3BE8C"
```

Replace the nine text roles (`menuText` through `controlSelectedText`):

```diff
-    readonly property string menuText: text
-    readonly property string menuMutedText: textMuted
-    readonly property string menuActionText: accent
+    readonly property string menuText: dark ? text : readableTextOnSurfaces(text, [menuBackground, menuHoverBackground])
+    readonly property string menuMutedText: dark ? textMuted : readableTextOnSurfaces(textMuted, [menuBackground, menuHoverBackground])
+    readonly property string menuActionText: readableText(accent, menuBackground)
     readonly property string menuHoverBackground: surfaceHover
-    readonly property string menuHoverText: textStrong
+    readonly property string menuHoverText: readableText(textStrong, menuHoverBackground)
     readonly property string menuSelectedBackground: surfaceActive
-    readonly property string menuSelectedText: accentSecondary
+    readonly property string menuSelectedText: readableText(accentSecondary, menuSelectedBackground)
     readonly property string controlNormalFill: surface
     readonly property string controlNormalBorder: highContrast ? textStrong : border
-    readonly property string controlNormalText: text
+    readonly property string controlNormalText: dark ? readableText(text, controlNormalFill) : readableTextOnSurfaces(text, [controlNormalFill, controlHoverFill])
     readonly property string controlHoverFill: surfaceHover
     readonly property string controlHoverBorder: highContrast ? textStrong : borderStrong
-    readonly property string controlHoverText: text
+    readonly property string controlHoverText: readableText(text, controlHoverFill)
     readonly property string controlFocusFill: surface
     readonly property string controlFocusBorder: highContrast ? textStrong : accent
-    readonly property string controlFocusText: text
+    readonly property string controlFocusText: readableText(text, controlFocusFill)
     readonly property string controlSelectedFill: surfaceActive
     readonly property string controlSelectedBorder: highContrast ? textStrong : accentSecondary
-    readonly property string controlSelectedText: accentSecondary
+    readonly property string controlSelectedText: readableText(accentSecondary, controlSelectedFill)
```

Add the helpers directly above `function applyAppearanceColors`:

```qml
    function luminance(color) {
        const channels = [1, 3, 5].map(function(offset) {
            const value = parseInt(color.slice(offset, offset + 2), 16) / 255;
            return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        });
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
    }

    function readableText(foreground, background) {
        const fg = luminance(foreground);
        const bg = luminance(background);
        if ((Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05) >= 4.5)
            return foreground;
        return bg > 0.179 ? "#000000" : "#ffffff";
    }

    function readableTextOnSurfaces(foreground, backgrounds) {
        // Some controls intentionally keep one text role while their fill
        // changes on hover. Check that role against both actual surfaces.
        function minimumContrast(color) {
            const fg = luminance(color);
            return Math.min.apply(null, backgrounds.map(function(background) {
                const bg = luminance(background);
                return (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05);
            }));
        }
        if (minimumContrast(foreground) >= 4.5)
            return foreground;
        return minimumContrast("#000000") > minimumContrast("#ffffff") ? "#000000" : "#ffffff";
    }

    function lightHover(background, foreground) {
        // ANSI bright-black is a terminal foreground, not a light UI surface.
        return "#" + [1, 3, 5].map(function(offset) {
            const bg = parseInt(background.slice(offset, offset + 2), 16);
            const fg = parseInt(foreground.slice(offset, offset + 2), 16);
            return Math.round(bg * 0.92 + fg * 0.08).toString(16).padStart(2, "0");
        }).join("");
    }
```

And in `applyAppearanceColors`:

```diff
-        root.surfaceHover = colors["surface-hover"];
+        root.surfaceHover = darkMode ? colors["surface-hover"]
+            : lightHover(colors.background, colors["text-strong"]);
...
-        root.accentText = colors["accent-text"];
+        root.accentText = readableText(colors["accent-text"], colors.accent);
```

**Applying it to the components.** Upstream changed 16 QML files the same way
(pass hover and selected states through the new roles). Tested with
`git apply --check` against Lyona `main` (2026-09-26), taking the patch from
upstream `b3c8f3d`:

| Result | Files |
| --- | --- |
| Applies cleanly (13) | `controlcenter/ControlCenterWindow.qml`, `controls/BluetoothWindow.qml`, `controls/ControlsActionButton.qml`, `core/MenuHeader.qml`, `core/MenuRow.qml`, `core/ShellButton.qml`, `health/SystemHealthWindow.qml`, `launcher/CommandMenuRow.qml`, `launcher/LauncherCategoryRow.qml`, `network/NetworkProfileRow.qml`, `network/NetworkWifiRow.qml`, `panel/TrayItem.qml`, `settings/SettingsWindow.qml` |
| Applies with fuzz 2 (1) | `controls/ControlsWindow.qml`: apply with `patch -p1 -F3`, then read it |
| Hand-merge (2) | `core/Theme.qml` (the block above), `launcher/LauncherResultDelegate.qml` (upstream also added `property bool hovered: resultMouse.containsMouse` and used `root.hovered`; ours differs on the `height:` line only, so add those two lines by hand) |
| Not in Lyona (2) | `controlcenter/ControlCenterActionButton.qml`, `controlcenter/ControlCenterOptionButton.qml`. Lyona's control center is `ControlCenterRow.qml`; read its hover text by hand. |

Fetch the patch with `git -C "$U" show b3c8f3d -- config/quickshell/<file>`,
where `$U` is a checkout of upstream (see `UPSTREAM-SYNC.md`).

**Test (new, not upstream's copy).** Add `make check-quickshell-theme-contrast`:
an Xvfb harness in the style of `tests/test-quickshell-overview-xvfb.sh` that
loads the real `Theme` singleton and, for every preset in `config/themes.toml`,
calls `Theme.applyAppearanceColors(colors, dark)` and asserts at least 4.5:1 for
these pairs: `menuHoverText` on `menuHoverBackground`, `controlHoverText` on
`controlHoverFill`, `controlNormalText` on both `controlNormalFill` and
`controlHoverFill`, `controlSelectedText` on `controlSelectedFill`,
`menuSelectedText` on `menuSelectedBackground`, `accentHoverText` on
`accentSecondary`, plus a dark-to-light switch in one process. Build the colour
maps in the shell wrapper by reading the mapping array out of
`emit_color_records()` in `scripts/dwm-settings-appearance`, so the test cannot
drift from the real key mapping. Before the fix this test fails for the 11
presets in the table above, which is its own mutation check.

Add the target to `check` and the `.PHONY` list. Not prototyped: the harness
itself has not been written or run.

**Also update** `docs/SYNC-SPRINT-6-THEME-CONSISTENCY-AND-WINDOW-OVERVIEW.md`
S6-03 (already done in this review change: it now records the reproduction and
points here), and close `#116` from the PR for this item.

**Not tested here, and cannot be from CSS alone:** how it looks. Solarized
Light and Catppuccin Latte hover in the real shell, checked by eye, is a manual
step for the PR. Upstream's own before/after evidence is
`docs/validation/issue-349.md` at `b3c8f3d`.

## S11-02: Broadcast the GTK and icon theme over XSETTINGS

Upstream `#351` also writes `Net/ThemeName` and `Net/IconThemeName` into
`xsettingsd.conf` so already-running GTK 3 apps such as Thunar repaint when the
theme changes (its issue `#348`). Lyona's `scripts/theme-apply.sh` writes only
`Gtk/CursorThemeName` and `Gtk/CursorThemeSize` there (lines 614 to 621),
and sets `Net/ThemeName` only through `xfconf-query`, which xsettingsd does not
read. Upstream reports that this leaves already-running GTK 3 apps unaware of a theme switch; that is not reproduced here.

Upstream's resolution of *which* GTK theme to pick (Nordic, Dracula,
Gruvbox-Dark ...) is not needed: Lyona generates its own theme and already
knows the name (`GTK_THEME_NAME`, `theme-apply.sh:418`). Port only the
broadcast. `xsettingsd_write_line` in `scripts/dwm-xsettings-config.sh` already
preserves every other line and reloads the daemon with `SIGHUP`, and it has no
key whitelist to extend (upstream's `dwm-xsettings` did, ours does not).

In `scripts/theme-apply.sh`, extend the block that writes the cursor lines:

```diff
 	xsettingsd_write_line "$XSETTINGSD_CONFIG" '^[[:space:]]*Gtk/CursorThemeSize[[:space:]]' \
 		"Gtk/CursorThemeSize $CURSOR_SIZE"
+	XSETTINGS_GTK_THEME=${GTK_THEME_NAME//\\/\\\\}
+	XSETTINGS_GTK_THEME=${XSETTINGS_GTK_THEME//\"/\\\"}
+	xsettingsd_write_line "$XSETTINGSD_CONFIG" '^[[:space:]]*Net/ThemeName[[:space:]]' \
+		"Net/ThemeName \"$XSETTINGS_GTK_THEME\""
+	if [[ -n $ICON_THEME_EFFECTIVE ]]; then
+		XSETTINGS_ICON_THEME=${ICON_THEME_EFFECTIVE//\\/\\\\}
+		XSETTINGS_ICON_THEME=${XSETTINGS_ICON_THEME//\"/\\\"}
+		xsettingsd_write_line "$XSETTINGSD_CONFIG" '^[[:space:]]*Net/IconThemeName[[:space:]]' \
+			"Net/IconThemeName \"$XSETTINGS_ICON_THEME\""
+	elif [[ $TOOLKIT_BASELINE_ICON_PRESENT == 1 ]]; then
+		xsettingsd_write_line "$XSETTINGSD_CONFIG" '^[[:space:]]*Net/IconThemeName[[:space:]]' ''
+	fi
 fi
```

Reject carriage returns and over-long values before writing, as upstream did
(`[[ ${#name} -le 1024 && $name != *$'\r'* ]]`), since the value goes into a
daemon config file. The condition mirrors the existing `gtk2_set` branch at
lines 590 to 604, so both toolkits follow the same "icon theme set, unset, or
untouched" rule.

Tests: extend `tests/test-dwm-settings-theme.sh` (already asserts the cursor
lines) with: switching to a dark preset writes `Net/ThemeName "Lyona-<theme>"`;
switching again replaces the line rather than duplicating it; other keys
(`Xft/DPI`, the cursor lines) survive; a name containing `"` or a backslash is
escaped; a name containing `\r` is rejected. Also add the icon set/unset case.

Risk: low. `xsettingsd_write_line` already returns early when `xsettingsd` is not
installed. Not tested against live apps: a running Thunar repainting is a
manual check for the PR.

## S11-03: Clicking the empty panel closes open popups

Upstream `#340` (the "universal click-away" part). By the code, clicking outside
a popup dismisses it, but the transparent click-away surface starts below the
panel (`ClickAwayPopup.qml`, `panelOffset`), so clicking the empty part of the
top bar itself does nothing. Not reproduced by hand.
Add a background `MouseArea` in `config/quickshell/panel/DwmPanel.qml`, right
after the `PillShadow` line inside the `island` rectangle. The patch from
`ebe57c6` applies cleanly (`git apply --check`, 2026-09-26):

```diff
         PillShadow { cornerRadius: island.radius }

+        MouseArea {
+            anchors.fill: parent
+            onClicked: root.popupRequested(root, "")
+        }
+
         RowLayout {
```

`shell.qml`'s `selectPanelPopup(panel, "")` already closes the command menu,
launcher, notification history, control-center utility and every panel popup
for an empty id, so no `shell.qml` change is needed (upstream's three-line
`shell.qml` hunk is already present in ours).

Test: add a pin to `tests/test-quickshell-panel-menus.sh` next to the existing
`DwmPanel.qml` pins:

```sh
grep -Fq 'onClicked: root.popupRequested(root, "")' "$panel/DwmPanel.qml"
```

Then check by hand that clicking a button in the bar still opens its popup (the
buttons sit above the new background `MouseArea`, so they should keep their
own clicks). That interaction is not covered by any automated test here.

## S11-04: Keep a test's bad-config notification off the real desktop

Upstream `#354`, test half. See "Something that affects the person running the
tests" above for the cause. In `tests/test-xvfb-runtime.sh`, put a fake
`notify-send` first on the `PATH` that dwm is launched with, log what it is
called with, and assert the log. Ours launches dwm at line ~636 with
`PATH="$repo:$PATH"`.

Add before that launch:

```sh
# dwm posts "dwm: bad config" through notify-send when a config fails to load.
# A separate X display still inherits the caller's D-Bus session, so capture
# the call instead of raising a critical notification on the real desktop.
mkdir -p "$work/bin"
: >"$work/notifications.log"
cat >"$work/bin/notify-send" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${DWM_XVFB_NOTIFICATION_LOG:?}"
EOF
chmod 755 "$work/bin/notify-send"
```

and change the launch environment:

```diff
-	PATH="$repo:$PATH" \
+	PATH="$work/bin:$repo:$PATH" \
+	DWM_XVFB_NOTIFICATION_LOG="$work/notifications.log" \
```

Then assert the behaviour the test was implicitly exercising. After the
invalid `'='` config at line ~692, poll for the captured line (upstream's
`wait_for_config_notifications`, a 100-iteration loop of `sleep 0.05`):

```sh
grep -Fxq -- '-u critical dwm: bad config hotkeys.toml: invalid config - loaded defaults' "$work/notifications.log"
```

and assert that a valid reload emitted nothing (`[ ! -s "$work/notifications.log" ]`
after the valid `]`-terminated reload at line ~684). The message is built in `notify_bad_config()` (`dwm.c:3486` onward) as
`"%s: %s - loaded defaults"` from the config file's base name and a reason
string, so read the reason our parser produces for `'='` before writing the
assertion; upstream's text may not match ours.

Also check `scripts/run-tests`: it does not isolate the D-Bus session for any
test, so other tests that start dwm or call `notify-send` for real would leak
the same way. A one-time `grep -l notify-send tests/*.sh` while doing this item
is cheap; fixing any others is in scope.

Verification: after the change, run the test on a live desktop and confirm no
"dwm: bad config" notification appears; run it once with the fake
`notify-send` removed to confirm the assertion fails.

## S11-05: Document desktop dependencies and install profiles for Arch

Upstream `2a0e9b3` added a "dependencies and install profiles" page (Astro
site, Fedora package names). Lyona keeps mdBook (`docs/src/`) and has no such
page; `docs/src/install.md` does not list what gets installed. The source of
truth is `scripts/dwm-packages.sh` (`dwm_packages arch required|desktop|optional|iso|build`).

Add `docs/src/dependencies.md`, add it to `docs/src/SUMMARY.md`, and link it
from `docs/src/install.md`. Content: what each profile is for, which are
installed by `install.sh` and by the ISO, the optional packages and what is
lost without each, and that Arch is the only supported platform. Do not copy
upstream's Fedora tables.

To stop the page drifting, add a check (in `tests/test-arch-packages.sh` or a
sibling) that every package in the profiles the page documents appears in it.
`dwm_packages arch <profile>` prints one package per line for `required`,
`desktop`, `optional`, `iso`, `build` and `full`, and prints nothing for an
unknown profile, so list the profiles explicitly:

```sh
missing=$(for profile in required desktop optional; do dwm_packages arch "$profile"; done |
	sort -u |
	while IFS= read -r package; do
		grep -Fq -- "$package" docs/src/dependencies.md || printf '%s\n' "$package"
	done)
if [ -n "$missing" ]; then
	printf 'docs/src/dependencies.md does not mention:\n%s\n' "$missing" >&2
	exit 1
fi
```

The failure is collected into a variable and tested afterwards, because an
`exit` inside a pipeline runs in a subshell and would not stop the script.
Verify the check fails when a package is removed from the page. Not prototyped.

## S11-06: Qt palettes for qt5ct/qt6ct and a GTK 2 theme

**Decided (D-11): option C.** Fixes a real fault and adds GTK 2 coverage. Both go
through `scripts/lyona-gtk-theme`, so the palette that drives GTK 3/4 also
drives Qt and GTK 2.

### What is wrong today (verified 2026-09-26, qt6ct 0.11, Qt 6, Quickshell as the probe)

Quickshell's `SystemPalette` reports the palette Qt took from its platform theme,
so it shows what a Qt app would get. Dracula preset, generated scheme from the
prototype below:

| Setup | Palette Qt reports |
| --- | --- |
| `qt6ct`, `color_scheme_path` set, `custom_palette` **absent** | default light: window `#efefef`, base `#ffffff` |
| `qt6ct`, `color_scheme_path` set, `custom_palette=false` | default light (same) |
| `qt6ct`, `color_scheme_path` set, `custom_palette=true` | window `#282a36`, base `#393a45`, text `#f8f8f2`, highlight `#bd93f9` |
| no platform theme | default light |
| `gtk3` platform theme, dark `Lyona-dracula` GTK theme | window `#282a36`, base `#282a36`, text `#f8f8f2`, highlight `#bd93f9` |

Three consequences:

1. **Without `qt6ct`/`qt5ct`, Qt apps already follow the palette.** The `gtk3`
   platform theme reads the generated GTK theme's colours. Nothing to fix there.
2. **With `qt6ct` or `qt5ct` installed, Lyona's Qt block has no effect.**
   `theme-apply.sh` selects `qt6ct` as the platform theme, then writes only
   `color_scheme_path`, and only if the user already has a `qt6ct.conf`
   (`scripts/theme-apply.sh:662-677`). Qt ignores that path unless
   `custom_palette=true`. The result is a light Qt app on a dark desktop, and
   installing the tool makes Qt theming worse than not installing it. Both
   `qt5ct` and `qt6ct` read the same three keys (`Appearance`,
   `color_scheme_path`, `custom_palette`, confirmed in both plugins).
3. **GTK 2:** `theme-apply.sh` writes the theme name into `~/.gtkrc-2.0`, but the
   generator emits no `gtk-2.0` files, so a GTK 2 app cannot find it.

`qt6ct` and `qt5ct` are optional packages and Lyona installs no Qt application by
default, so this bites people who add their own Qt apps and the configuration
tool. GTK 2 is not in any Lyona package set.

### The change

**1. Generator: emit a Qt scheme and a GTK 2 theme.** Prototyped in a scratch copy
of `scripts/lyona-gtk-theme`; `shellcheck` and `shfmt -d` clean; all 15 presets
generate. It reuses the palette the generator already resolves (`BG`, `SURFACE`,
`OVERLAY`, `BORDER`, `FG`, `MUTED`, `ACCENT`), picks highlighted-text colour by
contrast (a fixed colour fails on some accents: white on Catppuccin's accent is
2.03:1), and puts placeholder text at 70% toward the foreground (the 45% "muted"
tone gave 1.8:1). Output goes in each theme directory:
`Lyona-<id>/gtk-2.0/gtkrc` and `Lyona-<id>/qt/colors.conf`.

```diff
--- a/scripts/lyona-gtk-theme
+++ b/scripts/lyona-gtk-theme
@@ -151,6 +151,44 @@
 	fi
 }
 
+# WCAG relative luminance of #RRGGBB, as a decimal between 0 and 1.
+luminance() {
+	local colour=$1 r g b
+	r=$(hex_component "$colour" 1)
+	g=$(hex_component "$colour" 3)
+	b=$(hex_component "$colour" 5)
+	awk -v r="$r" -v g="$g" -v b="$b" '
+		function lin(v) {
+			v = v / 255
+			return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4
+		}
+		BEGIN { printf "%.6f", 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) }'
+}
+
+# WCAG contrast ratio between two #RRGGBB colours.
+contrast() {
+	awk -v a="$(luminance "$1")" -v b="$(luminance "$2")" '
+		BEGIN {
+			hi = a > b ? a : b
+			lo = a > b ? b : a
+			printf "%.2f", (hi + 0.05) / (lo + 0.05)
+		}'
+}
+
+# The candidate (arguments after the first) with the best contrast against $1.
+best_text_on() {
+	local background=$1 best='' best_ratio=0 candidate ratio
+	shift
+	for candidate in "$@"; do
+		ratio=$(contrast "$candidate" "$background")
+		if awk -v r="$ratio" -v b="$best_ratio" 'BEGIN { exit !(r > b) }'; then
+			best=$candidate
+			best_ratio=$ratio
+		fi
+	done
+	printf '%s' "$best"
+}
+
 gtk3_import() {
 	if [[ $DARK_MODE == true ]]; then
 		printf '%s' 'resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css'
@@ -321,6 +359,85 @@
 EOF
 }
 
+# A qt5ct/qt6ct colour scheme: three lines of the 21 QPalette roles in Qt's own
+# order. Highlighted text is chosen for contrast against the accent, because a
+# fixed colour is unreadable on some accents; disabled text uses the muted tone.
+qt_colour() {
+	printf '#ff%s' "${1#\#}"
+}
+
+qt_role_line() {
+	local line=$1 i
+	shift
+	printf '%s=' "$line"
+	for i in "$@"; do
+		printf '%s' "$i"
+		[[ $i == "${!#}" ]] || printf ', '
+	done
+	printf '\n'
+}
+
+emit_qt_colours() {
+	local highlighted_text mid_light link_visited placeholder
+	local -a active disabled
+
+	highlighted_text=$(best_text_on "$ACCENT" "$BG" "$FG" '#000000' '#FFFFFF')
+	mid_light=$(blend "$SURFACE" "$OVERLAY" 50)
+	link_visited=$(blend "$ACCENT" "$FG" 40)
+	# Dimmer than text but still readable: 70% toward the foreground keeps
+	# at least 3:1 on Base for every shipped palette (45% gave 1.8:1).
+	placeholder=$(blend "$SURFACE" "$FG" 70)
+
+	# WindowText, Button, Light, Midlight, Dark, Mid, Text, BrightText,
+	# ButtonText, Base, Window, Shadow, Highlight, HighlightedText, Link,
+	# LinkVisited, AlternateBase, NoRole, ToolTipBase, ToolTipText,
+	# PlaceholderText
+	active=("$FG" "$SURFACE" "$OVERLAY" "$mid_light" "$BORDER" "$BORDER" "$FG" "$FG"
+		"$FG" "$SURFACE" "$BG" '#000000' "$ACCENT" "$highlighted_text" "$ACCENT"
+		"$link_visited" "$OVERLAY" '#000000' "$SURFACE" "$FG" "$placeholder")
+	disabled=("${active[@]}")
+	disabled[0]=$MUTED
+	disabled[6]=$MUTED
+	disabled[8]=$MUTED
+	disabled[13]=$MUTED
+
+	printf '[ColorScheme]\n'
+	printf 'active_colors=%s\n' "$(qt_join "${active[@]}")"
+	printf 'inactive_colors=%s\n' "$(qt_join "${active[@]}")"
+	printf 'disabled_colors=%s\n' "$(qt_join "${disabled[@]}")"
+}
+
+qt_join() {
+	local out='' colour
+	for colour in "$@"; do
+		out+="${out:+, }$(qt_colour "$colour")"
+	done
+	printf '%s' "$out"
+}
+
+# GTK 2 has no CSS: a gtkrc that sets the palette for every widget state. The
+# theme name in ~/.gtkrc-2.0 (theme-apply.sh) resolves to this directory.
+emit_gtk2_rc() {
+	local id=$1 highlighted_text
+
+	highlighted_text=$(best_text_on "$ACCENT" "$BG" "$FG" '#000000' '#FFFFFF')
+
+	printf '# Lyona-%s -- generated by lyona-gtk-theme from the %s palette.\n' "$id" "$id"
+	printf '# Do not edit: regenerate with lyona-gtk-theme generate %s\n' "$id"
+	printf 'style "lyona-palette" {\n'
+	printf '  bg[NORMAL] = "%s"\n  base[NORMAL] = "%s"\n  fg[NORMAL] = "%s"\n  text[NORMAL] = "%s"\n' \
+		"$BG" "$SURFACE" "$FG" "$FG"
+	printf '  bg[PRELIGHT] = "%s"\n  base[PRELIGHT] = "%s"\n  fg[PRELIGHT] = "%s"\n  text[PRELIGHT] = "%s"\n' \
+		"$OVERLAY" "$OVERLAY" "$FG" "$FG"
+	printf '  bg[ACTIVE] = "%s"\n  base[ACTIVE] = "%s"\n  fg[ACTIVE] = "%s"\n  text[ACTIVE] = "%s"\n' \
+		"$ACCENT" "$ACCENT" "$highlighted_text" "$highlighted_text"
+	printf '  bg[SELECTED] = "%s"\n  base[SELECTED] = "%s"\n  fg[SELECTED] = "%s"\n  text[SELECTED] = "%s"\n' \
+		"$ACCENT" "$ACCENT" "$highlighted_text" "$highlighted_text"
+	printf '  bg[INSENSITIVE] = "%s"\n  base[INSENSITIVE] = "%s"\n  fg[INSENSITIVE] = "%s"\n  text[INSENSITIVE] = "%s"\n' \
+		"$BG" "$SURFACE" "$MUTED" "$MUTED"
+	printf '}\nclass "*" style "lyona-palette"\n'
+}
+
 generate_one() {
 	local id=$1 file=$2 outdir=$3
 
@@ -329,11 +446,13 @@
 
 	resolve_palette "$id" "$file"
 
-	mkdir -p -- "$outdir/gtk-3.0" "$outdir/gtk-4.0" ||
+	mkdir -p -- "$outdir/gtk-2.0" "$outdir/gtk-3.0" "$outdir/gtk-4.0" "$outdir/qt" ||
 		die "could not create $outdir"
 	emit_index_theme "$id" >"$outdir/index.theme"
+	emit_gtk2_rc "$id" >"$outdir/gtk-2.0/gtkrc"
 	emit_css "$id" "$(gtk3_import)" >"$outdir/gtk-3.0/gtk.css"
 	emit_css "$id" "$(gtk4_import)" >"$outdir/gtk-4.0/gtk.css"
+	emit_qt_colours >"$outdir/qt/colors.conf"
 }
 
 case ${1:-} in
```

**2. `theme-apply.sh`: point qt5ct/qt6ct at it, and set both keys.** The block
below was run in isolation against six situations (missing config; existing
config with other keys and sections preserved; dark preset with no generated
scheme falls back to the tool's `darker.conf` with `custom_palette=true`; light
preset with none writes an empty path and `custom_palette=false`; a data path
containing `&` and `|` is written literally; a config with no `[Appearance]`
section) and with `RUNTIME_ONLY=1` (writes nothing). It creates `qt6ct.conf`
with only an `[Appearance]` section when none exists, so `qt6ct` users get
themed Qt without opening its GUI first. `dwm-settings-theme` already lists both
files in its rollback set (`integration_path_list_for`, with an `existed` flag
per file), so a created file is removed on rollback. The lint result matches
the script's baseline (`shellcheck`: 1 existing finding; `shfmt -d`: clean).

```diff
--- a/scripts/theme-apply.sh
+++ b/scripts/theme-apply.sh
@@ -659,21 +659,52 @@
 
 fi
 
+# Set one key in the [Appearance] section of a qt5ct/qt6ct config, keeping every
+# other key and section. Values here are paths and booleans from this script.
+qt_ct_set() {
+	local file=$1 key=$2 value=$3
+	value=${value//\\/\\\\}
+	value=${value//&/\\&}
+	value=${value//|/\\|}
+	if grep -q "^$key=" "$file"; then
+		sed -i "s|^$key=.*|$key=$value|" "$file"
+	elif grep -q '^\[Appearance\]' "$file"; then
+		sed -i "/^\[Appearance\]/a $key=$value" "$file"
+	else
+		printf '\n[Appearance]\n%s=%s\n' "$key" "$value" >>"$file"
+	fi
+}
+
+# qt5ct/qt6ct only use color_scheme_path when custom_palette=true (checked with
+# qt6ct 0.11: the path alone leaves Qt on its default light palette), so both
+# keys are written. The palette's own generated scheme wins; without one, dark
+# presets fall back to the tool's generic dark scheme.
 if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 &&
 	("$QT_PLATFORM_THEME" == "qt5ct" || "$QT_PLATFORM_THEME" == "qt6ct") ]]; then
 	QT_CT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/${QT_PLATFORM_THEME}/${QT_PLATFORM_THEME}.conf"
-	if [[ -f "$QT_CT_CONF" ]]; then
-		if [[ "$DARK_MODE" == "true" ]]; then
-			QT_CT_SCHEME="/usr/share/${QT_PLATFORM_THEME}/colors/darker.conf"
-		else
-			QT_CT_SCHEME=""
-		fi
-		if grep -q '^color_scheme_path' "$QT_CT_CONF"; then
-			sed -i "s|^color_scheme_path=.*|color_scheme_path=$QT_CT_SCHEME|" "$QT_CT_CONF"
-		else
-			sed -i "/^\[Appearance\]/a color_scheme_path=${QT_CT_SCHEME}" "$QT_CT_CONF"
+	QT_CT_SCHEME=""
+	for QT_CT_CANDIDATE in \
+		"${XDG_DATA_HOME:-$HOME/.local/share}/themes/Lyona-$THEME_NAME/qt/colors.conf" \
+		"/usr/share/themes/Lyona-$THEME_NAME/qt/colors.conf"; do
+		if [[ -f $QT_CT_CANDIDATE ]]; then
+			QT_CT_SCHEME=$QT_CT_CANDIDATE
+			break
 		fi
+	done
+	if [[ -z $QT_CT_SCHEME && $DARK_MODE == "true" ]]; then
+		QT_CT_SCHEME="/usr/share/${QT_PLATFORM_THEME}/colors/darker.conf"
+	fi
+	if [[ -n $QT_CT_SCHEME ]]; then
+		QT_CT_CUSTOM=true
+	else
+		QT_CT_CUSTOM=false
+	fi
+	if [[ ! -f $QT_CT_CONF ]]; then
+		mkdir -p "${QT_CT_CONF%/*}"
+		printf '[Appearance]\n' >"$QT_CT_CONF"
 	fi
+	qt_ct_set "$QT_CT_CONF" color_scheme_path "$QT_CT_SCHEME"
+	qt_ct_set "$QT_CT_CONF" custom_palette "$QT_CT_CUSTOM"
 fi
 
 # Refresh cached named cursors in existing clients as well as the root window.
```

**3. Install, uninstall and inventory.** `install-gtk-themes` runs `generate-all`,
so it picks the new files up; uninstall removes each `Lyona-<id>` directory
recursively, so it does too. Only the `check-install` inventory lists files
explicitly (`Makefile:789`):

```diff
-		awk '/^\[theme\./ { id = $$0; sub(/^\[theme\./, "", id); sub(/\].*$$/, "", id); print "usr/share/themes/Lyona-" id "/index.theme"; print "usr/share/themes/Lyona-" id "/gtk-3.0/gtk.css"; print "usr/share/themes/Lyona-" id "/gtk-4.0/gtk.css"; }' config/themes.toml; \
+		awk '/^\[theme\./ { id = $$0; sub(/^\[theme\./, "", id); sub(/\].*$$/, "", id); print "usr/share/themes/Lyona-" id "/index.theme"; print "usr/share/themes/Lyona-" id "/gtk-2.0/gtkrc"; print "usr/share/themes/Lyona-" id "/gtk-3.0/gtk.css"; print "usr/share/themes/Lyona-" id "/gtk-4.0/gtk.css"; print "usr/share/themes/Lyona-" id "/qt/colors.conf"; }' config/themes.toml; \
```

Add two targets (the Python one follows `check-display-profiles`, the Xvfb one
follows `check-quickshell-queued-run-xvfb`'s exit-77 skip), list them in
`.PHONY`, and call them from `check`:

```make
check-app-palettes:
	/usr/bin/python3 tests/test-app-palettes.py

check-qt-palette-xvfb:
	@tests/test-qt-palette-xvfb.sh; status=$$?; [ $$status -eq 77 ] && exit 0; exit $$status
```

**4. Tests (both new, both run against the prototype).**

`tests/test-app-palettes.py` checks structure and readability for every preset.
Worst cases measured on the 15 shipped presets: text on base 5.94:1, text on
window 6.66:1, highlighted text on highlight 5.01:1, placeholder on base 3.13:1.
Mutation-checked: a fixed white highlighted text fails it (Catppuccin 2.03:1), and
a 45% placeholder fails it (Catppuccin Latte 2.01:1).

```python
#!/usr/bin/env python3
"""Generated Qt palettes and GTK 2 themes: structure, and readable colours for every preset."""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
GENERATOR = REPO / "scripts/lyona-gtk-theme"
THEMES = REPO / "config/themes.toml"

# QPalette roles in the order qt5ct/qt6ct read them.
ROLES = [
    "WindowText", "Button", "Light", "Midlight", "Dark", "Mid", "Text",
    "BrightText", "ButtonText", "Base", "Window", "Shadow", "Highlight",
    "HighlightedText", "Link", "LinkVisited", "AlternateBase", "NoRole",
    "ToolTipBase", "ToolTipText", "PlaceholderText",
]


def luminance(colour):
    channels = [int(colour[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    channels = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def contrast(a, b):
    x, y = luminance(a), luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)


class AppPaletteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        subprocess.run([str(GENERATOR), "generate-all", str(THEMES), cls.tmp.name], check=True)
        cls.themes = sorted(Path(cls.tmp.name).glob("Lyona-*"))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def scheme(self, theme):
        lines = (theme / "qt/colors.conf").read_text().splitlines()
        self.assertEqual(lines[0], "[ColorScheme]", theme.name)
        self.assertEqual(len(lines), 4, theme.name)
        result = {}
        for line in lines[1:]:
            key, value = line.split("=", 1)
            colours = [c.strip() for c in value.split(",")]
            self.assertEqual(len(colours), len(ROLES), f"{theme.name} {key}")
            for colour in colours:
                self.assertRegex(colour, r"^#ff[0-9A-Fa-f]{6}$", f"{theme.name} {key}")
            result[key] = ["#" + c[3:] for c in colours]
        self.assertEqual(sorted(result), ["active_colors", "disabled_colors", "inactive_colors"])
        return result

    def test_every_palette_has_a_qt_scheme_and_a_gtk2_theme(self):
        expected = len(re.findall(r"^\[theme\.", THEMES.read_text(), re.M))
        self.assertGreaterEqual(expected, 10)
        self.assertEqual(len(self.themes), expected)
        for theme in self.themes:
            self.scheme(theme)
            rc = (theme / "gtk-2.0/gtkrc").read_text()
            for state in ("NORMAL", "PRELIGHT", "ACTIVE", "SELECTED", "INSENSITIVE"):
                for name in ("bg", "base", "fg", "text"):
                    self.assertIn(f"{name}[{state}] =", rc, theme.name)
            self.assertIn('class "*" style "lyona-palette"', rc, theme.name)

    def test_qt_colours_are_readable_for_every_preset(self):
        for theme in self.themes:
            active = dict(zip(ROLES, self.scheme(theme)["active_colors"]))
            for text, background, minimum in (
                ("Text", "Base", 4.5),
                ("Text", "Window", 4.5),
                ("HighlightedText", "Highlight", 4.5),
                ("ToolTipText", "ToolTipBase", 4.5),
                # Placeholder text is meant to be dimmer than text; 3:1 is the floor.
                ("PlaceholderText", "Base", 3.0),
            ):
                ratio = contrast(active[text], active[background])
                self.assertGreaterEqual(
                    ratio, minimum, f"{theme.name}: {text} on {background} is {ratio:.2f}:1"
                )

    def test_window_and_base_follow_the_gtk_theme(self):
        # The same palette drives GTK and Qt, so an app in either toolkit matches.
        for theme in self.themes:
            css = (theme / "gtk-3.0/gtk.css").read_text()
            bg = re.search(r"@define-color lyona_bg\s+(#[0-9A-Fa-f]{6})", css).group(1)
            surface = re.search(r"@define-color lyona_surface\s+(#[0-9A-Fa-f]{6})", css).group(1)
            active = dict(zip(ROLES, self.scheme(theme)["active_colors"]))
            self.assertEqual(active["Window"].upper(), bg.upper(), theme.name)
            self.assertEqual(active["Base"].upper(), surface.upper(), theme.name)


if __name__ == "__main__":
    unittest.main()
```

`tests/test-qt-palette-xvfb.sh` proves the generated scheme really becomes Qt's
palette under `qt6ct`, for a dark and a light preset, and keeps a negative
control (without `custom_palette=true` the scheme must be ignored) so a future
`qt6ct` that stops requiring it is noticed. It skips (exit 77) when `qt6ct`,
`quickshell`, `Xvfb` or `dbus-run-session` is missing. Mutation-checked with a
wrong palette index.

```sh
#!/bin/sh
set -eu

# Sync Sprint 11 S11-06 (docs/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md):
# a palette the generator writes for qt5ct/qt6ct really becomes the palette Qt
# apps get, and qt6ct ignores color_scheme_path unless custom_palette=true (the
# reason theme-apply.sh must set both). Quickshell's SystemPalette reports the
# palette Qt took from the platform theme.
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ ! -e /usr/lib/qt6/plugins/platformthemes/libqt6ct.so ]; then
	printf 'SKIP: qt6ct is not installed\n'
	exit 77
fi
if [ "${DWM_QT_PALETTE_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_QT_PALETTE_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
xvfb_pid=
cleanup() {
	if [ -n "$xvfb_pid" ]; then
		kill "$xvfb_pid" 2>/dev/null || true
		wait "$xvfb_pid" 2>/dev/null || true
	fi
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$work/themes" "$work/qml" "$work/runtime"
chmod 700 "$work/runtime"
"$repo/scripts/lyona-gtk-theme" generate-all "$repo/config/themes.toml" "$work/themes"

cat >"$work/qml/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
    SystemPalette { id: p; colorGroup: SystemPalette.Active }
    Timer {
        interval: 300
        running: true
        onTriggered: {
            console.info("PALETTE window=" + p.window + " base=" + p.base + " text=" + p.text + " highlight=" + p.highlight);
            Qt.quit();
        }
    }
}
QML

Xvfb -displayfd 3 -screen 0 800x600x24 -nolisten tcp -extension GLX \
	3>"$work/display" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
while [ ! -s "$work/display" ] && [ "$i" -lt 100 ]; do
	i=$((i + 1))
	sleep 0.05
done
display_number=$(sed -n '1p' "$work/display")
case $display_number in
'' | *[!0-9]*)
	cat "$work/xvfb.log" >&2
	exit 1
	;;
esac

# The palette Qt reports for a qt6ct configuration, as "window base text highlight".
palette_with() {
	home=$work/home-$1
	mkdir -p "$home/.config/qt6ct"
	printf '[Appearance]\ncolor_scheme_path=%s\n' "$2" >"$home/.config/qt6ct/qt6ct.conf"
	[ -z "${3:-}" ] || printf 'custom_palette=%s\n' "$3" >>"$home/.config/qt6ct/qt6ct.conf"
	env HOME="$home" XDG_CONFIG_HOME="$home/.config" DISPLAY=":$display_number" \
		XDG_RUNTIME_DIR="$work/runtime" QT_QPA_PLATFORMTHEME=qt6ct \
		timeout 30 quickshell --no-duplicate --path "$work/qml/shell.qml" 2>&1 |
		sed 's/\x1b\[[0-9;]*m//g' |
		sed -n 's/.*PALETTE window=\(#[0-9a-f]*\) base=\(#[0-9a-f]*\) text=\(#[0-9a-f]*\) highlight=\(#[0-9a-f]*\).*/\1 \2 \3 \4/p' |
		head -n 1
}

# Roles 11, 10, 1 and 13 of active_colors (1-based) are Window, Base, Text, Highlight;
# see ROLES in tests/test-app-palettes.py.
expected_from() {
	awk -F'[=,]' '/^active_colors=/ {
		for (i = 2; i <= NF; i++) { gsub(/^[ \t]*#ff/, "", $i); $i = tolower($i) }
		printf "#%s #%s #%s #%s\n", $12, $11, $2, $14
	}' "$1"
}

for preset in dracula catppuccin-latte; do
	scheme=$work/themes/Lyona-$preset/qt/colors.conf
	expected=$(expected_from "$scheme")

	applied=$(palette_with "$preset-on" "$scheme" true)
	if [ "$applied" != "$expected" ]; then
		printf '%s: qt6ct with custom_palette=true gave "%s", expected "%s"\n' "$preset" "$applied" "$expected" >&2
		exit 1
	fi

	for flag in '' false; do
		ignored=$(palette_with "$preset-off-$flag" "$scheme" "$flag")
		if [ -z "$ignored" ] || [ "$ignored" = "$expected" ]; then
			printf '%s: qt6ct applied color_scheme_path without custom_palette=true ("%s"); theme-apply.sh may no longer need to set it\n' "$preset" "$ignored" >&2
			exit 1
		fi
	done
done

printf 'Qt palette under qt6ct: PASS\n'
```

Extend `tests/test-lyona-gtk-theme.sh`, next to its existing per-theme
assertions (`assert_file "$dir/gtk-3.0/gtk.css"`), with:

```sh
	assert_file "$dir/gtk-2.0/gtkrc"
	assert_file "$dir/qt/colors.conf"
```

### Not verified, and why

- **GTK 2 rendering.** GTK 2 is not installed on this host and not in any Lyona
  package set, so the `gtkrc` was checked for structure only, and its layout
  copies upstream's (a `style` block plus `class "*" style`). GTK 2 looks for a
  theme in `~/.themes` and the system data directory, and I could not confirm it
  searches `~/.local/share/themes`, where on-demand generation writes a user's
  theme. System installs (`/usr/share/themes`) are unaffected. If a check on a
  machine with a GTK 2 app shows the user path is not searched, symlink
  `~/.themes/Lyona-<id>` when generating there.
- **`qt5ct`.** It reads the same keys, but only `qt6ct` was run.
- **Real applications.** The palette Qt reports was checked, not a rendered Qt
  app. Open a Qt app (or `qt6ct` itself) under a light and a dark preset.
- **Existing `qt6ct` users' customisations.** The block sets `color_scheme_path`
  and `custom_palette` on every theme switch, as the old block did for the path. A
  user who prefers their own scheme should set `PERSONALIZATION[qt]` to another
  platform theme; say so in the CHANGELOG.

## S11-07: Square popups and a 1 px focus ring

**Decided (D-10, 2026-09-26): square popups, and the keyboard focus ring goes to
1 px.** Upstream `#340` squares every popup, flyout and notification and makes
the focus border the same width as the idle border. In Lyona this is a small
change, because one shared component
draws the frame: `core/ShellSurface.qml` uses `Theme.popupRadius`, and 13
QML files use that component. `popupRadius` is used nowhere else.

**`config/quickshell/core/Theme.qml`** (lines 144 and 186):

```diff
-    readonly property int popupRadius: controlRadius
+    readonly property int popupRadius: 0
...
-    readonly property int notificationAccentRadius: dp(2)
+    readonly property int notificationAccentRadius: 0
```

**Notification cards** take the popup radius so they square off with the popups
(upstream `#340` does the same; ours are at these lines):

```diff
--- a/config/quickshell/notifications/NotificationCard.qml        (line 18)
-    radius: Theme.largeSurfaceCardRadius
+    radius: Theme.popupRadius
--- a/config/quickshell/notifications/NotificationHistoryWindow.qml  (line 94)
-                            radius: Theme.largeSurfaceCardRadius
+                            radius: Theme.popupRadius
```

**Focus ring, `Theme.qml` line 140:**

```diff
-    readonly property int controlFocusBorderWidth: dp(highContrast ? 3 : 2)
+    readonly property int controlFocusBorderWidth: controlBorderWidth
```

`controlBorderWidth` is `dp(highContrast ? 2 : 1)`, so the focus ring becomes
1 px normally (was 2) and 2 px in high-contrast mode (was 3). The idle and
focus widths now match, which is upstream's stated reason (no stroke "popping"
when focus moves). Update the accessibility pin that would otherwise fail:

```diff
--- a/tests/test-quickshell-accessibility.sh   (line 82)
-assert_contains "$theme" 'readonly property int controlFocusBorderWidth: dp(highContrast ? 3 : 2)'
+assert_contains "$theme" 'readonly property int controlFocusBorderWidth: controlBorderWidth'
```

**Two things to check by eye, because the change is wider than the name
suggests.** 15 places use `controlFocusBorderWidth`. Ten switch to it only when
the control has focus (buttons, search boxes, sliders, switches), which is the
intended change. Five apply it **unconditionally** as an emphasis border, not a
focus ring: `core/PanelSlider.qml:83` and `settings/AppearanceSettingsPane.qml`
lines 361, 502, 737 and 934. Those will thin from 2 px to 1 px too. Look at the
slider handle and the Appearance pane's selected swatches; if they read too
weak, give them their own token instead of `controlFocusBorderWidth`.

Accessibility note, so the trade-off is explicit: with equal widths, focus is
shown by the border colour (`controlFocusBorder`, the accent) rather than by a
thicker line. High-contrast mode keeps a 2 px border. Keyboard focus should be
checked on a light and a dark preset, since that is now the only cue.

**Deliberately not changed:**

- The monitor preview tile border in `DisplaySettingsPane.qml` (`Theme.dp(2)`,
  line 351); upstream drops it to 1 px as part of the same "uniform border"
  idea, but it marks the selected monitor, so it is your call.
- `PillShadow`: its `cornerRadius` follows the surface, and its opacity is 0,
  so nothing changes there.

**Visual consequence to be aware of.** Only the popup frames and notification
cards go square. About 83 places still round their own corners inside them
(`controlRadius` 6 dp on buttons and rows, `largeSurfaceCardRadius` 8 dp on
launcher results and cards), so a square frame will contain rounded rows. That
matches what upstream ships, but if you want a fully square look, the
follow-up is setting `controlRadius`, `largeSurfaceCardRadius`, `pillRadius`
and `smallRadius` to 0 as well, which changes the whole shell and deserves its
own look. I would try the small change first and judge it on screen.

**Tests.** No existing test pins these radii (checked: `grep` of
`tests/*.sh` for `popupRadius`, `notificationAccentRadius`,
`largeSurfaceCardRadius` finds nothing; only the focus-width pin above exists), so add pins to
`tests/test-quickshell-design-system.sh` for the three new values. Then run
`check-quickshell-large-surfaces-xvfb`, which loads these surfaces and
measures the idle CPU. Appearance is a manual check: open the launcher, the
control center, Settings and a notification and look.

## S11-08: A layout switcher in the Control Center

**Decided (D-12).** Upstream issue `#297` (a contributor request with no upstream
code) asks for a visual way to switch dwm layouts for people who do not know the
keybindings. Today dwm has three layouts (`[]=` tile, `><>` floating, `[M]`
monocle, `config.def.h:33`), switched only by `setlayout` hotkeys (`layout_idx`
in `hotkeys.toml`). Quickshell shows and controls nothing about layouts: dwm
publishes no current layout and accepts no set-layout request. This item is the
only one in the sprint that changes the dwm C core (about 54 changed lines, no new
dependency, nothing blocking in the event loop).

### Design

- dwm publishes the selected monitor's layout for its current tag as the root
  property `_DWM_LAYOUT` (a CARDINAL: an index into `layouts[]`, the same index
  `layout_idx` uses). It is written only when the value changes, because the
  state bridge watches it.
- dwm accepts a request through the root property `_DWM_SET_LAYOUT`. It reads the
  value, **deletes the property** (so a request is consumed once), range-checks
  the index, and calls `setlayout()` exactly as the hotkey does. Out-of-range and
  negative values are ignored.
- Why a property and not a client message: `xdotool` cannot send an arbitrary
  client message, but `xprop -root -f _DWM_SET_LAYOUT 32c -set _DWM_SET_LAYOUT N`
  needs nothing new (the state bridge already depends on `xprop`). Any local X
  client can already set root properties and send `xdotool` key events, so this
  adds no new capability; it is the same trust the EWMH messages dwm accepts carry.
- `dwm-quickshell-state` gains a `layout=` field (and watches `_DWM_LAYOUT`), and
  a `layout <index>` command. `DwmState.qml` gains `layoutIndex` and
  `setLayout()`. The Control Center's main page gains a "Window layout" row of
  three buttons using the existing `PresetButton`. It acts on the **selected
  (focused) monitor**, as the hotkeys do.
- Old dwm builds publish no `_DWM_LAYOUT`: `layout=` is empty, `layoutIndex` is
  `-1`, and the buttons are disabled.

### Changes

**1. `dwm.c`.** Prototyped in a scratch copy: compiled with the repo's flags and no
warnings, then run under Xvfb. Verified there: initial `_DWM_LAYOUT` is `0`;
requesting `2`, `1`, `0` changes it; requesting `7` and `-1` changes nothing;
`_DWM_SET_LAYOUT` is gone after each request; dwm stays up. Layouts are per tag,
and both paths publish: on tag 1 set monocle (`2`), switching to tag 2 shows its
own layout (`0`), `Super+f` there gives `1`, switching back shows tag 1's `2`,
`Super+t` gives `0`.

```diff
--- a/dwm.c
+++ b/dwm.c
@@ -83,7 +83,7 @@
        NetWMWindowTypeMenu, NetWMWindowTypePopupMenu, NetWMWindowTypeDropdownMenu,
        NetWMWindowTypeCombo, NetWMWindowTypeDnd,
        NetClientList, NetDesktopNames, NetDesktopViewport, NetNumberOfDesktops, NetCurrentDesktop,
-       NetWMDesktop, NetDwmMonitorDesktops, NetDwmSelectedMonitor, NetLast };
+       NetWMDesktop, NetDwmMonitorDesktops, NetDwmSelectedMonitor, NetDwmLayout, NetDwmSetLayout, NetLast };
 enum { WMProtocols, WMDelete, WMState, WMTakeFocus, WMLast };
 enum { ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle,
        ClkClientWin, ClkRootWin, ClkLast };
@@ -348,6 +348,8 @@
 static void setviewport(void);
 static void updatecurrentdesktop(void);
 static void updateselectedmonitor(void);
+static void updatelayoutprop(void);
+static void applylayoutrequest(void);
 
 static void managealtbar(Window win, XWindowAttributes *wa);
 static void managetray(Window win, XWindowAttributes *wa);
@@ -1357,6 +1359,7 @@
 	}
 	selmon->sel = c;
 	updateselectedmonitor();
+	updatelayoutprop();
 	// drawbars();
 }
 
@@ -2367,6 +2370,9 @@
 		updatestatus();
 	} else if ((ev->window == root) && (ev->atom == XA_RESOURCE_MANAGER)) {
 		updatedpi(0);
+	} else if ((ev->window == root) && (ev->atom == netatom[NetDwmSetLayout])) {
+		if (ev->state == PropertyNewValue)
+			applylayoutrequest();
 	} else if (ev->state == PropertyDelete) {
 		return;
 	} else if ((c = wintoclient(ev->window))) {
@@ -3343,6 +3349,7 @@
 
 	copystr(selmon->ltsymbol, sizeof selmon->ltsymbol,
 	        selmon->lt[selmon->sellt]->symbol);
+	updatelayoutprop();
 	if (selmon->sel)
 		arrange(selmon);
 	// else
@@ -4262,6 +4269,8 @@
 	netatom[NetWMDesktop] = XInternAtom(dpy, "_NET_WM_DESKTOP", False);
 	netatom[NetDwmMonitorDesktops] = XInternAtom(dpy, "_DWM_MONITOR_DESKTOPS", False);
 	netatom[NetDwmSelectedMonitor] = XInternAtom(dpy, "_DWM_SELECTED_MONITOR", False);
+	netatom[NetDwmLayout] = XInternAtom(dpy, "_DWM_LAYOUT", False);
+	netatom[NetDwmSetLayout] = XInternAtom(dpy, "_DWM_SET_LAYOUT", False);
 	dwmfullscreenmonitorsatom = XInternAtom(dpy, "_DWM_FULLSCREEN_MONITORS", False);
 	dwmtagupdateatom = XInternAtom(dpy, "DWM_TAG_UPDATE", False);
 
@@ -5164,6 +5173,7 @@
 	free(monitor_desktops);
 	updateselectedmonitor();
 	updatefullscreenmonitors();
+	updatelayoutprop();
 }
 
 void
@@ -5184,6 +5194,52 @@
 	selectedmonitorcachevalid = 1;
 }
 
+/* Publish the selected monitor's layout for the current tag as an index into
+ * layouts[] (the same index hotkeys.toml's layout_idx uses), so a status
+ * client can show and highlight it. Written only when the value changes: a
+ * status client watches this property. */
+void
+updatelayoutprop(void)
+{
+	static long cache = -1;
+	long data[] = { 0 };
+	long idx;
+
+	if (!selmon)
+		return;
+	idx = (long)(selmon->lt[selmon->sellt] - layouts);
+	if (idx < 0 || idx >= (long)LENGTH(layouts) || idx == cache)
+		return;
+	data[0] = idx;
+	ewmh_replace_root_cardinal(netatom[NetDwmLayout], data, 1);
+	cache = idx;
+}
+
+/* A status client asks for a layout by setting the root property
+ * _DWM_SET_LAYOUT to an index into layouts[]. The request is consumed
+ * (deleted) and range-checked, then applied to the selected monitor exactly as
+ * the setlayout hotkey would. Any X client can set a root property, which is
+ * the same trust the EWMH messages dwm already accepts carry. */
+void
+applylayoutrequest(void)
+{
+	Atom type;
+	int format;
+	unsigned long n, after;
+	unsigned char *data = NULL;
+	long idx;
+
+	if (XGetWindowProperty(dpy, root, netatom[NetDwmSetLayout], 0, 1, True,
+	    XA_CARDINAL, &type, &format, &n, &after, &data) != Success || !data)
+		return;
+	if (type == XA_CARDINAL && format == 32 && n == 1) {
+		idx = *(long *)data;
+		if (idx >= 0 && idx < (long)LENGTH(layouts))
+			setlayout(&(Arg){ .v = &layouts[idx] });
+	}
+	XFree(data);
+}
+
 #if SHOWWINICON
 void
 updateicon(Client *c)
```

**2. `scripts/dwm-quickshell-state` and its test.** Prototyped in a scratch copy;
`shellcheck` and `shfmt -d` clean; the existing state test plus the new
assertions pass, and the test fails when the `_DWM_LAYOUT` parse is removed.
Run against the prototype dwm above: `state` reports `layout=0`, after
`layout 2` it reports `layout=2`, after `layout 9` it stays `1` (dwm ignored it),
`layout abc` prints the usage line and sends nothing, and the `watch` stream
emitted a new block when the layout changed.

```diff
--- a/scripts/dwm-quickshell-state
+++ b/scripts/dwm-quickshell-state
@@ -269,6 +269,7 @@
 		_DWM_FULLSCREEN_MONITORS \
 		_DWM_MONITOR_DESKTOPS \
 		_DWM_SELECTED_MONITOR \
+		_DWM_LAYOUT \
 		WM_NAME 2>/dev/null |
 		awk '
 			function value(   text) {
@@ -333,10 +334,11 @@
 			}
 			/^_DWM_MONITOR_DESKTOPS/ { desktops = value(); gsub(/[[:space:]"]/, "", desktops); next }
 			/^_DWM_SELECTED_MONITOR/ { split(value(), f, /[[:space:]]+/); selected = f[1]; next }
+			/^_DWM_LAYOUT/ { split(value(), f, /[[:space:]]+/); layout = f[1]; next }
 			/^WM_NAME/ { status = collapse(unquote(value())); next }
 			END {
-				printf "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
-					current, count, names, clients, fullscreen, desktops, selected, status
+				printf "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
+					current, count, names, clients, fullscreen, desktops, selected, layout, status
 			}
 		'
 }
@@ -350,6 +352,7 @@
 		IFS= read -r fullscreen_monitors
 		IFS= read -r monitor_desktops
 		IFS= read -r focused_monitor
+		IFS= read -r layout
 		IFS= read -r status
 	} <<ROOT_SNAPSHOT
 $(root_snapshot)
@@ -383,6 +386,7 @@
 	printf 'current=%s\n' "$current"
 	printf 'monitor_desktops=%s\n' "$monitor_desktops"
 	printf 'focused_monitor=%s\n' "$focused_monitor"
+	printf 'layout=%s\n' "$layout"
 	printf 'count=%s\n' "$count"
 	printf 'names=%s\n' "$names"
 	printf 'occupied=%s\n' "$occupied"
@@ -411,6 +415,7 @@
 			DWM_TAG_UPDATE \
 			_DWM_MONITOR_DESKTOPS \
 			_DWM_SELECTED_MONITOR \
+			_DWM_LAYOUT \
 			_NET_NUMBER_OF_DESKTOPS \
 			_NET_DESKTOP_NAMES \
 			_NET_ACTIVE_WINDOW \
@@ -472,6 +477,21 @@
 	rmdir "$watch_dir"
 }
 
+# Ask dwm for a layout by index into its layouts[] (the index hotkeys.toml's
+# layout_idx uses). dwm reads and clears this root property, and ignores an
+# index outside its layouts, so the range is enforced there; only the shape is
+# checked here.
+set_layout() {
+	index=${1:-}
+	case $index in
+	'' | *[!0-9]* | ???*)
+		printf 'usage: %s layout <index>\n' "$0" >&2
+		return 2
+		;;
+	esac
+	xprop -root -f _DWM_SET_LAYOUT 32c -set _DWM_SET_LAYOUT "$index"
+}
+
 switch_workspace() {
 	target=${1:-}
 	case $target in
@@ -548,11 +568,14 @@
 focus)
 	focus_window "${2:-}"
 	;;
+layout)
+	set_layout "${2:-}"
+	;;
 close)
 	close_window "${2:-}"
 	;;
 *)
-	printf 'usage: %s [state|watch|switch <zero-based-workspace>|focus <window-id>|close <window-id>]\n' "$0" >&2
+	printf 'usage: %s [state|watch|switch <zero-based-workspace>|focus <window-id>|close <window-id>|layout <index>]\n' "$0" >&2
 	exit 2
 	;;
 esac
```

```diff
--- a/tests/test-quickshell-state.sh
+++ b/tests/test-quickshell-state.sh
@@ -41,6 +41,10 @@
 	fi
 	exec sleep 30
 fi
+if [ "\$1" = "-root" ] && [ "\$2" = "-f" ]; then
+	printf '%s\n' "\$*" >>"$work/xprop-set.log"
+	exit 0
+fi
 if [ "\$1" = "-root" ]; then
 	if [ "\$2" = "_NET_CLIENT_LIST" ]; then
 		printf '_NET_CLIENT_LIST(WINDOW): window id # 0xaa, 0xbb, 0xcc, 0xdd, 0xee\n'
@@ -54,6 +58,7 @@
 _DWM_FULLSCREEN_MONITORS(STRING) = "1, 0, 1"
 _DWM_MONITOR_DESKTOPS(STRING) = "0, 1, 2"
 _DWM_SELECTED_MONITOR(CARDINAL) = 1
+_DWM_LAYOUT(CARDINAL) = 2
 WM_NAME(STRING) = "AC  |   VOL 15%"
 ROOT
 	exit 0
@@ -152,6 +157,7 @@
 expect 'count=9'
 expect 'names=one|two|three'
 expect 'focused_monitor=1'
+expect 'layout=2'
 expect 'monitor_desktops=0,1,2'
 expect 'status=AC | VOL 15%'
 
@@ -190,6 +196,19 @@
 [[ $total -le 8 ]] ||
 	fail "expected at most 8 xprop calls for 5 windows, got $total" "$work/xprop.log"
 
+# Asking for a layout sets the _DWM_SET_LAYOUT root property; a malformed index
+# is refused before anything is sent.
+: >"$work/xprop-set.log"
+PATH="$bin:$PATH" "$helper" layout 2 || fail 'layout 2 was refused'
+grep -Fqx -- '-root -f _DWM_SET_LAYOUT 32c -set _DWM_SET_LAYOUT 2' "$work/xprop-set.log" ||
+	fail 'layout did not set _DWM_SET_LAYOUT' "$work/xprop-set.log"
+for bad in '' abc -1 100 '1 2'; do
+	if PATH="$bin:$PATH" "$helper" layout "$bad" 2>/dev/null; then
+		fail "layout accepted a malformed index: $bad"
+	fi
+done
+[[ $(wc -l <"$work/xprop-set.log") -eq 1 ]] || fail 'a refused layout still reached xprop' "$work/xprop-set.log"
+
 watch_pid=
 # shellcheck disable=SC2016 # deferred by design: cleanup_add's argument is
 # eval'd later by lyona_run_cleanup, once $watch_pid actually holds a value.
```

**3. Quickshell.** Not run; these are small and follow existing patterns
(`closeWindow()` for the command, `PresetButton` in a `GridLayout` as the power
presets use, `SectionLabel` as the Appearance pane uses).

`config/quickshell/state/DwmState.qml`:

```diff
     property int currentWorkspace: 0
     property int focusedMonitorIndex: -1
+    // Index into dwm's layouts[] for the selected monitor's current tag
+    // (0 tile, 1 floating, 2 monocle), or -1 until dwm publishes _DWM_LAYOUT.
+    property int layoutIndex: -1
```

```diff
             } else if (key === "focused_monitor") {
                 const parsed = parseInt(value, 10);

                 root.focusedMonitorIndex = isNaN(parsed) ? -1 : parsed;
+            } else if (key === "layout") {
+                const parsed = parseInt(value, 10);
+
+                root.layoutIndex = isNaN(parsed) ? -1 : parsed;
             } else if (key === "names") {
```

```diff
     function closeWindow(windowId) {
         // Each request owns its command, even while an earlier close is running.
         Quickshell.execDetached(["dwm-quickshell-state", "close", windowId]);
     }
+
+    // Ask dwm to switch the selected monitor's current tag to a layout, by index
+    // into its layouts[]. dwm ignores an index it does not have.
+    function setLayout(index) {
+        Quickshell.execDetached(["dwm-quickshell-state", "layout", String(index)]);
+    }
```

`config/quickshell/controlcenter/ControlCenterWindow.qml`:

```diff
     required property var controlCenterModel
+    required property var dwmState
     required property var healthModel
```

```diff
     readonly property var powerPresets: root.powerModel.timeoutPresets
+    // Mirrors dwm's layouts[] (config.def.h): the index is what dwm expects.
+    readonly property var layoutChoices: [
+        { "label": "Tile", "index": 0 },
+        { "label": "Floating", "index": 1 },
+        { "label": "Monocle", "index": 2 }
+    ]
```

and on the overview page, between the "Power" row and the separator after it:

```diff
                     MenuRow {
                         Layout.fillWidth: true
                         implicitHeight: root.compactRowHeight
                         label: "Power"
                         navigates: true
                         onActivated: root.openSessionPower()
                     }
+
+                    PanelSeparator {
+                        Layout.topMargin: Theme.compactSpacing
+                        Layout.bottomMargin: Theme.compactSpacing
+                    }
+
+                    SectionLabel { label: "Window layout" }
+                    GridLayout {
+                        Layout.fillWidth: true
+                        columns: 3
+                        columnSpacing: Theme.spacingSm
+                        rowSpacing: Theme.spacingSm
+
+                        Repeater {
+                            model: root.layoutChoices
+
+                            delegate: PresetButton {
+                                required property var modelData
+
+                                Layout.fillWidth: true
+                                label: modelData.label
+                                active: root.dwmState.layoutIndex === modelData.index
+                                enabled: root.dwmState.layoutIndex >= 0
+                                onActivated: root.dwmState.setLayout(modelData.index)
+                            }
+                        }
+                    }

                     PanelSeparator {
```

`config/quickshell/shell.qml`, in the `ControlCenterWindow` block (line ~1451):

```diff
     ControlCenterWindow {
         controlCenterModel: controlCenterModel
+        dwmState: dwmState
         launcherModel: launcherModel
```

Several tests only grep `ControlCenterWindow.qml` (`test-quickshell-panel-menus.sh`,
`-controlcenter.sh`, `-update-model.sh`, `-power-model.sh`, `-panel-settings.sh`,
`test-settings.sh`); none constructs it, so the new required property breaks
none of them. Re-run them anyway.

**4. dwm behaviour test.** Add to `tests/test-xvfb-runtime.sh` right after
`xprop -root _DWM_SELECTED_MONITOR | grep -Eq '= 0$'` (line ~647). Every command
below was run by hand against the prototype dwm with the results above; the
snippet itself was not run inside the harness.

```sh
# Sync Sprint 11 S11-08: dwm publishes the selected monitor's layout for the
# current tag as _DWM_LAYOUT and takes a request through _DWM_SET_LAYOUT.
wait_for_layout() {
	i=0
	while [ "$i" -lt 100 ]; do
		[ "$(DISPLAY=$display xprop -root _DWM_LAYOUT 2>/dev/null | sed 's/.*= //')" = "$1" ] && return 0
		i=$((i + 1))
		sleep 0.05
	done
	printf 'expected _DWM_LAYOUT %s\n' "$1" >&2
	return 1
}
set_layout_property() {
	DISPLAY=$display xprop -root -f _DWM_SET_LAYOUT 32c -set _DWM_SET_LAYOUT "$1"
}
wait_for_layout 0
set_layout_property 2
wait_for_layout 2
set_layout_property 7
set_layout_property -1
sleep 0.2
wait_for_layout 2
DISPLAY=$display xprop -root _DWM_SET_LAYOUT 2>&1 | grep -q 'not found'
# Layouts are per tag: another tag has its own.
DISPLAY=$display xdotool set_desktop 1
wait_for_layout 0
DISPLAY=$display xdotool set_desktop 0
wait_for_layout 2
set_layout_property 0
wait_for_layout 0
```

The hotkey path (`Super+f`, `Super+t`) was also checked by hand; the harness
rewrites `hotkeys.toml` with its own bindings, so it is left out of the snippet.

**5. QML pins.** Add to `tests/test-quickshell-panel-menus.sh`:

```sh
grep -Fq 'required property var dwmState' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'onActivated: root.dwmState.setLayout(modelData.index)' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'property int layoutIndex: -1' "$repo/config/quickshell/state/DwmState.qml"
grep -Fq 'key === "layout"' "$repo/config/quickshell/state/DwmState.qml"
grep -Fq 'function setLayout(index)' "$repo/config/quickshell/state/DwmState.qml"
# The QML list must have one entry per layout dwm has.
qml_layouts=$(grep -c '"index": [0-9]' "$controlcenter/ControlCenterWindow.qml")
c_layouts=$(awk '/^static const Layout layouts\[\]/,/^};/' "$repo/config.def.h" | grep -c '^[[:space:]]*{ *"')
[ "$qml_layouts" = "$c_layouts" ] || {
	printf 'ControlCenterWindow.qml lists %s layouts, config.def.h defines %s\n' "$qml_layouts" "$c_layouts" >&2
	exit 1
}
```

**6. Docs.** `docs/src/control-center.md`: describe the "Window layout" row. Also
`CHANGELOG.md` and `TASKS.md`/evidence per `UPSTREAM-SYNC.md`.

### Not verified, and why

- **The QML.** Nothing in the UI ran. By hand: open the Control Center, confirm
  the current layout's button is highlighted, click each of the three and watch
  the windows re-tile, press `Super+t`/`Super+f` and confirm the highlight
  follows, and switch tags and confirm it follows the tag's own layout.
- **Multiple monitors.** The request applies to the selected monitor, as the
  hotkeys do; only one monitor was available.
- **A customised `layouts[]`.** The QML list is static. If a user's `config.h`
  reorders or adds layouts, the buttons would map to different layouts. The
  count pin catches a length mismatch in the repository's defaults only. A later
  improvement is for dwm to publish the symbols too.
- **Real windows.** The prototype ran with no client windows, so `arrange()` was
  not exercised by the property path (the hotkey path calls the same function).

## S11-09: A Picom window corner-radius slider

**Decided (D-12).** The corner half of issue `#297`. dwm draws square X borders, so
rounded window corners come from the compositor: Picom's `corner-radius` option.
Lyona's Compositor settings (Settings > Appearance > Compositor) expose opacity
and backend only. Add a "Window corner radius" slider, 0 to 32 px. It follows
`set-backend` exactly: a top-level scalar edited through the same
`Configuration.changes()` machinery, so comments and formatting are preserved, an
include is edited at its source, a stale revision is refused, and the edit is
validated before it is published. **No dwm change.**

### Facts checked (2026-09-26, Picom v13)

- `corner-radius VALUE` is a plain top-level option; `0` means no rounding; a
  per-window `corner-radius` also exists in `rules`, which overrides the global
  value (Picom's manual).
- Picom excludes fullscreen windows from rounding by default (manual).
- The manual says it "does not interact well with `--transparent-clipping`". No
  default Picom configuration ships in this repository, so a user's own config is
  the only place that could combine them; the slider's detail text says so.
- Real Picom accepts `corner-radius = 8;`: `picom --config F --backend xrender
  --diagnostics` (the helper's own validation command) and the same with `glx`
  both exit 0 under Xvfb. **`--diagnostics` also exits 0 for `corner-radius =
  "eight";`**, so Picom is not a type check; the helper's integer validation is
  the guard, and it has tests.
- Xvfb has no compositing (EGL errors in the diagnostics), so the rounding itself
  cannot be observed here.

### Changes

**1. `scripts/dwm-settings-picom`, and its tests.** Prototyped in a scratch copy of
the helper and `tests/test-picom.py`; the file parses; the 5 new tests pass;
the whole file passes (56 tests, the 51 existing ones included); two mutations
each fail the new tests (dropping the range check; not clearing the setting at
0). The helper writes `corner-radius = N;` for `N > 0` and removes the entry at
`0`, replaces an existing value rather than duplicating it, changes a value that
lives in an included file at its source, refuses fractional, negative,
non-finite and over-range values, and refuses to edit while Picom runs with a
command-line `--corner-radius` (as it does for opacity overrides).

```diff
--- a/scripts/dwm-settings-picom
+++ b/scripts/dwm-settings-picom
@@ -35,6 +35,8 @@
 # owner that exits a moment later. Retry that refusal rather than fail the user.
 TRANSIENT_REFUSAL = "Another composite manager is already running"
 LAUNCH_RETRIES = 3
+# Largest window corner radius the helper will write, in pixels.
+CORNER_RADIUS_MAX = 32
 BEGIN = "# lyona opacity defaults begin"
 END = "# lyona opacity defaults end"
 
@@ -444,6 +446,20 @@
             raise Error("Picom opacity must be between 0 and 1")
         return result
 
+    def corner_radius(self):
+        value = self.scalar("corner-radius", 0)
+        if (
+            isinstance(value, bool)
+            or not isinstance(value, (int, float))
+            or not math.isfinite(value)
+            or value != int(value)
+            or not 0 <= value <= CORNER_RADIUS_MAX
+        ):
+            raise Error(
+                f"Picom corner radius must be a whole number from 0 to {CORNER_RADIUS_MAX}"
+            )
+        return int(value)
+
     def changes(self, values):
         edits = {}
         for key, value in values.items():
@@ -801,6 +817,7 @@
         "editable": False,
         "active": 100,
         "inactive": 100,
+        "corner_radius": 0,
         "policy": "auto",
         "effective": "",
         "override": "",
@@ -816,6 +833,7 @@
         result["revision"] = config.revision()
         active, inactive = config.opacity()
         result.update(active=active * 100, inactive=inactive * 100)
+        result["corner_radius"] = config.corner_radius()
         policy, effective, override, gpu = backend(
             config, detect and result["installed"]
         )
@@ -968,6 +986,19 @@
             if any(not math.isfinite(v) or not 0 <= v <= 100 for v in args):
                 raise Error("Opacity must be between 0 and 100 percent")
             changes = config.opacity_changes(*(v / 100 for v in args))
+        elif action == "set-corner-radius":
+            radius = args[0]
+            if (
+                not math.isfinite(radius)
+                or radius != int(radius)
+                or not 0 <= radius <= CORNER_RADIUS_MAX
+            ):
+                raise Error(
+                    f"Corner radius must be a whole number from 0 to {CORNER_RADIUS_MAX} pixels"
+                )
+            if any(option(p["args"], ("--corner-radius",)) for p in processes()):
+                raise Error("Remove the command-line corner radius override before editing")
+            changes = config.changes({"corner-radius": None if radius == 0 else int(radius)})
         elif action == "set-backend":
             if os.environ.get("PICOM_BACKEND"):
                 raise Error(
@@ -1215,6 +1246,9 @@
     opacity.add_argument("active", type=float)
     opacity.add_argument("inactive", type=float)
     opacity.add_argument("revision")
+    corner = subs.add_parser("set-corner-radius")
+    corner.add_argument("radius", type=float)
+    corner.add_argument("revision")
     selector = subs.add_parser("set-backend")
     selector.add_argument("backend", choices=BACKENDS)
     selector.add_argument("revision")
@@ -1225,10 +1259,12 @@
         print(json.dumps(status()))
     elif args.action == "watch":
         watch()
-    elif args.action in ("set-opacity", "set-backend", "copy-config"):
+    elif args.action in ("set-opacity", "set-corner-radius", "set-backend", "copy-config"):
         values = (
             [args.active, args.inactive]
             if args.action == "set-opacity"
+            else [args.radius]
+            if args.action == "set-corner-radius"
             else [args.backend]
             if args.action == "set-backend"
             else []
```

```diff
--- a/tests/test-picom.py
+++ b/tests/test-picom.py
@@ -317,6 +317,53 @@
             )
         self.assertEqual(child.read_text(), "active-opacity=.8;")
 
+    def test_corner_radius_is_set_replaced_and_cleared(self):
+        config = self.write("# keep\nactive-opacity = 0.8;\n")
+        self.assertEqual(config.corner_radius(), 0)
+        picom.mutate("set-corner-radius", [8], config.revision())
+        text = self.path.read_text()
+        self.assertIn("# keep", text)
+        self.assertIn("corner-radius = 8;", text)
+        self.assertEqual(picom.Configuration().corner_radius(), 8)
+        picom.mutate("set-corner-radius", [12], picom.Configuration().revision())
+        self.assertEqual(self.path.read_text().count("corner-radius"), 1)
+        self.assertEqual(picom.Configuration().corner_radius(), 12)
+        picom.mutate("set-corner-radius", [0], picom.Configuration().revision())
+        self.assertNotIn("corner-radius", self.path.read_text())
+        self.assertIn("# keep", self.path.read_text())
+        self.assertIn("active-opacity = 0.8;", self.path.read_text())
+
+    def test_corner_radius_rejects_bad_values_and_unreadable_config(self):
+        config = self.write("corner-radius = 4;\n")
+        for value in (-1, picom.CORNER_RADIUS_MAX + 1, 2.5, float("nan"), float("inf")):
+            with self.assertRaises(picom.Error):
+                picom.mutate("set-corner-radius", [value], config.revision())
+        self.assertEqual(self.path.read_text(), "corner-radius = 4;\n")
+        for text in ("corner-radius = oops;\n", 'corner-radius = "5";\n', "corner-radius = 99;\n"):
+            with self.assertRaises(picom.Error):
+                self.write(text).corner_radius()
+
+    def test_corner_radius_refuses_a_command_line_override(self):
+        config = self.write("")
+        running = [{"args": ["picom", "--corner-radius", "6"], "pid": 1}]
+        with patch.object(picom, "processes", return_value=running):
+            with self.assertRaisesRegex(picom.Error, "corner radius override"):
+                picom.mutate("set-corner-radius", [4], config.revision())
+        self.assertEqual(self.path.read_text(), "")
+
+    def test_corner_radius_in_an_include_is_changed_at_its_source(self):
+        include = self.config / "extra.conf"
+        include.write_text("corner-radius = 3;\n")
+        config = self.write('@include "extra.conf"\n')
+        picom.mutate("set-corner-radius", [7], config.revision())
+        self.assertIn("corner-radius = 7;", include.read_text())
+        self.assertNotIn("corner-radius", self.path.read_text())
+
+    def test_status_reports_the_corner_radius(self):
+        self.write("corner-radius = 6;\n")
+        with patch.object(picom, "renderer", return_value="intel"):
+            self.assertEqual(picom.status(False)["corner_radius"], 6)
+
     def test_backend_precedence_and_auto(self):
         config = self.write('backend="glx"; # preserve\n')
         with patch.object(picom, "renderer", return_value="nvidia"):
```

Also add a sentence to the detail text `status()` builds (next to "Global
opacity; custom window rules may override these defaults."): `"Corner radius
applies to every window except fullscreen ones; per-window rules can override it,
and it does not combine well with transparent-clipping."`

**2. `config/quickshell/appearance/PicomModel.qml`.** Not run.

```diff
     property var snapshot: ({ protocol: 1, editable: false, installed: false,
-        active: 100, inactive: 100, policy: "auto", effective: "", override: "",
+        active: 100, inactive: 100, corner_radius: 0, policy: "auto", effective: "", override: "",
```

`accept()` validates the response strictly, so add the field's check (tolerating a
missing field from an older helper):

```diff
                 || value.active < 0 || value.active > 100 || value.inactive < 0 || value.inactive > 100
+                || (value.corner_radius !== undefined
+                    && (!Number.isInteger(value.corner_radius) || value.corner_radius < 0 || value.corner_radius > 32))
                 || ["auto", "xrender", "glx", "egl"].indexOf(value.policy) < 0)
```

```diff
     function setOpacity(active, inactive, revision) {
         root.mutate("set-opacity", [String(active), String(inactive)], revision);
     }
+
+    function setCornerRadius(radius, revision) {
+        root.mutate("set-corner-radius", [String(radius)], revision);
+    }
```

**3. `config/quickshell/settings/PicomSettingsPane.qml`.** Not run. It repeats the
opacity sliders' debounce (apply on release, or 250 ms after the last keyboard
step) with its own state, so a radius edit and an opacity edit do not interfere.

```diff
     property real inactiveOpacity: 100
+    property real cornerRadius: 0
     property bool changed: false
+    property bool radiusChanged: false
     property string editRevision: ""
+    property string radiusRevision: ""
```

```diff
     function synchronize() {
         if (!root.model.snapshot.editable) {
             keyboardDelay.stop();
+            radiusDelay.stop();
             root.changed = false;
-        } else if (foreground.pressed || background.pressed || root.changed) return;
+            root.radiusChanged = false;
+        } else if (foreground.pressed || background.pressed || corners.pressed
+                || root.changed || root.radiusChanged) return;
         root.activeOpacity = root.model.snapshot.active;
         root.inactiveOpacity = root.model.snapshot.inactive;
+        root.cornerRadius = root.model.snapshot.corner_radius || 0;
     }
```

```diff
+    function applyCornerRadius() {
+        radiusDelay.stop();
+        if (!root.radiusChanged) return;
+        if (!root.model.snapshot.editable) {
+            root.synchronize();
+            return;
+        }
+        if (root.model.busy) return;
+        root.radiusChanged = false;
+        root.model.setCornerRadius(root.cornerRadius, root.radiusRevision);
+    }
+
```

```diff
         function onBusyChanged() {
             if (!root.model.busy) {
                 if (root.changed) keyboardDelay.restart();
+                else if (root.radiusChanged) radiusDelay.restart();
                 else root.synchronize();
             }
         }
```

```diff
+    UiText {
+        text: "Window corner radius: " + Math.round(root.cornerRadius) + " px"
+        color: Theme.menuText
+    }
+    Controls.Slider {
+        id: corners
+        objectName: "picomCornerRadius"
+        Accessible.name: "Window corner radius"
+        palette.highlight: Theme.accent
+        palette.button: Theme.controlNormalFill
+        Layout.fillWidth: true
+        from: 0; to: 32; stepSize: 1
+        value: root.cornerRadius
+        enabled: root.model.editable
+        onMoved: {
+            if (!root.radiusChanged) root.radiusRevision = root.model.snapshot.revision;
+            root.cornerRadius = value;
+            root.radiusChanged = true;
+            if (!pressed) radiusDelay.restart();
+        }
+        onPressedChanged: { if (!pressed) root.applyCornerRadius(); }
+    }
     UiText {
         text: "Backend" + ...
```

```diff
     Timer {
         id: keyboardDelay
         interval: 250
         onTriggered: root.applyOpacity()
     }
+    Timer {
+        id: radiusDelay
+        interval: 250
+        onTriggered: root.applyCornerRadius()
+    }
```

**4. QML tests.** Extend the existing Picom model harness (`tests/qml/PicomModel.inc`,
`tests/fixtures/picom-model.py`, run by `check-quickshell-picom-model-xvfb`):
give its fixture snapshot a `corner_radius`, assert `accept()` rejects `-1`, `33`
and `2.5`, accepts a response with no `corner_radius`, and that
`setCornerRadius(8, "rev")` runs `set-corner-radius 8 rev`. Read the harness
first; it was not read for this plan. Add source pins for the slider
(`objectName: "picomCornerRadius"`, `from: 0; to: 32`) next to the existing
opacity-slider pins in the settings tests, and one real-Picom case to
`tests/test-picom-xvfb.py`: `set-corner-radius 8`, then `status` reports `8` and
Picom still starts.

**5. Docs.** `docs/src/theming.md`, section "Picom opacity and backend": add the
corner-radius slider and the fullscreen and `transparent-clipping` notes.
`CHANGELOG.md`, `TASKS.md`, evidence.

### Not verified, and why

- **The rounding itself.** Xvfb cannot composite. Check by eye on a real session
  with each backend the machine supports: a tiled window, a floating window, a
  window with dwm's border, and a fullscreen window (should stay square).
- **Interaction with dwm's border.** dwm draws a 1 px X border; how Picom clips
  it at a rounded corner was not observed.
- **The QML** (model, pane, slider behaviour).

---

## Verification (whole sprint)

Same gates as every sprint:

```bash
scripts/run-tests make clean all check-shell check-format check-quickshell-qml
scripts/run-tests make check
```

then the manual **Full suite (manual)** workflow on the branch and on `main`.
New or extended targets: `check-quickshell-theme-contrast` (S11-01),
`check-appearance` (S11-02), `check-app-palettes` and `check-qt-palette-xvfb`
(S11-06), `check-picom` (S11-09), `check-quickshell-state` and
`check-xvfb-runtime` (S11-08). S11-04 is confirmed on a live desktop by seeing
no stray notification.

Automated checks here cover values, files and behaviour under Xvfb, not
appearance. Do not mark these verified without the by-eye checks each item lists:
S11-01 a light and a dark preset, S11-02 a running Thunar, S11-06 a Qt app under
`qt6ct`, S11-07 the launcher, control center, Settings and a notification,
S11-08 each layout button, S11-09 rounded corners on a real compositor.

## Not in this sprint

Upstream's `#355` (Fedora DNF defaults, initial-update service, kickstarts),
`#353`, `#357` and issue `#356` (Fedora NetworkManager packaging), the desktop
updater half of `#354` (D-8), `#341` and `#342` (workflow bumps for actions
Lyona does not use), issue `#298`, dwm gaps, and a border-width slider (D-12).
