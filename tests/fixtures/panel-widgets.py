"""Instrument an isolated production shell for the panel widgets test.

Every helper becomes `true`, so nothing installed on the machine running the
test can be started, except the state helper's keyboard requests (#470), which
go to the test's stub (PANEL_KEYBOARD_STUB) so the test can count them and make
them fail.
"""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Panel widgets fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (helper === "dwm-quickshell-state" && action === "keyboard")\n'
    '            return [Quickshell.env("PANEL_KEYBOARD_STUB")].concat(args || []);\n'
    '        return ["true"];\n        const argv = args || [];',
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Panel widgets fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
