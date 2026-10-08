#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
model=$repo/config/quickshell/power/PowerModel.qml
pane=$repo/config/quickshell/settings/PowerSettingsPane.qml
settings=$repo/config/quickshell/settings/SettingsModel.qml
control_center=$repo/config/quickshell/controlcenter/ControlCenterModel.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
shell=$repo/config/quickshell/shell.qml
# The settings target's test getters (Sync Sprint 12 S12-16).
settings_test_ipc=$repo/config/quickshell/settings/SettingsTestIpc.qml

grep -Fq 'import Quickshell.Services.UPower' "$model"
grep -Fq 'readonly property var nativeBattery: UPower.displayDevice' "$model"
grep -Fq 'function onOnBatteryChanged()' "$model"
grep -Fq 'Math.round(battery.percentage * 100)' "$model"
grep -Fq 'function nativeBatteryStatus(state)' "$model"
for state in Charging Discharging Empty FullyCharged PendingCharge PendingDischarge; do
	grep -Fq "UPowerDeviceState.$state" "$model"
done
grep -Fq 'return "pending-charge"' "$model"
grep -Fq 'return "pending-discharge"' "$model"
grep -Fq 'function onProfileChanged()' "$model"
grep -Fq 'property bool nativeProfileObserved: false' "$model"
grep -Fq 'if (root.nativeProfileObserved) root.updateNativeProfile();' "$model"

grep -Fq 'fields[0] === "power-protocol"' "$model"
# The header through the shared rule (Sync Sprint 16 R16-53).
grep -Fq 'protocolValid = Protocol.validHeader(fields, 1);' "$model"
grep -Fq '!/^[0-9]+$/.test(value)' "$model"
grep -Fq '!/^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/.test(value)' "$model"
grep -Fq '!protocolValid || !providerSeen' "$model"
for record in power-dpms power-lock power-external power-battery \
	power-profile-support power-profile power-suspend power-lid; do
	grep -Fq "fields[0] === \"$record\"" "$model"
done
grep -Fq 'fields[0] === "power-lid-policy"' "$model"
grep -Fq 'function validLidAction(value)' "$model"
grep -Fq 'root.boundedInteger(fields[3], 0, 100)' "$model"
grep -Fq 'root.dpmsState = "unavailable"' "$model"
grep -Fq 'root.lockState = "unavailable"' "$model"
grep -Fq 'root.dpmsEnabled = false;' "$model"
grep -Fq 'root.lockRunning = false;' "$model"
grep -Fq 'root.batteryPercent = 0;' "$model"
grep -Fq 'root.clearExternalPowerState("External power provider returned malformed state")' "$model"
grep -Fq 'root.profileState = "unavailable"' "$model"
grep -Fq 'root.suspendState = "unavailable"' "$model"
grep -Fq 'root.lidState = "unavailable"' "$model"
grep -Fq 'root.lidPolicyState = "unavailable"' "$model"

grep -Fq 'property int mutationGeneration: 0' "$model"
grep -Fq 'property int actionGeneration: 0' "$model"
grep -Fq 'property int snapshotGeneration: 0' "$model"
grep -Fq 'root.snapshotGeneration !== root.mutationGeneration' "$model"
grep -Fq 'root.actionGeneration !== root.mutationGeneration' "$model"
grep -Fq 'if (root.busy || actionProcess.running) return;' "$model"
grep -Fq 'if (root.sectionVisible) root.refresh();' "$model"
grep -Fq 'property string mutationOrigin: ""' "$model"
grep -Fq 'function messageFor(origin)' "$model"
grep -Fq 'root.mutationOrigin === origin ? root.message : ""' "$model"

[ "$(grep -Fc 'Commands.powerHelperCommand("power-watch")' "$model")" -eq 1 ]
grep -Fq 'readonly property bool sectionVisible:' "$model"
grep -Fq 'property bool sessionMenuVisible: false' "$model"
grep -Fq '|| root.sessionMenuVisible' "$model"
grep -Fq 'function openSettings()' "$model"
grep -Fq 'function closeSettings()' "$model"
grep -Fq 'function openControlCenter()' "$model"
grep -Fq 'function closeControlCenter()' "$model"
grep -Fq 'function openSessionMenu()' "$model"
grep -Fq 'function closeSessionMenu()' "$model"
assert_contains "$model" 'watcher.stop()'
grep -Fq 'snapshotProcess.running = false' "$model"
assert_contains "$model" 'WatchedProcess {'
assert_contains "$model" 'active: root.sectionVisible'
if grep -Fq 'repeat: true' "$model"; then
	printf 'Power model must not poll.\n' >&2
	exit 1
fi

grep -Fq 'property var powerModel: null' "$settings"
grep -Fq 'root.powerModel.openSettings()' "$settings"
grep -Fq 'root.powerModel.closeSettings()' "$settings"
grep -Fq 'property var powerModel: null' "$control_center"
grep -Fq 'root.powerModel.openControlCenter()' "$control_center"
grep -Fq 'root.powerModel.closeControlCenter()' "$control_center"
grep -Fq 'PowerSettingsPane {' "$repo/config/quickshell/settings/SettingsWindow.qml"
grep -Fq 'setProfile(profileButton.modelData.id, "settings")' "$pane"
grep -Fq 'setDpms(!root.powerModel.dpmsEnabled, "settings")' "$pane"
grep -Fq 'setLock(!root.powerModel.lockEnabled, "settings")' "$pane"
grep -Fq 'root.powerModel.messageFor("settings")' "$pane"
grep -Fq 'function powerBusy(): bool' "$settings_test_ipc"
grep -Fq 'function powerMessage(): string' "$settings_test_ipc"
grep -Fq 'function powerSetDpms(enabled: bool): void' "$settings_test_ipc"
grep -Fq 'root.powerModel.setDpms(enabled, "settings")' "$settings_test_ipc"

