"""Instrument an isolated production shell; never run installed desktop helpers."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Settings fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
model = qml / "settings/SettingsModel.qml"
text = replace_once(model.read_text(), "id: root",
                    "id: root\n    property bool testInitialLoading: false")
for method, counter in (
    ("activateSection(id)", "testActivations"),
    ("refreshDisplays()", "testDisplayReads"),
    ("refreshInput()", "testInputReads"),
):
    signature = f"function {method} {{"
    text = replace_once(
        text, signature,
        f"property int {counter}: 0\n    {signature}\n        {counter}++;",
    )
# A queued refresh flag may only clear once the process it queued has started;
# a clear with nothing running is the frame in which a pane could present early.
for flag, process in (("capabilityRefreshPending", "providerProcess"),
                      ("displayRefreshPending", "displayDiscoverProcess"),
                      ("inputRefreshPending", "inputDiscoverProcess"),
                      ("automaticDisplayRefreshPending", "automaticDisplayStatusProcess")):
    text = replace_once(text, "id: root", "id: root\n    on" + flag[0].upper() + flag[1:]
                        + "Changed: if (!" + flag + " && !" + process
                        + ".running && visible) testQueuedGap = true")
text = replace_once(text, "id: root", "id: root\n    property bool testQueuedGap: false")
model.write_text(text)
commands = qml / "core/Commands.qml"
text = replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (action === "preview-status" && (helper === "dwm-settings-display" || helper === "dwm-settings-input")) return ["sleep", "0.75"];\n'
    '        if (action === "status" && (helper === "dwm-accessibility-settings" || helper === "dwm-panel-settings")) return ["sleep", "0.75"];\n'
    '        if (helper === "dwm-system-management" && action.indexOf("snapshot") === 0) return ["sleep", "0.75"];\n'
    '        return ["true"];\n        const argv = args || [];',
)
commands.write_text(text)
for relative, visible in (("defaults/AutostartModel.qml", "settingsVisible"),
                          ("defaults/DefaultAppsModel.qml", "settingsVisible"),
                          ("power/PowerModel.qml", "sectionVisible")):
    path = qml / relative
    text = replace_once(path.read_text(), "id: root", "id: root\n"
                        "    property bool testQueuedGap: false\n"
                        "    onSnapshotPendingChanged: if (!snapshotPending && !snapshotProcess.running && "
                        + visible + ") testQueuedGap = true")
    path.write_text(text)
# The 200 percent checks measure text against fixed-size rows, so they depend on
# the font's line height: Noto Sans (installed on the CI image and on Lyona
# systems) is about 1.36 times its size, FreeSans (a common fallback) about 1.2.
# Pin every UiText to Noto Sans's line height so a run gives the same answer on
# any host instead of passing where the font happens to be short.
ui_text = qml / "core/UiText.qml"
ui_text.write_text(replace_once(
    ui_text.read_text(), "    verticalAlignment: Text.AlignVCenter\n",
    "    verticalAlignment: Text.AlignVCenter\n"
    "    lineHeightMode: Text.FixedHeight\n"
    "    lineHeight: Math.ceil(font.pixelSize * 1.362)\n",
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Settings fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])

# The harness holds the panes back with testInitialLoading, and records any pane
# that presents while one of its own models still reports a read in flight.
window = qml / "settings/SettingsWindow.qml"
text = window.read_text().replace(
    "dataLoading: ", "dataLoading: root.settingsModel.testInitialLoading || ")
text = replace_once(text, "id: root", """id: root
    property bool testEarlyPresentation: false
    function testPresentation(item) {
        const type = String(item);
        let pending = false;
        if (type.startsWith("DisplaySettingsPane")) pending = settingsModel.displayActionBusy || settingsModel.displayRefreshPending || settingsModel.automaticDisplayRefreshPending;
        if (type.startsWith("InputSettingsPane")) pending = settingsModel.inputActionBusy || settingsModel.inputRefreshPending;
        if (type.startsWith("AppearanceSettingsPane")) pending = appearanceModel.initialLoading
            || accessibilityModel.initialLoading || panelSettingsModel.initialLoading || notificationModel.initialLoading;
        if (type.startsWith("SystemSettingsPane")) pending = systemManagementModel.initialLoading;
        if (pending) {
            testEarlyPresentation = true;
            console.error("Responsiveness FAILED: First presentation preceded provider completion: " + type);
        }
    }""")
text = text.replace("DeferredSettingsPane {", "DeferredSettingsPane {\n                                onPresentedChanged: if (presented) root.testPresentation(item)")
window.write_text(text)
