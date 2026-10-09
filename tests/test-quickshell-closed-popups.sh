#!/usr/bin/env bash
set -euo pipefail

# #287: a closed popup holds no list items, so an update while it is closed
# rebuilds nothing; opening it shows the model's current data at once. #288:
# notification history is capped in size as well as count.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

qs=$repo/config/quickshell
gated() { # FILE MODEL
	grep -Fq "model: root.visible ? $2 : []" "$qs/$1" || fail "$1 keeps $2 while closed"
}
gated notifications/NotificationHistoryWindow.qml root.notificationModel.history
gated network/NetworkWindow.qml root.networkModel.activeConnections
gated network/NetworkWindow.qml root.networkModel.wifiNetworks
gated network/NetworkWindow.qml root.networkModel.savedProfiles
gated controls/BluetoothWindow.qml root.bluetoothModel.devices
gated controls/ControlsWindow.qml root.controlsModel.outputDevices

model=$qs/notifications/NotificationModel.qml
grep -Fq '"summary": root.clipText(item.summary, root.maxHistorySummary),' "$model" ||
	fail 'a notification summary enters history uncut'
grep -Fq '"body": root.clipText(item.body, root.maxHistoryBody),' "$model" ||
	fail 'a notification body enters history uncut'
grep -Fq '.map(entry => root.historyEntry(entry, entry.timestamp));' "$model" ||
	fail 'a saved history is loaded uncut'

printf 'Closed popups hold no list items; history is capped in size: PASS\n'
