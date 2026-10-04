import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

// The panel weather's popup (Sync Sprint 12 S12-20): the current conditions, or
// why there are none. Until the weather shows, the location can be set here as
// well as in Settings, Appearance, where the units are.
ClickAwayPopup {
    id: root

    required property var weatherModel
    required property var panelWindow

    // The location field, for a weather not yet set or not found.
    readonly property bool askLocation: weatherModel.weatherState !== "available"
        && weatherModel.weatherState !== "loading"
    readonly property int cardWidth: Theme.dp(320)
    readonly property int cardHeight: Theme.dp(190)
        + (askLocation ? Theme.controlHeight + Theme.spacingMd + Theme.dp(24) : 0)
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

            RowLayout {
                Layout.fillWidth: true
                visible: root.askLocation

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Theme.controlHeight, locationInput.implicitHeight + 12)
                    color: Theme.controlNormalFill
                    border.color: locationInput.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                    border.width: Theme.controlBorderWidth
                    radius: Theme.controlRadius

                    TextInput {
                        id: locationInput

                        anchors.fill: parent
                        anchors.margins: 6
                        text: root.weatherModel.location
                        color: Theme.textStrong
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.inputFontSize
                        maximumLength: 100
                        clip: true
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Weather location"
                        onAccepted: root.weatherModel.setLocation(text)
                    }

                    UiText {
                        anchors.fill: parent
                        anchors.margins: 6
                        visible: locationInput.text.length === 0 && !locationInput.activeFocus
                        text: "City, for example Berlin"
                        color: Theme.menuMutedText
                    }
                }

                ShellButton {
                    label: "Set location"
                    enabled: !root.weatherModel.busy && locationInput.text.trim().length > 0
                    onActivated: root.weatherModel.setLocation(locationInput.text)
                }
            }

            UiText {
                Layout.fillWidth: true
                visible: root.askLocation && root.weatherModel.message.length > 0
                text: root.weatherModel.message
                color: Theme.menuMutedText
                font.pixelSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
            }

            Item {
                Layout.fillHeight: true
            }

            UiText {
                Layout.fillWidth: true
                text: "Weather from Open-Meteo. Units are in Settings, Appearance."
                color: Theme.menuMutedText
                font.pixelSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
            }
        }
    }
}
