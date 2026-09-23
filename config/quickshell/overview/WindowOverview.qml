import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

// The cross-tag window overview popup (Sync Sprint 7 S7-03, docs/SYNC-SPRINT-7-OVERVIEW-FOUNDATION.md,
// design doc "A new popup"/"Opening it", keyboard navigation added in Sync
// Sprint 8 S8-01, docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md). ClickAwayPopup-based
// the same way ControlsWindow is, so it inherits the click-away dismiss the
// transparent surface already gives every popup built on it; Escape is
// handled explicitly below, the same way ControlsWindow's own content does.
// The rest of the key handling is the exact Keys.onPressed shape
// LauncherWindow.qml already has: arrows/Home/End move OverviewModel's own
// selectedIndex, Enter activates it.
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
            } else if (event.key === Qt.Key_Down) {
                root.overviewModel.selectRelative(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                root.overviewModel.selectRelative(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Home) {
                root.overviewModel.selectAbsolute(0);
                event.accepted = true;
            } else if (event.key === Qt.Key_End) {
                root.overviewModel.selectAbsolute(root.overviewModel.flatCards.length - 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.overviewModel.activateSelected();
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
                                    selected: cardDelegate.modelData.flatIndex === root.overviewModel.selectedIndex
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
