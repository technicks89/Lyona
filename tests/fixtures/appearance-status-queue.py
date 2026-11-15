"""Instrument an isolated production shell for the Settings status queue test.

Every helper becomes `true`, so nothing installed on the machine running the
test can be started, except dwm-settings-appearance and dwm-settings-wallpaper,
which go to the test's wrapper (APPEARANCE_STUB) with the helper's name first.
"""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Appearance fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (helper === "dwm-settings-appearance" || helper === "dwm-settings-wallpaper")\n'
    '            return [Quickshell.env("APPEARANCE_STUB"), helper, action].concat(args || []);\n'
    '        return ["true"];\n        const argv = args || [];',
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Appearance fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
