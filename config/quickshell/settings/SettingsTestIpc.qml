// The settings IPC target's getters and drivers for the Xvfb tests (Sync
// Sprint 12 S12-16). shell.qml creates this only when LYONA_SHELL_TEST_IPC=1,
// so a normal session has no settingsTest target; the product's commands stay
// on the settings target in shell.qml.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// A Scope holds the objects: an IpcHandler offers its own properties over IPC,
// and these cannot cross it.
Scope {
    id: root

    required property var settingsModel
    required property var appearanceModel
    required property var systemManagementModel
    required property var updateModel
    required property var autostartModel
    required property var powerModel
    required property var defaultsModel
    required property var controlsModel
    required property var panelSettingsModel
    required property var networkModel
    required property var bluetoothModel
    required property var clock

    IpcHandler {
        target: "settingsTest"

        function currentSection(): string {
            return root.settingsModel.selectedSectionId;
        }

        function displayCount(): int {
            return root.settingsModel.displayOutputs.length;
        }

        function displayStatus(): string {
            return root.settingsModel.displayState;
        }

        function displayDpi(): int {
            return root.settingsModel.displayDpi;
        }

        function displayDpiSource(): string {
            return root.settingsModel.displayDpiSource;
        }

        // Pure reads over Theme's own state, distinct from displayDpi() above
        // (which reads the helper-reported value via settingsModel). These
        // prove the DPI hot-reload path actually reached Theme.uiScale, not
        // just that the helper discovered a DPI. See 4783fe1:docs/SYNC-P0-DPI-GATE.md.
        function themeDisplayDpi(): int {
            return Theme.displayDpi;
        }

        function themeUiScale(): string {
            return Theme.uiScale.toFixed(4);
        }

        function themeColor(role: string): string {
            return String(Theme[role] || "");
        }

        function themeHighContrast(): bool {
            return Theme.highContrast;
        }

        function inputCount(): int {
            return root.settingsModel.inputDevices.length;
        }

        function inputStatus(): string {
            return root.settingsModel.inputState;
        }

        function inputAccessibilityValue(settingId: string): string {
            const setting = root.settingsModel.inputSettings.find(function(item) {
                return item.device === "accessx" && item.id === settingId;
            });
            return setting ? setting.value : "";
        }

        function inputAccessibilityPreview(settingId: string, enabled: bool): void {
            root.settingsModel.previewInput("accessx", settingId, enabled ? "1" : "0");
        }

        function inputPreviewState(): string {
            return root.settingsModel.previewKind;
        }

        function inputPreviewAction(action: string): void {
            if (root.settingsModel.previewKind !== "input") return;
            if (action === "keep") root.settingsModel.keepPreview();
            else if (action === "revert") root.settingsModel.revertPreview();
        }

        function inputAccessibilityReset(settingId: string): void {
            if (root.settingsModel.previewOperationLocked) return;
            root.settingsModel.resetInput("accessx", settingId);
        }

        function networkProviderStatus(): string {
            return root.networkModel.providerState;
        }

        function networkDeviceCount(): int {
            return root.networkModel.devices.length;
        }

        function bluetoothProviderStatus(): string {
            return root.bluetoothModel.providerState;
        }

        function bluetoothDeviceCount(): int {
            return root.bluetoothModel.devices.length;
        }

        function audioProviderStatus(): string {
            return root.controlsModel.audioProviderState;
        }

        function audioSourceKind(): string {
            return root.controlsModel.audioSourceKind;
        }

        function audioOutputCount(): int {
            return root.controlsModel.outputDevices.length;
        }

        function audioInputCount(): int {
            return root.controlsModel.inputDevices.length;
        }

        function audioStreamCount(): int {
            return root.controlsModel.audioStreams.length;
        }

        function powerProviderStatus(): string {
            return root.powerModel.providerState;
        }

        function powerBatteryAvailable(): bool {
            return root.powerModel.batteryAvailable;
        }

        function powerBatteryPercent(): int {
            return root.powerModel.batteryPercent;
        }

        function powerActiveProfile(): string {
            return root.powerModel.activeProfile;
        }

        function powerDpmsStatus(): string {
            return root.powerModel.dpmsState;
        }

        function powerDpmsEnabled(): bool {
            return root.powerModel.dpmsEnabled;
        }

        function powerDpmsTimeout(): int {
            return root.powerModel.dpmsTimeout;
        }

        function powerLockStatus(): string {
            return root.powerModel.lockState;
        }

        function powerLockEnabled(): bool {
            return root.powerModel.lockEnabled;
        }

        function powerLockTimeout(): int {
            return root.powerModel.lockTimeout;
        }

        function powerBusy(): bool {
            return root.powerModel.busy;
        }

        function powerMessage(): string {
            return root.powerModel.messageFor("settings");
        }

        function powerSetDpms(enabled: bool): void {
            root.powerModel.setDpms(enabled, "settings");
        }

        function defaultsProviderStatus(): string {
            return root.defaultsModel.providerState;
        }

        function defaultsRoleCount(): int {
            return root.defaultsModel.roles.length;
        }

        function defaultsMessage(): string {
            return root.defaultsModel.messageFor("settings");
        }

        function defaultsBusy(): bool {
            return root.defaultsModel.busy;
        }

        function defaultsRoleDesktopId(role: string): string {
            const match = root.defaultsModel.roles.find(function(item) { return item.id === role; });
            return match ? match.desktopId : "";
        }

        function defaultsSetRole(role: string, desktopId: string): void {
            root.defaultsModel.setRole(role, desktopId, "settings");
        }

        function defaultsResetRole(role: string): void {
            root.defaultsModel.resetRole(role, "settings");
        }

        function autostartProviderStatus(): string {
            return root.autostartModel.providerState;
        }

        function autostartEntryCount(): int {
            return root.autostartModel.entries.length;
        }

        function autostartMessage(): string {
            return root.autostartModel.messageFor("settings");
        }

        function autostartBusy(): bool {
            return root.autostartModel.busy;
        }

        function autostartEntryState(desktopId: string): string {
            const entry = root.autostartModel.entries.find(function(item) { return item.id === desktopId; });
            return entry ? entry.state : "";
        }

        function autostartEntryName(desktopId: string): string {
            const entry = root.autostartModel.entries.find(function(item) { return item.id === desktopId; });
            return entry ? entry.name : "";
        }

        function autostartEntryOrigin(desktopId: string): string {
            const entry = root.autostartModel.entries.find(function(item) { return item.id === desktopId; });
            return entry ? entry.origin : "";
        }

        function appearanceProviderStatus(): string {
            return root.appearanceModel.providerState;
        }

        function appearanceProviderDetail(): string {
            return root.appearanceModel.providerDetail;
        }

        function appearanceApplicationState(): string {
            return root.appearanceModel.applicationState;
        }

        function appearanceInventoryState(capability: string): string {
            const selection = root.appearanceModel.inventorySelections[capability];
            return selection ? selection.state : "";
        }

        function appearanceInventoryProviderState(): string {
            return root.appearanceModel.inventoryProviderState;
        }

        function appearanceInventoryWatchState(): string {
            return root.appearanceModel.inventoryWatchState;
        }

        function appearanceInventoryCandidateState(capability: string, token: string): string {
            const match = root.appearanceModel.inventoryCandidates.find(function(item) {
                return item.id === capability && item.token === token;
            });
            return match ? match.state : "";
        }

        function appearanceIntegrationState(integrationId: string): string {
            const match = root.appearanceModel.integrations.find(function(item) { return item.id === integrationId; });
            return match ? match.state : "";
        }

        function appearanceIntegrationDetail(integrationId: string): string {
            const match = root.appearanceModel.integrations.find(function(item) { return item.id === integrationId; });
            return match ? match.detail : "";
        }

        function appearanceErrorCode(scope: string): string {
            const match = root.appearanceModel.errors.find(function(item) { return item.scope === scope; });
            return match ? match.code : "";
        }

        function appearanceActiveTheme(): string {
            return root.appearanceModel.activeTheme;
        }

        function appearanceThemeCount(): int {
            return root.appearanceModel.themes.length;
        }

        function appearanceMutationReady(): bool {
            return root.appearanceModel.mutationReady;
        }

        function appearanceRefresh(): void {
            root.appearanceModel.refreshAll(true);
        }

        function capabilityStatus(capabilityId: string): string {
            return root.settingsModel.capabilityById(capabilityId).status;
        }

        function appearancePreviewState(): string {
            return root.appearanceModel.previewState;
        }

        function appearancePreviewRemaining(): int {
            return root.appearanceModel.previewRemaining;
        }

        function appearanceWallpaperState(): string {
            return root.appearanceModel.wallpaperState;
        }

        function appearanceWallpaperProviderState(): string {
            return root.appearanceModel.wallpaperProviderState;
        }

        function appearanceWallpaperProviderDetail(): string {
            return root.appearanceModel.wallpaperProviderDetail;
        }

        function appearanceWallpaperDetail(): string {
            return root.appearanceModel.wallpaperDetail;
        }

        function appearanceWallpaperMutationState(): string {
            return root.appearanceModel.wallpaperMutationState;
        }

        function appearanceWallpaperResetState(): string {
            return root.appearanceModel.wallpaperResetState;
        }

        function appearanceWallpaperResetDetail(): string {
            return root.appearanceModel.wallpaperResetDetail;
        }

        function appearanceWallpaperPath(): string {
            return root.appearanceModel.wallpaperPath;
        }

        function appearanceWallpaperFit(): string {
            return root.appearanceModel.wallpaperFit;
        }

        function appearanceWallpaperMutationDetail(): string {
            return root.appearanceModel.wallpaperMutationDetail;
        }

        function appearanceWallpaperResetReady(): bool {
            return root.appearanceModel.wallpaperResetReady;
        }

        function appearanceWallpaperPreviewState(): string {
            return root.appearanceModel.wallpaperPreviewState;
        }

        function appearanceWallpaperPreviewRemaining(): int {
            return root.appearanceModel.wallpaperPreviewRemaining;
        }

        function appearanceWallpaperStatusBusy(): bool {
            return root.appearanceModel.wallpaperStatusBusy;
        }

        function appearanceWallpaperReconcile(): void {
            root.appearanceModel.reconcileWallpaperPreview();
        }

        function appearanceFontState(): string {
            return root.appearanceModel.fontState;
        }

        function appearanceFontFamily(): string {
            return root.appearanceModel.fontFamily;
        }

        function appearanceFontScale(): string {
            return root.appearanceModel.fontScale.toFixed(2);
        }

        function appearanceFontMutationReady(): bool {
            return root.appearanceModel.fontMutationReady;
        }

        function appearanceFontPreviewState(): string {
            return root.appearanceModel.fontPreviewState;
        }

        function appearanceFontPreviewRemaining(): int {
            return root.appearanceModel.fontPreviewRemaining;
        }

        function appearanceToolkitProviderState(): string {
            return root.appearanceModel.toolkitProviderState;
        }

        function appearanceToolkitMutationReady(): bool {
            return root.appearanceModel.toolkitMutationReady;
        }

        function appearanceToolkitStatusBusy(): bool {
            return root.appearanceModel.toolkitStatusBusy;
        }

        function appearanceToolkitState(capability: string): string {
            return root.appearanceModel.toolkitSelectionFor(capability).state;
        }

        function appearanceMessage(): string {
            return root.appearanceModel.message;
        }

        function appearanceRecoveryState(): string {
            return root.appearanceModel.recoveryState;
        }

        function panelSettingsState(): string {
            return root.panelSettingsModel.providerState;
        }

        function panelWidgetEnabled(widget: string): bool {
            return root.panelSettingsModel.widgetEnabled(widget);
        }

        function panelWidgetSet(widget: string, enabled: bool): void {
            root.panelSettingsModel.setWidget(widget, enabled);
        }

        function panelWidgetsReset(): void {
            root.panelSettingsModel.reset();
        }

        function updateState(): string {
            return root.updateModel.updateState;
        }

        function updateInstalledVersion(): string {
            return root.updateModel.installedVersion;
        }

        function updateAvailableVersion(): string {
            return root.updateModel.availableVersion;
        }

        function updateConsistent(): bool {
            return root.updateModel.consistent;
        }

        function updateBusy(): bool {
            return root.updateModel.busy;
        }

        function updatePhase(): string {
            return root.updateModel.phase;
        }

        function updateApply(version: string): void {
            root.updateModel.apply(version);
        }

        function updateProgressShown(): bool {
            return root.updateModel.progressShown;
        }

        function updatePopupClosed(): bool {
            return root.updateModel.popupClosed;
        }

        function updateShowProgress(): void {
            root.updateModel.showProgress();
        }

        function updateClosePopup(): void {
            root.updateModel.closePopup();
        }

        function updateDismissProgress(): void {
            root.updateModel.dismissProgress();
        }

        function updateOutcomeSucceeded(): bool {
            return root.updateModel.actionSucceeded;
        }

        function updateMessage(): string {
            return root.updateModel.message;
        }

        function updateRefreshLog(): void {
            root.updateModel.refreshLog();
        }

        function updateLogState(): string {
            return root.updateModel.logState;
        }

        function updateLogText(): string {
            return root.updateModel.logText;
        }

        function updateLogTruncated(): bool {
            return root.updateModel.logTruncated;
        }

        function systemManagementUpdateCount(): int {
            return root.systemManagementModel.updates.length;
        }

        function systemManagementPackageChangeCount(): int {
            return root.systemManagementModel.packageChanges.length;
        }

        function systemManagementSnapshotState(): string {
            return root.systemManagementModel.snapshotState;
        }

        function systemManagementRestartState(): string {
            return root.systemManagementModel.updateRestart.status + ":" + root.systemManagementModel.updateRestart.value;
        }

        function systemManagementSettingsVisible(): bool {
            return root.systemManagementModel.settingsVisible;
        }

        function systemManagementDiscoveryStatus(): string {
            const discovery = root.systemManagementModel.discovery;
            return discovery.phase + ":" + (discovery.ready ? "ready"
                : discovery.failed ? "failed" : "inactive");
        }

        function systemManagementOperationState(): string {
            return root.systemManagementModel.operation.state;
        }

        function systemManagementOperationResult(): string {
            const result = root.systemManagementModel.operation.result;
            return result === null ? "" : result.actionId + ":" + result.state;
        }

        // Sync Phase 9 (92ec6e2:docs/SYNC-P9-REGIONAL-MUTATION.md §5.6): the preview
        // read is async (a real Process), so this returns whether the
        // request was accepted, matching updateApply()'s fire-and-forget
        // shape -- systemManagementRegionalPreviewResult() below is the
        // separate probe to poll, the same split
        // systemManagementOperationState()/systemManagementOperationResult()
        // already establish for async state.
        // Sync Sprint 1 S1-05 (#268): SystemManagementModel.prepareRegional()/
        // regionalPreview/confirmRegional()/discardRegional() moved into
        // SystemRegionalSettingsModel (systemManagementModel.regional) --
        // these probes keep their established names (existing tests call
        // them) but now route to that model.
        function systemManagementRegionalPreviewPending(): bool {
            return root.systemManagementModel.regional.request !== null;
        }

        function systemManagementRegionalPreview(action: string, argument: string): bool {
            return root.systemManagementModel.regional.prepare(action, argument);
        }

        function systemManagementRegionalPreviewResult(): string {
            const confirmation = root.systemManagementModel.regional.confirmation;
            const preview = confirmation === null ? null : confirmation.preview;
            return preview === null ? "" : preview.actionId + ":" + preview.current + ":" + preview.target;
        }

        function systemManagementRegionalConfirm(): bool {
            return root.systemManagementModel.regional.confirm();
        }

        function systemManagementRegionalDiscard(): void {
            root.systemManagementModel.regional.discard();
        }

        function systemManagementRegionalMessage(): string {
            return root.systemManagementModel.regional.message;
        }

        function systemManagementRegionalOwnsPreparation(): bool {
            return root.systemManagementModel.regional.ownsPreparation();
        }

        // Fire-and-poll, matching systemManagementRegionalPreview()'s own
        // split: the read is async, so request and result are separate
        // probes.
        function systemManagementRegionalRequestChoices(kind: string): bool {
            return root.systemManagementModel.regional.requestChoices(kind);
        }

        function systemManagementRegionalChoicesCount(kind: string): int {
            return root.systemManagementModel.regional.choices(kind).length;
        }

        // Sync Sprint 1 S1-04 (#266): delegated actions now go through a
        // visible confirmation step (prepareDelegate()/confirmDelegate()/
        // discardDelegate()), the same as regional mutations already do.
        // Kept as one convenience probe (prepare then confirm) for existing
        // test call sites that only care about the end-to-end outcome; the
        // individual steps below exist to test the confirmation step itself.
        function systemManagementDelegatedLaunch(action: string): bool {
            return root.systemManagementModel.prepareDelegate(action) && root.systemManagementModel.confirmDelegate();
        }

        function systemManagementNativeConfirmationPending(): bool {
            return root.systemManagementModel.nativeConfirmation !== null;
        }

        function systemManagementPrepareDelegate(action: string): bool {
            return root.systemManagementModel.prepareDelegate(action);
        }

        function systemManagementConfirmDelegate(): bool {
            return root.systemManagementModel.confirmDelegate();
        }

        function systemManagementDiscardDelegate(): void {
            root.systemManagementModel.discardDelegate();
        }

        function systemManagementNativeConfirmationMessage(): string {
            return root.systemManagementModel.nativeConfirmationMessage;
        }

        // Sync Sprint 2 S2-05 (#286): confirms opening the existing
        // dwm-system-health view via the "health-open" action's fixed
        // owner. openHealth() itself already checks the action is available.
        function systemManagementOpenHealth(): bool {
            return root.systemManagementModel.openHealth();
        }

        // Sync Sprint 1 S1-03 (#261): one discovery model per native domain,
        // same phase:ready/failed/inactive shape as systemManagementDiscoveryStatus()
        // above (the update domain's own probe), for "time", "locale",
        // "accounts" or "printers".
        function systemManagementNativeDiscoveryStatus(domain: string): string {
            const discovery = domain === "time" ? root.systemManagementModel.timeDiscovery
                : domain === "locale" ? root.systemManagementModel.localeDiscovery
                : domain === "accounts" ? root.systemManagementModel.accountDiscovery
                : domain === "printers" ? root.systemManagementModel.printerDiscovery
                : domain === "storage" ? root.systemManagementModel.storageDiscovery
                : domain === "security" ? root.systemManagementModel.securityDiscovery : null;
            if (discovery === null) return "";
            return discovery.phase + ":" + (discovery.ready ? "ready"
                : discovery.failed ? "failed" : "inactive");
        }

        // Sync Sprint 1 S1-08 (#275/#276): a time-service owner arrival is
        // uncertainty, not a confirmed change -- these expose
        // systemManagementModel.timeReconciliation's own reconciliation
        // state, distinct from timeDiscovery's plain watch-stream health.
        function systemManagementTimeReconciliationBlocked(): bool {
            return root.systemManagementModel.timeReconciliation.blocked;
        }

        function systemManagementTimeReconciliationDetail(): string {
            return root.systemManagementModel.timeReconciliation.detail;
        }

        function systemManagementTimeSampleNow(): void {
            root.systemManagementModel.timeReconciliation.sampleNow();
        }

        // #259/#261: the degradation-aware view, not the raw parsed record --
        // proves nativeProviderView() actually reflects a healthy read once
        // its own discovery monitor is up, for "regional", "accounts",
        // "printers" or "sources".
        function systemManagementNativeProviderStatus(owner: string): string {
            return root.systemManagementModel.nativeProviderView(owner).status;
        }

        // #259/#261: same for one native state identifier (e.g. "timezone",
        // "ntp-enabled", "locale", "accounts-count", "cups-service").
        function systemManagementNativeStateValue(identifier: string): string {
            const state = root.systemManagementModel.nativeStateView(identifier);
            return state.status + ":" + state.value;
        }

        function systemManagementAccountsCount(): int {
            return root.systemManagementModel.accounts.length;
        }

        function systemManagementRepositoriesCount(): int {
            return root.systemManagementModel.repositories.length;
        }

        // Sync Sprint 2 S2-05 (#286): same for the filesystem list (minor 2).
        function systemManagementFilesystemsCount(): int {
            return root.systemManagementModel.filesystems.length;
        }

        // Sync Sprint 1 S1-06 (#270): the shared ClockModel, not
        // system-management-specific, but exposed alongside these probes
        // since it now feeds SystemSettingsPane's "Local date and time" row.
        function clockPanelText(): string {
            return root.clock.panelText;
        }

        function clockSettingsText(): string {
            return root.clock.settingsText;
        }

        function autostartConfirming(): bool {
            return root.autostartModel.confirming;
        }

        function autostartConfirm(): void {
            root.autostartModel.confirmAction("settings");
        }

        function autostartCancel(): void {
            root.autostartModel.cancelConfirmation("settings");
        }

        function autostartSetSearch(query: string): void {
            root.autostartModel.setSearch(query);
        }

        function autostartFilteredCount(): int {
            return root.autostartModel.filteredEntries.length;
        }

        function autostartSet(desktopId: string, enabled: bool): void {
            const entry = root.autostartModel.entries.find(function(item) { return item.id === desktopId; });
            if (entry) root.autostartModel.requestSet(entry, enabled ? "enabled" : "disabled", "settings");
        }
    }
}
