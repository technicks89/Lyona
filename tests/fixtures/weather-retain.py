"""Instrument an isolated production shell; never run installed desktop helpers."""
from pathlib import Path
import sys


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"Weather retain fixture injection point changed: {old}")
    return text.replace(old, new, 1)


qml = Path(sys.argv[1])
# Every helper except the weather one becomes `true`, so nothing installed on
# the machine running the test can be started by the shell. The weather helper
# is found the normal way, through LYONA_DEV_SCRIPTS, which names the test's stub.
commands = qml / "core/Commands.qml"
commands.write_text(replace_once(
    commands.read_text(), "const argv = args || [];",
    'if (helper !== "lyona-weather") return ["true"];\n        const argv = args || [];',
))
# The test turns the widget on and off itself, instead of through the panel
# settings helper.
model = qml / "weather/WeatherModel.qml"
model.write_text(replace_once(
    model.read_text(),
    '''    readonly property bool enabled: root.panelSettingsModel
        ? root.panelSettingsModel.widgetEnabled("weather") : false''',
    "    property bool enabled: false",
))
shell = qml / "shell.qml"
text = shell.read_text()
if not text.rstrip().endswith("}"):
    raise SystemExit("Weather retain fixture shell root changed")
end = text.rfind("}")
shell.write_text(text[:end] + Path(sys.argv[2]).read_text() + text[end:])
