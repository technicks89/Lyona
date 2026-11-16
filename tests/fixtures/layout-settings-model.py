"""Instrument an isolated production shell for the Layout settings model test.

Every helper becomes `true`, so nothing installed on the machine running the
test can be started, except dwm-layout-settings and dwm-settings-theme
(#530, #534), which go to the test's stub (LAYOUT_STUB): a watch that follows
a feed file, writes logged (and slowed, so they queue), and title bars kept in
a file.
"""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Layout settings fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (helper === "dwm-layout-settings" || helper === "dwm-settings-theme")\n'
    '            return [Quickshell.env("LAYOUT_STUB"), helper, action].concat(args || []);\n'
    '        return ["true"];\n        const argv = args || [];',
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Layout settings fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
