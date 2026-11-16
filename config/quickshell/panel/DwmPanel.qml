import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

PanelWindow {
    id: root

    signal popupRequested(var panelWindow, string popupId)
    // Opens Settings on a section (Sync Sprint 15 S15-02: the update indicator).
    signal settingsRequested(var panelWindow, string sectionId)

    // Another panel popup opening closes the tray's menu.
    onPopupRequested: (panelWindow, popupId) => {
        if (popupId !== "tray" && trayLoader.item)
            trayLoader.item.closeMenu();
    }

    // The first item under the panel with this objectName, for the shell's test
    // IPC; undefined when there is none.
    function findItem(name) {
        const pending = [island];
        while (pending.length > 0) {
            const item = pending.shift();
            if (item.objectName === name) return item;
            for (const child of item.children || []) pending.push(child);
        }
        return undefined;
    }

    function batteryIcon(percent, status) {
        if (status.toLowerCase() === "charging") {
            return "󰂄";
        }

        if (percent >= 90) return "󰁹";
        if (percent >= 80) return "󰂂";
        if (percent >= 70) return "󰂁";
        if (percent >= 60) return "󰂀";
        if (percent >= 50) return "󰁿";
        if (percent >= 40) return "󰁾";
        if (percent >= 30) return "󰁽";
        if (percent >= 20) return "󰁼";
        if (percent >= 10) return "󰁻";
        return "󰂎";
    }

    required property var state
    required property var clock
    required property var networkModel
    required property var controlsModel
    required property var bluetoothModel
    // Optional: a harness without the calendar leaves the clock inert (S12-20).
    property var calendarModel: null
    property var weatherModel: null
    required property var controlCenterModel
    required property var panelSettingsModel
    required property var powerModel
    required property var powerMenuModel
    required property var updateModel
    required property bool primaryPanel
    // Null in a harness whose UpdateModel has no indicator (S15-02).
    readonly property var updateIndicator: root.updateModel ? root.updateModel.indicator : null
    // The keyboard pill's tooltip and accessible name (#534): the layout now
    // and the one a click switches to.
    readonly property string keyboardDescription: {
        const layouts = root.state.keyboardLayouts;
        const group = root.state.keyboardGroup;
        if (group < 0 || layouts.length < 2) return "Keyboard layout";
        return "Keyboard layout " + root.state.keyboardLabel + "; click to switch to "
            + layouts[(group + 1) % layouts.length];
    }

    // The panel's keyboard path (#534): Ctrl+Alt+Tab (lyona-shell panel
    // keyboard) moves the keyboard here. While keyboardMode is on the panel
    // says it takes input, and dwm gives it the keyboard when it asks; off,
    // it says it does not, and dwm hands the keyboard back to the window.
    property bool keyboardMode: false
    // The keyboard is on this panel now (not on a popup it opened).
    readonly property bool hasKeyboard: island.Window.active
    // A popup of this panel is open: the keyboard is on it, and comes back
    // here when it closes (dwm sees to that).
    readonly property bool popupOpen: root.networkModel.visible || root.controlsModel.visible
        || root.bluetoothModel.visible || root.controlCenterModel.visible
        || root.powerMenuModel.visible
        || (root.calendarModel !== null && root.calendarModel.visible)
        || (root.weatherModel !== null && root.weatherModel.visible)
        || (trayLoader.item !== null && trayLoader.item.menuOpen)
    // The objectName of the item with the keyboard, for the shell's test IPC.
    readonly property string keyboardItemName: island.Window.activeFocusItem
        ? island.Window.activeFocusItem.objectName : ""

    function toggleKeyboard() {
        if (root.keyboardMode && root.hasKeyboard)
            root.leaveKeyboard();
        else
            root.enterKeyboard();
    }

    // Starts on the first pill each time, as a new visit to the panel.
    function enterKeyboard() {
        root.keyboardMode = true;
        logoButton.forceActiveFocus();
        Qt.callLater(root.requestKeyboard);
    }

    function requestKeyboard() {
        const panelWindow = island.Window.window;
        if (root.keyboardMode && panelWindow)
            panelWindow.requestActivate();
    }

    function leaveKeyboard() {
        root.keyboardMode = false;
    }

    // Left and Right, as Shift+Tab and Tab: the pills are one row.
    function moveKeyboardFocus(forward) {
        const panelWindow = island.Window.window;
        const current = panelWindow ? panelWindow.activeFocusItem : null;
        if (!current) return;
        const next = current.nextItemInFocusChain(forward);
        if (next) next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }

    // The keyboard went somewhere other than a popup of this panel (a click
    // on a window, the launcher, a window that opened): the panel stops
    // taking it, so a later click on a pill does not move it here.
    onHasKeyboardChanged: if (!hasKeyboard && keyboardMode && !popupOpen) leaveKeyboard()
    // A popup opened from here closed: dwm gives the keyboard back to the
    // panel at once, unless something else took it (a click on a window).
    onPopupOpenChanged: if (!popupOpen && keyboardMode && !hasKeyboard) keyboardReturn.restart()

    Timer {
        id: keyboardReturn

        interval: 1000
        onTriggered: if (root.keyboardMode && !root.hasKeyboard && !root.popupOpen) root.leaveKeyboard()
    }

    focusable: keyboardMode
    implicitHeight: Theme.panelHeight
    color: Theme.barBackground
    // The panel's declaration that it is the bar: on X11 the exclusive zone
    // is the EWMH strut (_NET_WM_STRUT_PARTIAL), and dwm takes the dock that
    // reserves space for its bar, nothing else (#322). Keep it non-zero.
    exclusiveZone: Theme.panelHeight
    aboveWindows: root.state.fullscreenMonitorIndexes.indexOf(
        root.state.screenIndex(root.screen)) === -1

    anchors {
        top: true
        left: true
        right: true
    }

    Rectangle {
        id: island

        anchors.fill: parent
        anchors.leftMargin: Theme.panelEdgeMargin
        anchors.rightMargin: Theme.panelEdgeMargin
        anchors.topMargin: Theme.panelMargin
        anchors.bottomMargin: Theme.panelMargin
        opacity: 1.0
        color: Theme.barBackground
        border.color: Theme.border
        border.width: Theme.pillBorderWidth
        radius: Theme.barRadius

        PillShadow { cornerRadius: island.radius }

        // Keys a pill does not take itself, while the panel has the keyboard.
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.leaveKeyboard();
            } else if (event.key === Qt.Key_Right) {
                root.moveKeyboardFocus(true);
            } else if (event.key === Qt.Key_Left) {
                root.moveKeyboardFocus(false);
            } else if (event.key === Qt.Key_Home) {
                logoButton.forceActiveFocus(Qt.TabFocusReason);
            } else {
                return;
            }
            event.accepted = true;
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.popupRequested(root, "")
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.panelGap
            anchors.rightMargin: Theme.panelGap
            spacing: Theme.panelGap

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width)
                    height: parent.height
                    spacing: Theme.panelGap

                    LogoButton {
                        id: logoButton
                        objectName: "logoButton"
                        onActivated: {
                            root.popupRequested(root, "controlcenter");
                            root.controlCenterModel.toggle();
                        }
                    }

                    PanelPill {
                        visible: root.panelSettingsModel.widgetEnabled("workspaces")
                        Layout.preferredWidth: workspaceRow.implicitWidth + 8
                        Layout.preferredHeight: Theme.pillHeight
                        Accessible.role: Accessible.Grouping
                        Accessible.name: "Tags"

                        RowLayout {
                            id: workspaceRow

                            anchors.centerIn: parent
                            spacing: 1

                            Repeater {
                                model: root.state.workspaceIndexes(root.screen)

                                delegate: WorkspaceButton {
                                    required property int modelData

                                    objectName: "workspaceButton"
                                    label: root.state.workspaceNames[modelData]
                                    selected: modelData === root.state.currentWorkspaceForScreen(root.screen)
                                    occupied: root.state.workspaceOccupied(modelData)
                                    onClicked: root.state.switchWorkspaceForScreen(root.screen, modelData)
                                }
                            }
                        }
                    }

                    PanelPill {
                        Layout.preferredWidth: Math.min(activeTitle.implicitWidth + Theme.pillHorizontalPadding * 2, 260)
                        Layout.preferredHeight: Theme.pillHeight
                        outlined: true
                        Accessible.role: Accessible.StaticText
                        Accessible.name: "Window: " + root.state.titleForScreen(root.screen)

                        // A title too long for the pill scrolls once when it
                        // changes, then rests elided (#499).
                        ScrollingTitle {
                            id: activeTitle
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pillHorizontalPadding
                            anchors.rightMargin: Theme.pillHorizontalPadding
                            text: root.state.titleForScreen(root.screen)
                            // A title that keeps changing in one window scrolls
                            // at most every 30 s; a new window scrolls (#532).
                            key: root.state.monitorWindows[root.state.screenIndex(root.screen)] || root.state.activeWindowId
                            color: Theme.text
                        }
                    }

                }
            }

            PanelPill {
                id: clockPill

                Layout.preferredWidth: clockLabel.implicitWidth + Theme.pillHorizontalPadding * 2
                Layout.preferredHeight: Theme.pillHeight
                outlined: true
                active: root.calendarModel !== null && root.calendarModel.visible
                hovered: clockMouse.containsMouse
                // Named for screen readers, which can press it (#534).
                keyboardActivatable: clockMouse.enabled
                Accessible.role: clockMouse.enabled ? Accessible.Button : Accessible.StaticText
                Accessible.name: root.clock.panelText + (clockMouse.enabled ? ", calendar" : "")
                Accessible.onPressAction: clockPill.openCalendar()
                onTriggered: clockPill.openCalendar()

                function openCalendar() {
                    if (!clockMouse.enabled) return;
                    root.popupRequested(root, "calendar");
                    root.calendarModel.toggle(clockPill.mapToItem(null, 0, 0).x);
                }

                UiText {
                    id: clockLabel

                    anchors.centerIn: parent
                    text: root.clock.panelText
                    color: Theme.textStrong
                    font.bold: true
                }

                // The clock opens the month calendar (Sync Sprint 12 S12-20), when
                // its Bar Widgets switch is on; otherwise it does nothing, as before.
                MouseArea {
                    id: clockMouse

                    anchors.fill: parent
                    enabled: root.calendarModel !== null && root.panelSettingsModel.widgetEnabled("calendar")
                    hoverEnabled: enabled
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: clockPill.openCalendar()
                }
            }

            // The weather (Sync Sprint 12 S12-20), shown only when its Bar Widgets
            // switch is on, which it is not until the user turns it on (D-19).
            PanelPill {
                id: weatherPill

                visible: root.weatherModel !== null && root.weatherModel.enabled
                Layout.preferredWidth: weatherLabel.implicitWidth + Theme.pillHorizontalPadding * 2
                Layout.preferredHeight: Theme.pillHeight
                outlined: true
                active: root.weatherModel !== null && root.weatherModel.visible
                hovered: weatherMouse.containsMouse
                Accessible.role: Accessible.Button
                Accessible.name: "Weather: " + (root.weatherModel ? root.weatherModel.panelText : "")
                Accessible.onPressAction: weatherPill.openWeather()
                keyboardActivatable: true
                onTriggered: weatherPill.openWeather()

                function openWeather() {
                    root.popupRequested(root, "weather");
                    root.weatherModel.toggle(weatherPill.mapToItem(null, 0, 0).x);
                }

                UiText {
                    id: weatherLabel

                    anchors.centerIn: parent
                    text: root.weatherModel ? root.weatherModel.panelText : ""
                    // Subdued while it shows the last good report (#480).
                    color: root.weatherModel && root.weatherModel.stale ? Theme.textMuted : Theme.textStrong
                }

                MouseArea {
                    id: weatherMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: weatherPill.openWeather()
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.panelGap

                    Item { Layout.fillWidth: true }

                    Repeater {
                        model: root.state.statusSegments

                        delegate: PanelPill {
                            required property string modelData
                            Layout.preferredWidth: statusLabel.implicitWidth + Theme.pillHorizontalPadding * 2
                            Layout.preferredHeight: Theme.pillHeight
                            outlined: true

                            UiText {
                                id: statusLabel
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: Theme.text
                            }
                        }
                    }

                    RunningAppsArea { state: root.state }

                    Loader {
                        id: trayLoader

                        active: root.primaryPanel
                        sourceComponent: TrayArea {
                            panelWindow: root
                            runningApps: root.state.runningApps
                            // Close the panel's other popups, as their buttons do.
                            onMenuOpened: root.popupRequested(root, "tray")
                        }
                    }

                    PanelPill {
                        id: batteryPill
                        visible: root.powerModel.batteryAvailable
                        Layout.preferredWidth: batteryRow.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        hovered: batteryMouse.containsMouse
                        Accessible.role: Accessible.StaticText
                        Accessible.name: "Battery " + root.powerModel.batteryPercent.toString() + "%, " + root.powerModel.batteryStatus

                        RowLayout {
                            id: batteryRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: root.batteryIcon(root.powerModel.batteryPercent, root.powerModel.batteryStatus)
                                color: Theme.textStrong
                                font.pixelSize: Theme.scaledFontSize(14 * 1.1, 8)
                            }

                            UiText {
                                text: root.powerModel.batteryPercent.toString() + "%"
                                color: Theme.textStrong
                                font.pixelSize: Theme.panelFontSize
                            }
                        }

                        MouseArea {
                            id: batteryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }

                    // Updates are available (Sync Sprint 15 S15-02, decision D-25): a
                    // count, and a click opens Settings > System, where they are run.
                    // Hidden when everything is current, unless the user asks for it.
                    PanelPill {
                        id: updateAvailablePill
                        objectName: "updateAvailablePill"
                        visible: root.updateIndicator !== null && root.updateIndicator.shown
                        Layout.preferredWidth: updateAvailableRow.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        hovered: updateAvailableMouse.containsMouse
                        Accessible.role: Accessible.Button
                        Accessible.name: root.updateIndicator ? root.updateIndicator.summary : ""
                        Accessible.onPressAction: root.settingsRequested(root, "system")
                        keyboardActivatable: true
                        onTriggered: root.settingsRequested(root, "system")

                        RowLayout {
                            id: updateAvailableRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: "󰚰"
                                color: root.updateIndicator && root.updateIndicator.count > 0
                                    ? Theme.accent : Theme.textStrong
                            }

                            UiText {
                                visible: root.updateIndicator !== null && root.updateIndicator.count > 0
                                text: root.updateIndicator ? root.updateIndicator.count.toString() : ""
                                color: Theme.textStrong
                                font.pixelSize: Theme.panelFontSize
                            }
                        }

                        MouseArea {
                            id: updateAvailableMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.settingsRequested(root, "system")
                        }
                    }

                    // Shown while lyona-update runs, and briefly after it ends, so a
                    // hidden progress popup (or one closed by the Quickshell restart an
                    // apply causes) can always be brought back with a click.
                    PanelPill {
                        id: updatePill
                        objectName: "updatePill"
                        visible: root.updateModel.progressShown
                        Layout.preferredWidth: updateRow.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        active: root.updateModel.busy
                        hovered: updateMouse.containsMouse
                        Accessible.role: Accessible.Button
                        Accessible.onPressAction: root.updateModel.showProgress()
                        keyboardActivatable: true
                        onTriggered: root.updateModel.showProgress()
                        Accessible.name: root.updateModel.busy ? "Update in progress"
                            : root.updateModel.actionSucceeded ? "Update finished" : "Update failed"

                        RowLayout {
                            id: updateRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: "󰚰"
                                color: root.updateModel.busy ? Theme.accent
                                    : root.updateModel.actionSucceeded ? Theme.success : Theme.danger
                            }
                        }

                        MouseArea {
                            id: updateMouse
                            objectName: "updatePillArea"
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.updateModel.showProgress()
                        }
                    }

                    // The keyboard layout (#470, upstream dwm-titus #384), with two
                    // or more: a click switches to the next one.
                    PanelPill {
                        id: keyboardPill
                        objectName: "keyboardLayoutPill"
                        visible: root.panelSettingsModel.widgetEnabled("keyboard")
                            && root.state.keyboardLayouts.length >= 2
                            && root.state.keyboardLabel.length > 0
                        Layout.preferredWidth: keyboardLabel.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        hovered: keyboardMouse.containsMouse
                        Accessible.role: Accessible.Button
                        Accessible.name: root.keyboardDescription
                        Accessible.onPressAction: root.state.nextKeyboardLayout()
                        keyboardActivatable: true
                        onTriggered: root.state.nextKeyboardLayout()

                        UiText {
                            id: keyboardLabel
                            anchors.centerIn: parent
                            text: root.state.keyboardLabel
                            color: Theme.textStrong
                            font.bold: true
                        }

                        MouseArea {
                            id: keyboardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.state.nextKeyboardLayout()
                        }
                    }

                    PanelPill {
                        id: bluetoothPill
                        visible: root.panelSettingsModel.widgetEnabled("bluetooth")
                        Layout.preferredWidth: bluetoothRow.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        active: root.bluetoothModel.visible
                        hovered: bluetoothMouse.containsMouse
                        Accessible.role: Accessible.Button
                        Accessible.name: "Bluetooth: " + root.bluetoothModel.statusText
                        Accessible.onPressAction: bluetoothPill.openBluetooth()
                        keyboardActivatable: true
                        onTriggered: bluetoothPill.openBluetooth()

                        function openBluetooth() {
                            root.popupRequested(root, "bluetooth");
                            root.bluetoothModel.toggle();
                        }

                        RowLayout {
                            id: bluetoothRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: "󰂯"
                                color: Theme.textStrong
                                font.pixelSize: Theme.scaledFontSize(14 * 0.9, 8)
                            }
                        }

                        MouseArea {
                            id: bluetoothMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bluetoothPill.openBluetooth()
                        }
                    }

                    PanelPill {
                        id: networkPill
                        visible: root.panelSettingsModel.widgetEnabled("network")
                        Layout.preferredWidth: networkRow.implicitWidth + Theme.networkWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        active: root.networkModel.visible
                        hovered: networkMouse.containsMouse
                        Accessible.role: Accessible.Button
                        Accessible.name: "Network: " + root.networkModel.statusText
                        Accessible.onPressAction: networkPill.openNetwork()
                        keyboardActivatable: true
                        onTriggered: networkPill.openNetwork()

                        function openNetwork() {
                            root.popupRequested(root, "network");
                            root.networkModel.toggle();
                        }

                        RowLayout {
                            id: networkRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                // Unavailable too when the text names the missing
                                // service, "NetworkManager not installed" (#292).
                                text: root.networkModel.providerState === "unavailable"
                                    || root.networkModel.statusText.indexOf("offline") >= 0
                                    || root.networkModel.statusText.indexOf("unavailable") >= 0 ? "󰤭" : "󰤨"
                                color: Theme.textStrong
                                font.pixelSize: Theme.scaledFontSize(14 * 1.2, 8)
                            }
                        }

                        MouseArea {
                            id: networkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: networkPill.openNetwork()
                        }
                    }

                    PanelPill {
                        id: volumePill
                        visible: root.panelSettingsModel.widgetEnabled("volume")
                        Layout.preferredWidth: volumeRow.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        active: root.controlsModel.visible
                        hovered: controlsMouse.containsMouse
                        Accessible.role: Accessible.Button
                        Accessible.name: "Volume: " + root.controlsModel.volumeDisplayText
                        Accessible.onPressAction: volumePill.openControls()
                        keyboardActivatable: true
                        onTriggered: volumePill.openControls()
                        // Up and Down change the volume, as the wheel does.
                        Keys.onUpPressed: root.controlsModel.volumeUp()
                        Keys.onDownPressed: root.controlsModel.volumeDown()

                        function openControls() {
                            root.popupRequested(root, "controls");
                            root.controlsModel.toggle();
                        }

                        RowLayout {
                            id: volumeRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: root.controlsModel.volumeMuted ? "󰝟" : "󰕾"
                                color: Theme.textStrong
                                font.pixelSize: Theme.scaledFontSize(14 * 1.5, 8)
                            }

                            UiText {
                                visible: root.controlsModel.volumeText !== "VOL unavailable"
                                text: root.controlsModel.volumePercent.toString() + "%"
                                color: Theme.textStrong
                                font.pixelSize: Theme.panelFontSize
                            }
                        }

                        MouseArea {
                            id: controlsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: volumePill.openControls()
                            onWheel: function(wheel) {
                                if (wheel.angleDelta.y > 0) {
                                    root.controlsModel.volumeUp();
                                } else if (wheel.angleDelta.y < 0) {
                                    root.controlsModel.volumeDown();
                                }
                                wheel.accepted = true;
                            }
                        }
                    }

                    PanelPill {
                        id: powerPill
                        objectName: "powerPill"
                        visible: root.panelSettingsModel.widgetEnabled("power")
                        Layout.preferredWidth: Theme.pillHeight
                        Layout.preferredHeight: Theme.pillHeight
                        active: root.powerMenuModel.visible
                        hovered: powerMouse.containsMouse
                        Accessible.role: Accessible.Button
                        Accessible.name: "Power menu"
                        Accessible.onPressAction: powerPill.openPower()
                        keyboardActivatable: true
                        onTriggered: powerPill.openPower()

                        function openPower() {
                            root.popupRequested(root, "power");
                            root.powerMenuModel.toggle("panel");
                        }

                        IconText {
                            anchors.centerIn: parent
                            text: "󰐥"
                            color: Theme.textStrong
                            font.pixelSize: Theme.scaledFontSize(14 * 1.08, 8)
                        }

                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: powerPill.openPower()
                        }
                    }
                }
            }
        }
    }

    PanelTooltip {
        visible: logoButton.hovered || logoButton.activeFocus
        anchorWindow: root
        anchorItem: logoButton
        label: "Control Center"
        anchorY: Theme.panelHeight
    }

    PanelTooltip {
        visible: root.powerModel.batteryAvailable && batteryMouse.containsMouse
        anchorWindow: root
        anchorItem: batteryPill
        label: root.powerModel.batteryPercent.toString() + "% - " + root.powerModel.batteryStatus
        anchorY: Theme.panelHeight
        rightAligned: true
    }

    PanelTooltip {
        visible: updateAvailablePill.visible && (updateAvailableMouse.containsMouse || updateAvailablePill.activeFocus)
        anchorWindow: root
        anchorItem: updateAvailableMouse
        label: root.updateIndicator ? root.updateIndicator.summary : ""
        anchorY: Theme.panelHeight
        rightAligned: true
    }

    PanelTooltip {
        visible: bluetoothMouse.containsMouse || bluetoothPill.activeFocus
        anchorWindow: root
        anchorItem: bluetoothMouse
        label: root.bluetoothModel.statusText
        anchorY: Theme.panelHeight
        rightAligned: true
    }

    PanelTooltip {
        visible: networkMouse.containsMouse || networkPill.activeFocus
        anchorWindow: root
        anchorItem: networkMouse
        label: root.networkModel.statusText
        anchorY: Theme.panelHeight
        rightAligned: true
    }

    PanelTooltip {
        visible: controlsMouse.containsMouse || volumePill.activeFocus
        anchorWindow: root
        anchorItem: controlsMouse
        label: root.controlsModel.volumeDisplayText
        anchorY: Theme.panelHeight
        rightAligned: true
    }

    PanelTooltip {
        visible: keyboardPill.visible && (keyboardMouse.containsMouse || keyboardPill.activeFocus)
        anchorWindow: root
        anchorItem: keyboardMouse
        label: root.keyboardDescription
        anchorY: Theme.panelHeight
        rightAligned: true
    }

    PanelTooltip {
        visible: powerMouse.containsMouse || powerPill.activeFocus
        anchorWindow: root
        anchorItem: powerMouse
        label: "Power"
        anchorY: Theme.panelHeight
        rightAligned: true
    }
}
