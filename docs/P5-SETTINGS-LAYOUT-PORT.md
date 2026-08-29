# Port Plan — Settings Window Enlargement and Compaction (dwm-titus PR #186, part 2 of 2)

Upstream: [ChrisTitusTech/dwm-titus#186](https://github.com/ChrisTitusTech/dwm-titus/pull/186)
`feat(settings): persist panel widgets and compact Settings`.

Part 1 — panel-widget persistence — is planned in
[`P5-PANEL-WIDGETS-PORT.md`](P5-PANEL-WIDGETS-PORT.md). This is the second,
independent half, kept as its own commit: it is cosmetic, it touches numbers
our tests already pin, and it is independently revertible.

---

## Context

Our Settings window is a fixed 980x620 with generous section spacing, a 52 px
navigation row height, and display controls sized for a larger window than we
now have content for. Upstream's change:

- grows the window to 1180x760 **where the screen allows**, clamping to
  `screen.width - 32` / `screen.height - 32` on smaller outputs;
- tightens navigation rows, pane margins, and capability cards so all nine
  sections stay visible without reducing the user's configured text scale;
- compacts the display-output cards and position inputs, and makes the output
  card height content-driven instead of a hardcoded 126 px.

The tightening exists to buy room for the new "Panel widgets" section added in
part 1, but neither half depends on the other landing first.

### DPI impact

This commit does **not** change the DPI value or the scaling pipeline
(`dwm-settings-display` → `dpi.current` → `shell.qml` `dpiStateWatch` →
`Theme.applyDisplayDpi` → `Theme.uiScale` → `dp()`). Nothing here reads or
writes `Xft.dpi`. But it does resize DPI-dependent layout, so the DPI hot-reload
behaviour is worth re-checking after it lands:

| Change | Effect at high DPI / text scale |
| --- | --- |
| Output card `126` → `Math.max(104, outputContent.implicitHeight + 16)` (§3b) | **Improves.** Replaces a hardcoded height that clipped its own contents. |
| Capability card `Math.max(92, …+24)` → `Math.max(78, …+16)` (§2h) | **Neutral.** Content-driven either way; only the floor drops. |
| Nav row `52` → `44` (§2e) | **Would regress** — raw constant, content is scaled. Deviating from upstream; see §2e. |
| X/Y position inputs `72` → `60` (§3d, §3e) | **Slightly worse.** Raw width; a 4-digit coordinate at 2x scale has less room. Acceptable — the field elides, not clips — but verify at max text scale. |
| Window `980x620` → `1180x760` | **Neutral.** Both are raw, screen-clamped. Panes scroll, so the larger size only adds room. |

### Prerequisite: land a DPI hot-reload gate first (commit 0)

The table above is reasoning, not evidence, because **the DPI hot-reload path is
currently untested**:

- `tests/test-quickshell-settings-xvfb.sh:727-732` is the only DPI assertion
  under a running shell, and it reads `settings displayDpi` →
  `settingsModel.displayDpi`, the value parsed from `dwm-settings-display
  discover`. It proves the Settings pane *reports* DPI. It never reaches
  `Theme.displayDpi`, `Theme.uiScale`, or the `dpiStateWatch` `FileView`.
- `tests/test-settings.sh:333-399` covers the helper thoroughly (`dpi-set`,
  `dpi-apply-saved`, `dpi-reset`, rejection, Xresources, xrdb) but never starts
  Quickshell.
- Nothing writes `dpi.current` at runtime and asserts the shell reacted.
  `publish_dpi_state()` (`dwm-settings-display:282`) has no end-to-end cover,
  and no IPC exposes `Theme.uiScale`.

So before either commit, add the gate and prove it green on the **unmodified**
tree:

1. Two additive IPC probes in the `settings` handler — pure reads, no behaviour
   change:

```qml
        function themeDisplayDpi(): int {
            return Theme.displayDpi;
        }

        function themeUiScale(): real {
            return Theme.uiScale;
        }
```

2. An xvfb stage that actually exercises the reload:

```sh
test_stage='validating DPI hot reload into the shared theme'
[ "$(… call settings themeUiScale)" = 1 ]
mkdir -p "$runtime/dwm-settings-display"
printf 'dpi-state-protocol\t1\ndpi\t192\n' > "$runtime/dwm-settings-display/dpi.current"
# poll themeUiScale until it reads 2, without restarting the shell
# then: a malformed file must leave the value at 2 (the `valid` guard,
# shell.qml:192), not reset it to the 96/1.0 default
```

3. Run it on current `HEAD`. Green = hot reload works today and we have a
   baseline. Red = a live bug, found before adding to it.

4. The same stage then gates the panel commit and this one.

This also settles §2e empirically instead of by arithmetic: at 192 DPI, read the
nav delegate's `sectionRow.implicitHeight` and compare it against both `44` and
`52`. If `52` already overflows today, the `Math.max` deviation is a fix rather
than caution.

> Running any of this needs `xorg-server-xvfb` and `inotify-tools`, neither of
> which is installed on the current workstation.

### Two deliberate departures from upstream

1. **Navigation width.** Upstream hardcodes `Layout.preferredWidth: 232`,
   replacing `Theme.largeSurfaceNavWidth`. A raw number is not scaled by
   `Theme.dp()`, so it stops responding to the user's UI scale — the exact
   thing the rest of this change is trying to protect. And
   `largeSurfaceNavWidth` (`dp(248)`) is shared with
   `SystemHealthWindow.qml:161`, so narrowing the token would silently resize
   an unrelated surface. Add a dedicated scaled token instead.
2. **`statusColor`.** Upstream's diff context shows
   `root.statusColor(modelData.status)`; ours is already
   `Theme.statusColor(modelData.status)`. Leave ours alone.

---

## 1. `config/quickshell/core/Theme.qml`

Add a Settings-specific nav width next to the existing shared one (line ~175),
rather than changing `largeSurfaceNavWidth`:

```diff
     readonly property int largeSurfaceNavWidth: dp(248)
+    readonly property int settingsNavWidth: dp(232)
```

---

## 2. `config/quickshell/settings/SettingsWindow.qml`

**2a.** Window geometry, lines 24-25. `Math.min` against the screen keeps the
enlarged window usable on a 1024x600 panel:

```diff
-    implicitWidth: 980
-    implicitHeight: 620
+    implicitWidth: Math.min(1180, root.screen ? Math.max(1, root.screen.width - 32) : 1180)
+    implicitHeight: Math.min(760, root.screen ? Math.max(1, root.screen.height - 32) : 760)
```

**2b.** Outer column spacing, line 58:

```diff
             ColumnLayout {
                 anchors.fill: parent
-                spacing: Theme.sectionSpacing
+                spacing: Theme.spacingXl
```

**2c.** Nav/content split spacing and nav width, lines 159-162:

```diff
                 RowLayout {
                     Layout.fillWidth: true
                     Layout.fillHeight: true
-                    spacing: Theme.sectionSpacing
+                    spacing: Theme.spacingXl

                     Rectangle {
-                        Layout.preferredWidth: Theme.largeSurfaceNavWidth
+                        Layout.preferredWidth: Theme.settingsNavWidth
                         Layout.fillHeight: true
```

**2d.** Nav column margins and list spacing, lines 169-186:

```diff
                         ColumnLayout {
                             anchors.fill: parent
-                            anchors.margins: Theme.spacingXl
-                            spacing: Theme.spacingLg
+                            anchors.margins: Theme.spacingLg
+                            spacing: Theme.spacingMd

                             SectionLabel {
                                 label: "Sections"
                             }

                             ListView {
                                 id: sectionList

                                 Layout.fillWidth: true
                                 Layout.fillHeight: true
                                 clip: true
-                                spacing: Theme.spacingSm
+                                spacing: Theme.spacingXxs
                                 model: root.settingsModel.filteredSections
```

**2e.** Nav row height, line 195. This is the single biggest contributor to
getting all nine sections visible.

**Deviate from upstream here.** Upstream simply changes `52` to `44`. That is a
raw pixel constant: it is not run through `Theme.dp()` and it is not
content-driven, while everything inside the row *is* DPI- and text-scale-driven
(`fontBodySize` label + `fontCaptionSize` description + `spacingXxs`, all
multiplied by `uiScale` and `fontScale`). At 96 DPI / 1.0 text scale the
content is roughly 25 px and fits either number. At 192 DPI with a 1.5 text
scale it is roughly 73 px and overflows both — so this is a pre-existing defect
that upstream's number makes about 15% worse rather than a new one.

Since our DPI hot-reload work (commits `2a49ffd`, `aadbe8c`) exists precisely to
make these surfaces track `Xft.dpi`, make the row content-driven instead. This
uses the same `anchors.fill` + read-`implicitHeight` pattern upstream itself
uses for the display output card in §3b:

```diff
                                     width: sectionList.width
-                                    height: 52
+                                    height: Math.max(Theme.dp(44),
+                                        sectionRow.implicitHeight + Theme.spacingSm)
```

which needs an id on the row in §2f below.

**2f.** Nav row internals, lines 212-216. The `id` is what §2e reads:

```diff
                                     RowLayout {
+                                        id: sectionRow
+
                                         anchors.fill: parent
-                                        anchors.leftMargin: 12
-                                        anchors.rightMargin: 10
-                                        spacing: Theme.spacingLg
+                                        anchors.leftMargin: 10
+                                        anchors.rightMargin: 8
+                                        spacing: Theme.spacingMd
```

**2g.** Content pane margins, lines 285-286:

```diff
                         ColumnLayout {
                             anchors.fill: parent
-                            anchors.margins: Theme.spacingHuge
-                            spacing: Theme.sectionSpacing
+                            anchors.margins: Theme.spacingXxl
+                            spacing: Theme.spacingXl
```

**2h.** Capability list spacing (`capabilityList`, line ~399) and card
geometry, lines 410 and 429-433:

```diff
                                 clip: true
-                                spacing: Theme.spacingLg
+                                spacing: Theme.spacingMd
                                 model: root.settingsModel.capabilitiesForSection(root.settingsModel.selectedSectionId)
```

```diff
                                     width: capabilityList.width
-                                    height: Math.max(92, cardColumn.implicitHeight + 24)
+                                    height: Math.max(78, cardColumn.implicitHeight + 16)
```

```diff
                                         anchors.fill: parent
-                                        anchors.leftMargin: 16
-                                        anchors.rightMargin: 12
-                                        anchors.topMargin: 12
-                                        anchors.bottomMargin: 12
-                                        spacing: Theme.spacingSm
+                                        anchors.leftMargin: 12
+                                        anchors.rightMargin: 10
+                                        anchors.topMargin: 8
+                                        anchors.bottomMargin: 8
+                                        spacing: Theme.spacingXs
```

---

## 3. `config/quickshell/settings/DisplaySettingsPane.qml`

**3a.** Column spacing, line 49:

```diff
     ColumnLayout {
         id: contentColumn
         width: root.width
-        spacing: Theme.sectionSpacing
+        spacing: Theme.spacingLg
```

**3b.** Output card height becomes content-driven, line 102. The hardcoded 126
clipped its own contents once text scale went up:

```diff
                 Layout.fillWidth: true
-                Layout.preferredHeight: 126
+                Layout.preferredHeight: Math.max(104, outputContent.implicitHeight + 16)
                 color: Theme.controlNormalFill
```

**3c.** Which requires naming the content column, lines 118-123:

```diff
                 ColumnLayout {
+                    id: outputContent
+
                     anchors.fill: parent
-                    anchors.leftMargin: 16
-                    anchors.rightMargin: 10
-                    anchors.topMargin: 10
-                    anchors.bottomMargin: 10
+                    anchors.leftMargin: 12
+                    anchors.rightMargin: 8
+                    anchors.topMargin: 8
+                    anchors.bottomMargin: 8
                     spacing: Theme.tightSpacing
```

**3d.** X position input, lines 145-153:

```diff
                         Rectangle {
-                            Layout.preferredWidth: 72
-                            Layout.preferredHeight: Math.max(Theme.controlRowHeight,
-                                xPositionInput.implicitHeight + 14)
+                            Layout.preferredWidth: 60
+                            Layout.preferredHeight: Math.max(Theme.controlHeight,
+                                xPositionInput.implicitHeight + 10)
                             color: Theme.controlNormalFill; border.color: Theme.controlNormalBorder; radius: Theme.controlRadius
                             TextInput {
                                 id: xPositionInput
                                 anchors.fill: parent
-                                anchors.margins: 7
+                                anchors.margins: 5
```

**3e.** Y position input, lines 169-177 — identical shape:

```diff
                         Rectangle {
-                            Layout.preferredWidth: 72
-                            Layout.preferredHeight: Math.max(Theme.controlRowHeight,
-                                yPositionInput.implicitHeight + 14)
+                            Layout.preferredWidth: 60
+                            Layout.preferredHeight: Math.max(Theme.controlHeight,
+                                yPositionInput.implicitHeight + 10)
                             color: Theme.controlNormalFill; border.color: Theme.controlNormalBorder; radius: Theme.controlRadius
                             TextInput {
                                 id: yPositionInput
                                 anchors.fill: parent
-                                anchors.margins: 7
+                                anchors.margins: 5
```

**3f.** Profile name input, lines 288-290:

```diff
             Rectangle {
                 Layout.fillWidth: true
-                Layout.preferredHeight: Math.max(36, profileNameInput.implicitHeight + 16)
+                Layout.preferredHeight: Math.max(Theme.controlHeight,
+                    profileNameInput.implicitHeight + 12)
                 color: Theme.controlNormalFill; border.color: Theme.controlNormalBorder; radius: Theme.controlRadius
-                TextInput { id: profileNameInput; anchors.fill: parent; anchors.margins: 8; text: root.profileName; color: Theme.textStrong; font.family: Theme.fontFamily; font.pixelSize: Theme.inputFontSize; onTextChanged: root.profileName = text }
+                TextInput { id: profileNameInput; anchors.fill: parent; anchors.margins: 6; text: root.profileName; color: Theme.textStrong; font.family: Theme.fontFamily; font.pixelSize: Theme.inputFontSize; onTextChanged: root.profileName = text }
             }
```

Leave the `confirmationRow.implicitHeight + 16` binding at line 313 alone —
upstream does not touch it, and `test-quickshell-appearance-model.sh:225`
pins it.

---

## 4. `tests/test-quickshell-appearance-model.sh`

These asserts exist specifically to stop text-scale-responsive sizing from
regressing back to fixed heights, so they must move with the values. Lines
222-224:

```diff
-grep -Fq 'xPositionInput.implicitHeight + 14' "$display_pane"
-grep -Fq 'yPositionInput.implicitHeight + 14' "$display_pane"
-grep -Fq 'profileNameInput.implicitHeight + 16' "$display_pane"
+grep -Fq 'xPositionInput.implicitHeight + 10' "$display_pane"
+grep -Fq 'yPositionInput.implicitHeight + 10' "$display_pane"
+grep -Fq 'Math.max(104, outputContent.implicitHeight + 16)' "$display_pane"
+grep -Fq 'profileNameInput.implicitHeight + 12' "$display_pane"
 grep -Fq 'confirmationRow.implicitHeight + 16' "$display_pane"
```

---

## 5. `tests/test-quickshell-settings-xvfb.sh`

Parameterise the geometry so the clamp can actually be exercised, rather than
just asserting the new fixed size.

Line ~4, after `repo=`:

```diff
 repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
+screen_geometry=${DWM_SETTINGS_TEST_SCREEN_GEOMETRY:-1280x800x24}
+expected_window_width=${DWM_SETTINGS_EXPECTED_WINDOW_WIDTH:-1180}
+expected_window_height=${DWM_SETTINGS_EXPECTED_WINDOW_HEIGHT:-760}
```

Line 539:

```diff
-Xvfb "$display" -screen 0 1280x800x24 -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
+Xvfb "$display" -screen 0 "$screen_geometry" -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
```

Lines 701-702:

```diff
-[ "$width" = 980 ]
-[ "$height" = 620 ]
+[ "$width" = "$expected_window_width" ]
+[ "$height" = "$expected_window_height" ]
```

---

## 6. `CHANGELOG.md`

Under `## [Unreleased]` → `### Changed`:

```markdown
- Increase the Settings window to 1180x760 and tighten its navigation rows,
  pane margins, capability cards, and display controls so more options remain
  visible without reducing the configured text scale. Clamp the enlarged
  window to the active screen on smaller outputs.
```

---

## Verification

```bash
scripts/run-tests make check-quickshell-appearance-model check-quickshell-design-system
scripts/run-tests make check-quickshell-qml

# Default: full-size window on a 1280x800 screen
scripts/run-tests env DWM_SETTINGS_POWER_CPU_SECONDS=0 tests/test-quickshell-settings-xvfb.sh

# Clamped: 1024x768 -> 992x736
scripts/run-tests env DWM_SETTINGS_POWER_CPU_SECONDS=0 \
  DWM_SETTINGS_TEST_SCREEN_GEOMETRY=1024x768x24 \
  DWM_SETTINGS_EXPECTED_WINDOW_WIDTH=992 \
  DWM_SETTINGS_EXPECTED_WINDOW_HEIGHT=736 \
  tests/test-quickshell-settings-xvfb.sh

# Clamped on height only: 1024x600 -> 992x568
scripts/run-tests env DWM_SETTINGS_POWER_CPU_SECONDS=0 \
  DWM_SETTINGS_TEST_SCREEN_GEOMETRY=1024x600x24 \
  DWM_SETTINGS_EXPECTED_WINDOW_WIDTH=992 \
  DWM_SETTINGS_EXPECTED_WINDOW_HEIGHT=568 \
  tests/test-quickshell-settings-xvfb.sh

scripts/run-tests make check
```

Live desktop, after `scripts/dev-sync-install.sh` and a logout/login:

1. Open Settings. All nine sections are visible in the navigation list without
   scrolling, at the default text scale.
2. Raise the text scale (Settings → Appearance → Text scale) to its maximum.
   Navigation rows, capability cards, and the display X/Y and profile inputs
   grow with the text instead of clipping it — that is what the
   `implicitHeight + n` bindings buy, and what the `test-quickshell-appearance-model.sh`
   asserts guard.
3. Displays section: output cards size to their content; the X/Y position
   fields still accept and commit edits.
4. On a smaller output (or `xrandr --output ... --mode 1024x768`), the window
   clamps to the screen rather than overflowing it.
