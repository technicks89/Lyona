import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

/*
 * Read-only view of the last 64 KiB of the log lyona-update writes for apply
 * and rollback (UpdateModel.logText). Shared by the progress popup and the
 * Settings update card, so a failed update can be read in either place, and
 * after the Quickshell restart that an apply causes has taken the model's
 * in-memory copy of the output with it.
 */
Rectangle {
    id: root

    required property var model
    property int viewHeight: Theme.dp(220)

    readonly property string notice: {
        switch (root.model.logState) {
        case "ready": return "";
        case "empty": return "The update log is empty.";
        case "unavailable": return "No update log yet. It is written the next time an update or rollback runs.";
        default: return "Loading the update log...";
        }
    }

    Layout.fillWidth: true
    implicitHeight: root.viewHeight
    color: Theme.controlNormalFill
    border.color: Theme.controlNormalBorder
    border.width: Theme.controlBorderWidth
    radius: Theme.radius
    Accessible.name: "Update log"

    function refresh() {
        if (root.visible) root.model.refreshLog();
    }

    onVisibleChanged: root.refresh()
    Component.onCompleted: root.refresh()

    // A running update appends to the log; follow it while the view is open.
    Connections {
        target: root.model

        function onPhaseChanged() { root.refresh(); }
        function onProgressDetailChanged() { root.refresh(); }
        function onBusyChanged() { root.refresh(); }
    }

    Flickable {
        id: flick

        // Follow the tail while it grows, unless the person scrolled up to read.
        property bool followTail: true

        anchors.fill: parent
        anchors.margins: Theme.spacingMd
        contentWidth: width
        contentHeight: logBody.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        onContentHeightChanged: if (flick.followTail) flick.contentY = Math.max(0, flick.contentHeight - flick.height)
        onMovementEnded: flick.followTail = flick.contentY + flick.height >= flick.contentHeight - 2

        TextEdit {
            id: logBody

            objectName: "updateLogBody"
            width: flick.width
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: root.notice.length > 0 ? Theme.textMuted : Theme.textStrong
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            text: root.notice.length > 0
                ? root.notice
                : (root.model.logTruncated ? "... earlier output omitted ...\n" : "") + root.model.logText
        }
    }
}
