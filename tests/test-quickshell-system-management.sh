#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
shell_qml=$repo/config/quickshell/shell.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
system_pane=$repo/config/quickshell/settings/SystemSettingsPane.qml
system_model=$repo/config/quickshell/systemmanagement/SystemManagementModel.qml
discovery_cycle=$repo/config/quickshell/systemmanagement/SystemDiscoveryCycle.js
provider_discovery=$repo/config/quickshell/systemmanagement/SystemProviderDiscovery.qml
update_discovery=$repo/config/quickshell/systemmanagement/SystemUpdateDiscovery.qml
provider_root=$repo/scripts/dwm-system-management
commands=$repo/config/quickshell/core/Commands.qml
provider=$repo/scripts/dwm-settings-provider

test "$(grep -c 'SystemManagementModel {' "$shell_qml")" -eq 1
grep -Fq 'systemManagementModel: systemManagementModel' "$shell_qml"
grep -Fq 'import qs.systemmanagement' "$shell_qml"
grep -Fq 'systemManagementModel: root.systemManagementModel' "$settings_window"
grep -Fq 'required property var systemManagementModel' "$settings_window"
grep -Fq 'required property var systemManagementModel' "$system_pane"

grep -Fq 'function systemManagementCommand(action, args)' "$commands"

# Lifecycle: open/close pairing follows the same shape every other
# Settings-only model in this shell already uses (network/bluetooth/audio/
# power/defaults/autostart/appearance) -- never polled, gated on
# settingsVisible, and closing the section stops any in-flight fetch.
grep -Fq 'property var systemManagementModel: null' "$settings_model"
grep -Fq 'root.systemManagementModel.openSettings()' "$settings_model"
grep -Fq 'root.systemManagementModel.closeSettings()' "$settings_model"
grep -Fq 'root.selectedSectionId === "system" && root.systemManagementModel' "$settings_model"
grep -Fq 'function openSettings()' "$system_model"
grep -Fq 'function closeSettings()' "$system_model"
grep -Fq 'if (snapshotProcess.running) snapshotProcess.running = false;' "$system_model"

# Sync Phase 4: reads are coalesced through the discovery cycle, not fired
# per call. A request that arrives while one is already in flight is
# recorded (snapshotPending) and replayed once, never launched as a second
# overlapping process.
grep -Fq 'if (root.snapshotOwned || snapshotProcess.running) {' "$system_model"
grep -Fq 'root.snapshotPending = true;' "$system_model"
grep -Fq 'if (!discoveryModel.canTake()) return;' "$system_model"
grep -Fq 'discoveryModel.open();' "$system_model"
grep -Fq 'discoveryModel.close();' "$system_model"
grep -Fq 'discoveryModel.refresh();' "$system_model"
grep -Fq 'discoveryModel.take();' "$system_model"
grep -Fq 'discoveryModel.beforePublish(snapshotProcess.cycleToken);' "$system_model"
grep -Fq 'discoveryModel.complete(snapshotProcess.cycleToken, successful);' "$system_model"
grep -Fq 'SystemUpdateDiscovery {' "$system_model"
grep -Fq 'readonly property alias discovery: discoveryModel' "$system_model"
grep -Fq 'readonly property string discoveryDetail: discoveryModel.detail' "$system_model"

# Relaunch-ordering fix: StdioCollector.onStreamFinished can run before
# Process.running actually flips to false, and Qt.callLater gives no
# ordering guarantee relative to that transition either. Ownership must
# therefore be freed -- and any pending relaunch scheduled -- only from the
# real onRunningChanged(!running) observation, never from finishSnapshot
# (which onStreamFinished can call while the old process is still running).
# finishSnapshot must be bookkeeping-only.
grep -Fq 'snapshotProcess.cycleToken = null;' "$system_model"
finish_snapshot_body=$(awk '/^    function finishSnapshot\(successful\) \{/,/^    \}/' "$system_model")
if printf '%s\n' "$finish_snapshot_body" | grep -q 'snapshotOwned = false\|snapshotProcess.running = true'; then
	printf 'finishSnapshot must not touch ownership or relaunch directly; that belongs in onRunningChanged.\n' >&2
	exit 1
fi
running_changed_body=$(awk '/^        onRunningChanged: if \(!running\) \{/,/^        \}$/' "$system_model")
if ! printf '%s\n' "$running_changed_body" | grep -q 'root.snapshotOwned = false;'; then
	printf 'onRunningChanged must clear snapshotOwned once the process is confirmed not running.\n' >&2
	exit 1
fi
if ! printf '%s\n' "$running_changed_body" | grep -q 'Qt.callLater(function() {'; then
	printf 'onRunningChanged must queue the pending relaunch, not call requestSnapshot synchronously.\n' >&2
	exit 1
fi

# The fetch goes through the plain checkedCommand gate, not
# terminatingCheckedCommand -- this is a one-shot bounded read, not the
# long-running watch-* child terminatingCheckedCommand exists for
# (Sync Phase 4).
grep -Fq 'Commands.checkedCommand(Commands.systemManagementCommand("snapshot", []))' "$system_model"
if grep -q 'terminatingCheckedCommand' "$system_model"; then
	printf 'SystemManagementModel must use checkedCommand for the one-shot snapshot fetch.\n' >&2
	exit 1
fi

