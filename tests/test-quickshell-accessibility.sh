#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
model=$repo/config/quickshell/accessibility/AccessibilityModel.qml
watched_process=$repo/config/quickshell/core/WatchedProcess.qml
theme=$repo/config/quickshell/core/Theme.qml
commands=$repo/config/quickshell/core/Commands.qml
shell_qml=$repo/config/quickshell/shell.qml
pane=$repo/config/quickshell/settings/AppearanceSettingsPane.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
toggle=$repo/config/quickshell/core/PanelToggleSwitch.qml
button=$repo/config/quickshell/core/ShellButton.qml
bluetooth_window=$repo/config/quickshell/controls/BluetoothWindow.qml
provider=$repo/scripts/dwm-settings-provider

"$repo/scripts/quickshell-qmllint" --root "$repo/config/quickshell"

assert_contains "$model" 'accessibility-settings-protocol\t1\t0'
assert_contains "$model" 'accessibility-settings-action-protocol\t1\t0'
assert_contains "$model" 'readonly property bool mutationReady: root.mutationState === "available"'
assert_contains "$model" 'property string mutationState: "unavailable"'
assert_contains "$model" 'property string mutationDetail: "Loading accessibility policy"'
assert_contains "$model" 'root.mutationState = mutation[1];'
assert_contains "$model" 'root.mutationDetail = mutation[2];'
assert_contains "$model" 'root.mutationState = "unavailable";'
assert_contains "$model" 'Component.onCompleted: root.refresh()'
assert_contains "$model" 'Commands.accessibilitySettingsCommand("status", [])'
assert_contains "$model" 'Commands.accessibilitySettingsCommand("watch", [])'
assert_contains "$model" 'Commands.checkedCommand(' # set()/reset() go through the checked wrapper
assert_contains "$model" 'Theme.applyAccessibility(root.highContrast, root.reducedMotion)'
assert_contains "$model" 'Theme.applyAccessibility(false, false)'

# The watcher is a WatchedProcess, not a second inline copy of the watch
# lifecycle upstream carries. Verify the substitution instead of porting
# upstream's watchReady/watchSetupFailures assertions, which describe an
# implementation this file does not have.
assert_contains "$model" 'command: Commands.accessibilitySettingsCommand("watch", [])'
assert_contains "$model" 'active: true'
assert_contains "$model" 'settleInterval: 100'
assert_contains "$model" 'onSettled: root.refresh()'
if grep -Fq 'watchReady' "$model" || grep -Fq 'watchSetupFailures' "$model"; then
	printf 'Accessibility model reintroduced the inline watch-lifecycle bookkeeping WatchedProcess replaces\n' >&2
	exit 1
fi
assert_contains "$watched_process" 'if (!running && root.active)'
assert_contains "$watched_process" 'restartTimer.restart()'
assert_contains "$watched_process" 'if (root.active && !watchProcess.running)'
assert_contains "$watched_process" 'onTriggered: root.settled()'

# parseStatus()'s field-count/enum/duplicate-rejection validation is the
# boundary between an unprivileged helper's stdout and the shell's render
# state -- assert it is intact, not paraphrased. Phase 6 made the record set
# append-only (a trailing "mutation" row, and room for future record types),
# so the length check is now a lower bound and the terminator is found by
# its position from the end, not a fixed index.
assert_contains "$model" 'lines.length < 6'
assert_contains "$model" 'lines[lines.length - 1] !== "complete\tstatus"'
assert_contains "$model" '["available", "defaults", "partial", "unavailable"]'
assert_contains "$model" 'parsed[fields[1]] !== undefined'
assert_contains "$model" '["available", "unavailable"].indexOf(fields[1]) < 0'
assert_contains "$model" 'fields[0] === "accessibility-settings-protocol"'
assert_contains "$model" 'fields[0] === "complete"'

assert_contains "$theme" 'property bool highContrast: false'
assert_contains "$theme" 'property bool reducedMotion: false'
assert_contains "$theme" 'property string paletteTextMuted: "#D8DEE9"'
assert_contains "$theme" 'readonly property string textMuted: highContrast ? text : paletteTextMuted'
assert_contains "$theme" 'root.paletteTextMuted = colors["text-muted"];'
assert_contains "$theme" 'readonly property int animationFast: reducedMotion ? 0 : 120'
assert_contains "$theme" 'readonly property int animationNormal: reducedMotion ? 0 : 180'
# Lyona wraps border widths in dp() -- a bare highContrast ? 2 : 1 would be a
# hairline at high DPI, the opposite of what high contrast is for.
assert_contains "$theme" 'readonly property int controlBorderWidth: dp(highContrast ? 2 : 1)'
assert_contains "$theme" 'readonly property int controlFocusBorderWidth: dp(highContrast ? 3 : 2)'
assert_contains "$theme" 'readonly property string controlNormalBorder: highContrast ? textStrong : border'
assert_contains "$theme" 'readonly property string popupBorder: highContrast ? textStrong : borderStrong'
assert_contains "$theme" 'function applyAccessibility(highContrastEnabled, reducedMotionEnabled)'

