"""Instrument an isolated production shell; never run installed desktop helpers."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Picom model fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
# Every helper except the Picom one becomes `true`, so nothing installed on the
# machine running the test can be started by the shell. The Picom helper is
# found the normal way, in $XDG_DATA_HOME/lyona/scripts, where the test puts its stub.
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (helper !== "dwm-settings-picom") return ["true"];\n        const argv = args || [];',
))
model = qml / "appearance/AppearanceModel.qml"
model.write_text(replace_once(
    model.read_text(),
    "    PicomModel { id: picomModel; active: root.settingsVisible }\n",
    "    PicomModel { id: picomModel; active: root.settingsVisible }\n"
    "    readonly property var testPicom: picomModel\n",
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Picom model fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