[ "$(grep -Fc 'PowerModel {' "$shell")" -eq 1 ]
grep -Fq 'powerModel: powerModel' "$shell"
grep -Fq 'required property var powerModel' "$panel"
grep -Fq 'visible: root.powerModel.batteryAvailable' "$panel"
grep -Fq 'root.powerModel.batteryPercent.toString() + "%"' "$panel"
if grep -Fq 'visible: root.state.batteryAvailable' "$panel"; then
	printf 'Panel still renders battery state from the legacy DwmState model.\n' >&2
	exit 1
fi

grep -Fq 'root.powerModel.setDpms(!root.powerModel.dpmsEnabled, "controlcenter")' \
	"$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'root.powerModel.setLock(!root.powerModel.lockEnabled, "controlcenter")' \
	"$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'root.powerModel.messageFor("controlcenter")' \
	"$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'property bool confirming: false' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
for action in lock logout suspend reboot shutdown; do
	grep -Fq "\"id\": \"$action\"" "$repo/config/quickshell/power/PowerMenuModel.qml"
done
grep -Fq 'property string actionOrigin: ""' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
grep -Fq 'property string confirmationOrigin: ""' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
grep -A4 -F 'function rejectOverlap(origin)' \
	"$repo/config/quickshell/power/PowerMenuModel.qml" |
	grep -Fq 'root.rejectionMessage = "Another session action is already in progress";'
if grep -A4 -F 'function rejectOverlap(origin)' \
	"$repo/config/quickshell/power/PowerMenuModel.qml" |
	grep -Fq 'root.actionSucceeded = false;'; then
	printf 'Overlap rejection must not mutate the active action result.\n' >&2
	exit 1
fi
grep -Fq 'root.powerMenuModel.cancelConfirmation("settings")' \
	"$repo/config/quickshell/settings/SettingsModel.qml"
grep -Fq 'function clearOverlapRejection()' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
grep -Fq 'requestedAction.label + " is unavailable on this system"' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
request_action_block=$(sed -n \
	'/function requestAction(action, origin)/,/function cancelConfirmation(origin)/p' \
	"$repo/config/quickshell/power/PowerMenuModel.qml")
if printf '%s\n' "$request_action_block" | grep -Fq 'root.actionSucceeded = false'; then
	printf 'Unavailable session actions must not mutate another action result.\n' >&2
	exit 1
fi
busy_line=$(printf '%s\n' "$request_action_block" |
	grep -n -m1 -F 'if (root.busy || actionProcess.running)' | cut -d: -f1)
unavailable_line=$(printf '%s\n' "$request_action_block" |
	grep -n -m1 -F 'if (!requestedAction.available)' | cut -d: -f1)
if [ -z "$busy_line" ] || [ -z "$unavailable_line" ] ||
	[ "$busy_line" -ge "$unavailable_line" ]; then
	printf 'Busy session actions must reject before availability handling.\n' >&2
	exit 1
fi
grep -Fq 'this.text.trim() === actionProcess.expectedResult' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
grep -Fq 'this.text.trim() === actionProcess.expectedResult' \
	"$repo/config/quickshell/power/PowerModel.qml"
grep -Fq 'Commands.sessionActionCommand(requestedAction.id)' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
grep -Fq 'root.powerModel.openSessionMenu()' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
grep -Fq 'root.powerModel.closeSessionMenu()' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
if grep -R -Fq 'powerMenuModel.close()' "$repo/config/quickshell"; then
	printf 'Session confirmation closure must retain an explicit surface origin.\n' >&2
	exit 1
fi

# #243: peripheral batteries come from UPower's device list through the tested
# PeripheralBatteries.js, rebuilt on UPower's signals: no polling timer, no
# `upower` output. Settings and the Control Center show them only when there are
# some, and the display profiles' laptop detection (#310) does not use them.
grep -Fq 'import "PeripheralBatteries.js" as Peripherals' "$model"
grep -Fq 'model: UPower.devices.values' "$model"
grep -Fq 'const rows = Peripherals.select(devices);' "$model"
grep -Fq 'Peripherals.lowWarnings(rows, root.peripheralWarned)' "$model"
grep -Fq 'function onPercentageChanged() { peripheralWatcher.reread(); root.schedulePeripherals(); }' "$model"
if grep -Eq 'upower (-d|--dump|-i|--show-info)' "$model"; then
	printf 'PowerModel.qml must read UPower through its service API, not upower output.\n' >&2
	exit 1
fi
peripheral_block=$(sed -n '/id: peripheralWatchers/,/target: PowerProfiles/p' "$model")
if printf '%s\n' "$peripheral_block" | grep -Eq '\bTimer\b|\bProcess\b|watchChanges: true'; then
	printf 'The peripheral battery watchers must be event-driven: no Timer, Process or file watch.\n' >&2
	exit 1
fi
grep -Fq 'visible: root.powerModel.peripherals.length > 0' "$pane"
grep -Fq 'model: root.powerModel.peripherals' "$pane"
grep -Fq 'model: root.powerModel.peripherals' "$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'if scope != "Device":' "$repo/scripts/dwm-settings-display-profiles" || {
	printf 'The display profiles must keep ignoring device batteries (#310).\n' >&2
	exit 1
}

printf 'Quickshell shared power model and Settings contract: PASS\n'
