import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

// The clock's month calendar (Sync Sprint 12 S12-20), on the same click-away
// pattern as the network and Bluetooth popups. Arrows move a day or a week,
// Page Up and Page Down a month, Home returns to today, and Escape closes.
ClickAwayPopup {
    id: root

    required property var calendarModel
    required property var panelWindow

    readonly property int cellSize: Theme.dp(40)
    readonly property int cardWidth: root.cellSize * 7 + Theme.popupPadding * 2
    readonly property int cardHeight: Theme.dp(380)
    readonly property int edgeMargin: Theme.rowSpacing

    visible: panelWindow !== null && panelWindow.screen !== null && calendarModel.visible
    targetWindow: panelWindow
    popupWidth: cardWidth
    popupHeight: cardHeight
    popupX: panelWindow
        ? Math.max(edgeMargin, Math.min(calendarModel.anchorX, panelWindow.width - cardWidth - edgeMargin))
        : edgeMargin
    popupY: Theme.panelHeight
    onDismissed: calendarModel.close()

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
        Accessible.name: "Calendar, " + root.calendarModel.title

        Keys.onPressed: function(event) {
            const model = root.calendarModel;
            if (event.key === Qt.Key_Escape) model.close();
            else if (event.key === Qt.Key_Left) model.moveDays(-1);
            else if (event.key === Qt.Key_Right) model.moveDays(1);
            else if (event.key === Qt.Key_Up) model.moveDays(-7);
            else if (event.key === Qt.Key_Down) model.moveDays(7);
            else if (event.key === Qt.Key_PageUp) model.moveMonth(-1);
            else if (event.key === Qt.Key_PageDown) model.moveMonth(1);
            else if (event.key === Qt.Key_Home) model.goToday();
            else return;
            event.accepted = true;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.popupPadding
            spacing: Theme.spacingMd

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                ShellButton {
                    label: "<"
                    accessibleDescription: "Previous month"
                    onActivated: root.calendarModel.moveMonth(-1)
                }

                UiText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.calendarModel.title
                    color: Theme.popupText
                    font.bold: true
                    font.pixelSize: Theme.titleFontSize
                }

                ShellButton {
                    label: ">"
                    accessibleDescription: "Next month"
                    onActivated: root.calendarModel.moveMonth(1)
                }

                ShellButton {
                    label: "Today"
                    onActivated: root.calendarModel.goToday()
                }
            }

            GridLayout {
                Layout.alignment: Qt.AlignHCenter
                columns: 7
                rowSpacing: 0
                columnSpacing: 0

                Repeater {
                    model: root.calendarModel.weekdays

                    delegate: UiText {
                        required property string modelData

                        Layout.preferredWidth: root.cellSize
                        Layout.preferredHeight: Theme.dp(24)
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.menuMutedText
                        font.pixelSize: Theme.smallFontSize
                    }
                }

                Repeater {
                    model: root.calendarModel.cells

                    delegate: Rectangle {
                        id: dayCell

                        required property var modelData
                        required property int index

                        Layout.preferredWidth: root.cellSize
                        Layout.preferredHeight: root.cellSize
                        color: modelData.selected ? Theme.controlSelectedFill
                            : dayMouse.containsMouse ? Theme.menuHoverBackground : Theme.transparent
                        border.width: modelData.today ? Theme.controlFocusBorderWidth : 0
                        border.color: Theme.accent
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label + (modelData.today ? ", today" : "")

                        UiText {
                            anchors.centerIn: parent
                            text: String(dayCell.modelData.day)
                            color: dayCell.modelData.selected ? Theme.controlSelectedText
                                : dayCell.modelData.inMonth ? Theme.popupText : Theme.menuMutedText
                            font.bold: dayCell.modelData.today
                        }

                        MouseArea {
                            id: dayMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.calendarModel.selectCell(dayCell.index)
                        }
                    }
                }
            }
        }
    }
}
