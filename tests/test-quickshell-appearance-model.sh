#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
shell_qml=$repo/config/quickshell/shell.qml
# The settings target's test getters (Sync Sprint 12 S12-16).
settings_test_ipc=$repo/config/quickshell/settings/SettingsTestIpc.qml
theme=$repo/config/quickshell/core/Theme.qml
icon_text=$repo/config/quickshell/core/IconText.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
commands=$repo/config/quickshell/core/Commands.qml
model=$repo/config/quickshell/appearance/AppearanceModel.qml
# Split per helper (#282), as PicomModel.qml was.
wallpaper_model=$repo/config/quickshell/appearance/WallpaperModel.qml
font_model=$repo/config/quickshell/appearance/FontModel.qml
watched_process=$repo/config/quickshell/core/WatchedProcess.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
pane=$repo/config/quickshell/settings/AppearanceSettingsPane.qml
display_pane=$repo/config/quickshell/settings/DisplaySettingsPane.qml
input_pane=$repo/config/quickshell/settings/InputSettingsPane.qml
network_pane=$repo/config/quickshell/settings/NetworkSettingsPane.qml

"$repo/scripts/quickshell-qmllint" --root "$repo/config/quickshell"

test "$(grep -c 'AppearanceModel {' "$shell_qml")" -eq 1
grep -Fq 'appearanceModel: appearanceModel' "$shell_qml"
grep -Fq 'root.appearanceModel.openSettings()' "$settings_model"
grep -Fq 'root.appearanceModel.closeSettings()' "$settings_model"
test "$(grep -Fc 'root.appearanceModel.closeSettings()' "$settings_model")" -eq 2
grep -Fq 'AppearanceSettingsPane {' "$settings_window"
grep -Fq 'root.settingsModel.selectedSectionId === "appearance"' "$settings_window"
grep -Fq 'capability.id !== "themes"' "$settings_window"

grep -Fq 'function settingsAppearanceCommand(action, args)' "$commands"
grep -Fq 'function settingsFontCommand(action, args)' "$commands"
grep -Fq 'function settingsWallpaperCommand(action, args)' "$commands"
grep -Fq 'function settingsThemeCommand(action, args)' "$commands"
grep -Fq 'function booleanStatusCommand(command)' "$commands"
grep -Fq 'appearance-protocol' "$model"
grep -Fq 'appearance-action-protocol' "$model"
grep -Fq 'appearance-inventory-protocol' "$model"
grep -Fq 'value === "@legacy-colors" || root.validThemeName(value)' "$model"
grep -Fq 'root.validProviderActiveLabel(fields[1])' "$model"
grep -Fq 'fields[3] === "invalid"' "$model"
grep -Fq '"dark": fields[4] !== "false"' "$model"
grep -Fq 'value === "selected" || value === "recovery" || value === "unresolved"' "$model"
grep -Fq 'fields[1] === "none" && fields[2] === "unavailable"' "$model"
grep -Fq '"mutable": root.validThemeName(fields[1])' "$model"
grep -Fq 'Commands.checkedCommand(Commands.settingsThemeCommand(action, args))' "$model"
grep -Fq 'Commands.settingsThemeCommand("mutation-ready", [])' "$model"
grep -Fq 'property bool mutationReadinessPending: false' "$model"
grep -Fq 'root.mutationReady = false;' "$model"
grep -Fq 'QueuedRun.startOrQueue(readinessProcess, root, "mutationReadinessPending", actionProcess.running);' "$model"
grep -Fq 'if (!running && root.mutationReadinessPending && !actionProcess.running) {' "$model"
grep -Fq 'onStreamFinished: root.mutationReady = !root.mutationReadinessPending' "$model"
for mutation_function in startPreview applyTheme resetTheme; do
	sed -n "/function $mutation_function(/,/^    }/p" "$model" |
		grep -Fq 'root.mutationReadinessPending'
done
grep -Fq 'Theme.applyAppearanceColors(colors, darkMode)' "$model"
grep -Fq 'watchChanges: true' "$model"
test "$(cat "$model" "$font_model" | grep -Fc 'watchChanges: true')" -eq 5
grep -Fq 'model: root.integrationWatchPaths' "$model"
grep -Fq 'Commands.settingsAppearanceCommand("inventory", [])' "$model"
if grep -Fq 'Commands.checkedCommand(Commands.settingsAppearanceCommand("inventory", []))' \
	"$model"; then
	printf 'Appearance inventory remained behind the orphan-prone checked-command wrapper\n' >&2
	exit 1
