#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
core=$repo/config/quickshell/core
panel=$repo/config/quickshell/panel
controls=$repo/config/quickshell/controls
network=$repo/config/quickshell/network
controlcenter=$repo/config/quickshell/controlcenter
power=$repo/config/quickshell/power

for component in PanelHero PanelSeparator PanelSlider PanelToggleSwitch; do
	test -f "$core/$component.qml"
done
grep -Fq 'onEnabledChanged: if (enabled && !dragging) liveValue = value' "$core/PanelSlider.qml"
grep -Fq 'if (wheel.angleDelta.y === 0)' "$core/PanelSlider.qml"

grep -Fq 'readonly property int panelHeight: dp(30)' "$core/Theme.qml"
grep -Fq 'exclusiveZone: Theme.panelHeight' "$panel/DwmPanel.qml"
grep -Fq 'aboveWindows: root.state.fullscreenMonitorIndexes.indexOf(' "$panel/DwmPanel.qml"
grep -Fq 'signal popupRequested(var panelWindow, string popupId)' "$panel/DwmPanel.qml"
# The control center's "Window layout" row (Sync Sprint 11 S11-08) is wired to
# dwm through DwmState, and its list has one entry per layout dwm has.
grep -Fq 'required property var dwmState' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'onActivated: root.dwmState.setLayout(modelData.index)' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'property int layoutIndex: -1' "$repo/config/quickshell/state/DwmState.qml"
grep -Fq 'key === "layout"' "$repo/config/quickshell/state/DwmState.qml"
grep -Fq 'function setLayout(index)' "$repo/config/quickshell/state/DwmState.qml"
select_cc_body=$(sed -n '/^    ControlCenterWindow {/,/^    }/p' "$repo/config/quickshell/shell.qml")
printf '%s\n' "$select_cc_body" | grep -Fq 'dwmState: dwmState'
qml_layouts=$(grep -c '"index": [0-9]' "$controlcenter/ControlCenterWindow.qml")
c_layouts=$(awk '/^static const Layout layouts\[\]/,/^};/' "$repo/config.def.h" | grep -c '^[[:space:]]*{ *"')
[ "$qml_layouts" = "$c_layouts" ] || {
	printf 'ControlCenterWindow.qml lists %s layouts, config.def.h defines %s\n' "$qml_layouts" "$c_layouts" >&2
	exit 1
}
# Clicking the empty part of the bar asks for the empty popup id (Sync Sprint 11
# S11-03), and selectPanelPopup() closes every popup and floating window for it,
# including the ones that hold no input grab (launcher, command menu, notification
# history, control-center utility windows).
grep -Fq 'onClicked: root.popupRequested(root, "")' "$panel/DwmPanel.qml"
select_popup_body=$(sed -n '/function selectPanelPopup(panel, popupId)/,/^    }$/p' "$repo/config/quickshell/shell.qml")
for closer in 'commandMenuModel.close();' 'launcherModel.close();' \
	'notificationModel.closeHistory();' 'controlCenterModel.closeUtility();'; do
	printf '%s\n' "$select_popup_body" | grep -Fq "$closer"
done
grep -Fq 'model: root.state.workspaceIndexes(root.screen)' "$panel/DwmPanel.qml"
grep -Fq 'sourceComponent: TrayArea {' "$panel/DwmPanel.qml"
grep -Fq 'RunningAppsArea { state: root.state }' "$panel/DwmPanel.qml"

grep -Fq 'outlined: true' "$panel/DwmPanel.qml"
grep -Fq 'outlined ? Theme.controlNormalFill : Theme.transparent' "$core/PanelPill.qml"
grep -Fq 'Theme.controlSelectedFill' "$panel/WorkspaceButton.qml"
grep -Fq 'Theme.controlSelectedFill' "$panel/RunningAppItem.qml"
grep -Fq 'Theme.controlHoverFill' "$panel/TrayItem.qml"

grep -Fq 'PanelHero {' "$controls/ControlsWindow.qml"
grep -Fq 'title: "Audio"' "$controls/ControlsWindow.qml"
grep -Fq 'PanelSlider {' "$controls/ControlsWindow.qml"
grep -Fq 'root.controlsModel.volumeSet(Math.round(value))' "$controls/ControlsWindow.qml"
grep -Fq 'PanelHero {' "$controls/BluetoothWindow.qml"
grep -Fq 'PanelToggleSwitch {' "$controls/BluetoothWindow.qml"
grep -Fq 'root.bluetoothModel.action("bluetooth-power", [checked ? "off" : "on"])' \
	"$controls/BluetoothWindow.qml"
grep -Fq 'readonly property bool powered: available && statusText !== "BT off"' \
	"$controls/BluetoothModel.qml"

