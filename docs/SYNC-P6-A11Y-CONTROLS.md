# Sync Phase 6 — accessibility Settings controls

Upstream: [`#202`](https://github.com/ChrisTitusTech/dwm-titus/pull/202)
`Phase 5: add accessibility Settings controls` (`28a374f`, +811 / -127).
Depends on [Phase 4](SYNC-P4-A11Y-CAPABILITIES.md) and
[Phase 5](SYNC-P5-CONTRAST-MOTION.md).
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Phase 5 made contrast and motion *work*. This makes them *reachable* — and does it
with keyboard navigation and screen-reader metadata, which is the accessibility half
that matters.

## Files

| File | Upstream | Note |
| --- | --- | --- |
| `config/quickshell/settings/AppearanceSettingsPane.qml` | +124 | New "Accessibility" group |
| `config/quickshell/core/PanelToggleSwitch.qml` | +17 / -2 | `Accessible.*` + `requestToggle()` |
| `config/quickshell/core/ShellButton.qml` | +13 / -3 | `Accessible.*` + `requestActivation()` |
| `config/quickshell/controls/BluetoothWindow.qml` | +2 | First caller of the new required property |
| `config/quickshell/settings/SettingsModel.qml` | +4 | Model wiring |
| `config/quickshell/settings/SettingsWindow.qml` | +2 | Section wiring |
| `config/quickshell/shell.qml` | +34 | IPC probes for the xvfb test |
| `scripts/dwm-accessibility-settings` | +80 | Mutation-readiness reporting |
| `scripts/dwm-settings-provider` | +91 | Mutation state in the capability records |
| `scripts/dwm-settings-appearance` | +3 | Advertise the group |

## The core-widget changes come first

`PanelToggleSwitch` and `ShellButton` are used across the whole shell, so these two
hunks land before the pane that depends on them.

### `config/quickshell/core/PanelToggleSwitch.qml`

```diff
     property bool checked: false
     property bool busy: false
+    required property string accessibleName
+    property string accessibleDescription: ""
     signal toggled
```

```diff
     activeFocusOnTab: root.enabled && !root.busy
+    Accessible.role: Accessible.CheckBox
+    Accessible.name: root.accessibleName
+    Accessible.description: root.accessibleDescription
+    Accessible.checkable: true
+    Accessible.checked: root.checked
+    Accessible.onPressAction: root.requestToggle()
+    Accessible.onToggleAction: root.requestToggle()
+
+    function requestToggle() {
+        if (root.enabled && !root.busy) root.toggled();
+    }
```

```diff
     Keys.onPressed: function(event) {
         if (!root.enabled || root.busy || event.isAutoRepeat) return;
         if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
-            root.toggled();
+            root.requestToggle();
             event.accepted = true;
         }
     }
```

```diff
         onClicked: {
             root.forceActiveFocus();
-            root.toggled();
+            root.requestToggle();
         }
```

`requestToggle()` exists because the three entry points — key, click, and the
assistive-technology press action — must share one guard. Without it the
`Accessible.onPressAction` path bypasses the `enabled`/`busy` check that the
keyboard path enforces, and a screen reader can toggle a disabled control.

**`accessibleName` is `required`.** That is deliberate and it is a compile-time
sweep: every existing `PanelToggleSwitch` instantiation must be given a name in this
commit or the QML fails to load. Find them all with:

```bash
grep -rn "PanelToggleSwitch {" config/quickshell
```

### `config/quickshell/core/ShellButton.qml`

```diff
     required property string label
+    property string accessibleDescription: ""
     property bool danger: false
```

```diff
     activeFocusOnTab: root.enabled
+    Accessible.role: Accessible.Button
+    Accessible.name: root.label
+    Accessible.description: root.accessibleDescription
+    Accessible.onPressAction: root.requestActivation()
```

```diff
+    function requestActivation() {
+        if (root.enabled) root.activated();
+    }
+
     Keys.onPressed: event => {
         if (root.enabled && !event.isAutoRepeat
                 && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
-            root.activated();
+            root.requestActivation();
             event.accepted = true;
         }
     }
```

```diff
-        onClicked: root.activated()
+        onClicked: root.requestActivation()
```

`Accessible.name` reuses the existing `label`, so `ShellButton` needs no new required
property and every existing call site keeps working.

`ShellButton` already reads `Theme.controlFocusBorderWidth` for its focus ring
(`border.width: root.activeFocus ? …`), so Phase 5's
`dp(highContrast ? 3 : 2)` becomes visible here with no further edit. That
interaction is the reason this phase follows Phase 5 rather than preceding it.

### `config/quickshell/controls/BluetoothWindow.qml`

The first caller of the new required property, and the template for the sweep:

```diff
                     enabled: root.bluetoothModel.available && root.bluetoothModel.actionsAvailable
+                    accessibleName: "Bluetooth power"
+                    accessibleDescription: "Turn the Bluetooth adapter on or off"
                     onToggled: root.bluetoothModel.action("bluetooth-power", [checked ? "off" : "on"])
```

## `config/quickshell/settings/AppearanceSettingsPane.qml`

The new "Accessibility" group: a `PanelToggleSwitch` for high contrast, one for
reduced motion, and a provider-status row.

**Use Lyona's `StatusCard`** (`config/quickshell/core/StatusCard.qml`) for the status
row. Upstream repeats an inline `component StatusCard` in each pane; Lyona already
de-duplicated it out of `PowerSettingsPane` and `AppearanceSettingsPane`:

```qml
        StatusCard {
            label: "Accessibility provider"
            statusState: root.accessibilityModel.mutationState
            value: root.accessibilityModel.mutationReady ? "Ready" : "Read-only"
            detail: root.accessibilityModel.mutationDetail
        }
```

`StatusCard` takes its border and value colour from `Theme.statusColor()`, so the
pane supplies no colour of its own — and it inherits Phase 5's high-contrast border
automatically.

Both toggles bind `busy` to `accessibilityModel.busy` and `enabled` to
`accessibilityModel.mutationReady`, so a read-only provider renders a disabled
control with a stated reason rather than a control that silently fails.

## Helper and provider changes

`scripts/dwm-accessibility-settings` gains mutation-readiness reporting: `status`
emits a `mutation\t{available|unavailable}\tDETAIL` row, so the pane can distinguish
"you cannot change this" from "this is off".

`scripts/dwm-settings-provider` (+91) folds that state into the contrast and
reduced-motion capability records added in
[Phase 4](SYNC-P4-A11Y-CAPABILITIES.md). Keep the field-validation style already
established there — bounded lengths, whitelisted states, reject on any malformed
row.

## `config/quickshell/shell.qml`

The +34 lines are IPC probes for `tests/test-quickshell-settings-xvfb.sh` to read
back the rendered accessibility state. Pure reads, in the same `settings` handler
that [Phase 0](SYNC-P0-DPI-GATE.md) extended.

## Verification

```bash
scripts/run-tests make check-quickshell-qml
scripts/run-tests make check-accessibility
scripts/run-tests make check-quickshell-settings-xvfb
scripts/run-tests make check-quickshell-controls
scripts/run-tests make check-settings
```

`check-quickshell-qml` is the one that catches a missed `accessibleName` — the
`required property` will fail to load, not fail silently.

Manual:

1. Open Settings → Appearance, `Tab` through the Accessibility group. Every control
   must take focus in order, with a visible ring, and respond to `Space` and
   `Enter`.
2. Toggle high contrast from the pane and confirm the focus ring on the *pane's own
   controls* thickens as it applies — the live proof that Phase 5's
   `controlFocusBorderWidth` reaches the surface changing it.
3. Make the provider read-only (`chmod 500 ~/.config/lyona`) and confirm both
   toggles disable with the reason shown in the `StatusCard`, rather than accepting
   input and failing.
4. Confirm the Bluetooth toggle in the Control Center still works — it is the
   instance that gained `accessibleName`.

## Closes

`TASKS.md:91` — *Add accessible Settings controls with keyboard navigation, visible
focus, …*
