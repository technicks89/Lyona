#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
model=$repo/config/quickshell/accessibility/AccessibilityModel.qml
watched_process=$repo/config/quickshell/core/WatchedProcess.qml
theme=$repo/config/quickshell/core/Theme.qml
commands=$repo/config/quickshell/core/Commands.qml
shell_qml=$repo/config/quickshell/shell.qml

"$repo/scripts/quickshell-qmllint" --root "$repo/config/quickshell"

assert_contains "$model" 'accessibility-settings-protocol\t1\t0'
assert_contains "$model" 'accessibility-settings-action-protocol\t1\t0'
assert_contains "$model" 'readonly property bool mutationReady: root.providerState !== "unavailable"'
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
# state -- assert it is intact, not paraphrased.
assert_contains "$model" 'lines.length !== 5'
assert_contains "$model" 'lines[4] !== "complete\tstatus"'
assert_contains "$model" '["available", "defaults", "partial", "unavailable"].indexOf(state[1]) < 0'
assert_contains "$model" 'parsed[fields[1]] !== undefined'

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
# whole reason the palette slot was split out (see docs/SYNC-P5-CONTRAST-MOTION.md).
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

printf 'Quickshell accessibility policy model: PASS\n'
