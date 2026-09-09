import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var updateModel
    required property var systemManagementModel
    property var capabilities: []
    property string confirmVersion: ""

    readonly property var additionalCapabilities: root.capabilities.filter(function(capability) {
        return capability.id !== "updates" && capability.id !== "package-updates";
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

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacingLg

            UiText {
                Layout.fillWidth: true
                text: root.systemManagementModel.busy
                    ? "Loading..."
                    : root.systemManagementModel.updateProvider.status === "available"
                        ? root.systemManagementModel.message
                        : root.systemManagementModel.updateProvider.detail
                color: Theme.statusColor(root.systemManagementModel.updateProvider.status)
                font.bold: true
                elide: Text.ElideRight
            }

            ShellButton {
                objectName: "reloadSystemStatus"
                label: root.systemManagementModel.busy ? "Loading..." : "Reload status"
                enabled: !root.systemManagementModel.busy
                onActivated: root.systemManagementModel.refresh()
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.systemManagementModel.recoveryProvider.status !== "unsupported"
            text: root.systemManagementModel.recoveryProvider.detail
            color: Theme.statusColor(root.systemManagementModel.recoveryProvider.status)
            wrapMode: Text.WordWrap
        }

        UiText {
            Layout.fillWidth: true
            visible: root.systemManagementModel.discoveryDetail.length > 0
            text: root.systemManagementModel.discoveryDetail
            color: Theme.warning
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "System updates" }

        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 720 ? 3 : 1
            columnSpacing: Theme.spacingMd
            rowSpacing: Theme.spacingMd

            StatusCard {
                Layout.fillWidth: true
                label: "Pending updates"
                statusState: root.systemManagementModel.updateSummary.status
                value: root.systemManagementModel.updateSummary.value
                detail: root.systemManagementModel.updateSummary.detail
            }

            StatusCard {
                Layout.fillWidth: true
                label: "Last refresh"
                statusState: root.systemManagementModel.updateLastRefresh.status
                value: root.systemManagementModel.updateLastRefresh.value === "unknown"
                    ? "Unknown"
                    : Theme.formatDuration(Number(root.systemManagementModel.updateLastRefresh.value)) + " ago"
                detail: root.systemManagementModel.updateLastRefresh.detail
            }

            StatusCard {
                Layout.fillWidth: true
                label: "Restart guidance"
                statusState: root.systemManagementModel.updateRestart.status
                value: root.systemManagementModel.updateRestart.value
                detail: root.systemManagementModel.updateRestart.detail
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.systemManagementModel.snapshotState === "loaded"
                && root.systemManagementModel.updates.length === 0
            text: "No pending Arch updates"
            color: Theme.menuMutedText
        }

        Repeater {
            model: root.systemManagementModel.updates
            delegate: RowLayout {
                id: updateRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Theme.spacingSm

                UiText {
                    Layout.fillWidth: true
                    text: updateRow.modelData.name + " " + updateRow.modelData.version
                    color: updateRow.modelData.installability === "blocked"
                        ? Theme.menuMutedText : Theme.menuText
                    elide: Text.ElideRight
                }

                UiText {
                    text: updateRow.modelData.installability === "blocked"
                        ? "Blocked" : updateRow.modelData.severity
                    color: updateRow.modelData.severity === "security" || updateRow.modelData.severity === "critical"
                        ? Theme.danger : Theme.menuMutedText
                }
            }
        }

        SectionLabel {
            visible: root.systemManagementModel.packageChanges.length > 0
            label: "Dependency preview"
        }

        Repeater {
            model: root.systemManagementModel.packageChanges
            delegate: RowLayout {
                id: changeRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Theme.spacingSm

                UiText {
                    Layout.fillWidth: true
                    text: changeRow.modelData.name + " " + changeRow.modelData.version
                    color: Theme.menuText
                    elide: Text.ElideRight
                }

                UiText {
                    text: changeRow.modelData.action
                    color: Theme.menuMutedText
                }
            }
        }

        Repeater {
            model: root.systemManagementModel.errors
            delegate: UiText {
                id: errorRow

                required property var modelData

                Layout.fillWidth: true
                text: errorRow.modelData.detail
                color: Theme.danger
                wrapMode: Text.WordWrap
            }
        }

        UiText {
            Layout.fillWidth: true
            text: "This pane reads update and recovery state only. Metadata refresh, "
                + "update installation, and cancellation require a separate confirmed "
                + "operation workflow."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
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
