#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
shell_qml=$repo/config/quickshell/shell.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
system_pane=$repo/config/quickshell/settings/SystemSettingsPane.qml
control_center=$repo/config/quickshell/controlcenter/ControlCenterWindow.qml
update_model=$repo/config/quickshell/system/UpdateModel.qml
lyona_update_root=$repo/scripts/lyona-update-root
lyona_update=$repo/scripts/lyona-update
commands=$repo/config/quickshell/core/Commands.qml
provider=$repo/scripts/dwm-settings-provider

test "$(grep -c 'UpdateModel {' "$shell_qml")" -eq 1
grep -Fq 'updateModel: updateModel' "$shell_qml"
grep -Fq 'import qs.system' "$shell_qml"
grep -Fq 'updateModel: root.updateModel' "$settings_window"
grep -Fq 'required property var updateModel' "$settings_window"
grep -Fq 'required property var updateModel' "$control_center"

grep -Fq 'function updateCommand(action, args)' "$commands"
grep -Fq 'function versionCommand(action, args)' "$commands"

# Settings section wiring: "system" already existed (health/authorization/
# administration); this boundary adds the dedicated pane over it rather than
# introducing a new section id.
grep -Fq 'SystemSettingsPane {' "$settings_window"
grep -Fq 'root.settingsModel.selectedSectionId === "system"' "$settings_window"
grep -Fq '&& root.settingsModel.selectedSectionId !== "system"' "$settings_window"
grep -Fq 'root.updateModel.refresh()' "$settings_model"
grep -Fq 'id === "system" && root.updateModel' "$settings_model"

# openWindow/open/openOnScreen gained an optional target section, defaulting
# to the first section so every existing call site keeps its old behavior.
grep -Fq 'function openWindow(sectionId)' "$settings_model"
grep -Fq 'const targetId = sectionId || root.sections[0].id' "$settings_model"
grep -Fq 'function openOnScreen(screen, sectionId)' "$settings_model"
grep -Fq 'function openSystemUpdate()' "$control_center"
grep -Fq 'root.settingsModel.openOnScreen(targetScreen, "system")' "$control_center"

# Control Center: the update row is conditional (behind only) and navigates
# to Settings rather than triggering apply() directly -- there is no apply
# action in Control Center by design (a multi-minute privileged operation
# does not belong behind a one-click row). tests/test-quickshell-controlcenter.sh
# exercises the dwm-quickshell-controlcenter *helper script*'s own protocol,
# not this QML file, so these assertions are the only coverage for the row.
grep -Fq 'visible: root.updateModel.updateAvailable' "$control_center"
if grep -A3 'visible: root.updateModel.updateAvailable' "$control_center" | grep -q '\.apply('; then
	printf 'The Control Center update row must navigate, not apply.\n' >&2
	exit 1
fi

# Protocol parsing is all-or-nothing: a record that fails the shape check
# never partially updates provider state.
grep -Fq 'lyona-update-protocol' "$update_model"
grep -Fq 'validUpdateStates.indexOf(state) < 0' "$update_model"
grep -Fq 'root.providerState = "unavailable"' "$update_model"
grep -Fq 'lyona-update-status-protocol' "$update_model"
# #280 VM: the progress popup shows how the last action ended, which the
# channel check (root.message) must not overwrite while it is shown.
progress_window=$repo/config/quickshell/system/UpdateProgressWindow.qml
grep -Fq 'property string outcomeMessage' "$update_model"
grep -Fq 'root.outcomeMessage = outcome === "succeeded"' "$update_model"
# A successful rollback is shown though it leaves an update available (#326).
grep -Fq '|| root.updateModel.lastOperation === "rollback")' "$system_pane" || {
	printf 'Settings must show a successful rollback while an update is available.\n' >&2
	exit 1
}
# Settings shows the action's outcome the same way (its status card keeps the check text).
grep -Fq 'text: root.updateModel.outcomeMessage' "$system_pane" ||
	fail 'Settings > System does not show how the last update or rollback ended'
if grep -Fq 'updateModel.message' "$progress_window"; then
	printf 'The update progress popup must show outcomeMessage, not the check message.\n' >&2
	exit 1
fi
grep -Fq 'lyona-version-protocol' "$update_model"

