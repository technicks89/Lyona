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
# Sync Phase 7: a required (recovery) fetch is not this pane's to kill --
# closeSettings must leave it running so operationModel can still reattach.
grep -Fq 'if (!root.snapshotRequired && snapshotProcess.running) snapshotProcess.running = false;' "$system_model"

# Sync Phase 4: reads are coalesced through the discovery cycle, not fired
# per call. A request that arrives while one is already in flight is
# recorded (snapshotPending) and replayed once, never launched as a second
# overlapping process. Sync Phase 7 adds a `required` parameter (operationModel
# recovering evidence) that is coalesced separately (requiredPending) and
# bypasses discoveryReady()'s settingsVisible tie. Sync Sprint 1 S1-03
# (#261) generalizes the single discoveryModel to five (discoveryModels()),
# each contributing its own cycle token via requestSnapshot()'s take() loop,
# and adds discoveryBatch so openSettings()/refresh() looping over all five
# results in at most one fetch, not up to five.
grep -Fq 'if (root.snapshotOwned || snapshotProcess.running || root.discoveryBatch) {' "$system_model"
grep -Fq 'root.snapshotPending = root.snapshotPending || !required;' "$system_model"
grep -Fq 'root.requiredPending = root.requiredPending || !!required;' "$system_model"
grep -Fq 'if (!required && (!ready || !root.discoveryModels().some(model => model.canTake()))) return;' "$system_model"
grep -Fq 'function discoveryModels() {' "$system_model"
grep -Fq 'function discoveryReady() {' "$system_model"
grep -Fq 'for (const model of root.discoveryModels()) model.open();' "$system_model"
grep -Fq 'for (const model of root.discoveryModels()) model.close();' "$system_model"
grep -Fq 'for (const model of root.discoveryModels()) model.refresh();' "$system_model"
grep -Fq 'const token = model.take();' "$system_model"
grep -Fq 'for (const item of tokens) item.model.beforePublish(item.token);' "$system_model"
grep -Fq 'for (const item of tokens) item.model.complete(item.token, successful);' "$system_model"
grep -Fq 'SystemUpdateDiscovery {' "$system_model"
grep -Fq 'readonly property alias discovery: discoveryModel' "$system_model"
grep -Fq 'readonly property alias timeDiscovery: timeDiscoveryModel' "$system_model"
grep -Fq 'readonly property alias localeDiscovery: localeDiscoveryModel' "$system_model"
grep -Fq 'readonly property alias accountDiscovery: accountDiscoveryModel' "$system_model"
grep -Fq 'readonly property alias printerDiscovery: printerDiscoveryModel' "$system_model"
grep -Fq 'readonly property string discoveryDetail: discoveryModel.detail' "$system_model"

# Relaunch-ordering fix: StdioCollector.onStreamFinished can run before
# Process.running actually flips to false, and Qt.callLater gives no
# ordering guarantee relative to that transition either. Ownership must
# therefore be freed -- and any pending relaunch scheduled -- only from the
# real onRunningChanged(!running) observation, never from finishSnapshot
# (which onStreamFinished can call while the old process is still running).
# finishSnapshot must be bookkeeping-only.
grep -Fq 'snapshotProcess.cycleTokens = [];' "$system_model"
finish_snapshot_body=$(awk '/^    function finishSnapshot\(successful\) \{/,/^    \}/' "$system_model")
if printf '%s\n' "$finish_snapshot_body" | grep -q 'snapshotOwned = false\|snapshotProcess.running = true'; then
	printf 'finishSnapshot must not touch ownership or relaunch directly; that belongs in onRunningChanged.\n' >&2
	exit 1
fi
# Sync Phase 7: the parsed operation state is handed to operationModel from
# this same bookkeeping step, on both the success and failure paths.
if ! printf '%s\n' "$finish_snapshot_body" | grep -Fq 'operationModel.acceptSnapshot(root.activeOperation, root.terminalHandoff);'; then
	printf 'finishSnapshot must hand a successful parse to operationModel.acceptSnapshot.\n' >&2
	exit 1
fi
if ! printf '%s\n' "$finish_snapshot_body" | grep -Fq 'operationModel.snapshotFailed();'; then
	printf 'finishSnapshot must tell operationModel when the snapshot failed.\n' >&2
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

# Sync Phase 7: confirmation is a captured snapshot the model owns
# (generation, requestGeneration and the discovery cycle epoch must all
# still match at confirm time), never a bare flag the pane could set.
grep -Fq 'signal confirmationInvalidated()' "$system_model"
grep -Fq 'property var updateConfirmation: null' "$system_model"
grep -Fq 'function updateActionReason(actionId) {' "$system_model"
grep -Fq 'function prepareUpdate(actionId) {' "$system_model"
grep -Fq 'function discardUpdate() {' "$system_model"
grep -Fq 'function confirmUpdate() {' "$system_model"
confirm_update_body=$(awk '/^    function confirmUpdate\(\) \{/,/^    \}/' "$system_model")
if ! printf '%s\n' "$confirm_update_body" | grep -Fq 'pending.epoch !== discoveryModel.cycle.epoch'; then
	printf 'confirmUpdate must invalidate a stale prompt rather than dispatch it.\n' >&2
	exit 1
fi

# Confirmed dispatch and the actual process/journal-control lifecycle belong
# to operationModel (SystemOperationModel), not this model or the pane.
grep -Fq 'readonly property alias operation: operationModel' "$system_model"
grep -Fq 'SystemOperationModel {' "$system_model"
grep -Fq 'operationModel.startUpdate(' "$system_model"
if grep -qE '\.installAll\(|\.cancelUpdate\(|\.refreshMetadata\(' "$system_model" "$system_pane"; then
	printf 'No mutation entry point may bypass operationModel.startUpdate/requestCancel.\n' >&2
	exit 1
