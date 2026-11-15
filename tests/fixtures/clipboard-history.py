"""Instrument an isolated production shell for the clipboard history test.

Every helper becomes `true`, so nothing installed on the machine running the
test can be started, except dwm-clipboard-history (#469), which goes to the
test's stub (CLIPBOARD_STUB): settings in files, a log of calls, and an observer
that follows a feed file of JSON records the test writes.
"""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Clipboard fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (helper === "dwm-clipboard-history")\n'
    '            return [Quickshell.env("CLIPBOARD_STUB"), action].concat(args || []);\n'
    '        return ["true"];\n        const argv = args || [];',
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Clipboard fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