# Nothing may write the derived textMuted property directly -- that is the
# whole reason the palette slot was split out (Phase 5, done -- see CHANGELOG.md).
if grep -rn '\.textMuted[[:space:]]*=' "$repo/config/quickshell" | grep -v "$theme:"; then
	printf 'Something outside Theme.qml assigns to the derived textMuted property\n' >&2
	exit 1
fi
if grep -n '\.textMuted[[:space:]]*=' "$theme" | grep -v 'readonly property string textMuted:'; then
	printf 'Theme.qml writes to its own derived textMuted property\n' >&2
	exit 1
fi

assert_contains "$commands" 'function accessibilitySettingsCommand(action, args)'
assert_contains "$shell_qml" 'import qs.accessibility'
assert_contains "$shell_qml" 'AccessibilityModel {'
assert_contains "$shell_qml" 'function themeColor(role: string): string {'
assert_contains "$shell_qml" 'function themeHighContrast(): bool {'
assert_contains "$shell_qml" 'accessibilityModel: accessibilityModel'

# ── Phase 6: reachable Settings controls, not just a working policy ─────

assert_contains "$toggle" 'required property string accessibleName'
assert_contains "$toggle" 'Accessible.role: Accessible.CheckBox'
assert_contains "$toggle" 'Accessible.name: root.accessibleName'
assert_contains "$toggle" 'Accessible.checkable: true'
assert_contains "$toggle" 'Accessible.checked: root.checked'
assert_contains "$toggle" 'Accessible.onPressAction: root.requestToggle()'
assert_contains "$toggle" 'Accessible.onToggleAction: root.requestToggle()'
assert_contains "$toggle" 'function requestToggle() {'
assert_contains "$toggle" 'root.requestToggle();'
# root.toggled() must be called from exactly one place: inside
# requestToggle() itself. Every input path (key, click, assistive-technology
# press) shares that one guard; a second direct call would bypass it.
if [ "$(grep -Fc 'root.toggled();' "$toggle")" -ne 1 ]; then
	printf 'PanelToggleSwitch must call root.toggled() from exactly one place (requestToggle())\n' >&2
	exit 1
fi

assert_contains "$button" 'property string accessibleDescription: ""'
assert_contains "$button" 'Accessible.role: Accessible.Button'
assert_contains "$button" 'Accessible.name: root.label'
assert_contains "$button" 'Accessible.onPressAction: root.requestActivation()'
assert_contains "$button" 'function requestActivation() {'
assert_contains "$button" 'onClicked: root.requestActivation()'

assert_contains "$bluetooth_window" 'accessibleName: "Bluetooth power"'
assert_contains "$bluetooth_window" 'accessibleDescription: "Turn the Bluetooth adapter on or off"'

assert_contains "$settings_window" 'required property var accessibilityModel'
assert_contains "$settings_window" 'accessibilityModel: root.accessibilityModel'
assert_contains "$settings_model" 'property var accessibilityModel: null'
assert_contains "$settings_model" 'root.accessibilityModel.refresh();'

assert_contains "$pane" 'required property var accessibilityModel'
assert_contains "$pane" 'component AccessibilityToggle: Rectangle {'
assert_contains "$pane" 'title: "High contrast"'
assert_contains "$pane" 'title: "Reduced motion"'
assert_contains "$pane" 'setting: "contrast"'
assert_contains "$pane" 'setting: "motion"'
assert_contains "$pane" 'root.accessibilityModel.setSetting('
assert_contains "$pane" 'label: "Reset contrast and motion"'
assert_contains "$pane" 'root.accessibilityModel.reset()'
assert_contains "$pane" ': root.accessibilityModel.mutationState'
assert_contains "$pane" ': root.accessibilityModel.mutationDetail'
assert_contains "$pane" '|| !root.accessibilityModel.mutationReady'
assert_contains "$pane" 'accessibleName: panelWidgetRow.modelData.label'
assert_contains "$pane" 'accessibleDescription: "Show this widget in the managed panel"'
# accessibility-contrast/accessibility-reduced-motion now have dedicated
# controls; the generic capability list must not show them a second time.
assert_contains "$pane" 'capability.id !== "accessibility-contrast"'
assert_contains "$pane" 'capability.id !== "accessibility-reduced-motion"'
assert_contains "$pane" 'model: root.additionalCapabilities'

# ── provider: the flip from Phase 4's static placeholders is real ───────

assert_contains "$provider" 'accessibility_mutation_state() {'
assert_contains "$provider" 'accessibility-settings-protocol\t1\t0") header = 1'
# shellcheck disable=SC2016 # this is a literal awk field reference to grep for, not shell expansion
assert_contains "$provider" '$1 == "mutation" {'
assert_contains "$provider" 'if ! provider_available dwm-accessibility-settings; then'
assert_contains "$provider" 'accessibility_state=missing'
assert_contains "$provider" 'accessibility_state=invalid'

printf 'Quickshell accessibility policy model: PASS\n'