# offline is informational: it reaches providerState/updateState the same
# way current/behind/ahead do, with no separate error-styled branch.
grep -Fq '"offline"' "$update_model"
if grep -A2 'state === "offline"' "$update_model" | grep -q 'danger\|failed'; then
	printf 'offline must not be styled as an error state.\n' >&2
	exit 1
fi

# consistent=false drives the error styling on the installed-version card.
grep -Fq 'root.updateModel.consistent ? "available" : "unavailable"' "$system_pane"
grep -Fq 'installedMismatchDetail' "$update_model"
grep -Fq 'installedMismatchDetail' "$system_pane"

# #334: an older release than the installed one is called one in Settings,
# before the password prompt (which cannot name the versions), and
# --allow-downgrade is passed only then, never on a routine update.
grep -Fq 'readonly property bool downgradeOffered: root.updateState === "downgrade-offered"' "$update_model" ||
	fail 'UpdateModel does not expose downgradeOffered'
grep -Fq 'if (root.downgradeOffered) args.push("--allow-downgrade");' "$update_model" ||
	fail 'UpdateModel does not limit --allow-downgrade to a downgrade offer'
if grep -Fq '"--version", version, "--allow-downgrade"' "$update_model"; then
	printf 'UpdateModel must not pass --allow-downgrade on a routine update.\n' >&2
	exit 1
fi
grep -Fq '(root.updateModel.downgradeOffered ? "Go back to " : "Update to ")' "$system_pane" ||
	fail 'Settings calls a downgrade "Update to"'
grep -Fq 'which is OLDER than the installed' "$system_pane" ||
	fail 'the Settings confirmation does not say the release is older'
grep -Fq 'root.updateModel.downgradeOffered ? "Install the older release" : "Update now"' "$system_pane" ||
	fail 'the Settings confirm button calls a downgrade "Update now"'

# Actions are inert while busy.
grep -Fq 'if (root.busy' "$update_model"

grep -Fq 'function apply(version) {' "$update_model"
grep -Fq 'function rollback(backupId) {' "$update_model"
grep -Fq 'function setChannel(value) {' "$update_model"

if grep -Eq 'repeat:[[:space:]]*true' "$update_model"; then
	printf 'UpdateModel must not use a repeating timer for the login check.\n' >&2
	exit 1
fi
grep -Fq 'loginCheckDone' "$update_model"
grep -Fq 'root.checkOnLogin' "$update_model"

# Confirmation before apply: no direct call path from a button straight into
# apply() without the pane's own confirmVersion gate.
grep -Fq 'property string confirmVersion' "$system_pane"
grep -Fq 'root.updateModel.apply(root.confirmVersion)' "$system_pane"
# Rollback asks first too (Sync Sprint 16 R16-25): the backup's button only
# chooses it, and rollback() runs from the confirmation alone.
grep -Fq 'property var confirmBackup: null' "$system_pane"
grep -Fq 'onActivated: root.confirmBackup = backupRow.modelData' "$system_pane"
[ "$(grep -c 'root.updateModel.rollback(' "$system_pane")" = 1 ] ||
	fail 'Settings calls rollback() from more than the confirmation'
grep -Fq 'root.updateModel.rollback(root.confirmBackup.id);' "$system_pane"
# Sync Sprint 16 R16-27: lyona's releases have their own heading, apart from
# the terminal's packages and Flatpak, whose package update waits for PackageKit.
grep -Fq 'SectionLabel { label: "lyona" }' "$system_pane"
grep -Fq 'label: "System packages and Flatpak"' "$system_pane"
lyona_line=$(grep -n 'SectionLabel { label: "lyona" }' "$system_pane" | cut -d: -f1)
channel_line=$(grep -n 'label: root.updateModel.channel === "preview" ? "Channel: preview"' "$system_pane" | cut -d: -f1)
terminal_line=$(grep -n 'label: "System packages and Flatpak"' "$system_pane" | cut -d: -f1)
[ "$lyona_line" -lt "$channel_line" ] && [ "$channel_line" -lt "$terminal_line" ] ||
	fail 'the lyona release card is not under the lyona heading'
grep -Fq '&& !root.updateModel.busy && !root.packageKitBusy' "$system_pane" ||
	fail 'Update packages is not disabled while PackageKit runs'

