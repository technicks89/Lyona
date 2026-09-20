import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

PopupWindow {
    id: root

    required property var notificationModel
    required property var panelWindow

    readonly property int popupWidth: Math.min(Theme.dp(400),
        panelWindow ? Math.max(1, panelWindow.width - edgeMargin * 2) : Theme.dp(400))
    readonly property int edgeMargin: Theme.rowSpacing

    visible: panelWindow !== null && panelWindow.screen !== null
        && notificationModel.notifications.length > 0
    implicitWidth: popupWidth
    // Cap the stack at the space below the panel so a burst of notifications
    // (or large text) scrolls instead of running off the screen.
    readonly property int maxStackHeight: panelWindow && panelWindow.screen
        ? Math.max(0, panelWindow.screen.height - Theme.panelHeight - edgeMargin * 2)
        : 0
    implicitHeight: Math.min(notificationsColumn.implicitHeight, maxStackHeight)
    anchor.window: panelWindow
    anchor.rect.x: panelWindow
        ? Math.max(edgeMargin, panelWindow.width - popupWidth - edgeMargin)
        : edgeMargin
    anchor.rect.y: Theme.panelHeight
    color: Theme.transparent

    Flickable {
        id: viewport
        objectName: "notificationViewport"
        anchors.fill: parent
        contentWidth: width
        contentHeight: notificationsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        onVisibleChanged: if (visible) contentY = 0

        ColumnLayout {
            id: notificationsColumn

            width: parent.width
            opacity: 1.0
            spacing: Theme.spacingLg

            Repeater {
                model: root.notificationModel.notifications

                delegate: NotificationCard {
                    id: notificationCard

                    required property var modelData

                    item: notificationCard.modelData
                    onDismiss: root.notificationModel.dismiss(notificationCard.modelData.key)
                    onExpired: root.notificationModel.expire(notificationCard.modelData.key)
                }
            }
        }
    }
}
