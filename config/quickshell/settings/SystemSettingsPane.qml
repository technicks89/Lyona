import QtQuick
import QtQuick.Layouts
import qs.core
import qs.system

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var updateModel
    required property var systemManagementModel
    property var capabilities: []
    property string confirmVersion: ""
    // The backup "Roll back" was chosen for, until it is confirmed or cancelled
    // (Sync Sprint 16 R16-25).
    property var confirmBackup: null
    // A PackageKit operation is running or starting: the terminal's package
    // update would contend with it for the package database.
    readonly property bool packageKitBusy: root.systemManagementModel.dispatchingUpdate
        || !!root.systemManagementModel.operation.progress
        || root.systemManagementModel.activeOperation !== null
    property bool showUpdateLog: false
    // Sync Sprint 1 S1-06 (#270): the shared clock's formatted settings text,
    // shown beside the timezone row below.
    property string clockText: ""

    // Only rows that need the user: not ones that work, and not ones that are
    // unsupported by design, such as delegated administration (#293).
    readonly property var additionalCapabilities: root.capabilities.filter(function(capability) {
        return capability.id !== "updates" && capability.id !== "package-updates"
            && capability.status !== "available" && capability.status !== "unsupported";
    })

    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    onVisibleChanged: if (!visible) {
        root.confirmVersion = "";
        root.confirmBackup = null;
    }
    // #267/S1-05 (#269): layout publication (a card appearing/disappearing
    // above a confirmation, or the window resizing) can move a focused
    // regional or delegate control after it first received focus -- follow
    // geometry changes rather than polling or leaving focus off-screen.
    onHeightChanged: Qt.callLater(root.revealFocusedControl)
    onContentHeightChanged: Qt.callLater(root.revealFocusedControl)

    function revealFocusedControl() {
        regionalControls.revealFocusedControl();
        delegateControls.revealFocusedControl();
        informationControls.revealFocusedControl();
    }

    // Sync Phase 7 (92ec6e2:docs/SYNC-P7-OPERATION-SURFACE.md): SystemUpdateControls
    // moves keyboard/tab focus onto its own buttons and scroll lists, which
    // this Flickable does not know about on its own -- reveal() keeps that
    // focus target on screen the same way this pane already scrolls itself
    // via Keys.onPressed below.
    function reveal(target) {
        const position = target.mapToItem(content, 0, 0);
        if (position.y < root.contentY)
            root.contentY = Math.max(0, position.y);
        else if (position.y + target.height > root.contentY + root.height)
            root.contentY = Math.min(Math.max(0, root.contentHeight - root.height),
                position.y + target.height - root.height);
    }

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
                onActivated: {
                    root.updateModel.refresh();
                    // The panel's count too (S15-02): by hand, only from here.
                    if (root.updateModel.indicator) root.updateModel.indicator.check(true);
                }
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

        StatusCard {
            objectName: "devScriptsCard"
            visible: root.updateModel.devScripts.length > 0
            label: "Helpers"
            statusState: "partial"
            value: "Development checkout"
            detail: "Running helpers from a development checkout: " + root.updateModel.devScripts
                + ". Unset LYONA_DEV_SCRIPTS to use the installed ones."
        }

        SectionLabel { label: "Update status" }

        // The panel's updates-available indicator (Sync Sprint 15 S15-02, D-25).
        ColumnLayout {
            objectName: "updateIndicatorSettings"
            Layout.fillWidth: true
            visible: root.updateModel.indicator !== null
            spacing: Theme.spacingSm

            StatusCard {
                label: "Panel indicator"
                statusState: !root.updateModel.indicator ? "available"
                    : root.updateModel.indicator.count > 0 ? "partial"
                    : root.updateModel.indicator.systemState === "error"
                        || root.updateModel.indicator.systemState === "unavailable" ? "restricted" : "available"
                value: !root.updateModel.indicator ? ""
                    : root.updateModel.indicator.checking ? "Checking..."
                    : root.updateModel.indicator.count > 0
                        ? root.updateModel.indicator.count + " available" : "Nothing to install"
                detail: root.updateModel.indicator ? root.updateModel.indicator.summary : ""
            }

            RowLayout {
                Layout.fillWidth: true

                UiText {
                    Layout.fillWidth: true
                    text: "Check every"
                    color: Theme.menuText
                }

                Repeater {
                    model: [1, 3, 6, 12, 24]

                    delegate: ShellButton {
                        required property int modelData

                        label: modelData + " h"
                        primary: root.updateModel.indicator !== null
                            && root.updateModel.indicator.intervalHours === modelData
                        enabled: root.updateModel.indicator !== null && !root.updateModel.indicator.settingsBusy
                        onActivated: root.updateModel.indicator.setIntervalHours(modelData)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                UiText {
                    Layout.fillWidth: true
                    text: "Show the panel icon when everything is up to date"
                    color: Theme.menuText
                    wrapMode: Text.WordWrap
                }

                PanelToggleSwitch {
                    checked: root.updateModel.indicator !== null && root.updateModel.indicator.showWhenCurrent
                    busy: root.updateModel.indicator !== null && root.updateModel.indicator.settingsBusy
                    enabled: root.updateModel.indicator !== null
                    accessibleName: "Show the update icon when current"
                    accessibleDescription: "Keep the panel's update icon visible when nothing needs updating"
                    onToggled: root.updateModel.indicator.setShowWhenCurrent(!checked)
                }
            }

            UiText {
                Layout.fillWidth: true
                visible: root.updateModel.indicator !== null && root.updateModel.indicator.message.length > 0
                text: root.updateModel.indicator ? root.updateModel.indicator.message : ""
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }
        }

        // lyona's own releases (Sync Sprint 16 R16-27): apart from the system's
        // packages and Flatpak, which follow.
        SectionLabel { label: "lyona" }

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

        // How the last apply or rollback ended (outcomeMessage); the channel
        // check's own text is the status card's detail above.
        UiText {
            Layout.fillWidth: true
            // A failed or cancelled action is shown even with an update still
            // available, which is exactly when the reason matters, and so is a
            // rollback, which leaves one available; an update's success only
            // until the "Update to" button replaces it. Never an outcome older
            // than a day (#326).
            visible: !root.updateModel.busy && root.updateModel.outcomeMessage.length > 0
                && root.updateModel.outcomeRecent
                && (!root.updateModel.updateAvailable || !root.updateModel.actionSucceeded
                    || root.updateModel.lastOperation === "rollback")
            text: root.updateModel.outcomeMessage
            color: root.updateModel.actionSucceeded ? Theme.success : Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "Update log" }

        ShellButton {
            Layout.alignment: Qt.AlignLeft
            label: root.showUpdateLog ? "Hide update log" : "View update log"
            onActivated: root.showUpdateLog = !root.showUpdateLog
        }

        UpdateLogView {
            Layout.fillWidth: true
            visible: root.showUpdateLog
            model: root.updateModel
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
                    enabled: !root.updateModel.busy && root.confirmBackup === null
                    onActivated: root.confirmBackup = backupRow.modelData
                }
            }
        }

        // Rolling back replaces the running lyona, so it asks first, as
        // updating does (Sync Sprint 16 R16-25).
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.confirmBackup !== null
            spacing: Theme.spacingXs

            UiText {
                Layout.fillWidth: true
                text: root.confirmBackup === null ? ""
                    : "Roll back to " + root.confirmBackup.version + " (" + root.confirmBackup.date + ")? "
                        + "It replaces the running lyona. Quickshell will restart; a session restart may also be required."
                color: Theme.popupText
                wrapMode: Text.WordWrap
            }

            RowLayout {
                spacing: Theme.spacingSm

                ShellButton {
                    label: "Roll back now"
                    danger: true
                    enabled: !root.updateModel.busy
                    onActivated: {
                        root.updateModel.rollback(root.confirmBackup.id);
                        root.confirmBackup = null;
                    }
                }

                ShellButton {
                    label: "Cancel"
                    onActivated: root.confirmBackup = null
                }
            }
        }

        // Updates in a terminal (Sync Sprint 15 S15-03, S15-04, decision D-26),
        // beside PackageKit's preview below: the full output, and the tool's own
        // confirmation. yay updates AUR packages too when it is installed. Under
        // their own heading, after lyona's (Sync Sprint 16 R16-27).
        SectionLabel {
            visible: root.updateModel.indicator !== null
            label: "System packages and Flatpak"
        }

        ColumnLayout {
            objectName: "terminalUpdateSettings"
            Layout.fillWidth: true
            visible: root.updateModel.indicator !== null
            spacing: Theme.spacingSm

            UiText {
                Layout.fillWidth: true
                text: "Each runs in your terminal, where you read the plan and confirm it. "
                    + "Update packages updates the system's packages: with yay when it is installed (AUR packages included), "
                    + "otherwise pacman, which asks for your password. Update Flatpak apps updates Flatpak apps only. "
                    + "For the same system packages without a terminal, use System updates below."
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true

                ShellButton {
                    label: root.updateModel.indicator && root.updateModel.indicator.terminalBusy
                        && root.updateModel.indicator.terminalProvider === "system"
                        ? "Updating packages..." : "Update packages"
                    // Not while PackageKit is changing packages (Sync Sprint 16 R16-27).
                    enabled: root.updateModel.indicator !== null && !root.updateModel.indicator.terminalBusy
                        && !root.updateModel.busy && !root.packageKitBusy
                    onActivated: root.updateModel.indicator.updateInTerminal("system")
                }

                ShellButton {
                    visible: root.updateModel.indicator !== null
                        && root.updateModel.indicator.flatpakState !== "unavailable"
                    label: root.updateModel.indicator && root.updateModel.indicator.terminalBusy
                        && root.updateModel.indicator.terminalProvider === "flatpak"
                        ? "Updating Flatpak apps..."
                        : root.updateModel.indicator && root.updateModel.indicator.flatpakCount > 0
                        ? "Update Flatpak apps (" + root.updateModel.indicator.flatpakCount + ")"
                        : "Update Flatpak apps"
                    enabled: root.updateModel.indicator !== null && !root.updateModel.indicator.terminalBusy
                    onActivated: root.updateModel.indicator.updateInTerminal("flatpak")
                }

                Item { Layout.fillWidth: true }
            }

            UiText {
                Layout.fillWidth: true
                visible: root.packageKitBusy
                text: "Update packages is available again when the system update below finishes."
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }

            UiText {
                Layout.fillWidth: true
                visible: root.updateModel.indicator !== null && root.updateModel.indicator.terminalResult.length > 0
                text: root.updateModel.indicator ? root.updateModel.indicator.terminalDetail : ""
                color: root.updateModel.indicator && root.updateModel.indicator.terminalResult === "succeeded"
                    ? Theme.success : Theme.menuText
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true

                UiText {
                    Layout.fillWidth: true
                    text: "Float the update terminal"
                    color: Theme.menuText
                }

                PanelToggleSwitch {
                    checked: root.updateModel.indicator !== null && root.updateModel.indicator.floatTerminal
                    busy: root.updateModel.indicator !== null && root.updateModel.indicator.settingsBusy
                    enabled: root.updateModel.indicator !== null
                    accessibleName: "Float the update terminal"
                    accessibleDescription: "Open the update terminal as a floating window instead of tiling it"
                    onToggled: root.updateModel.indicator.setFloatTerminal(!checked)
                }
            }

            // Lyona never edits a window-rules.toml it did not install; it says
            // what to add instead.
            UiText {
                objectName: "floatRuleHint"
                Layout.fillWidth: true
                visible: root.updateModel.indicator !== null && root.updateModel.indicator.floatTerminal
                    && !root.updateModel.indicator.floatRulePresent
                // Where it goes, too (Sync Sprint 16 R16-31).
                text: "For the terminal to float, add this line inside the rules = [ ... ] array "
                    + "in ~/.config/lyona/window-rules.toml: "
                    + "{ class=\"lyona-update-float\", isfloating=1 },"
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
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

        // Two ways to update the same packages, side by side: say how they
        // differ rather than leave the user to guess (#326).
        UiText {
            Layout.fillWidth: true
            text: "The same system packages as Update packages above, through PackageKit, without a terminal: "
                + "refresh the package lists, then install the updates found. AUR packages are not included; "
                + "use Update packages for those, which waits while PackageKit is working."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        SystemUpdateControls {
            id: updateControls
            model: root.systemManagementModel
            onRevealRequested: target => root.reveal(target)
        }

        SectionLabel { label: "Regional" }

        UiText {
            objectName: "systemLocalTime"
            Layout.fillWidth: true
            text: root.clockText.length > 0 ? "Local date and time: " + root.clockText
                : "Local date and time unavailable"
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        SystemRegionalControls {
            id: regionalControls
            model: root.systemManagementModel
            viewportHeight: root.height
            onRevealRequested: target => root.reveal(target)
        }

        // Sync Sprint 1 S1-04 (#267): moved out of SystemRegionalControls
        // into its own component, now that delegated launches get a visible
        // confirmation step instead of dispatching immediately -- it
        // supplies its own SectionLabel.
        SystemDelegateControls {
            id: delegateControls
            model: root.systemManagementModel
            onRevealRequested: target => root.reveal(target)
        }

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

        StatusCard {
            id: operationCard
            objectName: "systemOperationFallback"
            readonly property var operation: root.systemManagementModel.operation.progress
                || root.systemManagementModel.activeOperation
            readonly property bool packageOperation: operationCard.operation !== null
                && (operationCard.operation.kind === "update" || operationCard.operation.kind === "refresh")
            Layout.fillWidth: true
            visible: operationCard.operation !== null && updateControls.active === null
            label: operationCard.packageOperation ? "Update recovery"
                : operationCard.operation === null ? "Active operation" : operationCard.operation.actionId
            statusState: "partial"
            value: operationCard.operation === null ? ""
                : operationCard.operation.percent === "unknown"
                    ? operationCard.operation.state
                    : operationCard.operation.state + " / " + operationCard.operation.percent + "%"
            detail: operationCard.packageOperation
                ? "Live package progress is unavailable. Reload status to recover this operation."
                : operationCard.operation === null ? "" : operationCard.operation.detail
        }

        StatusCard {
            id: resultCard
            readonly property var result: root.systemManagementModel.operation.result
            Layout.fillWidth: true
            visible: resultCard.result !== null
            label: resultCard.result === null ? "Verified operation result"
                : resultCard.result.kind === "update" ? "Package updates"
                : resultCard.result.kind === "refresh" ? "Metadata refresh" : resultCard.result.actionId
            statusState: resultCard.result !== null && resultCard.result.state === "succeeded" ? "available" : "partial"
            value: resultCard.result === null ? "" : resultCard.result.state
            detail: resultCard.result === null ? "" : (resultCard.result.kind === "update" || resultCard.result.kind === "refresh")
                ? (resultCard.result.state === "succeeded"
                    ? (resultCard.result.kind === "update" ? "Package updates completed." : "Repository metadata refreshed.")
                    : "The operation " + resultCard.result.state + ". Review any error or recovery guidance before retrying.")
                : resultCard.result.detail
        }

        UiText {
            objectName: "systemOperationGuidance"
            Layout.fillWidth: true
            visible: root.systemManagementModel.operation.detail.length > 0
                && (root.systemManagementModel.operation.result === null
                    || root.systemManagementModel.operation.blocked
                    || root.systemManagementModel.operation.state !== "result"
                    || (root.systemManagementModel.operation.result.state !== "succeeded"
                        && root.systemManagementModel.operation.operationError === null))
            text: root.systemManagementModel.operation.detail
            color: root.systemManagementModel.operation.blocked ? Theme.danger : Theme.menuMutedText
            wrapMode: Text.WordWrap
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
            text: "Reload status reads PackageKit and recovery state. Metadata refresh and "
                + "update installation require visible confirmation above. Delegated launches "
                + "also require confirmation; those tools own their internal changes. PackageKit "
                + "owns update authorization and safe cancellation."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        SystemInformationControls {
            id: informationControls
            model: root.systemManagementModel
            onRevealRequested: target => root.reveal(target)
        }

        SectionLabel {
            visible: root.additionalCapabilities.length > 0
            label: "Needs attention"
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
