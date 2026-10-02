import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

// The panel weather's popup (Sync Sprint 12 S12-20): the current conditions, or
// why there are none. The location and units are set in Settings, Appearance.
ClickAwayPopup {
    id: root

    required property var weatherModel
    required property var panelWindow

    readonly property int cardWidth: Theme.dp(320)
    readonly property int cardHeight: Theme.dp(190)
    readonly property int edgeMargin: Theme.rowSpacing

    visible: panelWindow !== null && panelWindow.screen !== null && weatherModel.visible
    targetWindow: panelWindow
    popupWidth: cardWidth
    popupHeight: cardHeight
    popupX: panelWindow
        ? Math.max(edgeMargin, Math.min(weatherModel.anchorX, panelWindow.width - cardWidth - edgeMargin))
        : edgeMargin
    popupY: Theme.panelHeight
    onDismissed: weatherModel.close()

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(function() {
                content.forceActiveFocus();
            });
        }
    }

    ShellSurface {
        id: content

        anchors.fill: parent
        focus: true
        Accessible.role: Accessible.Pane
        Accessible.name: "Weather"

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.weatherModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.popupPadding
            spacing: Theme.spacingMd

            UiText {
                Layout.fillWidth: true
                text: root.weatherModel.weatherState === "available" ? root.weatherModel.place : "Weather"
                color: Theme.popupText
                font.bold: true
                font.pixelSize: Theme.titleFontSize
                elide: Text.ElideRight
            }

            UiText {
                Layout.fillWidth: true
                visible: root.weatherModel.weatherState === "available"
                text: root.weatherModel.panelText + "  " + root.weatherModel.description
                color: Theme.popupText
                font.pixelSize: Theme.titleFontSize
            }

            UiText {
                Layout.fillWidth: true
                visible: root.weatherModel.weatherState === "available"
                text: "Observed " + root.weatherModel.observed.replace("T", " ")
                color: Theme.menuMutedText
                font.pixelSize: Theme.smallFontSize
            }

            UiText {
                Layout.fillWidth: true
                visible: root.weatherModel.weatherState !== "available"
                text: root.weatherModel.weatherState === "loading" ? "Loading..." : root.weatherModel.detail
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }

            Item {
                Layout.fillHeight: true
            }

            UiText {
                Layout.fillWidth: true
                text: "Weather from Open-Meteo. Set the location in Settings, Appearance."
                color: Theme.menuMutedText
                font.pixelSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
            }
        }
    }
}
