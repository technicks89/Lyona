#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
network_model=$repo/config/quickshell/network/NetworkModel.qml
bluetooth_model=$repo/config/quickshell/controls/BluetoothModel.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
network_pane=$repo/config/quickshell/settings/NetworkSettingsPane.qml
bluetooth_pane=$repo/config/quickshell/settings/BluetoothSettingsPane.qml

grep -Fq 'run_parent_bound nmcli monitor' "$repo/scripts/dwm-quickshell-network"
grep -Fq 'run_parent_bound playerctl --follow' "$repo/scripts/dwm-quickshell-controls"
grep -Fq 'networkMonitorRestartTimer.restart()' "$network_model"

for pattern in \
	'fields[0] === "connectivity-protocol"' \
	'fields[1] === "1"' \
	'!protocolValid || !providerSeen || malformed' \
	'fields.length < 5' \
	'root.providerState = "failure"'; do
	grep -Fq "$pattern" "$network_model"
	grep -Fq "$pattern" "$bluetooth_model"
done

grep -Fq 'else if (fields[0] === "network-profile")' "$network_model"
grep -Fq 'else if (fields[0] === "wifi-network")' "$network_model"
grep -Fq 'else if (fields[0] === "bluetooth-adapter")' "$bluetooth_model"
grep -Fq 'else if (fields[0] === "bluetooth-device")' "$bluetooth_model"

grep -Fq 'function openSettings()' "$network_model"
# The parent-bound watchdog moved into the shared helper; the callers have to
# reach it, and it has to still refuse a parent it cannot identify.
# shellcheck disable=SC2016 # matching the helper's source text verbatim
assert_contains "$repo/scripts/dwm-watchdog.sh" '[ -n "$parent_identity" ] || return 1'
for watchdog_caller in dwm-quickshell-network dwm-quickshell-controls; do
	assert_contains "$repo/scripts/$watchdog_caller" 'dwm-watchdog.sh'
done
grep -Fq 'property string wifiPasswordPromptOrigin: ""' "$network_model"
grep -Fq 'function supportsFixedWifiSecurity(security)' "$network_model"
grep -Fq 'function closeSettings()' "$network_model"
grep -Fq 'function openSettings()' "$bluetooth_model"
grep -Fq 'function closeSettings()' "$bluetooth_model"
grep -Fq 'root.actionOrigin === origin && actionProcess.running' "$network_model"
grep -Fq 'root.scanOrigin === origin && scanProcess.running' "$bluetooth_model"
grep -Fq 'operationState === "delegated"' "$bluetooth_model"
grep -Fq 'root.connections = []' "$network_model"
grep -Fq 'root.operationState = "unavailable"' "$bluetooth_model"

if grep -Fq 'repeat: true' "$network_model" || grep -Fq 'repeat: true' "$bluetooth_model"; then
	printf 'Connectivity models must not poll.\n' >&2
	exit 1
fi
grep -Fq 'stdout: SplitParser { onRead: monitorSettleTimer.restart() }' "$bluetooth_model"

grep -Fq 'networkModel: networkModel' "$repo/config/quickshell/shell.qml"
grep -Fq 'bluetoothModel: bluetoothModel' "$repo/config/quickshell/shell.qml"
grep -Fq 'root.networkModel.openSettings()' "$settings_model"
grep -Fq 'root.bluetoothModel.openSettings()' "$settings_model"
grep -Fq 'NetworkSettingsPane {' "$settings_window"
grep -Fq 'BluetoothSettingsPane {' "$settings_window"

grep -Fq 'connectSelectedWifi("settings")' "$network_pane"
grep -Fq 'function onWifiPasswordChanged()' "$network_pane"
grep -Fq 'passwordInput.clear()' "$network_pane"
grep -Fq 'Confirm Forget' "$network_pane"
grep -Fq 'root.networkModel.wifiPasswordPromptOrigin === "settings"' "$network_pane"
grep -Fq 'delegated: !root.networkModel.supportsFixedWifiSecurity(modelData.security)' "$network_pane"
grep -Fq 'forgetProfile(profileRow.modelData, "settings")' "$network_pane"
grep -Fq 'bluetooth-trust' "$bluetooth_pane"
grep -Fq 'bluetooth-remove' "$bluetooth_pane"
grep -Fq 'Confirm Remove' "$bluetooth_pane"
grep -Fq 'actionAddress === modelData.address' "$bluetooth_pane"

printf 'Quickshell connectivity contract: PASS\n'
