import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

/*
 * Progress for lyona-update, visible outside Settings. An apply restarts
 * Quickshell part way through, so the shell that starts up afterwards reads
 * the status file (UpdateModel) and shows this again, still in progress or
 * with the outcome. It is a popup anchored under the panel, like the
 * notification stack, so it needs no window rule and never takes focus; it is
 * centered so it stays clear of the notifications on the right and the
 * Control Center on the left.
 */
PopupWindow {
    id: root

    required property var updateModel
    required property var panelWindow

    property bool showLog: false

    readonly property int edgeMargin: Theme.rowSpacing
    readonly property int popupWidth: Math.min(Theme.dp(460),
        panelWindow ? Math.max(1, panelWindow.width - edgeMargin * 2) : Theme.dp(460))
    readonly property int maxHeight: panelWindow && panelWindow.screen
        ? Math.max(0, panelWindow.screen.height - Theme.panelHeight - edgeMargin * 2) : 0
    readonly property bool failed: !root.updateModel.busy && !root.updateModel.actionSucceeded

    function phaseLabel(phase) {
        switch (phase) {
        case "checking": return "Checking for the release";
        case "downloading": return "Downloading the release";
        case "verifying": return "Verifying the download";
        case "building": return "Building";
        case "installing": return "Installing (you may be asked to authenticate)";
        case "verifying-install": return "Verifying the installed files";
        case "restarting": return "Restarting the desktop shell";
        default: return "Working";
        }
    }

    visible: panelWindow !== null && panelWindow.screen !== null
        && updateModel.progressShown && !updateModel.popupClosed
    implicitWidth: popupWidth
    implicitHeight: Math.min(card.implicitHeight, maxHeight)
    anchor.window: panelWindow
    anchor.rect.x: panelWindow ? Math.max(edgeMargin, (panelWindow.width - popupWidth) / 2) : edgeMargin
    anchor.rect.y: Theme.panelHeight
    color: Theme.transparent

    ShellSurface {
        id: card

        anchors.fill: parent
        implicitHeight: content.implicitHeight + margin * 2

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Theme.spacingLg

            UiText {
                Layout.fillWidth: true
                text: root.updateModel.busy ? "Updating Lyona"
                    : root.updateModel.actionSucceeded ? root.updateModel.message : "The update did not finish"
                color: root.failed ? Theme.danger : Theme.textStrong
                font.pixelSize: Theme.titleFontSize
                font.bold: true
                elide: Text.ElideRight
            }

            UiText {
                Layout.fillWidth: true
                text: root.updateModel.busy ? root.phaseLabel(root.updateModel.phase)
                    : (root.failed ? root.updateModel.message : "")
                visible: text.length > 0
                color: Theme.menuText
                wrapMode: Text.WordWrap
            }

            UiText {
                Layout.fillWidth: true
                visible: root.updateModel.busy && root.updateModel.progressDetail.length > 0
                text: root.updateModel.progressDetail
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }

            // Indeterminate: the release tooling reports phases, not percentages.
            Rectangle {
                id: track

                Layout.fillWidth: true
                Layout.preferredHeight: Theme.dp(4)
                visible: root.updateModel.busy
                radius: height / 2
                color: Theme.controlNormalFill
                clip: true

                Rectangle {
                    id: sweep

                    width: Theme.reducedMotion ? track.width : track.width * 0.3
                    height: track.height
                    radius: height / 2
                    color: Theme.accent

                    SequentialAnimation on x {
                        running: track.visible && !Theme.reducedMotion
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: -sweep.width
                            to: track.width
                            duration: 1400
                        }
                    }
                }
            }

            UpdateLogView {
                Layout.fillWidth: true
                visible: root.showLog
                model: root.updateModel
                viewHeight: Theme.dp(220)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingLg

                ShellButton {
                    label: root.showLog ? "Hide log" : "View log"
                    onActivated: root.showLog = !root.showLog
                }

                Item { Layout.fillWidth: true }

                // While it runs the popup can only be tucked away (the panel
                // indicator brings it back); once finished it is dismissed.
                ShellButton {
                    label: root.updateModel.busy ? "Hide" : "Dismiss"
                    primary: !root.updateModel.busy
                    onActivated: root.updateModel.busy
                        ? root.updateModel.closePopup() : root.updateModel.dismissProgress()
                }
            }
        }
    }
}
