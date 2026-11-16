"""Instrument an isolated copy of the production shell for an xvfb test (#531).

    shell-stub.py QML_DIR INCLUDE [ROUTE ...]

Every helper becomes `true`, so nothing installed on the machine running the
test can be started by the shell, except the helpers a ROUTE sends to a stub.
INCLUDE (the test's QML) is added at the end of shell.qml's root object.

A ROUTE is HELPERS[@ACTION]:ENV:PASS
  HELPERS  one helper name, or several separated by commas
  ACTION   only this action of them (any action without it)
  ENV      the environment variable holding the stub's path
  PASS     what the stub is given before the helper's arguments:
           helper  the helper's name and the action
           action  the action
           args    nothing

One script for every such test, in place of a copy of it per test that
differed only in these names, each breaking alone when Commands.qml changed.
"""
from pathlib import Path
import re
import sys

INJECTION = "const argv = args || [];"


def fail(message):
    raise SystemExit(f"shell-stub fixture: {message}")


def route_code(route):
    match = re.fullmatch(r"([A-Za-z0-9_.,-]+)(?:@([A-Za-z0-9_-]+))?:([A-Z][A-Z0-9_]*):(helper|action|args)", route)
    if not match:
        fail(f"bad route {route!r} (HELPERS[@ACTION]:ENV:helper|action|args)")
    helpers, action, env, passed = match.groups()
    condition = " || ".join(f'helper === "{name}"' for name in helpers.split(","))
    if action:
        condition = f"({condition}) && action === \"{action}\""
    prefix = {"helper": ".concat([helper, action])", "action": ".concat([action])", "args": ""}[passed]
    return (f"if ({condition})\n"
            f"            return [Quickshell.env(\"{env}\")]{prefix}.concat(args || []);\n        ")


def main():
    if len(sys.argv) < 3:
        fail("usage: shell-stub.py QML_DIR INCLUDE [ROUTE ...]")
    qml = Path(sys.argv[1])
    include = Path(sys.argv[2]).read_text()
    commands = qml / "core/Commands.qml"
    text = commands.read_text()
    if text.count(INJECTION) != 1:
        fail(f"Commands.qml injection point changed: {INJECTION}")
    code = "".join(route_code(route) for route in sys.argv[3:])
    commands.write_text(text.replace(INJECTION, code + 'return ["true"];\n        ' + INJECTION, 1))
    shell = qml / "shell.qml"
    text = shell.read_text()
    if not text.rstrip().endswith("}"):
        fail("shell.qml's root object changed")
    end = text.rfind("}")
    shell.write_text(text[:end] + include + text[end:])


main()
