import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.core

pragma ComponentBehavior: Bound

Rectangle {
    id: root

    required property var item

    signal dismiss
    signal expired
    signal actionInvoked(string identifier)

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(Theme.dp(82), content.implicitHeight + Theme.dp(28))

    opacity: 1.0
    radius: Theme.popupRadius
    color: item.urgency === NotificationUrgency.Critical ? Theme.dangerSurface : Theme.surface
    border.color: item.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.popupBorder
    border.width: Theme.controlBorderWidth

    // No timeout for a notification with buttons (timeoutMs 0).
    Timer {
        interval: root.item.timeoutMs
        running: root.item.timeoutMs > 0
        repeat: false
        onTriggered: root.expired()
    }

    RowLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Theme.dp(14)
        spacing: Theme.spacingXxl

        Rectangle {
            Layout.preferredWidth: Theme.notificationAccentWidth
            Layout.fillHeight: true
            radius: Theme.notificationAccentRadius
            color: root.item.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.accent
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.tightSpacing

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.item.appName
                color: root.item.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.menuActionText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontCaptionSize
                font.bold: true
                font.letterSpacing: 0.6
                elide: Text.ElideRight
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.item.summary || root.item.urgencyName
                color: Theme.popupText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodyFontSize
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.item.body || ""
                color: Theme.menuText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Theme.tightSpacing
                visible: (root.item.actions || []).length > 0
                spacing: Theme.tightSpacing

                Repeater {
                    model: root.item.actions || []

                    delegate: ShellButton {
                        id: actionButton

                        required property var modelData

                        label: actionButton.modelData.text
                        onActivated: root.actionInvoked(actionButton.modelData.identifier)
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: Theme.closeButtonSize - Theme.listSpacing
            Layout.preferredHeight: Theme.closeButtonSize - Theme.listSpacing
            radius: Theme.controlRadius
            color: closeMouse.containsMouse ? Theme.controlHoverFill : Theme.transparent
            border.color: closeMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
            border.width: Theme.controlBorderWidth

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "x"
                color: closeMouse.containsMouse ? Theme.controlHoverText : Theme.menuMutedText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                font.bold: true
            }

            MouseArea {
                id: closeMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismiss()
            }
        }
    }
}
