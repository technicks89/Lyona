import QtQuick
import QtQuick.Layouts
import qs.core

/*
 * A provider-status row: label on the left, optional value on the right, and
 * a detail line underneath, framed in the status colour.
 *
 * Was an identical inline `component StatusCard` in both PowerSettingsPane and
 * AppearanceSettingsPane. The border and value take their colour from
 * Theme.statusColor(), so a pane no longer has to supply one.
 */
Rectangle {
    id: statusCard

    required property string label
    required property string statusState
    required property string detail
    property string value: ""

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(70, statusColumn.implicitHeight + Theme.spacingLg * 2)
    color: Theme.controlNormalFill
    border.color: Theme.statusColor(statusCard.statusState)
    border.width: Theme.controlBorderWidth
    radius: Theme.controlRadius

    ColumnLayout {
        id: statusColumn
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingXs

        RowLayout {
            Layout.fillWidth: true
            UiText {
                Layout.fillWidth: true
                text: statusCard.label
                color: Theme.controlNormalText
                font.bold: true
                elide: Text.ElideRight
            }
            UiText {
                visible: statusCard.value.length > 0
                text: statusCard.value
                color: Theme.statusColor(statusCard.statusState)
                font.bold: true
            }
        }
        UiText {
            Layout.fillWidth: true
            text: statusCard.detail
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }
    }
}