fi
grep -Fq 'Commands.settingsAppearanceCommand("watch-inventory", [])' "$model"
grep -Fq 'PicomModel { id: picomModel; active: root.settingsVisible }' "$model"
grep -Fq 'function startInventoryWatcher(restartIfRunning)' "$model"
sed -n '/function startInventoryWatcher(restartIfRunning)/,/^    }/p' "$model" |
	grep -Fq 'if (!root.settingsVisible) return;'
grep -Fq 'root.startInventoryWatcher(true);' "$model"
grep -Fq 'if (restartIfRunning === true) root.inventoryWatchRestartPending = true;' "$model"
grep -Fq 'root.inventoryWatchSawEvent = false' "$model"
grep -Fq 'if (!root.inventoryWatchReady && !root.inventoryWatchFailed' "$model"
grep -Fq 'root.inventoryPendingAllowUnwatched = root.inventoryPendingAllowUnwatched' "$model"
grep -Fq 'root.refreshInventory(root.inventoryPendingAllowUnwatched)' "$model"
grep -Fq 'Qt.callLater(root.retryInventoryRefresh)' "$model"
grep -Fq 'if (line === "ready\tinventory")' "$model"
grep -Fq 'root.refreshInventory(true)' "$model"
grep -Fq 'root.inventoryWatchFailed = true' "$model"
grep -Fq 'root.inventoryWatchState = "unavailable"' "$model"
grep -Fq '&& !root.inventoryWatchFailed' "$model"
# The compositor is configuration-backed (PicomModel watches the Picom
# configuration itself), so the model no longer runs a compositor process
# watcher of its own.
grep -Fq 'picomModel.refresh();' "$model"
# The window corner radius slider (Sync Sprint 11 S11-09): the helper's command,
# the model's setter, and a slider that covers the helper's range.
grep -Fq 'root.mutate("set-corner-radius", [String(radius)], revision);' "$repo/config/quickshell/appearance/PicomModel.qml"
grep -Fq 'objectName: "picomCornerRadius"' "$repo/config/quickshell/settings/PicomSettingsPane.qml"
grep -Fq 'from: 0; to: 32; stepSize: 1' "$repo/config/quickshell/settings/PicomSettingsPane.qml"
grep -Fq 'CORNER_RADIUS_MAX = 32' "$repo/scripts/dwm-settings-picom"
if grep -Eq 'compositorWatch|watch-compositor' "$model"; then
	printf 'AppearanceModel still carries the old compositor process watcher\n' >&2
	exit 1
fi
grep -Fq 'if (!root.settingsVisible) return;' "$model"
grep -Fq 'inventoryWatch.stop();' "$model"
# #279: the inventory watch is a WatchedProcess that never restarts itself.
sed -n '/id: inventoryWatch$/,/^    }/p' "$model" | grep -Fq 'restartPolicy: "never"'
# Upstream f4f477c hardens their appearance watcher so a helper that dies
# while the surface is open gets restarted, and a burst of change lines
# coalesces into one refresh. Lyona already has both properties in the
# shared WatchedProcess component the other models' watchers use --
# verify that instead of porting a second, inline copy.
# Restarted only while active, after a delay that backs off (Sync Sprint 16 R16-36).
assert_contains "$watched_process" 'if (!root.active || root.runGeneration !== root.generation)'
assert_contains "$watched_process" 'restartTimer.interval = root.restartDelay;'
assert_contains "$watched_process" 'restartTimer.restart()'
assert_contains "$watched_process" 'if (root.active && !watchProcess.running && root.restartGeneration === root.generation)'
assert_contains "$watched_process" 'onTriggered: root.settled()'
grep -Fq 'root.inventoryCandidates = candidates' "$model"
grep -Fq 'candidate.id === "wallpaper"' "$wallpaper_model"
grep -Fq 'candidate.id === "font"' "$font_model"
grep -Fq 'Commands.checkedCommand(Commands.settingsFontCommand("status", []))' "$font_model"
grep -Fq 'Commands.settingsFontCommand("mutation-ready", [])' "$font_model"
grep -Fq 'Commands.checkedCommand(Commands.settingsFontCommand(action, args))' "$font_model"
grep -Fq 'function preview(family, scale)' "$font_model"
grep -Fq 'function apply(family, scale)' "$font_model"
grep -Fq 'function reset()' "$font_model"
grep -Fq 'Theme.applyFontPreferences(root.family, root.scale)' "$font_model"
grep -Fq 'root.statusRetryAttempts = 0;' "$font_model"
grep -Fq 'root.statusRetryAttempts < 3' "$font_model"
grep -Fq 'statusRetryTimer.restart();' "$font_model"
grep -Fq 'id: statusRetryTimer' "$font_model"
grep -Fq 'root.mutationReady = false;' "$font_model"
test "$(grep -Fc '!root.mutationReady || readinessProcess.running' "$font_model")" -eq 3
grep -Fq 'root.previewToken = root.actionToken;' "$font_model"
grep -Fq 'root.previewRemaining = 30;' "$font_model"
finish_font_action=$(sed -n '/function finishAction()/,/^    }/p' "$font_model")
printf '%s\n' "$finish_font_action" |
	grep -Fq 'root.actionKind === "keep" || root.actionKind === "revert"'