# Protocol parsing is all-or-nothing, matching every other helper protocol
# parser in this shell: a record that fails validation discards the whole
# snapshot rather than rendering a partial one, and a snapshot without a
# trailing complete\tsnapshot is never accepted.
grep -Fq 'system-management-protocol' "$system_model"
grep -Fq 'lines[lines.length - 1] !== "complete\tsnapshot"' "$system_model"
grep -Fq 'omitted a mandatory record' "$system_model"
grep -Fq 'omitted a mandatory action' "$system_model"
grep -Fq 'validStatus.indexOf' "$system_model"
grep -Fq 'validSeverity.indexOf' "$system_model"
grep -Fq 'validInstallability.indexOf' "$system_model"
grep -Fq 'validRestart.indexOf' "$system_model"
grep -Fq 'validPlanAction.indexOf' "$system_model"
grep -Fq 'validErrorCode.indexOf' "$system_model"
grep -Fq 'seenUpdateIds[fields[1]]' "$system_model"
grep -Fq 'maxListRecords' "$system_model"

# The restart-guidance heuristic (docs/SYNC-P2-UPDATE-SNAPSHOT.md section 5)
# must never be collapsed to a boolean here -- "unknown" is a distinct,
# legitimate value from "none", not an error state.
grep -Fq '"unknown"' "$system_model"
grep -Fq '"system"' "$system_model"

# Read-only at this boundary: no mutation call exists yet, and the pane must
# say so rather than the earlier "not yet enabled" wording Sync Phase 7
# replaces.
if grep -qE '\.installAll\(|\.cancelUpdate\(|\.refreshMetadata\(' "$system_model" "$system_pane"; then
	printf 'No mutation entry point may exist before Sync Phase 7.\n' >&2
	exit 1
fi
grep -Fq 'require a separate confirmed' "$system_pane"

# The privileged step is still lyona-update's alone; this pane never invokes
# privilege escalation directly.
if grep -q 'pkexec\|sudo' "$system_pane" "$system_model"; then
	printf 'System management pane/model must not invoke privilege escalation directly.\n' >&2
	exit 1
fi

# additionalCapabilities must exclude both the lyona-update "updates"
# capability (Sync Phase 1's coexistence rule) and the new "package-updates"
# capability this boundary gives its own dedicated section to -- otherwise
# the same status would render twice.
grep -Fq 'capability.id !== "updates" && capability.id !== "package-updates"' "$system_pane"
grep -Fq 'emit_capability system package-updates' "$provider"
grep -Fq 'emit_capability system health' "$provider"
grep -Fq 'emit_capability system authorization' "$provider"

# Settings section wiring: "system" already existed and already excluded
# the generic capability-list fallback (UPDATE-003); this boundary must not
# introduce a second exclusion or a duplicate pane mount.
test "$(grep -c 'SystemSettingsPane {' "$settings_window")" -eq 1
test "$(grep -c '!== "system"' "$settings_window")" -eq 1

# Sync Phase 4 (docs/SYNC-P4-DISCOVERY-EVENTS.md): live discovery monitoring.
grep -Fq 'function create()' "$discovery_cycle"
grep -Fq 'function owns(cycle, token)' "$discovery_cycle"
grep -Fq 'unresolved: false' "$discovery_cycle"

grep -Fq 'domain: "updates"' "$update_discovery"

# The refactored, generic-from-the-start form is ported directly (upstream's
# a6d65c08/#260) -- five domains selectable, only "updates" has a helper
# behind it yet; the other four are Sync Phase 9.
grep -Fq 'function domainDefinition(value)' "$provider_discovery"
grep -Fq '"watch-updates"' "$provider_discovery"
grep -Fq '"watch-regional"' "$provider_discovery"
grep -Fq '"watch-accounts"' "$provider_discovery"
grep -Fq '"watch-units"' "$provider_discovery"

# Deliberately unwrapped: both checkedCommand and terminatingCheckedCommand
# buffer the wrapped command's stdout to a temp file and only `cat` it once
# the child exits -- correct for a bounded one-shot read, but it defeats
# live event streaming entirely (ready/changed would only ever arrive as one
# batch at shutdown). helperCommand's own script already execs the real
# helper, so this Process's PID already *is* the helper and monitor.signal()
# reaches it directly -- no orphaning risk to guard against here. This
# corrects docs/SYNC-P4-DISCOVERY-EVENTS.md's own terminatingCheckedCommand
# instruction, found wrong when the xvfb test's snapshot never left "idle"
# with a real (non-instantly-exiting) watch-updates stub.
grep -Fq 'monitor.command = Commands.systemManagementCommand(selected.action, selected.args);' "$provider_discovery"
grep -Fq 'Timer { id: setupDeadline; interval: 12000' "$provider_discovery"
grep -Fq 'Timer { id: stopDeadline; interval: 1500' "$provider_discovery"
grep -Fq 'monitor.signal(15)' "$provider_discovery"
grep -Fq 'monitor.signal(9)' "$provider_discovery"

# Any event line that is not exactly "<prefix>\tready" or "<prefix>\tchanged"
# fails the monitor -- unlike the snapshot protocol, unknown records here
# are never tolerated.
grep -Fq 'else root.failMonitor();' "$provider_discovery"

grep -Fq 'function systemManagementDiscoveryStatus(): string' "$shell_qml"

# The Python side: a bounded, read-only event stream, not a transaction.
grep -Fq 'class UpdateEventMonitor:' "$provider_root"
grep -Fq 'def watch_update_events() -> int:' "$provider_root"
grep -Fq 'list(argv) == ["watch-updates"]' "$provider_root"
if awk '/^class UpdateEventMonitor:/,/^def watch_update_events\(\) -> int:/' "$provider_root" |
	awk '/^def watch_update_events\(\) -> int:/{exit} {print}' |
	grep -q 'PackageKitGlib'; then
	printf 'UpdateEventMonitor must not touch PackageKitGlib transaction machinery.\n' >&2
	exit 1
fi

# The pane surfaces the live-monitoring state as an advisory line, per the
# phase document's exact wording ("Reload status to retry/reconcile").
grep -Fq 'root.systemManagementModel.discoveryDetail' "$system_pane"

printf 'Quickshell system-management model contract: PASS\n'
