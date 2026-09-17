import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

/*
 * Sync Phase 7 (docs/SYNC-P7-OPERATION-SURFACE.md): the visible confirm/
 * cancel surface for SystemManagementModel's update actions. Confirmation
 * itself is owned by the model (prepareUpdate()/confirmUpdate()) -- this
 * component only renders `updateConfirmation` and forwards user intent, so
 * a captured plan is never re-derived or re-validated in two places.
 */
ColumnLayout {
    id: root

    required property var model
    signal revealRequested(var target)

    readonly property var confirmation: root.model.updateConfirmation
    // Sync Sprint 1 S1-04 (#267): operationModel is shared across update,
    // regional and delegated dispatch now -- the cancel control below only
    // ever applied to update/refresh anyway (SystemOperationModel's own
    // cancel_journal_operation() restricts to that family), but a regional
    // or delegated operation's progress previously still lit up "PackageKit
    // owns the active operation" here, which is only true for updates.
    readonly property bool updateOperation: model.operation.progress !== null
        && (model.operation.progress.kind === "update" || model.operation.progress.kind === "refresh")

    Layout.fillWidth: true
    spacing: Theme.spacingMd

    component PlainText: UiText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    component ActionButton: ShellButton {
        id: actionButton
        onActiveFocusChanged: if (actionButton.activeFocus) root.revealRequested(actionButton);
    }

    component ScrollList: ListView {
        id: scrollList
        Layout.fillWidth: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: true
        keyNavigationEnabled: true
        onActiveFocusChanged: if (scrollList.activeFocus) root.revealRequested(scrollList);
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) {
                scrollList.currentIndex = 0;
                scrollList.positionViewAtBeginning();
            } else if (event.key === Qt.Key_End) {
                scrollList.currentIndex = scrollList.count - 1;
                scrollList.positionViewAtEnd();
            } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                scrollList.contentY = Math.max(scrollList.originY,
                    Math.min(scrollList.originY + Math.max(0, scrollList.contentHeight - scrollList.height),
                        scrollList.contentY + (event.key === Qt.Key_PageDown ? scrollList.height : -scrollList.height)));
            } else return;
            root.revealRequested(scrollList);
            event.accepted = true;
        }
    }

    RowLayout {
        Layout.fillWidth: true

        ActionButton {
            objectName: "prepareRefresh"
            label: "Refresh metadata..."
            enabled: root.confirmation === null && root.model.updateActionReason("updates-refresh") === ""
            onActivated: root.model.prepareUpdate("updates-refresh")
        }

        ActionButton {
            objectName: "prepareInstall"
            label: "Install updates..."
            enabled: root.confirmation === null && root.model.updateActionReason("updates-install-all") === ""
            onActivated: root.model.prepareUpdate("updates-install-all")
        }

        Item { Layout.fillWidth: true }
    }

    PlainText {
        id: refreshReason
        readonly property string reason: root.model.updateActionReason("updates-refresh")
        visible: refreshReason.reason.length > 0
        text: refreshReason.reason.length > 0 ? "Metadata refresh: " + refreshReason.reason : ""
        color: Theme.menuMutedText
    }

    PlainText {
        id: installReason
        readonly property string reason: root.model.updateActionReason("updates-install-all")
        visible: installReason.reason.length > 0
        text: installReason.reason.length > 0 ? "Update installation: " + installReason.reason : ""
        color: Theme.menuMutedText
    }

    PlainText {
        visible: text.length > 0
        text: root.model.confirmationMessage
        color: Theme.warning
    }

    Rectangle {
        id: confirmationCard
        Layout.fillWidth: true
        implicitHeight: confirmationContent.implicitHeight + Theme.spacingLg * 2
        visible: root.confirmation !== null
        // prepareInstall/prepareRefresh already holding focus (e.g. activated
        // by keyboard without a focus change) fires no onActiveFocusChanged
        // on them -- this card becoming visible is what must reveal it then,
        // alongside (not instead of) the focus-based path below.
        onVisibleChanged: if (confirmationCard.visible) root.revealRequested(confirmationCard);
        color: Theme.controlNormalFill
        border.color: Theme.warning
        border.width: Theme.controlBorderWidth
        radius: Theme.controlRadius

        ColumnLayout {
            id: confirmationContent
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd

            PlainText {
                text: root.confirmation !== null && root.confirmation.actionId === "updates-install-all"
                    ? "Confirm package updates" : "Confirm metadata refresh"
                font.bold: true
                color: Theme.controlNormalText
            }

            PlainText {
                text: "PackageKit owns this system change and may ask for administrator authorization. "
                    + "Closing Settings does not cancel it. Cancellation is available only while PackageKit "
                    + "says it is safe; a request is not a completed cancellation. If interrupted, reload "
                    + "status to recover the recorded operation."
                color: Theme.menuText
            }

            PlainText {
                text: root.confirmation !== null && root.confirmation.actionId === "updates-install-all"
                    ? "Review every change below, including dependency additions and removals. This is the "
                        + "current preview, not an atomic frozen plan: PackageKit may resolve differently "
                        + "before execution. The helper rechecks the preview generation before starting."
                    : "Refresh downloads repository metadata and changes the package cache. It does not "
                        + "install package updates. Use Reload status for a read-only status request."
                color: Theme.warning
            }

            PlainText {
                visible: root.confirmation !== null && root.confirmation.changes.length > 0
                text: root.confirmation === null ? ""
                    : root.confirmation.changes.length + " package changes / scroll to inspect all rows"
                color: Theme.menuText
            }

            ScrollList {
                objectName: "confirmedPackageChanges"
                Layout.preferredHeight: Math.min(contentHeight, 280)
                visible: count > 0
                model: root.confirmation === null ? [] : root.confirmation.changes
                spacing: Theme.spacingSm
                delegate: ColumnLayout {
                    id: change
                    required property var modelData
                    width: ListView.view.width
                    spacing: Theme.spacingXs

                    PlainText {
                        text: change.modelData.action.toUpperCase() + " / "
                            + change.modelData.name + " " + change.modelData.version
                        color: change.modelData.action === "remove" || change.modelData.action === "obsolete"
                            ? Theme.danger : Theme.accent
                        font.bold: true
                    }
                    PlainText { text: change.modelData.packageId; color: Theme.menuText }
                    PlainText { text: change.modelData.summary; color: Theme.menuMutedText }
                }
            }

            RowLayout {
                ActionButton {
                    objectName: "declineUpdate"
                    label: "Not now"
                    onActivated: root.model.discardUpdate()
                }

                ActionButton {
                    objectName: "confirmUpdate"
                    label: "Confirm"
                    danger: true
                    enabled: root.confirmation !== null
                        && root.model.updateActionReason(root.confirmation.actionId) === ""
                    onActivated: root.model.confirmUpdate()
                }
            }
        }
    }

    PlainText {
        objectName: "operationOwnerNote"
        visible: root.model.operation.busy
        text: "The active system operation remains owned. Keep watching here or close Settings and return later."
        color: Theme.menuMutedText
    }

    ActionButton {
        objectName: "cancelUpdate"
        visible: root.model.operation.streamOwned && root.updateOperation
        label: "Request cancellation"
        enabled: root.model.operation.canCancel
        onActivated: root.model.operation.requestCancel()
    }

    PlainText {
        visible: root.model.operation.streamOwned && root.updateOperation && !root.model.operation.canCancel
            && root.model.operation.cancelDetail.length === 0
        text: "Cancellation is not currently safe or available. Wait for PackageKit's verified result."
        color: Theme.menuMutedText
    }

    PlainText {
        visible: text.length > 0
        text: root.model.operation.cancelDetail
        color: Theme.warning
    }

    PlainText {
        id: operationErrorText
        readonly property var operationError: root.model.operation.operationError
        visible: operationErrorText.operationError !== null
        text: operationErrorText.operationError === null ? ""
            : operationErrorText.operationError.provider + " / " + operationErrorText.operationError.code
                + ": " + operationErrorText.operationError.detail
        color: Theme.danger
    }

    PlainText {
        id: operationAuditText
        readonly property var audit: root.model.operation.audit
        visible: operationAuditText.audit !== null
        text: operationAuditText.audit === null ? ""
            : "Verified audit: " + operationAuditText.audit.actionId + " / " + operationAuditText.audit.result
                + " / " + operationAuditText.audit.started + " - " + operationAuditText.audit.finished
                + " / " + operationAuditText.audit.detail
        color: Theme.menuMutedText
    }

    PlainText {
        visible: root.model.operation.log.length > 0
        text: "Operation log (bounded / scroll for earlier progress)"
        font.bold: true
        color: Theme.menuText
    }

    ScrollList {
        objectName: "updateOperationLog"
        Layout.preferredHeight: Math.min(contentHeight, 180)
        visible: count > 0
        model: root.model.operation.log
        spacing: Theme.spacingXs
        delegate: PlainText {
            required property var modelData
            width: ListView.view.width
            text: modelData.state + " / " + modelData.percent + " / " + modelData.detail
            color: Theme.menuText
        }
    }
}