printf '%s\n' "$finish_font_action" | grep -Fq '|| root.actionKind === "abandon"'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.previewState = "none";'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.previewToken = "";'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.previewFamily = "";'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.previewScale = 1.0;'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.previewRemaining = 0;'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.previewDetail = "";'
if sed -n '/function clearStatus(detail)/,/^    }/p' "$font_model" |
	grep -Fq 'Theme.applyFontPreferences'; then
	printf 'Transient font status failure still repaints the shell with fallback preferences\n' >&2
	exit 1
fi
test "$(grep -Fc 'fontModel.refreshStatus();' "$model")" -eq 3
# The countdowns are PreviewCountdown components (Sync Sprint 12 S12-14).
grep -Fq 'active: root.appearance.settingsVisible && root.previewState === "active"' "$font_model"
grep -Fq 'property alias previewRemaining: countdown.remaining' "$font_model"
grep -Fq 'Commands.settingsWallpaperCommand("status", ["--read-only"])' "$wallpaper_model"
if grep -Fq 'Commands.checkedCommand(Commands.settingsWallpaperCommand("status"' "$wallpaper_model"; then
	printf 'Wallpaper status remained behind the orphan-prone checked-command wrapper\n' >&2
	exit 1
fi
grep -Fq 'Commands.settingsWallpaperCommand(action === "reconcile" ? "status" : action, args)' "$wallpaper_model"
grep -Fq 'function preview(path, fit)' "$wallpaper_model"
grep -Fq 'function reset()' "$wallpaper_model"
grep -Fq 'function reconcilePreview()' "$wallpaper_model"
grep -Fq 'function clearStatus(detail)' "$wallpaper_model"
grep -Fq 'root.path = "";' "$wallpaper_model"
grep -Fq 'const preservePreview = (root.previewState === "active"' "$wallpaper_model"
grep -Fq '|| root.previewState === "failed")' "$wallpaper_model"
grep -Fq '&& root.previewToken.length > 0;' "$wallpaper_model"
grep -Fq 'if (!preservePreview) {' "$wallpaper_model"
grep -Fq 'Installed wallpaper helper does not report reset readiness' "$wallpaper_model"
grep -Fq 'root.clearStatus("Wallpaper helper returned an unsupported response")' "$wallpaper_model"
grep -Fq 'provider = { "state": fields[2], "detail": fields[4] }' "$model"
grep -Fq 'root.providerDetail = provider.detail' "$wallpaper_model"
grep -Fq 'root.mutationDetail = mutation.detail' "$wallpaper_model"
grep -Fq 'root.resetReady = reset.state === "available"' "$wallpaper_model"
grep -Fq 'QueuedRun.startOrQueue(statusProcess, root, "statusPending",' "$wallpaper_model"
grep -Fq '|| actionProcess.running || root.appearance.inventoryRunning' "$wallpaper_model"
grep -Fq 'readonly property bool reading: statusProcess.running || actionProcess.running' "$wallpaper_model"
grep -Fq 'if (wallpaperModel.reading) {' "$model"
grep -Fq 'if (!running && root.appearance.settingsVisible && root.appearance.inventoryPending) {' "$wallpaper_model"
grep -Fq '} else if (!running && root.appearance.settingsVisible && root.statusPending) {' "$wallpaper_model"
grep -Fq '} else if (!running && wallpaperModel.statusPending && root.settingsVisible) {' "$model"
grep -Fq 'readonly property bool statusBusy: readinessProcess.running' "$wallpaper_model"
grep -Fq 'Commands.settingsWallpaperCommand("reset-ready", [])' "$wallpaper_model"
grep -Fq 'readinessProcess.running || actionProcess.running || root.appearance.inventoryRunning,' "$wallpaper_model"
if grep -Fq '|| root.appearance.inventoryWatchStarting) {' "$wallpaper_model"; then
	printf 'Wallpaper status discovery is still gated on inventory watcher startup\n' >&2
	exit 1
