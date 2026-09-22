import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

// The cross-tag window overview popup, mouse-only for now (Sync Sprint 7
// S7-03, docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md, design doc "A new
// popup"/"Opening it"). ClickAwayPopup-based the same way ControlsWindow is,
// so it inherits the click-away dismiss the transparent surface already
// gives every popup built on it; Escape is handled explicitly below, the
// same way ControlsWindow's own content does. Keyboard navigation between
// cards is Sprint 8, not here.
ClickAwayPopup {
    id: root

    required property var overviewModel
    required property var panelWindow

    readonly property int cardWidth: Theme.dp(420)
    readonly property int cardHeight: Math.max(Theme.dp(320), overviewColumn.implicitHeight + Theme.popupPadding * 2)

    visible: panelWindow !== null && panelWindow.screen !== null && overviewModel.visible
    targetWindow: panelWindow
    popupWidth: root.cardWidth
    popupHeight: root.cardHeight
    popupX: panelWindow ? Math.max(Theme.rowSpacing, (panelWindow.width - root.cardWidth) / 2) : Theme.rowSpacing
    popupY: Theme.panelHeight
    onDismissed: overviewModel.close()

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(function() {
                content.forceActiveFocus();
            });
        } else {
            root.overviewModel.close();
        }
    }

    ShellSurface {
        id: content

        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.overviewModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: overviewColumn

            anchors.fill: parent
            spacing: Theme.popupSpacing

            PanelHero {
                Layout.fillWidth: true
                iconText: "󰕰"
                title: "Windows"
                subtitle: root.overviewModel.groups.length + " tag"
                    + (root.overviewModel.groups.length === 1 ? "" : "s")
            }

            Text {
                Layout.fillWidth: true
                visible: root.overviewModel.groups.length === 0
                text: "No open windows"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                horizontalAlignment: Text.AlignHCenter
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: groupsColumn.implicitHeight

                ColumnLayout {
                    id: groupsColumn

                    width: parent.width
                    spacing: Theme.popupSpacing

                    Repeater {
                        model: root.overviewModel.groups

                        ColumnLayout {
                            id: groupDelegate

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: Theme.compactSpacing

                            SectionLabel {
                                label: groupDelegate.modelData.tagLabel
                            }

                            Repeater {
                                model: groupDelegate.modelData.windows

                                OverviewCard {
                                    id: cardDelegate

                                    required property var modelData

                                    Layout.fillWidth: true
                                    window: cardDelegate.modelData
                                    onFocusRequested: windowId => {
                                        root.overviewModel.dwmState.focusWindow(windowId);
                                        root.overviewModel.close();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
