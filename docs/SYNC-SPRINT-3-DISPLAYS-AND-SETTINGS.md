# Sync Sprint 3 — displays, Settings responsiveness, Appearance and shell polish

Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md). Upstream surveyed at `d4c6d89`.
Independent of Sprints 1–2 except [S3-05](#s3-05-settings-readiness-and-startup-work),
which touches `SystemRegionalControls.qml` (a 5-line hunk from `#294`). If Sprint 1
hasn't merged, apply that hunk when it does.

**Goal:** everything upstream did to the everyday desktop surfaces since
`dd55e58`, **plus** two open upstream issues Chris filed that upstream has
not fixed yet (`#310`, `#315`), plus the one pre-existing open sync item
(`c3e9a18`).

| Item | Upstream | Kind | Size |
| --- | --- | --- | --- |
| [S3-01](#s3-01-relative-monitor-placement-and-numbered-preview) | `#289` `55dbd76` | Port | ~+420 |
| [S3-02](#s3-02-docked-and-undocked-display-profiles) | `#290` `6b7548b` | Port + Arch adaptation | ~+870 |
| [S3-03](#s3-03-hide-dock-profiles-without-a-system-battery) | issue **`#310` (open upstream)** | **New work**, literal code | ~+80 |
| [S3-04](#s3-04-control-center-compaction) | `c3e9a18` | Port — **open since the first survey** | ~+80 |
| [S3-05](#s3-05-settings-readiness-and-startup-work) | `#291` (Settings half), `#294` `080b39e`, `#295` `8df119c`, issue **`#315` (open)** | Port + new work | ~+900 |
| [S3-06](#s3-06-power-menu-settings-full-screen-cursor-reload-tray-self-heal) | `#307` `56ec27b` — closes issues `#302`–`#306` | Port | ~+690 |
| [S3-07](#s3-07-appearance-simplification-and-desktop-typography) | `#327` `a5b829d`, `68a0d1f` | Port — **decision D-7** | ~+880 |
| [S3-08](#s3-08-panel-stays-sharp-under-popups) | `#324` `c44dae4` | Port — applies cleanly | ~+60 |
| [S3-09](#s3-09-pre-survey-gaps-183-188-191) | `#183` `e91d018`, `#188` `c8f574b`, `#191` `4d776bc` | **Found in this survey:** never ported or never recorded | ~+30 / ~+1,000 tests / ~+40 |

Suggested order: S3-08 (trivial) → S3-04 → S3-01 → S3-02 → S3-03 → S3-06 →
S3-05 → S3-07 (largest, and it touches the most shared files, so land it last)
→ S3-09. Exceptions inside S3-09: port `#191`'s refresh coalescing **before
S3-05**, which calls it. `#183` is independent and can go any time. `#188`'s
tests target the Appearance surface, so they land last.

---

## S3-01: Relative monitor placement and numbered preview

Upstream `#289` (`55dbd76`).

| Upstream file | Lyona | Change |
| --- | --- | --- |
| `config/quickshell/settings/DisplayLayout.js` | **New** | 66 lines: pure placement math (left-of / right-of / above / below → x/y) |
| `config/quickshell/settings/DisplaySettingsPane.qml` | exists, **428 changed lines vs upstream HEAD** | +102/−52: per-output "position relative to" selector; numbered monitor tiles in the preview |
| `config/quickshell/settings/SettingsModel.qml` | exists | +42 |
| `scripts/dwm-settings-display` | exists | +29/−3 — accept relative placement; see literal hunk below |
| `tests/quickshell-display-layout.qml` | **New** | → `tests/qml/tst_display_layout.qml` |
| `tests/test-dwm-display-setup.sh`, `tests/test-settings.sh` | exist | +37, +17/−3 |

`6b7548b` also carries a driver-quirk fix to `dwm-settings-display`'s
`discover()`. Take it here, since it matters for placement too:

```diff
@@ discover() {
+				# Some drivers separate the preferred/current markers from the rate.
+				if (i < NF && $(i + 1) ~ /^[+*]+$/) {
+					current = current || index($(i + 1), "*") > 0
+					preferred = preferred || index($(i + 1), "+") > 0
+				}
```

**Lyona adaptation:** Lyona's `DisplaySettingsPane.qml` carries the
resolution-preview/apply workflow (earlier sync Phase 9) and `Theme.dp()`
geometry. Port `#289`'s hunks **into** Lyona's file. Don't take upstream's
file: the resolution countdown, `ShellButton` primary/pending states and DPI
decoupling must survive. Wrap every new pixel constant in `Theme.dp()`.

---

## S3-02: Docked and undocked display profiles

Upstream `#290` (`6b7548b`). Adds an **unprivileged autorandr profile editor**,
`scripts/dwm-settings-display-profiles` (Python, 301 lines,
`status | save undocked|docked SPEC...`). It never applies a layout.
`autorandr` applies it at login and hotplug.

| File | Change |
| --- | --- |
| `scripts/dwm-settings-display-profiles` | **New** (Python) |
| `config/quickshell/core/Commands.qml` | `settingsDisplayProfilesCommand(action, args)` → `helperCommand("dwm-settings-display-profiles", action, args, true)` |
| `config/quickshell/settings/DisplaySettingsPane.qml` | +162 — "Automatic layouts" section with Undocked/Docked cards |
| `config/quickshell/settings/SettingsModel.qml` | +133 — `automaticDisplayState`, `automaticDisplayProfile()`, `automaticDisplayArrangement()`, save process |
| `Makefile` | `INSTALL_COMMANDS += scripts/dwm-settings-display-profiles`; `python3 tests/test-display-profiles.py` in a check target |
| `tests/test-display-profiles.py` | **New** (188) |
| `tests/quickshell-display-profiles.qml` | **New** → `tests/qml/tst_display_profiles.qml` |

**Lyona adaptations**

1. **Package.** `autorandr` is in Arch `extra` (1.15). Add it to the optional
   profile so a missing package degrades rather than failing installs:

   ```diff
    	arch:desktop-optional)
    …
    		printf '%s\n' \
    			thunar gvfs gvfs-smb tumbler thunar-archive-plugin file-roller \
    			xdg-user-dirs gnome-keyring networkmanager \
   -			rsync xkbset
   +			rsync xkbset autorandr
   ```

   Keep `archiso/packages.x86_64` in sync (`tests/test-arch-iso-builder.sh`
   enforces it).

2. **Message.** In `status()`:

   ```diff
   -        result["error"] = "Install the optional Fedora autorandr package for automatic dock layouts."
   +        result["error"] = "Install the optional autorandr package (pacman -S autorandr) for automatic dock layouts."
   ```

3. **Registration.** It's Python, like `dwm-system-management`. Add it to
   `INSTALL_COMMANDS` **only**, not to `check-shell`/`check-format`. Record it
   next to the existing Python-helper exception in `UPSTREAM-SYNC.md`'s
   "Global adaptation rules". Add a `check-display-profiles` target to `check:`
   and `.PHONY`.

4. **Hotplug.** Arch's `autorandr` package ships
   `autorandr.service` and `udev/40-monitor-hotplug.rules`, which work
   unchanged. Confirm Lyona's `autostart.sh` doesn't already run a competing
   `dwm-display-profile apply` at login. If it does, run `autorandr --change
   --default default` only when `~/.config/autorandr/{mobile,docked}` exists,
   and otherwise keep the existing path.

5. **Coexistence with `dwm-display-profile`.** Lyona's
   `scripts/dwm-display-profile` (named xrandr profiles in
   `~/.config/lyona/display-profiles`) is manual "Save layout / Use layout".
   `#290`'s profiles are automatic (login/hotplug). Keep both. The Settings
   pane already separates "Saved layouts" from the new "Automatic layouts"
   section in upstream's layout.

---

## S3-03: Hide dock profiles without a system battery

**Upstream issue `#310`, still open upstream. No upstream code exists; this
is Lyona's own implementation.** Acceptance criteria are copied from the
issue:

- No system battery → Docked/Undocked controls are hidden.
- System battery → shown.
- Peripheral batteries (mice, keyboards) don't count.
- Other display settings are unchanged.

Detection must use the kernel's `scope` attribute. Peripheral HID batteries
report `scope=Device`. System batteries report `System` or no `scope` file at
all (older ACPI drivers).

**`scripts/dwm-settings-display-profiles`** (after S3-02):

```diff
 ROLES = {"undocked": "mobile", "docked": "docked"}
+POWER_SUPPLY = Path(os.environ.get("DWM_POWER_SUPPLY_ROOT", "/sys/class/power_supply"))
+
+
+def system_battery_present():
+    """True only for a laptop/system battery; HID peripheral batteries report scope=Device."""
+    try:
+        supplies = sorted(POWER_SUPPLY.iterdir())
+    except OSError:
+        return False
+    for supply in supplies:
+        try:
+            if (supply / "type").read_text().strip() != "Battery":
+                continue
+            scope_file = supply / "scope"
+            scope = scope_file.read_text().strip() if scope_file.exists() else "System"
+        except OSError:
+            continue
+        if scope != "Device":
+            return True
+    return False
@@ def status():
-    result = dict(version=1, available=bool(shutil.which("autorandr")), profiles=[],
-                  detected=[], current=[], default="", error="")
+    result = dict(version=1, available=bool(shutil.which("autorandr")), profiles=[],
+                  detected=[], current=[], default="", error="",
+                  battery=system_battery_present())
+    if not result["battery"]:
+        return result
     if not result["available"]:
```

**`config/quickshell/settings/SettingsModel.qml`**:

```diff
-    property var automaticDisplayState: ({ available: false, profiles: [], detected: [], current: [], default: "", error: "Loading automatic layouts" })
+    property var automaticDisplayState: ({ available: false, battery: false, profiles: [], detected: [], current: [], default: "", error: "Loading automatic layouts" })
+    readonly property bool automaticDisplaysRelevant: automaticDisplayState.battery === true
@@ automaticDisplayStatusProcess
-                    if (state.version !== 1 || !Array.isArray(state.profiles)
+                    if (state.version !== 1 || typeof state.battery !== "boolean" || !Array.isArray(state.profiles)
```

**`config/quickshell/settings/DisplaySettingsPane.qml`**: wrap the
"Automatic layouts" header text, the status text and the `RowLayout` of
`automaticCard`s in one `ColumnLayout`:

```diff
+        ColumnLayout {
+            Layout.fillWidth: true
+            spacing: Theme.spacingLg
+            // #310: laptop-only controls. Peripheral batteries do not count.
+            visible: root.settingsModel.automaticDisplaysRelevant
+
         Text {
             Layout.fillWidth: true
             text: "Automatic layouts - login and dock connection"
 …
         RowLayout {
             Layout.fillWidth: true
             spacing: Theme.spacingLg
             Repeater {
                 model: ["undocked", "docked"]
 …
         }
+        }
```

**Tests.** Add to `tests/test-display-profiles.py`:

```python
class BatteryPresenceTests(unittest.TestCase):
    def supply(self, root, name, kind, scope=None):
        path = Path(root) / name
        path.mkdir()
        (path / "type").write_text(kind + "\n")
        if scope is not None:
            (path / "scope").write_text(scope + "\n")

    def check(self, entries, expected):
        with tempfile.TemporaryDirectory() as root:
            for entry in entries:
                self.supply(root, *entry)
            with mock.patch.object(profiles, "POWER_SUPPLY", Path(root)):
                self.assertIs(profiles.system_battery_present(), expected)

    def test_desktop_with_only_ac_adapter(self):
        self.check([("AC", "Mains")], False)

    def test_wireless_mouse_battery_is_not_a_laptop(self):
        self.check([("hidpp_battery_0", "Battery", "Device")], False)

    def test_laptop_battery_with_system_scope(self):
        self.check([("BAT0", "Battery", "System"), ("AC", "Mains")], True)

    def test_laptop_battery_without_scope_attribute(self):
        self.check([("BAT1", "Battery")], True)

    def test_missing_power_supply_class(self):
        with mock.patch.object(profiles, "POWER_SUPPLY", Path("/nonexistent")):
            self.assertFalse(profiles.system_battery_present())

    def test_status_omits_profiles_without_battery(self):
        with mock.patch.object(profiles, "system_battery_present", return_value=False):
            result = profiles.status()
        self.assertEqual((result["battery"], result["profiles"]), (False, []))
```

In `tests/test-settings.sh`'s xvfb display-pane block, add one assertion with
`DWM_POWER_SUPPLY_ROOT` pointed at an empty fixture directory: the
"Automatic layouts" text must not be visible.

---

## S3-04: Control Center compaction

Upstream `c3e9a18` "refactor(quickshell): compact control surfaces". Open
since the first survey. It was noted as supplementary scope beside the
already-done Settings compaction and never picked up.

```bash
git -C "$U" show c3e9a18 -- config/quickshell/controlcenter/ControlCenterWindow.qml \
  config/quickshell/settings/DisplaySettingsPane.qml
```

`ControlCenterWindow.qml` +36/−36 removes section headers, adds a
`compactRowHeight` token and uses `Theme.compactSpacing` throughout.
`DisplaySettingsPane.qml` changes +3/−3.

**Lyona adaptation:** `Theme.compactSpacing` already exists in Lyona's
`Theme.qml`, so no token work is needed. Wrap `compactRowHeight` in `dp()`.
Also check
`#307`'s one-line `ControlCenterWindow.qml` change (S3-06) and Sprint 2's
`#282` change don't conflict.

---

## S3-05: Settings readiness and startup work

### From `#291` (Settings half of `d359a4f`)

| File | Change |
| --- | --- |
| `config/quickshell/settings/InputSettingsPane.qml` | Label column: `Layout.maximumWidth: 150` + `wrapMode: Text.WordWrap`, so long labels stop pushing controls off-screen |
| `config/quickshell/settings/SettingsWindow.qml` | +1/−1 |
| `scripts/seed-autostart-overrides.sh` | +17/−1 — Settings autostart exclusions honoured after a user manager restart |
| `tests/test-install-preservation.sh`, `tests/test-xvfb-runtime.sh` | +30/−4, +1 |
| `.github/PULL_REQUEST_TEMPLATE.md`, `AGENTS.md`, `CONTRIBUTING.md` | Upstream's "local review gates" wording. **Don't port.** Lyona has its own review process |

```diff
-                            Text { Layout.preferredWidth: 150; text: settingRow.modelData.label; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodyFontSize }
+                            Text {
+                                Layout.preferredWidth: Theme.dp(150)
+                                Layout.maximumWidth: Theme.dp(150)
+                                text: settingRow.modelData.label
+                                color: Theme.text
+                                font.family: Theme.fontFamily
+                                font.pixelSize: Theme.bodyFontSize
+                                wrapMode: Text.WordWrap
+                            }
```

### From `#294` (`080b39e`): lazy panes

**New file `config/quickshell/settings/DeferredSettingsPane.qml`** (verbatim
from upstream):

```qml
import QtQuick

Loader {
    id: root

    required property bool selected
    required property bool windowVisible
    property bool visited: false

    // Keep visited items alive: switching sections must preserve local drafts,
    // scroll positions and bindings to the independently owned operation models.
    active: visited
    asynchronous: true
    visible: selected && status === Loader.Ready
    focus: true

    function loadIfSelected() {
        if (windowVisible && selected) visited = true;
    }
    onSelectedChanged: loadIfSelected()
    onWindowVisibleChanged: loadIfSelected()
    Component.onCompleted: loadIfSelected()
}
```

`SettingsModel.qml`: don't re-activate a section that's already selected
(three call sites), refresh only the visible section's provider, and open with
`refreshCapabilities()` instead of a full `refresh()`:

```diff
+        if (root.searchQuery === value) return;
 …
-            root.selectedSectionId = root.filteredSections[0].id;
-            root.activateSection(root.selectedSectionId);
+            const id = root.filteredSections[0].id;
+            if (root.selectedSectionId !== id) {
+                root.selectedSectionId = id;
+                root.activateSection(id);
+            }
 …
-                root.selectedSectionId = id;
-                root.activateSection(id);
+                if (root.selectedSectionId !== id) {
+                    root.selectedSectionId = id;
+                    root.activateSection(id);
+                }
 …
-        root.selectedSectionId = sections[root.selectedIndex].id;
-        root.activateSection(root.selectedSectionId);
+        const id = sections[root.selectedIndex].id;
+        if (root.selectedSectionId !== id) {
+            root.selectedSectionId = id;
+            root.activateSection(id);
+        }
 …
+        if (root.selectedSectionId === "displays") root.refreshDisplays();
+        if (root.selectedSectionId === "input") root.refreshInput();
 …
-        root.refresh();
+        root.refreshCapabilities();
```

`SettingsWindow.qml` +69/−42 swaps each pane for `DeferredSettingsPane {
sourceComponent: … }`. Take the hunk as-is. Lyona's pane list may differ, so
wrap exactly Lyona's panes.

New test `tests/test-quickshell-settings-responsiveness-xvfb.sh` (61) with
`tests/qml/SettingsResponsiveness.inc` (87) and
`tests/fixtures/settings-responsiveness.py` (37):

```diff
+check-quickshell-settings-responsiveness-xvfb:
+	tests/test-quickshell-settings-responsiveness-xvfb.sh
+
 …
 check:
+	$(MAKE) check-quickshell-settings-responsiveness-xvfb
```

(and `.PHONY`). `#307` (S3-06) and `#327` (S3-07) extend
`SettingsResponsiveness.inc` further, by +41/−4 and +280/−5.

### From `#295` (`8df119c`)

Test race fix: wait for the notification-policy file to persist before the
restart assertion. New fixture `tests/fixtures/delay-notification-policy.py`
(24); `tests/test-quickshell-settings-xvfb.sh` +13/−1. Upstream's
`docs/PRE-P7-MAINTENANCE.md` isn't ported.

### Issue `#315`, open upstream: no layout shift while panels load

No upstream fix yet. `DeferredSettingsPane` makes this worse on first visit:
the pane appears only at `Loader.Ready`, so content pops in. Lyona's
implementation:

```diff
 Loader {
     id: root
 …
-    visible: selected && status === Loader.Ready
+    visible: selected
     focus: true
+
+    // #315: reserve the pane's space while it loads, so the first visit
+    // fades in instead of popping in and reflowing the window.
+    Rectangle {
+        anchors.fill: parent
+        visible: root.selected && root.status !== Loader.Ready
+        color: "transparent"
+        Text {
+            anchors.centerIn: parent
+            text: "Loading…"
+            color: Theme.textMuted
+            font.family: Theme.fontFamily
+            font.pixelSize: Theme.smallFontSize
+        }
+    }
+    onLoaded: if (item) { item.opacity = 0; fadeIn.target = item; fadeIn.start(); }
+    NumberAnimation { id: fadeIn; property: "opacity"; to: 1; duration: Theme.reducedMotion ? 0 : 120 }
```

(Add `import qs.core` for `Theme`. `Theme.reducedMotion` exists in Lyona's
`Theme.qml:10`; it's the earlier sync Phase 5 motion policy.)

The **in-pane** shift the issue names, where Appearance controls appear and
disappear as capabilities resolve, is fixed at the source by S3-07. `#327`
deletes the unreliable Picom capability toggles. Sprint 4's S4-01 replaces
them with config-backed sliders that are always present. Acceptance for
`#315` is checked **after** S3-07 and S4-01: extend
`SettingsResponsiveness.inc` so that each pane's first child `y` stays the
same between `Loader.Ready` and 2 s later, with providers delayed by
`settings-responsiveness.py`.

---

## S3-06: Power menu, Settings full screen, cursor reload, tray, Self-Heal

Upstream `#307` (`56ec27b`). Closes upstream issues `#302`–`#306`, all filed
by Chris. Split into commits by issue:

### `#302` Settings full screen, like System Health

```diff
 FloatingWindow {
-    implicitWidth: Math.min(1180, root.screen ? Math.max(1, root.screen.width - 32) : 1180)
-    implicitHeight: Math.min(760, root.screen ? Math.max(1, root.screen.height - 32) : 760)
+    fullscreen: true
+    implicitWidth: root.screen ? root.screen.width : 1180
+    implicitHeight: root.screen ? root.screen.height : 760
 …
+        radius: 0
```

This **reverses** Lyona's `CHANGELOG.md` entry "Increase the Settings window
to 1180x760 … Clamp the enlarged window to the active screen". Update that
CHANGELOG context and `SPEC.md` §5 if it names a window size. `44800ba` also
opens Settings on the focused screen:

```diff
-            settingsModel.open();
+            settingsModel.openOnScreen(dwmState.focusedScreen());
 …
-            settingsModel.toggle();
+            if (settingsModel.visible) settingsModel.close();
+            else settingsModel.openOnScreen(dwmState.focusedScreen());
```

Lyona's `shell.qml` already calls `settingsModel.openOnScreen(screen)` on one
path (`:87`), so the function exists. Change only the two IPC paths still
using `open()`/`toggle()` (`shell.qml:1025`, `:1041`). Update the
`Makefile` xvfb geometry expectations (`DWM_SETTINGS_EXPECTED_WINDOW_WIDTH=1024
…HEIGHT=768` for a 1024x768 screen).

### `#303` Appearance scroll jitter

```diff
 Flickable {
+    objectName: "appearanceSettingsPane"
 …
+    flickableDirection: Flickable.VerticalFlick
+    boundsBehavior: Flickable.StopAtBounds
+    Controls.ScrollBar.vertical: Controls.ScrollBar {}
```

(`import QtQuick.Controls as Controls` if Lyona's pane doesn't have it.)

### `#304` Cursor applies to existing windows without a reboot

| File | Change |
| --- | --- |
| `scripts/dwm-cursor-reload` | **New** (Python, 214): replaces named cursors in existing X11 clients and keeps one X11 owner |
| `scripts/theme-apply.sh` | Write `Gtk/CursorThemeName`/`Gtk/CursorThemeSize` into xsettingsd config; call `dwm-cursor-reload "$CURSOR_THEME" "$CURSOR_SIZE"` after apply; strict personalization fails on cursor publication failure |
| `scripts/dwm-xsettings` | **N/A in Lyona.** See the adaptation below |
| `tests/test-cursor-reload.py` | **New** (200) → `check-cursor-reload: xvfb-run -a /usr/bin/python3 tests/test-cursor-reload.py` |
| `Makefile` | `INSTALL_COMMANDS += scripts/dwm-cursor-reload`; `check-cursor-reload` in `check:` and `.PHONY` |

**Lyona adaptation:** Lyona has no `dwm-xsettings`. The xsettingsd job lives
in `scripts/dwm-settings-display` (`write_xsettings_dpi()`, around `:261`),
and the daemon starts in `scripts/autostart.sh:400`. Put the cursor keys in
the **same** `xsettingsd.conf` that `write_xsettings_dpi()` writes, through
one shared writer, and **preserve** DPI lines when writing cursor lines (and
the reverse). After writing, `pkill -HUP -u "$UID" -x xsettingsd` as the
DPI path already does. `dwm-xsettings`' `wait_for_active` publication
check becomes an optional `xprop -root _XSETTINGS_SETTINGS`-based wait in
`theme-apply.sh`'s strict branch. `dwm-cursor-reload` uses only `ctypes`
against `libX11`/`libXcursor` (both in `arch:build`/`x11` already), so no new
Python package is needed.

### `#305` Hide Blueman's tray icon

```diff
-    visible: SystemTray.items.values.length > 0
+    readonly property var visibleItems: SystemTray.items.values.filter(function(item) {
+        return item.id !== "blueman" && item.id !== "blueman-applet";
+    })
+    visible: visibleItems.length > 0
 …
-        model: SystemTray.items.values
+        model: root.visibleItems
```

`tests/test-quickshell-tray.sh` +1/−1.

### `#306` Self-Heal in Quick Actions

`config/quickshell/controlcenter/ControlCenterModel.qml`:

```diff
+    property string actionError: ""
 …
             { "id": "open-wallpapers", "label": "Wallpaper Folder" }
+            , { "id": "self-heal", "label": "Self-Heal" }
 …
+        root.actionError = "";
 …
+        stderr: StdioCollector {
+            onStreamFinished: root.actionError = this.text.trim().slice(0, 1024)
+        }
+
-                    : "Action failed: " + root.pendingAction;
+                    : (root.actionError.length > 0 ? root.actionError
+                        : "Action failed: " + root.pendingAction);
```

`scripts/dwm-quickshell-controlcenter`: add upstream's `self_heal()`
verbatim (it already uses `$dwm_config_dir`, which Lyona sets to
`$config_home/lyona`, so the path file is `~/.config/lyona/self-heal.path`),
and wire it into Lyona's `action()` at `:1598`:

```diff
 	browser) launch_background dwm-default-apps open https:// ;;
+	self-heal) self_heal ;;
 	*)
```

**Lyona adaptation:** Lyona ships no `dwm-self-heal`. Upstream doesn't
either; it expects a user-provided script. `SPEC.md`'s Health dashboard
already has `dwm-system-health repair-user|repair-system`.

**Decision D-6, decided (2026-09-16), asked of the user directly:** upstream
parity — Self-Heal stays user-configured only, with no default script.
`dwm-system-health`'s repair flow isn't auto-wired to it. File that as a
`ROADMAP.md` Future Evaluation item, not built here.

`tests/test-quickshell-controlcenter.sh` +40 covers a path with spaces, exit
status 7, a missing executable and an unavailable terminal.

### Power menu labels

```diff
-            "label": "Log Out",
+            "label": "Logout",
```

(`PowerMenuWindow.qml` +4/−3: unavailable actions explain themselves on
selection.)

---

## S3-07: Appearance simplification and desktop typography

Upstream `#327` (`a5b829d`, 34 files) and `68a0d1f`.

### Decision D-7: font scale vs Lyona's `Theme.dp()` — decided, asked of the user directly

Upstream `#327` rewrites `Theme.qml` so that **spacing and control sizes
scale with `fontScale`** (`scaledSize()`), and divides font sizes by the
screen's `devicePixelRatio` when `desktopTypography` is on ("so a 200%
desktop never becomes a 400% shell").

Lyona already solved "scale the whole shell" differently.
`Theme.uiScale` comes from the published DPI (`Theme.qml:93`). Every geometry
constant goes through `dp()` (`:107`), and DPI hot-reloads (`2a49ffd`). Porting
`scaledSize()` on top of `dp()` would **double-scale** geometry at non-100%
text sizes.

**Decided (2026-09-16):**

- **Port:** `desktopFontFamily`, `desktopFontScale`, `desktopFollowsSystemScale`
  and `applySharedTypography()` from `AppearanceModel.qml`. The shell text
  follows the desktop font family and text scale set in Appearance. That's
  the "unify desktop font scaling" user-visible behavior.
- **Port:** `requestedFontScale` range `0.75…2.0` (was `0.8…1.5`), and
  `scaledFontSize(value, minimum)` for **font sizes only**.
- **Don't port:** `scaledSize()` on spacing/control geometry, or the
  `nativeScale` division. Lyona's `dp()` already accounts for DPI, and Qt's
  `devicePixelRatio` stays 1.0 under Lyona's X11 session because Lyona
  publishes `Xft/DPI` rather than `QT_SCALE_FACTOR`. **Verify that claim
  first**, as agreed, by logging `Quickshell.screens[0].devicePixelRatio` at
  144 DPI before starting this item. If it isn't 1.0, the `nativeScale`
  compensation is needed after all — stop and re-open D-7 rather than
  guessing.
- **Port** all the per-surface fixes that ride along: `NetworkWindow.qml`
  (+121/−105, Wi-Fi password dialog usable at large text),
  `NotificationPopupWindow.qml` (+30/−15, constrained stacks),
  `SystemHealthWindow.qml` (+10/−6), `ClickAwayPopup.qml` (+24/−10),
  `ControlsWindow.qml`, `BluetoothWindow.qml`, `DwmPanel.qml`,
  `LogoButton.qml`, and the one-line pane fixes, wrapping constants in `dp()`.

The decision is recorded in `UPSTREAM-SYNC.md`'s Open decisions table.

### Appearance simplification

`AppearanceSettingsPane.qml` +52/−175 removes the capability-probed Picom
toggles and duplicate font controls. Lyona's pane is 856 changed lines away
from upstream HEAD. Port by **removing** the same sections from Lyona's pane,
not by taking upstream's file. `AppearanceModel.qml` −42 (Picom checks) goes
with it. Sprint 4's S4-01 brings in the replacement `PicomSettingsPane`. If
Sprint 4 won't follow within the same release, leave the old Picom rows in
place until then.

### Wallpaper discovery without decoding (`68a0d1f` + `#327`'s wallpaper hunk)

`scripts/dwm-settings-wallpaper` +24/−18 and then +18/−31: list wallpapers by
extension and `stat` without decoding every image on reload.
`tests/test-dwm-settings-wallpaper.sh` +53/−11 and +11/−42. Lyona's file
exists. Apply `68a0d1f` first, then `#327`'s hunk, with `git apply --3way`.

---

## S3-08: Panel stays sharp under popups

Upstream `#324` (`c44dae4`). **Applies cleanly** to Lyona (`git apply --check`
passes).

```diff
--- a/config/quickshell/core/ClickAwayPopup.qml
+++ b/config/quickshell/core/ClickAwayPopup.qml
@@ -17,12 +17,15 @@ PopupWindow {
     color: Theme.transparent
     grabFocus: true
     implicitWidth: targetWindow ? targetWindow.width : 0
-    implicitHeight: targetWindow && targetWindow.screen ? targetWindow.screen.height : 0
+    // Keep the transparent click-away surface below the panel so compositors
+    // cannot blur the bar through this popup. Content coordinates stay panel-relative.
+    readonly property int panelOffset: targetWindow ? targetWindow.height : 0
+    implicitHeight: targetWindow && targetWindow.screen ? Math.max(0, targetWindow.screen.height - panelOffset) : 0
 
     anchor {
         window: targetWindow
         rect.x: 0
-        rect.y: 0
+        rect.y: root.panelOffset
     }
 
     MouseArea {
@@ -34,7 +37,7 @@ PopupWindow {
         id: popupHost
 
         x: root.popupX
-        y: root.popupY
+        y: root.popupY - root.panelOffset
         width: root.popupWidth
         height: root.popupHeight
         opacity: 1.0
```

```diff
-check-quickshell-panel-menus:
+check-quickshell-panel-menus: all
 	tests/test-quickshell-panel-menus.sh
+	dbus-run-session -- xvfb-run -a /usr/bin/python3 tests/test-panel-popup.py
```

(Lyona's build target is `all`; upstream's is `dwm`.) New
`tests/test-panel-popup.py` (51), taken verbatim.

---

## S3-09: Pre-survey gaps (`#183`, `#188`, `#191`)

The earlier surveys started at the fork point, but three Chris PRs from
around it were never recorded as ported, excluded or diverged. Checked on
2026-09-16 with `git apply --check` (and `-R`) against Lyona `main`:

| Upstream | Result | Action |
| --- | --- | --- |
| `#183` `e91d018` *bound preview status retries* | **Not in Lyona. Applies cleanly.** | Port as-is |
| `#188` `c8f574b` *qualify optional component isolation* | **Not in Lyona.** None of its 20 `shell.qml` probe functions (`appearanceInventoryState`, `appearanceWallpaperProviderState`, …) exist, and there's no `check-phase5-optional-components` target | Port the tests, adapted |
| `#191` `4d776bc` *group accessibility settings* | Partly present. `capabilityById()` exists; the coalesced `refreshCapabilities()` and `capabilityRefreshPending` don't. The text-scale grouping was deliberately not ported (earlier sync Phase 6 note) | Port the refresh coalescing; record the grouping as diverged. **S3-05 needs this first** |

### `#183`: stop polling preview status after repeated zero-remaining reads

```bash
git -C "$U" show --format= e91d018 -- config tests | git apply
```

What it does: after more than three zero-remaining or unparsed
`preview-status` reads, `AppearanceModel.qml` sets
`previewStatusManualOnly = true` and stops automatic refreshes, which
otherwise retry forever. Only the Refresh button (`refreshAll(true)`) forces a
read. Every definitive result (`none`, `expired`, `preview-failed`, a positive
remaining time, or a finished keep/revert/abandon action) clears the flag.
The core lines:

```diff
+    property bool previewStatusManualOnly: false
 …
-    function refreshPreviewStatus() {
+    function refreshPreviewStatus(force) {
+        if (root.previewStatusManualOnly && force !== true) return;
 …
-    function refreshAll() {
+    function refreshAll(forcePreviewStatus) {
 …
-        root.refreshPreviewStatus();
+        root.refreshPreviewStatus(forcePreviewStatus === true);
 …
                         if (root.previewZeroRetryAttempts > 3) {
+                            root.previewStatusManualOnly = true;
                             root.message = "Automatic rollback status needs a manual refresh";
```

```diff
-                onActivated: root.appearanceModel.refreshAll()
+                onActivated: root.appearanceModel.refreshAll(true)
```

`tests/test-quickshell-appearance-model.sh` +6. S3-07 later rewrites parts of
`AppearanceSettingsPane.qml`, so keep the `refreshAll(true)` call on the
Refresh button when resolving that port.

### `#188`: optional-component isolation qualification

This proves that each optional desktop component (wallpaper, fonts,
personalization, the Picom inventory) failing or being absent leaves the rest
of Appearance usable. It adds 774 lines to `tests/test-quickshell-settings-xvfb.sh`,
the 20 read-only `shell.qml` IPC probes that test drives, and:

```diff
+check-phase5-optional-components:
+	tests/test-dwm-settings-appearance.sh
+	tests/test-dwm-settings-appearance-inventory.sh
+	tests/test-dwm-settings-toolkit.sh
+	tests/test-dwm-settings-wallpaper.sh
+	tests/test-quickshell-appearance-model.sh
+	tests/test-quickshell-controlcenter.sh
```

**Lyona adaptations:** upstream's `tests/test-dwm-settings-personalization.sh`
maps to Lyona's `tests/test-dwm-settings-toolkit.sh` (already in the target
above); upstream's
`AppearanceModel.qml` +9 and `dwm-settings-wallpaper` +1/−1 hunks through
`git apply --3way`. Take upstream's `tests/test-quickshell-settings-xvfb.sh`
block from **`a5b829d`'s version**, after S3-07, not `c8f574b`'s. Upstream
`#307` and `#327` both rewrote it (`Makefile`'s
`DWM_SETTINGS_EXPECTED_WINDOW_WIDTH=1024` geometry), and Lyona gets those
first. Add the target to `check:` and `.PHONY`. `docs/P5-OPTIONAL-COMPONENTS.md`
and `docs/P5-STATUS.md` aren't ported.

### `#191`: capability refresh coalescing (port), grouping (record)

S3-05's `#294` hunk replaces `root.refresh()` with `root.refreshCapabilities()`,
which comes from `#191` and doesn't exist in Lyona. **Land this before
S3-05.** From `4d776bc`'s `SettingsModel.qml`:

```diff
+    property bool capabilityRefreshPending: false
 …
     function refresh() {
-        if (!root.visible || providerProcess.running) return;
+        root.refreshCapabilities();
+    }
+
+    function refreshCapabilities() {
+        if (!root.visible) return;
+        if (providerProcess.running) {
+            root.capabilityRefreshPending = true;
+            return;
+        }
+        root.capabilityRefreshPending = false;
 …
+        onRunningChanged: {
+            if (!running && root.capabilityRefreshPending && root.visible) {
+                root.capabilityRefreshPending = false;
+                Qt.callLater(function() {
+                    if (!providerProcess.running) root.refreshCapabilities();
+                });
+            }
+        }
```

Upstream's `capabilityById()` also returns `unavailable` ("Capability
discovery is still refreshing") while `capabilityRefreshPending` is set.
Lyona's version at `SettingsModel.qml:140` predates that, so add the guard:

```diff
     function capabilityById(id) {
+        if (root.discoveryState !== "ready" || root.capabilityRefreshPending)
+            return { "status": "unavailable", "detail": "Capability discovery is still refreshing" };
```

Take the `shell.qml` `appearanceRefresh()`/`capabilityStatus()` probes too.
`#188`'s tests use them. Skip the `textScaleCapability` grouping in
`SettingsWindow.qml`/`AppearanceSettingsPane.qml`, and add to
`UPSTREAM-SYNC.md`'s "Already in Lyona" table: *`4d776bc` accessibility
grouping → diverged by decision (see the earlier Phase 6 note); capability
refresh coalescing ported in Sprint 3 S3-09.*

---

## Verification

```bash
scripts/run-tests make clean all check-shell check-format check-quickshell-qml
scripts/run-tests make check-settings check-display-setup check-display-profile check-display-profiles \
  check-quickshell-settings-xvfb check-quickshell-settings-responsiveness-xvfb \
  check-quickshell-controlcenter check-quickshell-tray check-quickshell-panel-menus \
  check-cursor-reload check-appearance check-quickshell-appearance-model \
  check-quickshell-design-system check-accessibility check-arch-packages check-archiso \
  check-phase5-optional-components
QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
```

Manual, on real hardware:

- A laptop shows Docked/Undocked. A desktop with a wireless mouse doesn't (`#310`).
- Settings opens full screen on the **focused** monitor of a two-monitor setup.
- Change the cursor theme: an already-open terminal and Thunar pick it up without re-login.
- Appearance at 144 DPI and 200% text: no double-scaled spacing (D-7), and the Wi-Fi password dialog stays usable.
- Opening Settings the first time shows no pane pop-in (`#315`).
- Closed-CPU baseline stays flat (`check-quickshell-large-surfaces-xvfb`).

## Closes

Upstream `#289`, `#290`, `#291` (Settings half), `#294`, `#295`, `#307`
(issues `#302`–`#306`), `#324`, `#327`, `68a0d1f`, `c3e9a18`, the `44800ba`
focused-screen hunk, `#183`, `#188`, `#191` (recorded); upstream issues `#310`
and `#315` (for Lyona).
