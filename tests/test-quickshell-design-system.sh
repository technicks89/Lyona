#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

theme=$repo/config/quickshell/core/Theme.qml
core=$repo/config/quickshell/core
shell=$repo/config/quickshell
design_doc=$repo/docs/OMARCHY-UI-ADAPTATION.md

qml_packages=$(bash -c '. "$1"; dwm_packages arch qml-validation' sh \
	"$repo/scripts/dwm-packages.sh")
[ "$(printf '%s\n' "$qml_packages" | wc -l)" -eq 2 ]
printf '%s\n' "$qml_packages" | grep -Fx quickshell >/dev/null
printf '%s\n' "$qml_packages" | grep -Fx qt6-declarative >/dev/null
[ "$(grep -Fc 'dwm_packages arch qml-validation' "$repo/.github/workflows/c-cpp.yml")" -eq 2 ]
for package in quickshell qt6-declarative; do
	if grep -Eq "(^|[^[:alnum:]_+-])$package([^[:alnum:]_+-]|-[0-9]|$)" \
		"$repo/.github/workflows/c-cpp.yml"; then
		printf '%s\n' "CI hard-codes $package instead of using the qml-validation profile." >&2
		exit 1
	fi
done

for token in \
	popupBackground popupBorder menuActionText menuHoverBackground \
	menuSelectedBackground menuSelectedText menuHeaderHeight \
	controlNormalFill controlHoverFill controlFocusBorder \
	controlSelectedFill controlDisabledFill spacingXxs spacingHuge \
	fontCaptionSize fontBodySmallSize fontBodySize fontTitleSize controlHeight \
	controlRowHeight controlPaddingX controlRadius popupPadding; do
	grep -Eq "readonly property (string|int) $token:" "$theme"
done

grep -Fq 'Theme.popupBackground' "$core/ShellSurface.qml"
grep -Fq 'Theme.popupBorder' "$core/ShellSurface.qml"
grep -Fq 'Theme.controlNormalFill' "$core/ShellButton.qml"
grep -Fq 'Theme.controlFocusBorder' "$core/ShellButton.qml"
grep -Fq 'Theme.menuHoverBackground' "$core/MenuRow.qml"
grep -Fq 'root.active ? Theme.menuSelectedBackground' "$core/MenuRow.qml"
grep -Fq 'Theme.menuSelectedText' "$core/MenuRow.qml"
grep -Fq 'Theme.menuHeaderHeight' "$core/MenuHeader.qml"
grep -Fq 'Theme.fontBodySmallSize' "$core/SectionLabel.qml"

grep -Fq 'This is a design influence, not a shell transplant.' "$design_doc"
grep -Fq 'current root-scoped models' "$design_doc"

# Shared UI vocabulary lives in core/ and Theme, not copied into panes.
grep -Eq '^    function statusColor\(' "$theme"
grep -Eq '^    function formatDuration\(' "$theme"
[ -f "$core/StatusCard.qml" ]
grep -Fq 'Theme.statusColor(statusCard.statusState)' "$core/StatusCard.qml"

# DefaultsSettingsPane keeps its own statusColor on purpose: it colours a
# generic capability list where "unsupported" is neutral rather than a fault.
duplicate_status_colour=$(grep -rl 'function statusColor(' "$shell" |
	grep -v 'core/Theme.qml' |
	grep -v 'settings/DefaultsSettingsPane.qml' || true)
if [ -n "$duplicate_status_colour" ]; then
	printf '%s\n' "statusColor() is duplicated outside Theme: $duplicate_status_colour" >&2
	exit 1
fi

duplicate_duration=$(grep -rl 'function formatDuration(' "$shell" |
	grep -v 'core/Theme.qml' || true)
if [ -n "$duplicate_duration" ]; then
	printf '%s\n' "formatDuration() is duplicated outside Theme: $duplicate_duration" >&2
	exit 1
fi

inline_status_card=$(grep -rl 'component StatusCard:' "$shell" || true)
if [ -n "$inline_status_card" ]; then
	printf '%s\n' "StatusCard is inlined instead of imported: $inline_status_card" >&2
	exit 1
fi

# A .filter() in a Repeater's model binding rescans the whole list per
# delegate and returns a fresh array, so QML rebuilds rather than diffs.
# Group in the model and look the group up instead.
if grep -REn -A 1 '^[[:space:]]*model: .*\.filter\(' "$shell"; then
	printf '%s\n' 'A Repeater model binding filters inline; group it in the model instead.' >&2
	exit 1
fi
grep -Fq 'candidatesForRole(' "$shell/defaults/DefaultAppsModel.qml"
grep -Fq 'candidatesForMime(' "$shell/defaults/DefaultAppsModel.qml"
grep -Fq 'inputSettingsFor(' "$shell/settings/SettingsModel.qml"

# The supervised watcher is defined once. Both timers are load-bearing:
# settle coalesces a burst of change lines into one refresh, restart brings a
# dead helper back while the surface is still open.
watched=$core/WatchedProcess.qml
[ -f "$watched" ]
grep -Fq 'stdout: SplitParser' "$watched"
grep -Fq 'interval: root.settleInterval' "$watched"
grep -Fq 'interval: root.restartInterval' "$watched"
grep -Fq 'if (!running && root.active)' "$watched"
grep -Fq 'if (root.active && !watchProcess.running)' "$watched"
# A watcher is event-driven; a repeating timer here would be a poll.
if grep -Fq 'repeat: true' "$watched"; then
	printf '%s\n' 'WatchedProcess must not poll.' >&2
	exit 1
fi

# No model may rebuild the whole pattern inline. The tell is a stdout handler
# that does nothing but restart a settle timer, next to a matching restart
# timer -- that combination is exactly what the component expresses.
#
# Watchers with a bespoke stdout handler (AppearanceModel's inventory
# handshake) and lone settle or restart timers (BluetoothModel, ControlsModel,
# NetworkModel, SettingsModel) are deliberately left alone: they are not this
# pattern, and folding them in would mean inventing options for one caller.
for model in "$shell"/*/*.qml; do
	[ -f "$model" ] || continue
	settle=$(sed -n 's/.*stdout: SplitParser { onRead: \([A-Za-z]*\)SettleTimer\.restart() }.*/\1/p' \
		"$model")
	[ -n "$settle" ] || continue
	printf '%s\n' "$settle" | while IFS= read -r prefix; do
		[ -n "$prefix" ] || continue
		if grep -Fq "id: ${prefix}RestartTimer" "$model"; then
			printf '%s\n' \
				"$model rebuilds the supervised-watcher pattern ($prefix); use WatchedProcess." >&2
			exit 1
		fi
	done || exit 1
done

if grep -REn \
	-e 'Quickshell\.(Wayland|Hyprland)' \
	-e 'WlrLayershell' \
	-e '(^|[^[:alnum:]_-])(hyprctl|uwsm-app|wl-copy|wl-paste)([^[:alnum:]_-]|$)' \
	"$shell"; then
	printf '%s\n' 'Managed Quickshell configuration contains a forbidden Wayland or Hyprland dependency.' >&2
	exit 1
fi

printf '%s\n' 'Quickshell design system: PASS'
