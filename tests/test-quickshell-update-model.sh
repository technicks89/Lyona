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

# The privileged step is still the one confirmed step from UPDATE-002; the
# pane never runs anything as root itself.
if grep -q 'pkexec\|sudo' "$system_pane"; then
	printf 'SystemSettingsPane must not invoke privilege escalation directly.\n' >&2
	exit 1
fi
grep -Fq 'lyona-update-root' "$lyona_update_root"
grep -Fq 'set-channel' "$lyona_update"

# Capability registration: a fourth "system" capability alongside the three
# that already existed.
grep -Fq 'emit_capability system updates' "$provider"

printf 'Quickshell update model contract: PASS\n'
