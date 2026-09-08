#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
shell_qml=$repo/config/quickshell/shell.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
system_pane=$repo/config/quickshell/settings/SystemSettingsPane.qml
system_model=$repo/config/quickshell/systemmanagement/SystemManagementModel.qml
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
grep -Fq 'if (!root.settingsVisible || snapshotProcess.running) return;' "$system_model"
grep -Fq 'if (snapshotProcess.running) snapshotProcess.running = false;' "$system_model"

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

printf 'Quickshell system-management model contract: PASS\n'
