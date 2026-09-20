"""Instrument an isolated production shell; never run installed desktop helpers."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Update progress fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
# Every helper command becomes `true`, so nothing installed on the machine
# running the test (lyona-update included) can be started by the shell.
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'return ["true"];\n        const argv = args || [];',
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Update progress fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
