

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.core
import qs.accessibility
import qs.appearance
import qs.calendar
import qs.controlcenter
import qs.controls
import qs.defaults
import qs.health
import qs.launcher
import qs.network
import qs.notifications
import qs.overview
import qs.panel
import qs.power
import qs.settings
import qs.state
import qs.system
import qs.weather
import qs.systemmanagement
import "core/Protocol.js" as Protocol

pragma ComponentBehavior: Bound

ShellRoot {
    id: root

    property var selectedPanelWindow: null
    readonly property var defaultPanelWindow: panelVariants.instances.length > 0
        ? panelVariants.instances[0] : null
    readonly property var activePanelWindow: selectedPanelWindow && selectedPanelWindow.screen
        ? selectedPanelWindow : defaultPanelWindow
    readonly property var activePanelScreen: activePanelWindow && activePanelWindow.screen
        ? activePanelWindow.screen
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    function selectPanelPopup(panel, popupId) {
        if (!panel || !panel.screen) {
            return;
        }

        commandMenuModel.close();
        launcherModel.close();
        notificationModel.closeHistory();
        controlCenterModel.closeUtility();
        if (popupId !== "bluetooth") bluetoothModel.close();
        if (popupId !== "calendar") calendarModel.close();
        if (popupId !== "weather") weatherModel.close();
        if (popupId !== "controlcenter") controlCenterModel.close();
        if (popupId !== "controls") controlsModel.close();
        if (popupId !== "network") networkModel.close();
        if (popupId !== "power") powerMenuModel.close("panel");
        if (popupId !== "overview") overviewModel.close();
        root.selectedPanelWindow = panel;
    }

    function openOverview(screen) {
        const panel = root.panelForScreen(screen || dwmState.focusedScreen());

        commandMenuModel.close();
        launcherModel.close();
        if (panel) root.selectPanelPopup(panel, "overview");
        overviewModel.open(panel ? panel.screen : screen);
    }

    function toggleOverview(screen) {
        if (overviewModel.visible) {
            overviewModel.close();
        } else {
            root.openOverview(screen);
        }
    }

    function openCommandMenu(screen) {
        networkModel.close();
        bluetoothModel.close();
        calendarModel.close();
        weatherModel.close();
        controlCenterModel.close();
        controlsModel.close();
        powerMenuModel.close("panel");
        launcherModel.close();
        overviewModel.close();
        if (screen) commandMenuModel.openOnScreen(screen); else commandMenuModel.open();
    }

    function toggleCommandMenu(screen) {
        if (commandMenuModel.visible) {
            commandMenuModel.close();
        } else {
            root.openCommandMenu(screen);
        }
    }

    function panelForScreen(screen) {
        if (screen) {
            for (const panel of panelVariants.instances) {
                if (panel.screen === screen || (panel.screen && panel.screen.name === screen.name)) {
                    return panel;
                }
            }
        }

        return root.activePanelWindow;
    }

    function runCommandMenuAction(target, action, argument, requestedScreen) {
        const panel = root.panelForScreen(requestedScreen);
        const screen = requestedScreen || (panel ? panel.screen : root.activePanelScreen);

        if (target === "settings" && (action === "open" || action === "select")) {
            settingsModel.openOnScreen(screen);
            if (action === "select") settingsModel.selectSection(argument);
        } else if (target === "network" && action === "open") {
            if (panel) root.selectPanelPopup(panel, "network");
            networkModel.open();
        } else if (target === "bluetooth" && action === "open") {
            if (panel) root.selectPanelPopup(panel, "bluetooth");
            bluetoothModel.open();
        } else if (target === "controls" && action === "open") {
            if (panel) root.selectPanelPopup(panel, "controls");
            controlsModel.open();
        } else if (target === "systemhealth" && action === "open") {
            systemHealthModel.openOnScreen(screen);
        } else if (target === "controlcenter" && action === "keybindings") {
            controlCenterModel.openKeybindsOnScreen(screen);
        } else if (target === "power" && action === "open") {
            if (panel) root.selectPanelPopup(panel, "power");
            powerMenuModel.open("panel");
        }
    }

    DwmState {
        id: dwmState
    }

    ClockModel {
        id: clock
        timezoneState: systemManagementModel.nativeStates.timezone || null
    }

    CalendarModel {
        id: calendarModel
        clock: clock
    }

    WeatherModel {
        id: weatherModel
        panelSettingsModel: panelSettingsModel
    }

    LauncherModel {
        id: launcherModel

        onVisibleChanged: {
            if (visible) {
                commandMenuModel.close();
                overviewModel.close();
            }
        }
    }

    CommandMenuModel {
        id: commandMenuModel
        launcherModel: launcherModel
        currentEntryIds: {
            const ids = [];

            if (settingsModel.visible) {
                ids.push("settings");
                if (settingsModel.selectedSectionId === "displays" || settingsModel.selectedSectionId === "input") {
                    ids.push(settingsModel.selectedSectionId);
                    ids.push("display-input");
                } else if (settingsModel.selectedSectionId === "power") {
                    ids.push("system");
                    ids.push("power-settings");
                } else if (settingsModel.selectedSectionId === "system") {
                    ids.push("system");
                    ids.push("system-settings");
                }
            }
            if (networkModel.visible) ids.push("network");
            if (bluetoothModel.visible) ids.push("bluetooth");
            if (controlsModel.visible) ids.push("audio");
            if (systemHealthModel.visible) ids.push("health");
            if (controlCenterModel.utilityVisible && controlCenterModel.utilityPage === "keybinds") ids.push("keybindings");
            if (powerMenuModel.visible) {
                ids.push("system");
                ids.push("power-menu");
            }

            return ids;
        }
        onIpcActionRequested: (target, action, argument, screen) => root.runCommandMenuAction(target, action, argument, screen)
    }

    PowerMenuModel {
        id: powerMenuModel
        powerModel: powerModel
    }

    PowerModel {
        id: powerModel
    }

    DefaultAppsModel {
        id: defaultsModel
    }

    AutostartModel {
        id: autostartModel
    }

    AppearanceModel {
        id: appearanceModel
    }

    AccessibilityModel {
        id: accessibilityModel
    }

    PanelSettingsModel {
        id: panelSettingsModel
    }

    UpdateModel {
        id: updateModel
        indicator: updateIndicator
    }

    // The panel's updates-available indicator (Sync Sprint 15 S15-02): one
    // instance, shared by every screen's panel.
    UpdateIndicatorModel {
        id: updateIndicator
        updateModel: updateModel
        networkModel: networkModel
    }

    SystemManagementModel {
        id: systemManagementModel
        healthModel: systemHealthModel
        targetScreen: settingsWindow.screen || settingsModel.targetScreen || root.activePanelScreen
        onHealthOpened: settingsModel.close()
    }

    readonly property string dpiStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "")
        + "/dwm-settings-display/dpi.current"

    function applyDpiState(text) {
        let dpi = 96;
        let valid = false;
        for (const line of String(text).trim().split("\n")) {
            const fields = line.split("\t");
            if (Protocol.isHeader(fields, "dpi-state-protocol", 1)) {
                valid = true;
            } else if (fields[0] === "dpi" && fields.length >= 2) {
                dpi = Number(fields[1]);
            }
        }
        if (valid)
            Theme.applyDisplayDpi(dpi);
    }

    FileView {
        id: dpiStateWatch
        path: root.dpiStatePath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyDpiState(this.text())
        onFileChanged: reload()
    }

    NetworkModel {
        id: networkModel
    }

    ControlsModel {
        id: controlsModel
    }

    OverviewModel {
        id: overviewModel
        dwmState: dwmState
    }

    BluetoothModel {
        id: bluetoothModel
    }

    ControlCenterModel {
        id: controlCenterModel
        powerModel: powerModel
        panelSettingsModel: panelSettingsModel
    }

    SystemHealthModel {
        id: systemHealthModel
    }

    SettingsModel {
        id: settingsModel
        networkModel: networkModel
        bluetoothModel: bluetoothModel
        controlsModel: controlsModel
        powerModel: powerModel
        powerMenuModel: powerMenuModel
        defaultsModel: defaultsModel
        autostartModel: autostartModel
        appearanceModel: appearanceModel
        accessibilityModel: accessibilityModel
        panelSettingsModel: panelSettingsModel
        updateModel: updateModel
        systemManagementModel: systemManagementModel
    }

    LazyLoader {
        active: true

        component: Item {
            Component.onCompleted: {
                networkModel.refresh();
                bluetoothModel.refresh();
                controlsModel.refresh();
            }
        }
    }

    NotificationModel {
        id: notificationModel
    }

    IpcHandler {
        target: "launcher"

        function applicationConsumers(): int {
            return launcherModel.applicationConsumers;
        }

        function close(): void {
            launcherModel.close();
        }

        function indexCount(): int {
            return launcherModel.apps.length;
        }

        function open(): void {
            launcherModel.open();
        }

        function toggle(): void {
            launcherModel.toggle();
        }
    }

    IpcHandler {
        target: "menu"

        function activeMenu(): string {
            return commandMenuModel.activeMenu;
        }

        function close(): void {
            commandMenuModel.close();
        }

        function open(): void {
            root.openCommandMenu(null);
        }

        function resultCount(): int {
            return commandMenuModel.rows.length;
        }

        function selectedLabel(): string {
            return commandMenuModel.selectedLabel;
        }

        function summon(): void {
            root.openCommandMenu(dwmState.focusedScreen());
        }

        function toggle(): void {
            root.toggleCommandMenu(null);
        }
    }

    IpcHandler {
        target: "power"

        function close(): void {
            powerMenuModel.close("panel");
        }

        function open(): void {
            powerMenuModel.open();
        }

        function toggle(): void {
            powerMenuModel.toggle();
        }

        // The menu at one action's confirmation: logout, reboot, suspend or
        // shutdown (Sync Sprint 16 R16-24).
        function confirm(action: string): void {
            powerMenuModel.askToConfirm(action);
        }
    }

    IpcHandler {
        target: "network"

        function close(): void {
            networkModel.close();
        }

        function open(): void {
            networkModel.open();
        }

        function refresh(): void {
            networkModel.refresh();
        }

        function status(): string {
            return networkModel.statusText;
        }

        function toggle(): void {
            networkModel.toggle();
        }
    }

    IpcHandler {
        target: "controls"

        function close(): void {
            controlsModel.close();
        }

        function bluetoothStatus(): string {
            return controlsModel.bluetoothText;
        }

        function open(): void {
            controlsModel.open();
        }

        function refresh(): void {
            controlsModel.refresh();
        }

        function micStatus(): string {
            return controlsModel.micText;
        }

        function mediaStatus(): string {
            return controlsModel.mediaText;
        }

        function mediaNext(): void {
            controlsModel.mediaNext();
        }

        function mediaPlayPause(): void {
            controlsModel.mediaPlayPause();
        }

        function mediaPrevious(): void {
            controlsModel.mediaPrevious();
        }

        function toggle(): void {
            controlsModel.toggle();
        }

        function volumeDown(): void {
            controlsModel.volumeDown();
        }

        function volumeStatus(): string {
            return controlsModel.volumeDisplayText;
        }

        function volumeSet(percent: int): void {
            controlsModel.volumeSet(percent);
        }

        function volumeToggleMute(): void {
            controlsModel.volumeToggleMute();
        }

        function volumeUp(): void {
            controlsModel.volumeUp();
        }
    }

    IpcHandler {
        target: "overview"

        function close(): void {
            overviewModel.close();
        }

        function open(): void {
            root.openOverview(null);
        }

        function toggle(): void {
            root.toggleOverview(null);
        }

        function windowCount(): int {
            return overviewModel.groups.reduce(function(total, group) {
                return total + group.windows.length;
            }, 0);
        }
    }

    IpcHandler {
        target: "notifications"

        function clear(): void {
            notificationModel.clear();
        }

        function count(): int {
            return notificationModel.notifications.length;
        }

        function clearHistory(): void {
            notificationModel.clearHistory();
        }

        function closeHistory(): void {
            notificationModel.closeHistory();
        }

        function historyCount(): int {
            return notificationModel.history.length;
        }

        function historyLatestSummary(): string {
            return notificationModel.historyLatestSummary();
        }

        function doNotDisturb(): bool {
            return notificationModel.doNotDisturb;
        }

        function popupTimeout(): int {
            return notificationModel.popupTimeoutMs;
        }

        function policyState(): string {
            return notificationModel.policyState;
        }

        function policyStatus(): string {
            return notificationModel.policyStatus();
        }

        function resetPolicy(): void {
            notificationModel.resetPolicy();
        }

        function setDoNotDisturb(enabled: bool): void {
            notificationModel.setDoNotDisturb(enabled);
        }

        function setPopupTimeout(timeoutMs: int): void {
            notificationModel.setPopupTimeout(timeoutMs);
        }

        function openHistory(): void {
            notificationModel.openHistory();
        }

        function toggleHistory(): void {
            notificationModel.toggleHistory();
        }
    }

    IpcHandler {
        target: "controlcenter"

        function close(): void {
            controlCenterModel.close();
        }

        function open(): void {
            controlCenterModel.open();
        }

        function openKeybinds(): void {
            controlCenterModel.openKeybinds();
        }

        function refresh(): void {
            controlCenterModel.refresh();
        }

        function toggle(): void {
            controlCenterModel.toggle();
        }
    }

    IpcHandler {
        target: "systemhealth"

        function close(): void {
            systemHealthModel.close();
        }

        function open(): void {
            systemHealthModel.openOnScreen(root.activePanelScreen);
        }

        function refresh(): void {
            systemHealthModel.refresh();
        }

        function toggle(): void {
            if (systemHealthModel.visible) {
                systemHealthModel.close();
            } else {
                systemHealthModel.openOnScreen(root.activePanelScreen);
            }
        }
    }

    // The clock's month calendar (Sync Sprint 12 S12-20). status is "closed", or
    // "open", the shown month (YYYY-MM) and the selected day, tab-separated.
    IpcHandler {
        id: calendarIpc

        target: "calendar"

        function close(): void {
            calendarModel.close();
        }

        function open(): void {
            root.selectPanelPopup(root.activePanelWindow, "calendar");
            calendarModel.open(0);
        }

        function status(): string {
            if (!calendarModel.visible) return "closed";
            const month = String(calendarModel.shownMonth + 1).padStart(2, "0");
            return "open\t" + calendarModel.shownYear + "-" + month + "\t" + calendarModel.selectedDay;
        }

        function toggle(): void {
            if (calendarModel.visible) calendarModel.close();
            else calendarIpc.open();
        }
    }

    IpcHandler {
        target: "settings"

        function close(): void {
            settingsModel.close();
        }

        function open(): void {
            settingsModel.openOnScreen(dwmState.focusedScreen());
        }

        function refresh(): void {
            settingsModel.refresh();
        }

        function select(section: string): void {
            settingsModel.selectSection(section);
        }

        function status(): string {
            return settingsModel.discoveryState;
        }

        function toggle(): void {
            if (settingsModel.visible) settingsModel.close();
            else settingsModel.openOnScreen(dwmState.focusedScreen());
        }
    }

    // The update indicator's test getters and driver (Sync Sprint 15 S15-02),
    // created only when LYONA_SHELL_TEST_IPC=1. pillCenter is the indicator's
    // centre on the first screen, for a real click.
    LazyLoader {
        active: Quickshell.env("LYONA_SHELL_TEST_IPC") === "1"

        component: Scope {
            IpcHandler {
                target: "updateIndicatorTest"

                function status(): string {
                    return [updateIndicator.shown ? "shown" : "hidden", updateIndicator.count,
                        updateIndicator.systemState, updateIndicator.intervalHours,
                        updateIndicator.showWhenCurrent ? "yes" : "no"].join("\t");
                }

                function check(): void {
                    updateIndicator.check(true);
                }

                function updateInTerminal(provider: string): void {
                    updateIndicator.updateInTerminal(provider);
                }

                function terminalStatus(): string {
                    return [updateIndicator.terminalBusy ? "busy" : "idle", updateIndicator.terminalProvider,
                        updateIndicator.terminalResult, updateIndicator.flatpakCount,
                        updateIndicator.floatTerminal ? "float" : "tile",
                        updateIndicator.floatRulePresent ? "rule" : "no-rule"].join("\t");
                }

                function pillCenter(): string {
                    const panel = panelVariants.instances[0];
                    const pill = panel ? panel.findItem("updateAvailablePill") : null;
                    if (!pill || !pill.visible) return "";
                    const point = pill.mapToItem(null, pill.width / 2, pill.height / 2);
                    return Math.round(point.x) + " " + Math.round(point.y);
                }
            }
        }
    }

    // The settings target's test getters and drivers (Sync Sprint 12 S12-16):
    // created only when LYONA_SHELL_TEST_IPC=1, which nothing in a normal
    // session sets.
    LazyLoader {
        active: Quickshell.env("LYONA_SHELL_TEST_IPC") === "1"

        component: SettingsTestIpc {
            settingsModel: settingsModel
            appearanceModel: appearanceModel
            systemManagementModel: systemManagementModel
            updateModel: updateModel
            autostartModel: autostartModel
            powerModel: powerModel
            defaultsModel: defaultsModel
            controlsModel: controlsModel
            panelSettingsModel: panelSettingsModel
            networkModel: networkModel
            bluetoothModel: bluetoothModel
            clock: clock
        }
    }

    IpcHandler {
        target: "tray"

        function count(): int {
            return SystemTray.items.values.length;
        }

        function ids(): string {
            const items = SystemTray.items.values;
            const ids = [];

            for (let i = 0; i < items.length; i++) {
                ids.push(items[i].id || items[i].title || items[i].tooltipTitle || "unknown");
            }

            return ids.join("\n");
        }

        function details(): string {
            const items = SystemTray.items.values;
            const rows = [];

            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                rows.push([
                    item.id || "unknown",
                    item.title || "",
                    item.icon || "",
                    item.hasMenu ? "menu" : "no-menu",
                    item.status === undefined || item.status === null ? "" : item.status
                ].join("\t"));
            }

            return rows.join("\n");
        }
    }

    LauncherWindow {
        launcherModel: launcherModel
    }

    CommandMenuWindow {
        commandMenuModel: commandMenuModel
    }

    PowerMenuWindow {
        powerMenuModel: powerMenuModel
        panelWindow: root.activePanelWindow
    }

    // feh draws the wallpaper for the screens' size when it is set, so after a
    // resolution or layout change it was left stretched or cut. The screens'
    // geometry is a binding: when it changes, draw the session's wallpaper
    // again, once the change has settled (one helper run, not one per output).
    readonly property string screenLayout: Quickshell.screens
        .map(screen => screen.x + "," + screen.y + " " + screen.width + "x" + screen.height).join(";")
    // The first layout is the one the session started with: autostart has set
    // the wallpaper for it.
    property string redrawnScreenLayout: ""
    onScreenLayoutChanged: {
        if (root.redrawnScreenLayout.length === 0) root.redrawnScreenLayout = root.screenLayout;
        else if (root.screenLayout !== root.redrawnScreenLayout) wallpaperRedrawTimer.restart();
    }

    Timer {
        id: wallpaperRedrawTimer

        interval: 1000
        repeat: false
        onTriggered: {
            // Changed and changed back while settling: nothing to redraw.
            if (root.screenLayout === root.redrawnScreenLayout) return;
            if (wallpaperRedraw.running) {
                wallpaperRedrawTimer.restart();
            } else {
                root.redrawnScreenLayout = root.screenLayout;
                wallpaperRedraw.running = true;
            }
        }
    }

    Process {
        id: wallpaperRedraw

        command: Commands.settingsWallpaperCommand("session-apply")
        running: false
    }

    Variants {
        id: panelVariants

        model: Quickshell.screens

        DwmPanel {
            required property var modelData

            screen: modelData
            state: dwmState
            clock: clock
            networkModel: networkModel
            controlsModel: controlsModel
            bluetoothModel: bluetoothModel
            calendarModel: calendarModel
            weatherModel: weatherModel
            controlCenterModel: controlCenterModel
            panelSettingsModel: panelSettingsModel
            powerModel: powerModel
            powerMenuModel: powerMenuModel
            updateModel: updateModel
            primaryPanel: modelData === Quickshell.screens[0]
            onPopupRequested: (panel, popupId) => root.selectPanelPopup(panel, popupId)
            onSettingsRequested: (panel, sectionId) => {
                root.selectPanelPopup(panel, "");
                settingsModel.openOnScreen(panel.screen, sectionId);
            }
        }
    }

    NetworkWindow {
        networkModel: networkModel
        panelWindow: root.activePanelWindow
    }

    NotificationPopupWindow {
        notificationModel: notificationModel
        panelWindow: root.defaultPanelWindow
    }

    NotificationHistoryWindow {
        notificationModel: notificationModel
    }

    ControlsWindow {
        controlsModel: controlsModel
        panelWindow: root.activePanelWindow
    }

    WindowOverview {
        overviewModel: overviewModel
        panelWindow: root.activePanelWindow
    }

    BluetoothWindow {
        bluetoothModel: bluetoothModel
        panelWindow: root.activePanelWindow
    }

    CalendarWindow {
        calendarModel: calendarModel
        panelWindow: root.activePanelWindow
    }

    WeatherWindow {
        weatherModel: weatherModel
        panelWindow: root.activePanelWindow
    }

    ControlCenterWindow {
        controlCenterModel: controlCenterModel
        dwmState: dwmState
        launcherModel: launcherModel
        panelWindow: root.activePanelWindow
        powerMenuModel: powerMenuModel
        powerModel: powerModel
        healthModel: systemHealthModel
        settingsModel: settingsModel
        updateModel: updateModel
    }

    UtilityDetailWindow {
        controlCenterModel: controlCenterModel
    }

    UpdateProgressWindow {
        id: updateProgressWindow
        updateModel: updateModel
        panelWindow: root.activePanelWindow
    }

    SystemHealthWindow {
        healthModel: systemHealthModel
        screen: systemHealthModel.targetScreen ? systemHealthModel.targetScreen : root.activePanelScreen
    }

    SettingsWindow {
        id: settingsWindow
        clock: clock
        settingsModel: settingsModel
        networkModel: networkModel
        bluetoothModel: bluetoothModel
        controlsModel: controlsModel
        powerModel: powerModel
        powerMenuModel: powerMenuModel
        defaultsModel: defaultsModel
        autostartModel: autostartModel
        appearanceModel: appearanceModel
        accessibilityModel: accessibilityModel
        notificationModel: notificationModel
        panelSettingsModel: panelSettingsModel
        weatherModel: weatherModel
        updateModel: updateModel
        systemManagementModel: systemManagementModel
    }
}