grep -Fq 'PanelHero {' "$network/NetworkWindow.qml"
grep -Fq 'title: "Network"' "$network/NetworkWindow.qml"
grep -Fq 'onDismissed: networkModel.close()' "$network/NetworkWindow.qml"
grep -Fq 'FloatingWindow {' "$network/NetworkWindow.qml"
grep -Fq 'wifiPasswordInput.forceActiveFocus();' "$network/NetworkWindow.qml"
grep -Fq 'Theme.controlSelectedFill' "$network/NetworkWifiRow.qml"
grep -Fq 'Theme.controlHoverFill' "$network/NetworkProfileRow.qml"
grep -Fq 'ShellButton {' "$network/NetworkWifiRow.qml"
grep -Fq 'ShellButton {' "$network/NetworkProfileRow.qml"

grep -Fq 'PanelSeparator {' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'activeFocusOnTab: presetButton.enabled' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space' \
	"$controlcenter/ControlCenterWindow.qml"
grep -Fq 'PanelSeparator {}' "$power/PowerMenuWindow.qml"
grep -Fq 'text: root.powerMenuModel.pendingAction ? root.powerMenuModel.pendingAction.detail : ""' "$power/PowerMenuWindow.qml"
grep -Fq 'onDismissed: powerMenuModel.close(root.actionOrigin)' "$power/PowerMenuWindow.qml"
grep -Fq 'enabled: !root.powerMenuModel.busy' "$power/PowerMenuWindow.qml"
grep -Fq 'root.powerMenuModel.requestAction(modelData, root.actionOrigin)' \
	"$power/PowerMenuWindow.qml"
for action in lock logout suspend reboot shutdown; do
	grep -Fq "\"id\": \"$action\"" "$power/PowerMenuModel.qml"
done

if grep -REn 'Quickshell\.(Wayland|Hyprland)|WlrLayershell|hyprctl|uwsm-app|wl-copy|wl-paste' \
	"$core"/PanelHero.qml "$core"/PanelSeparator.qml "$core"/PanelSlider.qml \
	"$core"/PanelToggleSwitch.qml "$panel" "$controls" "$network" "$controlcenter" "$power"; then
	printf 'Panel-menu views must remain X11-safe.\n' >&2
	exit 1
fi

if grep -REn '(^|[[:space:]])Process[[:space:]]*\{' \
	"$core"/PanelHero.qml "$core"/PanelSeparator.qml "$core"/PanelSlider.qml \
	"$core"/PanelToggleSwitch.qml; then
	printf 'Visual panel primitives must not own helper processes.\n' >&2
	exit 1
fi

# #384: without a compositor a popup is the menu alone, not a transparent
# surface X draws black. The compositor state is watched (XFixes events in
# dwm-window-thumb), not polled; a popup closes when it loses the keyboard,
# which dwm takes back on a click on the desktop or the selected window.
# tests/test-panel-popup.py checks all of it at runtime.
grep -Fq 'readonly property bool clickAwaySurface: Compositor.running' "$core/ClickAwayPopup.qml"
grep -Fq 'implicitWidth: clickAwaySurface ? areaWidth : menuWidth' "$core/ClickAwayPopup.qml"
grep -Fq 'onHasKeyboardChanged: if (!hasKeyboard) Qt.callLater(root.dismissWithoutKeyboard)' "$core/ClickAwayPopup.qml"
grep -Fq 'else if (root.open)' "$core/ClickAwayPopup.qml"
grep -Fq 'command: Commands.watchCommand(["dwm-window-thumb", "watch-compositor"])' "$core/Compositor.qml"
grep -Fq 'XCB_XFIXES_SELECTION_EVENT_MASK_SET_SELECTION_OWNER' "$repo/dwm-window-thumb.c"
if grep -n 'Timer' "$core/Compositor.qml"; then
	printf 'The compositor state must come from the watcher, not a timer.\n' >&2
	exit 1
fi
# Owners set open, not visible: only open tells a popup Qt closed from one its
# owner closed.
for popup in calendar/CalendarWindow controlcenter/ControlCenterWindow \
	controls/BluetoothWindow controls/ControlsWindow network/NetworkWindow \
	overview/WindowOverview panel/TrayMenu power/PowerMenuWindow weather/WeatherWindow; do
	file=$repo/config/quickshell/$popup.qml
	grep -Fq 'ClickAwayPopup {' "$file"
	grep -Eq '^    open:' "$file"
	if grep -En '^    visible:|root\.visible = ' "$file"; then
		printf '%s sets visible; a ClickAwayPopup owner sets open.\n' "$popup" >&2
		exit 1
	fi
done
[ "$(grep -rl --include='*.qml' 'ClickAwayPopup {' "$repo/config/quickshell" | wc -l)" -eq 9 ]
grep -Fq 'readonly property bool fades: !Theme.reducedMotion && Compositor.running' \
	"$repo/config/quickshell/overview/WindowOverview.qml"
# dwm: the selected window's clicks while a popup has the keyboard, and the
# desktop click.
sed -n '/^focusoverridewindow(Window win)/,/^}/p' "$repo/dwm.c" | grep -Fq 'grabbuttons(selmon->sel, 0);'
sed -n '/^buttonpress(XEvent \*e)/,/^}/p' "$repo/dwm.c" | grep -Fq '} else if (ev->window == root && overridefocus) {'

printf 'Quickshell panel menus: PASS\n'
