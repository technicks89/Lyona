"""Instrument an isolated production shell for the hidden Wi-Fi test.

Every helper becomes `true`, so nothing installed on the machine running the
test can be started, except the network helper's hidden join (#471), which goes
to the test's stub (HIDDEN_WIFI_STUB) so the test can see its arguments and its
stdin, and make it fail.
"""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Hidden Wi-Fi fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (helper === "dwm-quickshell-network" && action === "wifi-connect-hidden")\n'
    '            return [Quickshell.env("HIDDEN_WIFI_STUB")].concat(args || []);\n'
    '        return ["true"];\n        const argv = args || [];',
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Hidden Wi-Fi fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
