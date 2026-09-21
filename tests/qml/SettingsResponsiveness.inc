    // Runs inside an isolated copy of the production ShellRoot.
    property bool checkedAppearanceStatusDelay: false
    property bool checkedDisplayRecovery: false
    property bool checkedInputRecovery: false
    property bool checkedPolicyRead: false
    property bool checkedSystemRead: false
    property bool checkedUpdateRead: false
    property string delayedSection: ""
    property int delayedFrames: 0
    property int loadingFrames: 0
    property var loadingBounds: []
    property int responseStage: 0
    property var capPane: null
    property double capStarted: 0
    property int scrollFrames: 0
    property real scrollStartY: 0
    property var scrollPane: null
    property var responsePanes: []
    property double responseStarted: Date.now()
    property var responseFirstPane: null
    property var scaleHealthWindow: null
    property var scaleNotificationPopup: null
    property int scaleNotificationDismissed: -1
    property var scaleNetworkPopup: null
    property var scaleAudioPopup: null
    property var scaleOversizedPopup: null
    property var scaleRows: []
    property var scaleBluetoothPane: null
    // The content of the pane the loading-cap stage creates.
    Component {
        id: capProbe
        Rectangle { width: 10; height: 10 }
    }
    function responseCheck(ok, detail) {
        if (!ok) {
            console.error("Responsiveness FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function responseItems(item, predicate) {
        let result = predicate(item) ? [item] : [];
        for (const child of item.children || [])
            result = result.concat(responseItems(child, predicate));
        return result;
    }
    function responsePaneItems() {
        return responseItems(settingsWindow.contentItem, item => /^(Display|Input|Network|Bluetooth|Audio|Power|Defaults|Appearance|System)SettingsPane_QML/.test(String(item)));
    }
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (root.responseStage === 0) {
                console.info("Settings measurement: closed panes=" + root.responsePaneItems().length
                    + " items=" + root.responseItems(settingsWindow.contentItem, () => true).length
                    + " startup_ms=" + (Date.now() - root.responseStarted));
                root.responseCheck(root.responsePaneItems().length === 0, "Closed startup creates no panes");
                settingsModel.testInitialLoading = true;
                settingsModel.openWindow();
                settingsModel.refreshDisplays();
                settingsModel.refreshCapabilities();
                root.responseStarted = Date.now();
                root.responseStage = 1;
            } else if (root.responseStage === 1) {
                const panes = root.responsePaneItems();
                if (!panes.some(item => String(item).startsWith("DisplaySettingsPane"))) return;
                const initialPane = panes.find(item => String(item).startsWith("DisplaySettingsPane"));
                const viewport = initialPane.parent;
                if (settingsModel.testInitialLoading) {
                    // #315/#335: nothing of the pane shows, and the space it
                    // will occupy does not move, while its data is delayed.
                    root.responseCheck(initialPane.opacity === 0 && !initialPane.enabled,
                        "Initial controls stay hidden and disabled while data is delayed");
                    const bounds = [viewport.x, viewport.y, viewport.width, viewport.height];
                    if (root.loadingFrames === 0) root.loadingBounds = bounds;
                    else root.responseCheck(JSON.stringify(bounds) === JSON.stringify(root.loadingBounds),
                        "Loading viewport stays fixed while initial data is delayed");
                    root.loadingFrames++;
                    if (root.loadingFrames >= 6) settingsModel.testInitialLoading = false;
                    return;
                }
                if (settingsModel.displayActionBusy) {
                    root.responseCheck(initialPane.opacity === 0 && !initialPane.enabled,
                        "Display preview recovery keeps initial controls hidden");
                    root.checkedDisplayRecovery = true;
                    return;
                }
                if (initialPane.opacity !== 1) return;
                root.responseCheck(initialPane.enabled, "Settled controls become usable");
                root.responseCheck(JSON.stringify([viewport.x, viewport.y, viewport.width, viewport.height])
                    === JSON.stringify(root.loadingBounds), "Loaded viewport matches loading viewport");
                settingsModel.testInitialLoading = true;
                root.responseCheck(initialPane.opacity === 1 && initialPane.enabled,
                    "Later refresh does not hide existing controls");
                settingsModel.testInitialLoading = false;
                console.info("Settings measurement: first pane ready_ms=" + (Date.now() - root.responseStarted));
                const before = settingsModel.testActivations;
                settingsModel.setSearch("dis");
                settingsModel.setSearch("disp");
                settingsModel.selectSection("displays");
                settingsModel.selectRelative(1); // One matching section.
                console.info("Settings measurement: redundant activations=" + (settingsModel.testActivations - before));
                root.responseCheck(settingsModel.testActivations === before, "Same-section search/navigation does not rediscover");
                settingsModel.setSearch("audio");
                root.responseCheck(settingsModel.testActivations === before + 1 && settingsModel.selectedSectionId === "audio", "A changed search activates its section exactly once");
                settingsModel.selectSection("displays");
                root.responseCheck(settingsModel.testActivations === before + 2 && settingsModel.searchQuery === "", "Selecting outside the filter clears it without intermediate activation");
                const reads = settingsModel.testDisplayReads;
                settingsModel.refresh();
                root.responseCheck(settingsModel.testDisplayReads === reads + 1, "Explicit Refresh reloads display state");
                root.responseFirstPane = panes.find(item => String(item).startsWith("DisplaySettingsPane"));
                root.responseFirstPane.profileName = "Unsaved display profile";
                root.responseStage = 2;
                settingsModel.setSearch("");
            } else if (root.responseStage >= 2 && root.responseStage <= 10) {
                const index = root.responseStage - 2;
                const section = settingsModel.sections[index];
                if (root.delayedSection !== section.id) {
                    root.delayedSection = section.id;
                    root.delayedFrames = 0;
                    if (section.id === "input") settingsModel.recoverInputPreview();
                    if (section.id === "appearance") notificationModel.policyState = "loading";
                    if (section.id === "system") settingsModel.testIgnoreSystemModel = true;
                    settingsModel.selectSection(section.id);
                    if (section.id === "system") systemManagementModel.refresh();
                    if (section.id === "defaults") {
                        defaultsModel.refresh();
                        autostartModel.refresh();
                    }
                    if (section.id === "power") powerModel.refresh();
                }
                const expected = ["Display", "Input", "Network", "Bluetooth", "Audio", "Power", "Defaults", "Appearance", "System"][index];
                const pane = root.responsePaneItems().find(item => String(item).startsWith(expected + "SettingsPane"));
                if (pane && !pane.parent.presented && section.id === "input" && settingsModel.inputActionBusy) {
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "Input preview recovery keeps initial controls hidden");
                    root.checkedInputRecovery = true;
                }
                if (pane && section.id === "appearance" && !pane.parent.presented
                        && !appearanceModel.initialLoading && !accessibilityModel.initialLoading
                        && !panelSettingsModel.initialLoading && !settingsModel.busy
                        && !settingsModel.capabilityRefreshPending) {
                    // Only the notification policy is still loading, so only its
                    // term can be what keeps the pane hidden.
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "Notification policy read and first save keep Appearance hidden");
                    root.checkedPolicyRead = true;
                    if (++root.delayedFrames === 3) notificationModel.policyState = "defaults";
                    if (root.delayedFrames === 6) {
                        notificationModel.popupTimeoutMs = notificationModel.popupTimeoutMs === 4000 ? 10000 : 4000;
                        notificationModel.savePolicy();
                    }
                }
                if (pane && section.id === "system" && root.delayedFrames < 6) {
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "A delayed System snapshot keeps System hidden");
                    root.checkedSystemRead = true;
                    root.delayedFrames++;
                }
                if (pane && section.id === "system" && !pane.parent.presented && updateModel.initialLoading) {
                    // The System pane's own model is ignored for this stage (the
                    // fixture switch), so only the update card's version read can
                    // be what keeps the pane hidden.
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "The update card's version read keeps System hidden");
                    root.checkedUpdateRead = true;
                }
                if (section.id === "appearance" && pane && !pane.parent.presented
                        && !appearanceModel.initialLoading && !settingsModel.busy
                        && !settingsModel.capabilityRefreshPending
                        && (accessibilityModel.initialLoading || panelSettingsModel.initialLoading)) {
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "Late accessibility/panel status cannot reveal default controls");
                    root.checkedAppearanceStatusDelay = true;
                }
                if (!pane || !pane.visible || pane.opacity !== 1 || pane.width <= 0 || pane.height <= 0) return;
                root.responseCheck(pane.width > 0 && pane.height > 0, "Loaded pane has layout geometry: " + section.id);
                if (section.id === "appearance") root.responseCheck(notificationModel.policyState === "available",
                    "The delayed first policy save produces a valid available policy");
                if (section.id === "input") {
                    const reads = settingsModel.testInputReads;
                    settingsModel.refresh();
                    root.responseCheck(settingsModel.testInputReads === reads + 1, "Explicit Refresh reloads input state");
                }
                root.responsePanes.push(pane);
                root.responseStage++;
            } else if (root.responseStage === 11) {
                root.responseCheck(!settingsWindow.testEarlyPresentation, "First presentation waits for every pending provider");
                root.responseCheck(root.checkedDisplayRecovery && root.checkedInputRecovery,
                    "Exercised both delayed preview-recovery reads");
                root.responseCheck(root.checkedUpdateRead,
                    "Exercised the update card's version read finishing after the System snapshot");
                root.responseCheck(root.checkedPolicyRead && root.checkedSystemRead,
                    "Exercised the notification policy and System snapshot initial reads");
                root.responseCheck(!autostartModel.testQueuedGap && !defaultsModel.testQueuedGap
                        && !powerModel.testQueuedGap && !settingsModel.testQueuedGap,
                    "Queued refresh flags remain set until the next process starts");
                root.responseCheck(root.checkedAppearanceStatusDelay,
                    "Exercised panel/accessibility reads finishing after other Appearance data");
                settingsModel.testInitialLoading = true;
                settingsModel.close();
                root.responseCheck(root.responsePaneItems().length === 9, "Closing retains visited panes");
                settingsModel.openWindow();
                root.responseStage++;
            } else if (root.responseStage === 12) {
                root.responseCheck(root.responsePaneItems().length === 9, "Reopening does not duplicate panes");
                root.responseCheck(root.responseFirstPane.opacity === 1 && root.responseFirstPane.enabled,
                    "Previously loaded controls stay usable when reopening during a refresh");
                settingsModel.testInitialLoading = false;
                root.responseCheck(root.responsePaneItems().indexOf(root.responseFirstPane) >= 0, "First pane identity survives navigation and close");
                root.responseCheck(root.responseFirstPane.profileName === "Unsaved display profile", "Unsaved profile name survives navigation and close");
                root.responseCheck(root.responsePanes.every(item => root.responsePaneItems().indexOf(item) >= 0), "Every visited pane survives");
                root.responseCheck(settingsWindow.fullscreen, "Settings requests fullscreen like System Health");
                settingsModel.selectSection("appearance");
                root.scrollPane = root.responsePaneItems().find(item => item.objectName === "appearanceSettingsPane");
                root.responseCheck(root.scrollPane !== undefined, "Appearance scroll surface is available");
                root.responseStage = 13;
            } else if (root.responseStage === 13) {
                root.responseCheck(root.scrollPane.contentHeight > root.scrollPane.height, "Appearance has scrollable content");
                root.scrollPane.contentY = 0;
                root.scrollPane.flick(1200, 1600);
                root.responseStage = 14;
            } else if (root.responseStage >= 14 && root.responseStage <= 17) {
                const pane = root.scrollPane;
                root.responseCheck(Math.abs(pane.contentX) < 0.1, "Diagonal input must not shift Appearance horizontally");
                root.responseCheck(pane.contentY >= -0.1 && pane.contentY <= Math.max(0, pane.contentHeight - pane.height) + 0.1,
                    "Appearance must not overscroll and bounce back");
                if (++root.scrollFrames < 20) return;
                if (root.responseStage === 14) {
                    pane.cancelFlick();
                    root.scrollStartY = pane.contentY;
                    pane.flick(-1200, -1600);
                } else if (root.responseStage === 15) {
                    root.responseCheck(pane.contentY > root.scrollStartY + 1, "An inward flick from the top must scroll down");
                    pane.cancelFlick();
                    pane.contentY = Math.max(0, pane.contentHeight - pane.height);
                    pane.flick(-1200, -1600);
                } else if (root.responseStage === 16) {
                    pane.cancelFlick();
                    root.scrollStartY = pane.contentY;
                    pane.flick(1200, 1600);
                } else {
                    root.responseCheck(pane.contentY < root.scrollStartY - 1, "An inward flick from the bottom must scroll up");
                    // Shell surfaces at the largest text scale: nothing may run
                    // off-screen or become unreachable.
                    Theme.applyFontPreferences("Noto Sans", 2);
                    const health = Qt.createComponent("health/SystemHealthWindow.qml");
                    root.scaleHealthWindow = health.createObject(root, {healthModel: systemHealthModel});
                    root.scaleHealthWindow.visible = true;
                    const launcher = Qt.createComponent("launcher/LauncherResultDelegate.qml");
                    const wifi = Qt.createComponent("network/NetworkWifiRow.qml");
                    const notifications = Qt.createComponent("notifications/NotificationPopupWindow.qml");
                    root.scaleNotificationPopup = notifications.createObject(root,
                        {panelWindow: root.defaultPanelWindow, notificationModel: {
                            notifications: [0, 1, 2, 3, 4, 5, 6, 7].map(key => ({key: key, appName: "Test application",
                                summary: "Notification " + key, body: "A long notification body that wraps across several lines so the complete stack needs scrolling at large text sizes.",
                                urgency: 1, urgencyName: "Normal", timeoutMs: 100000})),
                            dismiss: key => { root.scaleNotificationDismissed = key; }, expire: () => {}}});
                    const network = Qt.createComponent("network/NetworkWindow.qml");
                    root.scaleNetworkPopup = network.createObject(root, {panelWindow: root.defaultPanelWindow,
                        networkModel: {visible: true, busy: false, actionsAvailable: true, editorAvailable: false,
                            wifiPasswordPromptVisible: true, wifiPasswordPromptOrigin: "panel", wifiPassword: "",
                            statusText: "Online", message: "", activeConnections: [], savedProfiles: [], wifiNetworks: [],
                            selectedWifiIndex: -1, selectedWifiNetwork: () => ({ssid: "Test network"}),
                            cancelWifiPasswordPrompt: () => {}, close: () => {}}});
                    const audio = Qt.createComponent("controls/ControlsWindow.qml");
                    root.scaleAudioPopup = audio.createObject(root, {panelWindow: root.defaultPanelWindow,
                        controlsModel: {visible: true, busy: false, volumeMuted: false, volumeDisplayText: "50%",
                            message: "", volumePercent: 50, micText: "MIC on", mediaText: "Track",
                            mediaPlayer: "Player", outputDevices: [{name: "output", description: "Speakers", isDefault: true}],
                            close: () => {}}});
                    const clickAway = Qt.createComponent("core/ClickAwayPopup.qml");
                    root.scaleOversizedPopup = clickAway.createObject(root, {targetWindow: root.defaultPanelWindow,
                        popupWidth: 300, popupHeight: root.defaultPanelWindow.screen.height * 2, visible: true});
                    const bluetooth = Qt.createComponent("settings/BluetoothSettingsPane.qml");
                    root.scaleBluetoothPane = bluetooth.createObject(settingsWindow.contentItem,
                        {width: 1000, height: 900, bluetoothModel: {
                            providerState: "available", statusText: "Bluetooth", powered: true,
                            available: true, actionsAvailable: true, busy: false, message: "",
                            actionAddress: "", devices: [{name: "Headphones", address: "00:11:22:33:44:55",
                                connected: false, paired: false, trusted: false}]}});
                    root.scaleRows = [
                        launcher.createObject(settingsWindow.contentItem, {width: 700, index: 0,
                            selected: false, modelData: {name: "Application", generic: "Description", comment: "", primaryCategory: "Utility", icon: ""},
                            launcherModel: {categoryLabel: () => "Utility"}}),
                        wifi.createObject(settingsWindow.contentItem, {width: 700,
                            network: {ssid: "Network", security: "WPA2", signal: 80, device: "wlan0", active: false}})
                    ];
                }
                root.scrollFrames = 0;
                root.responseStage++;
            } else if (root.responseStage === 18) {
                const tiles = root.responseItems(root.scaleHealthWindow.contentItem,
                    item => item.objectName === "healthSummaryTile");
                root.responseCheck(tiles.length === 4, "Health summary renders four tiles");
                for (const tile of tiles) {
                    root.responseCheck(tile.x >= 0 && tile.x + tile.width <= tile.parent.width + 1,
                        "Health tiles wrap within the available width");
                    const labels = root.responseItems(tile, item => item.text !== undefined);
                    for (const label of labels) {
                        const point = label.mapToItem(tile, 0, 0);
                        root.responseCheck(point.x >= 0 && point.x + label.width <= tile.width
                            && label.contentWidth <= label.width + 1,
                            "Health summary label fits at 200 percent: " + label.text);
                    }
                    const caption = labels[0].mapToItem(tile, 0, 0);
                    const count = labels[1].mapToItem(tile, 0, 0);
                    root.responseCheck(caption.x + labels[0].width <= count.x,
                        "Health caption and count do not overlap");
                }
                root.scaleHealthWindow.destroy();
                const sections = root.responseItems(settingsWindow.contentItem,
                    item => item.selected !== undefined && item.modelData !== undefined
                        && item.modelData.id !== undefined);
                const bluetoothRows = root.responseItems(root.scaleBluetoothPane,
                    item => item.modelData !== undefined && item.modelData.address !== undefined);
                root.responseCheck(bluetoothRows.length > 0, "200 percent Bluetooth rows are rendered");
                const rows = root.scaleRows.concat(sections, bluetoothRows);
                root.responseCheck(root.scaleRows.every(item => item !== null) && sections.length > 0,
                    "200 percent row checks have rendered delegates");
                for (const row of rows) {
                    for (const text of root.responseItems(row, item => item.visible && item.text !== undefined)) {
                        const point = text.mapToItem(row, 0, 0);
                        root.responseCheck(point.y >= -1 && point.y + text.height <= row.height + 1,
                            "200 percent text fits its row: " + text.text);
                    }
                }
                const viewport = root.responseItems(root.scaleAudioPopup.contentItem,
                    item => item.objectName === "popupViewport")[0];
                root.responseCheck(viewport && viewport.height <= root.defaultPanelWindow.screen.height,
                    "Audio popup stays on screen at 200 percent");
                const card = root.responseItems(root.scaleAudioPopup.contentItem,
                    item => String(item).startsWith("ShellSurface"))[0];
                root.responseCheck(card !== undefined, "Audio popup card is rendered");
                for (const text of root.responseItems(card, item => item.visible && item.text !== undefined)) {
                    const point = text.mapToItem(card, 0, 0);
                    root.responseCheck(point.y >= -1 && point.y + text.height <= card.height + 1,
                        "200 percent audio controls fit inside the scrollable card: " + text.text);
                }
                // A popup taller than the screen is clamped to it and scrolls.
                const oversized = root.responseItems(root.scaleOversizedPopup.contentItem,
                    item => item.objectName === "popupViewport")[0];
                root.responseCheck(oversized && oversized.contentHeight > oversized.height
                    && oversized.height <= root.defaultPanelWindow.screen.height,
                    "Oversized popup stays on screen and scrolls");
                oversized.contentY = oversized.contentHeight - oversized.height;
                root.responseCheck(oversized.contentY > 0, "Oversized popup can scroll to its bottom");
                root.scaleOversizedPopup.destroy();
                const networkSurface = root.scaleNetworkPopup.popupContent.find(item => item.content !== undefined);
                const prompt = networkSurface.content.find(item => item.title === "dwm network password");
                root.responseCheck(prompt && prompt.visible && prompt.height <= prompt.screen.height,
                    "200 percent Wi-Fi prompt fits the screen");
                const passwordViewport = root.responseItems(prompt.contentItem,
                    item => item.objectName === "passwordViewport")[0];
                const connect = root.responseItems(prompt.contentItem, item => item.label === "Connect")[0];
                root.responseCheck(passwordViewport && connect,
                    "Wi-Fi prompt keeps its action controls");
                passwordViewport.contentY = Math.max(0, passwordViewport.contentHeight - passwordViewport.height);
                const actionPosition = connect.mapToItem(passwordViewport, 0, 0);
                root.responseCheck(actionPosition.y >= -1
                    && actionPosition.y + connect.height <= passwordViewport.height + 1,
                    "Wi-Fi Connect action is reachable at maximum scale");
                const notificationViewport = root.responseItems(root.scaleNotificationPopup.contentItem,
                    item => item.objectName === "notificationViewport")[0];
                root.responseCheck(root.scaleNotificationPopup.height + Theme.panelHeight
                    <= root.defaultPanelWindow.screen.height && notificationViewport.contentHeight > notificationViewport.height,
                    "Eight large notifications stay within the screen and scroll");
                notificationViewport.contentY = notificationViewport.contentHeight - notificationViewport.height;
                const lastCard = root.responseItems(root.scaleNotificationPopup.contentItem,
                    item => item.item !== undefined && item.item.key === 7)[0];
                const dismissText = root.responseItems(lastCard, item => item.text === "x")[0];
                const dismissPosition = dismissText.mapToItem(notificationViewport, 0, 0);
                root.responseCheck(dismissPosition.y >= -1
                    && dismissPosition.y + dismissText.height <= notificationViewport.height + 1,
                    "The final notification dismiss control is reachable");
                lastCard.dismiss();
                root.responseCheck(root.scaleNotificationDismissed === 7, "Final notification dismiss reaches its model");
                root.scaleNotificationPopup.destroy();
                root.scaleNetworkPopup.destroy();
                root.scaleAudioPopup.destroy();
                for (const row of root.scaleRows) row.destroy();
                root.scaleBluetoothPane.destroy();
                settingsModel.close();
                root.responseStage = 19;
            } else if (root.responseStage === 19) {
                // The loading gate has an upper bound: a pane whose reads never
                // finish is presented anyway once its cap passes. A fresh loader
                // is needed (every real pane has presented by now), held loading
                // for good and given a short cap of its own.
                const capComponent = Qt.createComponent("settings/DeferredSettingsPane.qml");
                root.capPane = capComponent.createObject(settingsWindow.contentItem, {
                    selected: true, windowVisible: true, dataLoading: true,
                    loadingTimeoutMs: 800, sourceComponent: capProbe});
                root.responseCheck(root.capPane !== null, "The loading-cap probe pane was created");
                root.capStarted = Date.now();
                root.responseStage = 20;
            } else if (root.responseStage === 20) {
                const pane = root.capPane;
                const elapsed = Date.now() - root.capStarted;
                if (!pane.presented) {
                    root.responseCheck(pane.item === null || (pane.item.opacity === 0 && !pane.item.enabled),
                        "A pane still loading stays hidden and disabled until its cap");
                    root.responseCheck(elapsed < 4000, "A pane whose reads never finish was never presented");
                    return;
                }
                root.responseCheck(elapsed >= 700, "The pane was presented before its cap: " + elapsed + " ms");
                root.responseCheck(pane.item !== null && pane.item.opacity === 1 && pane.item.enabled,
                    "The pane presented by its cap is visible and usable");
                pane.destroy();
                console.info("Settings responsiveness: PASS");
                Qt.quit();
            }
        }
    }