fi
grep -Fq '|| readinessProcess.running || statusProcess.running' "$wallpaper_model"
grep -Fq 'root.previewState = "active";' "$wallpaper_model"
test "$(grep -Fc 'root.previewState = "active";' "$wallpaper_model")" -eq 1
grep -Fq 'root.previewToken = root.actionToken;' "$wallpaper_model"
grep -Fq 'action === "reconcile" ? "status" : action' "$wallpaper_model"
grep -Fq 'root.parseStatus(text);' "$wallpaper_model"
grep -Fq 'Wallpaper preview expired and reverted automatically' "$wallpaper_model"
grep -Fq 'const previewDecision = root.previewState === "active"' "$wallpaper_model"
grep -Fq 'if (previewDecision && (root.appearance.inventoryRunning || root.appearance.inventoryPending' "$wallpaper_model"
grep -Fq '|| root.statusPending' "$wallpaper_model"
grep -Fq '|| (!previewDecision && root.appearance.inventoryWatchStarting' "$wallpaper_model"
if grep -Fq '&& !root.statusPending' "$wallpaper_model"; then
	printf 'Queued status work still blocks wallpaper inventory preemption\n' >&2
	exit 1
fi
grep -Fq 'if (inventoryProcess.running) inventoryProcess.running = false;' "$model"
grep -Fq 'root.statusPending = false;' "$wallpaper_model"
if grep -Fq 'actionPending' "$wallpaper_model"; then
	printf 'Wallpaper preview decisions still use a pane-scoped pending queue\n' >&2
	exit 1
fi
grep -Fq '&& !root.inventoryWatchFailed) {' "$model"
grep -Fq 'root.inventoryWatchRestartPending = false;' "$model"
grep -Fq 'if (root.inventoryWatchSawEvent) inventoryWatchRestartTimer.restart();' "$model"
grep -Fq 'if (!previewWasActive && preview.state === "active") {' "$wallpaper_model"
grep -Fq 'root.previewState = "none";' "$wallpaper_model"
grep -Fq 'Qt.callLater(root.refreshStatus)' "$wallpaper_model"
grep -Fq 'active: root.appearance.settingsVisible && root.previewState === "active"' "$wallpaper_model"
grep -Fq 'property alias previewRemaining: countdown.remaining' "$wallpaper_model"
if grep -Fq 'onTriggered: root.refreshStatus()' "$wallpaper_model"; then
	printf 'Wallpaper preview countdown still polls the full status helper every second\n' >&2
	exit 1
