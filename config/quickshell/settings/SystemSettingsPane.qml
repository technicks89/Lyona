import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var updateModel
    property var capabilities: []
    property string confirmVersion: ""

    readonly property var additionalCapabilities: root.capabilities.filter(function(capability) {
        return capability.id !== "updates";
    })

    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    onVisibleChanged: if (!visible) root.confirmVersion = "";

    ColumnLayout {
        id: content

        width: root.width
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true

            UiText {
                Layout.fillWidth: true
                text: root.updateModel.providerState === "available"
                    ? root.updateModel.providerDetail
                    : root.updateModel.busy ? "Working..." : root.updateModel.providerDetail
                color: Theme.statusColor(root.updateModel.providerState)
                font.bold: true
                elide: Text.ElideRight
            }

            ShellButton {
                label: root.updateModel.busy ? "Checking..." : "Check for updates"
                enabled: !root.updateModel.busy
                onActivated: root.updateModel.refresh()
            }
        }

        SectionLabel { label: "Installed" }

        StatusCard {
            label: "lyona"
            statusState: root.updateModel.consistent ? "available" : "unavailable"
            value: root.updateModel.installedVersion.length > 0 ? root.updateModel.installedVersion : "Unknown"
            detail: root.updateModel.consistent
                ? root.updateModel.installedSource + " / " + root.updateModel.installedCommit
                : "Installed records disagree: " + root.updateModel.installedMismatchDetail
        }

        SectionLabel { label: "Update status" }

        StatusCard {
            label: root.updateModel.channel === "preview" ? "Channel: preview" : "Channel: stable"
            statusState: root.updateModel.updateState === "current" ? "available"
                : root.updateModel.updateState === "offline" ? "restricted"
                : root.updateModel.updateAvailable ? "partial"
                : root.updateModel.updateState === "unavailable" ? "unavailable" : "available"
            value: root.updateModel.updateState
            detail: root.updateModel.message
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.updateModel.availableVersion.length > 0

            UiText {
                Layout.fillWidth: true
                text: "Available: " + root.updateModel.availableVersion
                    + (root.updateModel.availableDate.length > 0 ? " (" + root.updateModel.availableDate + ")" : "")
                color: Theme.menuText
                elide: Text.ElideRight
            }

            MenuRow {
                Layout.preferredWidth: 140
                label: "Release notes"
                navigates: true
                onActivated: Qt.openUrlExternally(
                    "https://github.com/technicks89/Lyona/releases/tag/v" + root.updateModel.availableVersion)
            }
        }

        ShellButton {
            Layout.alignment: Qt.AlignLeft
            visible: root.updateModel.updateAvailable && root.confirmVersion.length === 0
            label: "Update to " + root.updateModel.availableVersion
            primary: true
            enabled: !root.updateModel.busy
            onActivated: root.confirmVersion = root.updateModel.availableVersion
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.confirmVersion.length > 0
            spacing: Theme.spacingXs

            UiText {
                Layout.fillWidth: true
                text: "Install " + root.confirmVersion + " over the running system? "
                    + "Quickshell will restart; a session restart may also be required."
                color: Theme.popupText
                wrapMode: Text.WordWrap
            }

            RowLayout {
                spacing: Theme.spacingSm

                ShellButton {
                    label: "Update now"
                    primary: true
                    onActivated: {
                        root.updateModel.apply(root.confirmVersion);
                        root.confirmVersion = "";
                    }
                }

                ShellButton {
                    label: "Cancel"
                    onActivated: root.confirmVersion = ""
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.updateModel.busy
            spacing: Theme.spacingXxs

            UiText {
                Layout.fillWidth: true
                text: "Applying: " + root.updateModel.phase
                color: Theme.accent
                font.bold: true
            }

            UiText {
                Layout.fillWidth: true
                visible: root.updateModel.progressDetail.length > 0
                text: root.updateModel.progressDetail
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: !root.updateModel.busy && root.updateModel.message.length > 0
                && !root.updateModel.updateAvailable
            text: root.updateModel.message
            color: root.updateModel.actionSucceeded ? Theme.success : Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "Channel" }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            ShellButton {
                label: "Stable"
                primary: root.updateModel.channel === "stable"
                enabled: !root.updateModel.busy
                onActivated: root.updateModel.setChannel("stable")
            }

            ShellButton {
                label: "Preview"
                primary: root.updateModel.channel === "preview"
                enabled: !root.updateModel.busy
                onActivated: root.updateModel.setChannel("preview")
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.updateModel.channel === "preview"
            text: "Preview releases are pre-release builds and are not release-qualified."
            color: Theme.warning
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "Backups" }

        UiText {
            Layout.fillWidth: true
            visible: root.updateModel.backupsLoaded && root.updateModel.backups.length === 0
            text: "No backups yet"
            color: Theme.menuMutedText
        }

        Repeater {
            model: root.updateModel.backups
            delegate: RowLayout {
                id: backupRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Theme.spacingSm

                UiText {
                    Layout.fillWidth: true
                    text: backupRow.modelData.version + " (" + backupRow.modelData.date + ")"
                    color: Theme.menuText
                    elide: Text.ElideRight
                }

                ShellButton {
                    label: "Roll back"
                    enabled: !root.updateModel.busy
                    onActivated: root.updateModel.rollback(backupRow.modelData.id)
                }
            }
        }

        SectionLabel {
            visible: root.additionalCapabilities.length > 0
            label: "Additional capabilities"
        }

        Repeater {
            model: root.additionalCapabilities
            delegate: StatusCard {
                id: capabilityCard
                required property var modelData
                label: capabilityCard.modelData.label
                statusState: capabilityCard.modelData.status
                value: capabilityCard.modelData.status
                detail: capabilityCard.modelData.detail
            }
        }
    }
}
