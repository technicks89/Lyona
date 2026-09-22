"""Instrument an isolated production shell; never run installed desktop helpers."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Queued run fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
# Every helper except the autostart one becomes `true`, so nothing installed on
# the machine running the test can be started by the shell. The autostart helper
# is found the normal way, in $XDG_DATA_HOME/lyona/scripts, where the test puts its stub.
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (helper !== "dwm-xdg-autostart") return ["true"];\n        const argv = args || [];',
))
# Count the snapshot reads that really start.
model = qml / "defaults/AutostartModel.qml"
text = model.read_text()
text = replace_once(text, "    property bool snapshotPending: false\n",
                    "    property bool snapshotPending: false\n    property int testStarts: 0\n")
text = replace_once(text, "        onRunningChanged: {\n            if (!running && root.snapshotPending && root.settingsVisible) {",
                    "        onRunningChanged: {\n            if (running) root.testStarts++;\n"
                    "            if (!running && root.snapshotPending && root.settingsVisible) {")
model.write_text(text)
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Queued run fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