fi
grep -Fq 'model: root.settingsVisible ? root.statusWatchPaths : []' "$model"
grep -Fq 'watchChanges: root.settingsVisible' "$model"
grep -Fq 'onTriggered: if (root.settingsVisible) root.refreshAll()' "$model"
test "$(grep -Fc 'onTriggered: if (root.settingsVisible) root.refreshAll()' "$model")" -eq 2
grep -Fq 'active: root.previewState === "active"' "$model"
grep -Fq 'property alias previewRemaining: themeCountdown.remaining' "$model"
grep -Fq 'previewZeroRetryTimer.restart()' "$model"
grep -Fq 'if (!root.previewStatusParsed) root.previewZeroRetryAttempts++' "$model"
grep -Fq 'if (root.previewStatusManualOnly && force !== true) return;' "$model"
grep -Fq 'root.previewStatusManualOnly = true;' "$model"
grep -Fq 'root.previewStatusManualOnly = false;' "$model"
grep -Fq 'root.appearanceModel.refreshAll(true)' "$pane"
# Capability discovery requested while a provider run is in flight is
# coalesced into one follow-up run, and a discovery that is refreshing reports
# itself as such rather than as a stale answer (#191).
grep -Fq 'property bool capabilityRefreshPending: false' "$settings_model"
grep -Fq 'function refreshCapabilities()' "$settings_model"
grep -Fq 'QueuedRun.startOrQueue(providerProcess, root, "capabilityRefreshPending"' "$settings_model"
grep -Fq 'if (root.discoveryState !== "ready" || root.capabilityRefreshPending)' "$settings_model"
grep -Fq '"detail": "Capability discovery is still refreshing"' "$settings_model"
grep -Fq 'function capabilityById(id)' "$settings_model"
grep -Fq 'function appearanceRefresh(): void' "$settings_test_ipc"
grep -Fq 'root.appearanceModel.refreshAll(true);' "$settings_test_ipc"
grep -Fq 'function capabilityStatus(capabilityId: string): string' "$settings_test_ipc"
# The follow-up run is queued only if the provider is still idle when the
# deferred call fires. The pending flag is deliberately NOT cleared here (S5-01):
# it clears in refreshCapabilities() once the next run has started, so Settings
# never sees a frame with a queued refresh and nothing reporting it.
awk '
	/id: providerProcess/ { in_provider = 1 }
	in_provider && /onRunningChanged: \{/ {
		in_handler = 1
		depth = 0
	}
	in_handler {
		line = $0
		opens = gsub(/\{/, "", line)
		closes = gsub(/\}/, "", line)
		depth += opens - closes
		if (/root.capabilityRefreshPending = false;/) cleared = NR
		if (/Qt.callLater\(function\(\) \{/ && !deferred) deferred = NR
		if (/if \(!providerProcess.running\) root.refreshCapabilities\(\);/ && !guarded) guarded = NR
		if (depth == 0) {
			in_handler = 0
			verified = !cleared && deferred && guarded && deferred < guarded
		}
	}
	END {
		exit !verified
	}
' "$settings_model"
refresh_capabilities=$(sed -n '/function refreshCapabilities()/,/^    }/p' "$settings_model")
printf '%s\n' "$refresh_capabilities" |
	grep -Fq 'QueuedRun.startOrQueue(providerProcess, root, "capabilityRefreshPending"'
finish_action=$(sed -n '/function finishAction()/,/^    }/p' "$model")
test "$(printf '%s\n' "$finish_action" | grep -Fc 'root.previewStatusManualOnly = false;')" -eq 2
grep -Fq 'root.snapshotParsed = false' "$model"
grep -Fq 'root.snapshotRunGeneration === root.snapshotGeneration' "$model"
grep -Fq '&& !root.snapshotParsed' "$model"
grep -Fq 'const error = snapshotError.text.trim()' "$model"
grep -Fq 'Appearance provider failed before returning a valid snapshot' "$model"
grep -Fq 'readonly property string configHome: Xdg.configHome' "$model"
grep -Fq 'readonly property string dataHome: Xdg.dataHome' "$model"
grep -Fq 'readonly property string stateHome: Xdg.stateHome' "$model"
grep -Fq 'appliedTheme === null || !appliedTheme.valid' "$model"
grep -Fq 'if (root.activeState === "recovery") return "partial"' "$model"
grep -Fq 'if (wallpaperModel.providerState !== "available"' "$model"
grep -Fq '|| wallpaperModel.selectionState !== "available") return "partial"' "$model"
grep -Fq 'root.colorsComplete(colors)' "$model"
grep -Fq 'root.integrationsComplete(integrations)' "$model"
grep -Fq 'Qt.callLater(root.refreshSnapshot)' "$model"
grep -Fq 'onTriggered: root.refreshAll()' "$model"
grep -Fq 'const wasActive = root.previewState === "active"' "$model"
grep -Fq 'Theme preview completed outside Settings' "$model"

grep -Fq 'function applyAppearanceColors(colors, darkMode)' "$theme"
grep -Fq 'function applyFontPreferences(family, scale)' "$theme"
grep -Fq 'readonly property string iconFontFamily: "MesloLGS Nerd Font Mono"' "$theme"
grep -Fq 'readonly property int panelIconFontSize: scaledFontSize(14, 8)' "$theme"
grep -Fq 'font.pixelSize: Theme.panelIconFontSize' "$icon_text"
test "$(grep -Fc 'Theme.scaledFontSize(14 *' "$panel")" -eq 5
grep -Fq 'scaledFontSize(13, 10)' "$theme"
test "$(grep -Ec 'font\.pixelSize: Theme\.(bodyFontSize|inputFontSize)' "$display_pane")" -eq 14
test "$(grep -Ec 'font\.pixelSize: Theme\.(bodyFontSize|inputFontSize)' "$input_pane")" -eq 5
grep -Fq 'font.pixelSize: Theme.inputFontSize' "$network_pane"
grep -Fq 'passwordInput.implicitHeight + 2 * Theme.spacingSm' "$network_pane"
grep -Fq 'readonly property real scaleFactor:' "$display_pane"
grep -Fq 'font.pixelSize: Math.max(Theme.dp(10), Math.min(Theme.dp(32), monitorTile.height / 3))' "$display_pane"
grep -Fq 'Math.max(88, outputContent.implicitHeight + 12)' "$display_pane"
grep -Fq 'profileNameInput.implicitHeight + 12' "$display_pane"
grep -Fq 'confirmationRow.implicitHeight + 16' "$display_pane"
grep -Fq 'settingInput.implicitHeight + 14' "$input_pane"
# Phase 7: XKB input accessibility (done -- see CHANGELOG.md).
grep -Fq 'deviceCard.modelData.kind === "accessibility"' "$input_pane"
grep -Fq 'accessibleDescription: settingRow.modelData.label + ". Starts a timed preview."' "$input_pane"
grep -Fq 'if (root.settingsModel.previewKind !== "input") return;' "$settings_test_ipc"
grep -Fq 'if (root.settingsModel.previewOperationLocked) return;' "$settings_test_ipc"
if grep -Eq 'FileView|themes\.toml|function applyThemes' "$theme"; then
	printf 'Theme.qml still owns theme file parsing instead of the shared AppearanceModel\n' >&2
	exit 1
fi

grep -Fq 'Preview for 30 seconds' "$pane"
grep -Fq 'Preview wallpaper for 30 seconds' "$pane"
grep -Fq 'label: "Configured wallpaper"' "$pane"
grep -Fq 'label: "Wallpaper apply and preview unavailable"' "$pane"
grep -Fq 'root.appearanceModel.wallpaper.resetReady ? "Reset available" : "Protected"' "$pane"
grep -Fq 'readonly property bool wallpaperControlsBusy: root.appearanceBusy' "$pane"
grep -Fq '|| root.appearanceModel.wallpaper.statusBusy' "$pane"
grep -Fq 'readonly property bool wallpaperPreviewControlsBusy: root.appearanceBusy' "$pane"
grep -Fq '|| root.appearanceModel.wallpaper.previewActionBusy' "$pane"
grep -Fq 'enabled: !root.wallpaperPreviewControlsBusy' "$pane"
grep -Fq '? !root.wallpaperPreviewControlsBusy : !root.wallpaperControlsBusy' "$pane"
grep -Fq 'label: "Reset wallpaper"' "$pane"
grep -Fq 'label: "Managed shell font"' "$pane"
grep -Fq 'Preview font for 30 seconds' "$pane"
grep -Fq 'onActivated: root.appearanceModel.font.keepPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.font.revertPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.font.abandonPreview()' "$pane"
grep -Fq 'label: "Reset font"' "$pane"
grep -Fq 'label: "Repair wallpaper state"' "$pane"
test "$(grep -Fc 'root.appearanceModel.wallpaper.previewToken.length > 0' "$pane")" -eq 2
grep -Fq 'root.appearanceModel.wallpaper.resetReady' "$pane"
grep -Fq 'detail: root.appearanceModel.wallpaper.mutationDetail' "$pane"
grep -Fq 'else root.selectedWallpaperPath = "";' "$pane"
grep -Fq 'function wallpaperSelectionAvailable()' "$pane"
test "$(grep -Fc '&& root.wallpaperSelectionAvailable() && !root.wallpaperControlsBusy' "$pane")" -eq 2
grep -Fq 'function wallpaperEmptyDetail()' "$pane"
grep -Fq 'return root.appearanceModel.inventoryProviderDetail;' "$pane"
grep -Fq 'selection.detail === "Wallpaper candidate discovery did not complete"' "$pane"
grep -Fq 'root.appearanceModel.inventoryWatchDetail' "$pane"
grep -Fq '? " / Saved" : "")' "$pane"
grep -Fq 'detail: root.appearanceModel.wallpaper.providerDetail' "$pane"
grep -Fq 'root.appearanceModel.wallpaper.candidates' "$pane"
grep -Fq 'Component.onCompleted: {' "$pane"
grep -Fq 'root.ensureWallpaperSelection();' "$pane"
grep -Fq 'preferred = root.appearanceModel.resolvedTheme' "$pane"
grep -Fq 'label: "Additional capabilities"' "$pane"
grep -Fq 'model: root.additionalCapabilities' "$pane"
# accessibility-contrast/accessibility-reduced-motion have dedicated controls
# now (Phase 6, done -- see CHANGELOG.md); the generic list must not repeat them.
grep -Fq 'capability.id !== "accessibility-contrast"' "$pane"
grep -Fq 'capability.id !== "accessibility-reduced-motion"' "$pane"
grep -Fq 'onActivated: root.appearanceModel.keepPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.revertPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.abandonPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.recover()' "$pane"
grep -Fq 'Selected appearance is only partially applied' "$pane"
grep -Fq 'root.appearanceModel.integrations' "$pane"
grep -Fq 'root.appearanceModel.errors' "$pane"
grep -Fq 'function appearanceIntegrationState(integrationId: string): string' "$settings_test_ipc"
grep -Fq 'function appearanceWallpaperReconcile(): void' "$settings_test_ipc"
grep -Fq 'function appearanceWallpaperStatusBusy(): bool' "$settings_test_ipc"
grep -Fq 'function appearanceFontFamily(): string' "$settings_test_ipc"
grep -Fq 'function appearanceFontScale(): string' "$settings_test_ipc"
grep -Fq 'function appearanceFontPreviewState(): string' "$settings_test_ipc"
test "$(grep -Fc 'root.selectedTheme.valid && root.selectedTheme.mutable' "$pane")" -eq 2

# Cursor, icon, GTK and Qt overrides, in their own model (#282), as Picom's.
toolkit_model=$repo/config/quickshell/appearance/ToolkitModel.qml
grep -Fq 'ToolkitModel { id: toolkitModel; appearance: root }' "$model"
grep -Fq 'function settingsToolkitCommand(action, args)' "$commands"
grep -Fq 'toolkit-action-protocol' "$toolkit_model"

# A status that stopped early would render as a pane missing some
# capabilities, which reads as those capabilities being unsupported rather
# than as a truncated read. Both guards have to stay.
grep -Fq 'fields[0] === "complete"' "$toolkit_model"
grep -Fq 'root.clearStatus("Toolkit helper returned an incomplete response")' "$toolkit_model"

# The saved option and the value it resolves to are separate columns, so the
# selection record is six fields rather than five.
grep -Fq 'fields[0] === "selection" && fields.length === 6' "$toolkit_model"
grep -Fq 'fields[0] === "candidate" && fields.length === 3' "$toolkit_model"

# Settings must only offer what the helper says is installed, or it will
# offer a choice that is then refused.
grep -Fq 'return root.candidatesFor(capability).indexOf(value) !== -1' "$toolkit_model"

for toolkit_function in preview apply reset keepPreview revertPreview abandonPreview; do
	grep -Fq "function $toolkit_function(" "$toolkit_model" || {
		printf 'Toolkit model is missing %s\n' "$toolkit_function" >&2
		exit 1
	}
	grep -Fq "root.appearanceModel.toolkit.$toolkit_function(" "$pane" || {
		printf 'Appearance pane never calls %s\n' "$toolkit_function" >&2
		exit 1
	}
done

# A pending choice must survive the status refreshes that arrive while the
# pane is open, so the pane keeps its own selection beside the saved one.
grep -Fq 'function syncToolkitSelection()' "$pane"
grep -Fq 'function toolkitDirty(capability)' "$pane"

# The pane draws this capability itself; leaving it in the generic list would
# show it twice.
grep -Fq 'capability.id !== "toolkit"' "$settings_window"

if grep -ERq 'Quickshell\.(Wayland|Hyprland)|WlrLayershell|hyprctl|uwsm-app|wl-copy|wl-paste' \
	"$model" "$pane"; then
	printf 'Appearance model introduced a forbidden Wayland or Omarchy dependency\n' >&2
	exit 1
fi

printf 'Quickshell shared appearance model contract: PASS\n'
