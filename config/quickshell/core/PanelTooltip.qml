import QtQuick
import Quickshell
import qs.core
import "PanelTooltipPosition.js" as TooltipPosition

PopupWindow {
    id: root

    required property var anchorWindow
    required property var anchorItem
    property string label: ""
    property real anchorX: 0
    property real anchorY: 0
    property bool rightAligned: false
    readonly property real tooltipWidth: tooltipLabel.implicitWidth + Theme.pillHorizontalPadding * 2

    implicitWidth: root.tooltipWidth
    implicitHeight: Theme.pillHeight
    color: Theme.transparent
    mask: Region {}

    anchor.window: root.anchorWindow
    // A live binding, not only set from onAnchoring: it must stay correct if the
    // anchor window's width changes (a DPI change, a monitor hot-plug) between
    // anchoring passes, not just clip until the next one happens to run.
    anchor.rect.x: TooltipPosition.clampedX(root.anchorWindow.width, root.width, root.anchorX, root.rightAligned)
    anchor.rect.y: root.anchorY
    anchor.edges: Edges.Left | Edges.Top
    anchor.gravity: Edges.Right | Edges.Bottom
    anchor.onAnchoring: {
        const edge = root.rightAligned ? root.anchorItem.width : root.anchorItem.width / 2;
        const point = root.anchorItem.mapToGlobal(edge, 0);
        const screenX = root.anchorWindow.screen && root.anchorWindow.screen.x !== undefined
            ? root.anchorWindow.screen.x : 0;
        root.anchorX = point.x - screenX;
    }

    PanelPill {
        anchors.fill: parent

        UiText {
            id: tooltipLabel

            anchors.centerIn: parent
            text: root.label
            color: Theme.textStrong
            font.pixelSize: Theme.smallFontSize
        }
    }
}
