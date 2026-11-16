import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

// Settings > Fingerprint (#483): enroll and delete fingers, and choose where a
// finger is accepted instead of the password. Listed with a reader, or while a
// use is on without one (#522): then only the uses show, to turn them off.
Flickable {
    id: root

    required property var fingerprintModel
    property string pendingDelete: ""
    property string pendingRemoveExternal: ""
    property string chosenFinger: ""
    readonly property var model: fingerprintModel
    readonly property var unenrolled: model.fingerNames.filter(function(name) {
        return root.model.fingers.indexOf(name) < 0;
    })
    readonly property string nextFinger: root.unenrolled.indexOf(root.chosenFinger) >= 0
        ? root.chosenFinger : (root.unenrolled.length > 0 ? root.unenrolled[0] : "")
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    onVisibleChanged: if (!visible) {
        pendingDelete = "";
        pendingRemoveExternal = "";
    }

    // One place a finger can be used: its state, and the switch for it.
    component UseCard: ColumnLayout {
        id: useCard
        required property string use
        required property string title
        property string note: ""
        readonly property string useState: root.model.useState(use)
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        StatusCard {
            Layout.fillWidth: true
            label: useCard.title
            statusState: useCard.useState === "on" ? "available"
                : useCard.useState === "external" ? "partial"
                : useCard.useState === "unavailable" ? "unavailable" : "idle"
            value: useCard.useState === "on" ? "Finger or password"
                : useCard.useState === "off" ? "Password only"
                : useCard.useState === "external" ? "Set up outside Lyona" : "Unavailable"
            detail: root.model.useDetail(useCard.use)
        }

        UiText {
            Layout.fillWidth: true
            visible: useCard.note.length > 0
            text: useCard.note
            color: Theme.warning
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            ShellButton {
                visible: useCard.useState === "on" || useCard.useState === "off"
                label: useCard.useState === "on" ? "Turn Off" : "Turn On"
                accessibleDescription: useCard.title + ". The administrator password is asked for."
                enabled: !root.model.busy && (useCard.useState === "on"
                    || (root.model.moduleAvailable && root.model.fingers.length > 0))
                onActivated: root.model.setUse(useCard.use, useCard.useState === "on" ? "off" : "on")
            }
            ShellButton {
                visible: useCard.useState === "external"
                danger: true
                label: root.pendingRemoveExternal === useCard.use ? "Confirm Remove" : "Remove the Line Added Outside Lyona"
                accessibleDescription: "Removes fprintd from this PAM file after keeping a copy of it. The password keeps working."
                enabled: !root.model.busy
                onActivated: {
                    if (root.pendingRemoveExternal === useCard.use) {
                        root.pendingRemoveExternal = "";
                        root.model.setUse(useCard.use, "remove-external");
                    } else {
                        root.pendingRemoveExternal = useCard.use;
                    }
                }
            }
            UiText {
                Layout.fillWidth: true
                visible: useCard.useState === "off" && root.model.fingers.length === 0
                text: "Enroll a finger first"
                color: Theme.menuMutedText
            }
        }
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            UiText {
                Layout.fillWidth: true
                text: root.model.readerState === "available" ? root.model.readerDetail
                    : root.model.readerDetail.length > 0 ? root.model.readerDetail : "Reading the fingerprint reader..."
                color: Theme.statusColor(root.model.readerState)
                font.bold: true
                elide: Text.ElideRight
            }
            ShellButton {
                label: "Refresh"
                enabled: !root.model.busy
                onActivated: root.model.refresh()
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.model.message.length > 0
            text: root.model.message
            color: root.model.messageSeverity === "success" ? Theme.success
                : root.model.messageSeverity === "danger" ? Theme.danger
                : root.model.messageSeverity === "warning" ? Theme.warning : Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        UiText {
            Layout.fillWidth: true
            visible: root.model.loaded && !root.model.readerAvailable
            text: "No fingerprint reader was found, so fingers cannot be enrolled or deleted. A use that is still on asks for a finger first and then falls back to the password; turn it off below."
            color: Theme.warning
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.model.readerAvailable
            spacing: Theme.spacingLg

            // A finger enrolled outside Settings (#535).
            UiText {
                Layout.fillWidth: true
                visible: root.model.addedFingers.length > 0
                text: "Added outside Settings: " + root.model.addedFingers.map(function(name) {
                    return root.model.fingerLabel(name);
                }).join(", ") + ". It works wherever fingerprint is on. If you did not add it, delete it below."
                color: Theme.warning
                wrapMode: Text.WordWrap
            }

            ShellButton {
                visible: root.model.addedFingers.length > 0
                label: "I Added It"
                accessibleDescription: "Stop warning about the fingers added outside Settings"
                enabled: !root.model.busy
                onActivated: root.model.acknowledgeAdded()
            }

            SectionLabel { label: "Enrolled fingers" }

            UiText {
                Layout.fillWidth: true
                visible: root.model.fingers.length === 0
                text: "No fingers are enrolled yet"
                color: Theme.menuMutedText
            }

            Repeater {
                model: root.model.fingers
                delegate: RowLayout {
                    id: fingerRow
                    required property string modelData
                    Layout.fillWidth: true
                    UiText {
                        Layout.fillWidth: true
                        text: root.model.fingerLabel(fingerRow.modelData)
                        color: Theme.menuText
                    }
                    ShellButton {
                        danger: true
                        label: root.pendingDelete === fingerRow.modelData ? "Confirm Delete" : "Delete"
                        enabled: !root.model.busy
                        onActivated: {
                            if (root.pendingDelete === fingerRow.modelData) {
                                root.pendingDelete = "";
                                root.model.deleteFinger(fingerRow.modelData);
                            } else {
                                root.pendingDelete = fingerRow.modelData;
                            }
                        }
                    }
                }
            }

            SectionLabel { label: "Enroll a finger" }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                visible: root.unenrolled.length > 0
                Repeater {
                    model: root.unenrolled
                    delegate: ShellButton {
                        id: fingerChoice
                        required property string modelData
                        label: root.model.fingerLabel(fingerChoice.modelData)
                            + (root.nextFinger === fingerChoice.modelData ? " / Chosen" : "")
                        enabled: !root.model.busy
                        onActivated: root.chosenFinger = fingerChoice.modelData
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                ShellButton {
                    primary: true
                    label: root.model.enrollingFinger.length > 0
                        ? "Enrolling... " + root.model.enrollPassed + " scans"
                        : "Enroll " + root.model.fingerLabel(root.nextFinger)
                    visible: root.nextFinger.length > 0
                    enabled: !root.model.busy
                    onActivated: root.model.enroll(root.nextFinger)
                }
                ShellButton {
                    label: "Cancel"
                    visible: root.model.enrollingFinger.length > 0
                    onActivated: root.model.cancelEnroll()
                }
                UiText {
                    Layout.fillWidth: true
                    visible: root.nextFinger.length === 0
                    text: "Every finger is enrolled"
                    color: Theme.menuMutedText
                }
            }
        }

        SectionLabel { label: "Use a finger instead of the password" }

        UiText {
            Layout.fillWidth: true
            text: "When a use is on, a finger is asked for first; if it is not recognised, or after 10 seconds, the password prompt comes. The password always works."
                + (root.model.moduleAvailable ? "" : " pam_fprintd is not installed, so no use can be turned on.")
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        UseCard {
            use: "lightdm"
            title: "Login and lock screen"
            note: "A finger does not unlock your keyring. After a fingerprint login, apps that use saved passwords will ask for the keyring password."
        }

        UseCard {
            use: "polkit"
            title: "Administrator prompts"
        }

        UseCard {
            use: "sudo"
            title: "sudo in a terminal"
            note: "Any program you run can ask sudo for your finger, and a terminal does not show what a touch approves. Only touch the reader when you have just typed sudo yourself."
        }
    }
}