# The privileged step is still the one confirmed step from UPDATE-002; the
# pane never runs anything as root itself.
if grep -q 'pkexec\|sudo' "$system_pane"; then
	printf 'SystemSettingsPane must not invoke privilege escalation directly.\n' >&2
	exit 1
fi
# shellcheck disable=SC2016
grep -Fq 'lyona-update-root' "$lyona_update_root"
# Sync Sprint 12 S12-02: the release is hashed and extracted from one root-owned
# copy, and that copy and config.h are read with the invoking user's permissions.
# (A swap between two reads cannot be reproduced reliably in a test; these pin the
# single-copy shape. tests/test-lyona-update-root-backups.sh covers the rest.)
# shellcheck disable=SC2016 # the patterns match the literal source text
grep -Fq 'runuser -u "$invoking_user" -- cat -- "$tarball_path" >"$verified_tarball"' "$lyona_update_root"
# shellcheck disable=SC2016
grep -Fq 'actual_sha256=$(sha256sum -- "$verified_tarball"' "$lyona_update_root"
# shellcheck disable=SC2016
grep -Fq 'extract_verified_tree "$verified_tarball" "$verified_dir"' "$lyona_update_root"
# shellcheck disable=SC2016
grep -Fq 'runuser -u "$invoking_user" -- cat -- "$config_h_path" >"$verified_dir/config.h"' "$lyona_update_root"
# shellcheck disable=SC2016
if grep -Fq 'sha256sum -- "$tarball_path"' "$lyona_update_root" ||
	grep -Fq 'extract_verified_tree "$tarball_path"' "$lyona_update_root"; then
	printf 'lyona-update-root must hash and extract its own copy, never the user-owned tarball path.\n' >&2
	exit 1
fi
grep -Fq 'set-channel' "$lyona_update"

# Capability registration: a fourth "system" capability alongside the three
# that already existed.
grep -Fq 'emit_capability system updates' "$provider"

# Progress surfaces (Sync Sprint 4 S4-06). The popup and the panel indicator
# are driven by the model and exercised end to end by
# test-quickshell-update-progress-xvfb.sh; these pin the pieces it relies on.
update_progress=$repo/config/quickshell/system/UpdateProgressWindow.qml
update_log_view=$repo/config/quickshell/system/UpdateLogView.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
grep -Fq 'property bool progressShown: false' "$update_model"
grep -Fq 'property bool popupClosed: false' "$update_model"
grep -Fq 'readonly property int recentOutcomeMs: 10 * 60 * 1000' "$update_model"
grep -Fq 'readonly property int stalePendingMs: 60 * 60 * 1000' "$update_model"
grep -Fq 'root.progressShown = ageMs <= root.recentOutcomeMs;' "$update_model"
grep -Fq 'root.progressShown = ageMs <= root.stalePendingMs;' "$update_model"
grep -Fq 'readonly property string logPath: root.stateHome + "/lyona/update.log"' "$update_model"
# The log is read with tail on a fixed byte budget, never whole.
grep -Fq 'readonly property int logTailBytes: 64 * 1024' "$update_model"
grep -Fq 'command: ["tail", "-c", String(root.logTailBytes), root.logPath]' "$update_model"
grep -Fq 'UpdateProgressWindow {' "$shell_qml"
grep -Fq 'updateModel: updateModel' "$shell_qml"
grep -Fq 'required property var updateModel' "$update_progress"
grep -Fq 'required property var updateModel' "$panel"
grep -Fq 'visible: root.updateModel.progressShown' "$panel"
grep -Fq 'onClicked: root.updateModel.showProgress()' "$panel"
grep -Fq 'UpdateLogView {' "$system_pane"
grep -Fq 'UpdateLogView {' "$update_progress"
grep -Fq 'required property var model' "$update_log_view"
# lyona-update writes the log the viewer reads, and notifies on the outcome.
# shellcheck disable=SC2016 # matching the script's literal text, not expanding it
grep -Fq 'log_file=$state_home/lyona/update.log' "$lyona_update"
grep -Fq 'start_operation_log rollback' "$lyona_update"
grep -Fq 'notify_outcome' "$lyona_update"

printf 'Quickshell update model contract: PASS\n'
