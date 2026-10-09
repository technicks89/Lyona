"""Instrument an isolated production shell; never run installed desktop helpers."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Wallpaper reconcile fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
# Every helper command becomes `true`, so nothing installed on the machine
# running the test can be started by the shell.
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'return ["true"];\n        const argv = args || [];',
))
# Count the reconcile actions that really start (after the wallpaper model's
# own refusal checks), so the harness can tell a started one from a dropped one.
model = qml / "appearance/WallpaperModel.qml"
text = model.read_text()
text = replace_once(text, "    required property var appearance\n",
                    "    required property var appearance\n    property int testReconcileRuns: 0\n")
text = replace_once(text, "        root.busy = true;\n        root.actionKind = action;",
                    "        if (action === \"reconcile\") root.testReconcileRuns++;\n"
                    "        root.busy = true;\n        root.actionKind = action;")
model.write_text(text)
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Wallpaper reconcile fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