fi
grep -Fq 'update installation require visible confirmation above. Delegated launches' "$system_pane"
grep -Fq 'authorization and safe cancellation.' "$system_pane"
grep -Fq 'SystemUpdateControls {' "$system_pane"
grep -Fq 'onRevealRequested: target => root.reveal(target)' "$system_pane"
grep -Fq 'function reveal(target) {' "$system_pane"

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

# Sync Phase 7 (docs/SYNC-P7-OPERATION-SURFACE.md): confirmed dispatch and
# the process/journal-control lifecycle for one operation at a time.
operation_model=$repo/config/quickshell/systemmanagement/SystemOperationModel.qml
operation_protocol=$repo/config/quickshell/systemmanagement/SystemOperationProtocol.js
update_controls=$repo/config/quickshell/settings/SystemUpdateControls.qml

grep -Fq 'function startUpdate(action, generation) {' "$operation_model"
grep -Fq 'function requestCancel() {' "$operation_model"
grep -Fq 'function acceptSnapshot(active, terminal) {' "$operation_model"
grep -Fq 'function wasAcknowledged(operationId) {' "$operation_model"
grep -Fq 'readonly property bool canStart:' "$operation_model"
grep -Fq 'readonly property bool canCancel:' "$operation_model"
# Never exposed by IPC -- only the Settings caller (via updateActionReason/
# prepareUpdate/confirmUpdate) may reach startUpdate.
if grep -q 'startUpdate' "$shell_qml"; then
	printf 'shell.qml must not call operationModel.startUpdate directly; only the confirmed Settings surface may.\n' >&2
	exit 1
fi

grep -Fq '.pragma library' "$operation_protocol"
grep -Fq 'function actionKind(action) {' "$operation_protocol"
grep -Fq 'function consume(parser, buffer) {' "$operation_protocol"
grep -Fq 'function finish(parser, exitCode, normalExit, replay) {' "$operation_protocol"

grep -Fq 'required property var model' "$update_controls"
grep -Fq 'signal revealRequested(var target)' "$update_controls"
grep -Fq 'root.model.prepareUpdate("updates-refresh")' "$update_controls"
grep -Fq 'root.model.prepareUpdate("updates-install-all")' "$update_controls"
grep -Fq 'root.model.confirmUpdate()' "$update_controls"
grep -Fq 'root.model.discardUpdate()' "$update_controls"
grep -Fq 'root.model.operation.requestCancel()' "$update_controls"

grep -Fq 'function systemManagementOperationState(): string' "$shell_qml"
grep -Fq 'function systemManagementOperationResult(): string' "$shell_qml"

# Sync Sprint 1 S1-04 (#266, #267): delegated actions (accounts-open/
# password-open/printers-open/sources-open) get the same visible
# confirmation step regional mutations already have, instead of dispatching
# immediately on click.
delegate_controls=$repo/config/quickshell/settings/SystemDelegateControls.qml

grep -Fq 'function delegateDiscovery(actionId) {' "$system_model"
grep -Fq 'function delegateContextReason(actionId) {' "$system_model"
grep -Fq 'function delegateActionReason(actionId) {' "$system_model"
grep -Fq 'function prepareDelegate(actionId) {' "$system_model"
grep -Fq 'function discardDelegate() {' "$system_model"
grep -Fq 'function invalidateNativeConfirmation(domain) {' "$system_model"
grep -Fq 'function confirmDelegate() {' "$system_model"
grep -Fq 'property var nativeConfirmation: null' "$system_model"
grep -Fq 'property string nativeConfirmationMessage: ""' "$system_model"
grep -Fq 'property bool dispatchingNative: false' "$system_model"
# launchDelegated() dispatched immediately with no confirmation step -- it
# must be gone, not just unused, so nothing can regress to calling it.
if grep -q 'function launchDelegated' "$system_model"; then
	printf 'launchDelegated() must not exist -- delegated actions require prepareDelegate()/confirmDelegate().\n' >&2
	exit 1
fi

test -f "$delegate_controls"
grep -Fq 'required property var model' "$delegate_controls"
grep -Fq 'signal revealRequested(var target)' "$delegate_controls"
grep -Fq 'root.model.prepareDelegate(toolCard.modelData.id)' "$delegate_controls"
grep -Fq 'root.model.confirmDelegate()' "$delegate_controls"
grep -Fq 'root.model.discardDelegate()' "$delegate_controls"
grep -Fq 'SystemDelegateControls {' "$system_pane"

# Mutual exclusion with the update cancel control: a regional or delegated
# operation's progress must not enable "Request cancellation" -- only
# cancel_journal_operation()'s own update/refresh restriction ever permits it.
grep -Fq 'readonly property bool updateOperation:' "$update_controls"
grep -Fq 'visible: root.model.operation.streamOwned && root.updateOperation' "$update_controls"

# Never exposed by IPC directly -- only the confirmed Settings surface
# (prepareDelegate/confirmDelegate) may reach operationModel.startNative.
if grep -q 'systemManagementModel.startNative' "$shell_qml"; then
	printf 'shell.qml must not call operationModel.startNative directly; only the confirmed Settings surface may.\n' >&2
	exit 1
fi

grep -Fq 'function systemManagementPrepareDelegate(action: string): bool' "$shell_qml"
grep -Fq 'function systemManagementConfirmDelegate(): bool' "$shell_qml"
grep -Fq 'function systemManagementDiscardDelegate(): void' "$shell_qml"
grep -Fq 'function systemManagementNativeConfirmationPending(): bool' "$shell_qml"

printf 'Quickshell system-management model contract: PASS\n'
