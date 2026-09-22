#!/bin/sh
set -eu

# S5-01 (upstream #335, completing #315): a Settings pane stays hidden until
# every model behind it has finished its first read. The xvfb harness proves the
# behaviour; this proves the wiring it depends on is still in the source: each
# model's initialLoading expression, and that a queued-refresh flag is only ever
# cleared by core/QueuedRun.qml, after the process it queued has started.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

command -v python3 >/dev/null 2>&1 || {
	printf 'SKIP: python3 is unavailable\n'
	exit 77
}

python3 - "$repo/config/quickshell" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
failures = []


def source(relative):
    return re.sub(r"\s+", " ", (root / relative).read_text())


def need(relative, fragment, why):
    if fragment not in source(relative):
        failures.append(f"{relative}: {why}: missing `{fragment}`")


# Each model reports its finite initial reads, never a resident watch.
for relative, expression in (
    ("network/NetworkModel.qml", "snapshotProcess.running || editorCheckProcess.running"),
    ("controls/BluetoothModel.qml",
     "snapshotProcess.running || statusProcess.running || devicesProcess.running"),
    ("controls/ControlsModel.qml",
     "audioSnapshotProcess.running || volumeStatusProcess.running || micStatusProcess.running "
     "|| mediaStatusProcess.running || bluetoothStatusProcess.running"),
    ("defaults/AutostartModel.qml", "snapshotProcess.running || root.snapshotPending"),
    ("defaults/DefaultAppsModel.qml", "snapshotProcess.running || root.snapshotPending"),
    ("power/PowerModel.qml", "snapshotProcess.running || root.snapshotPending"),
    ("accessibility/AccessibilityModel.qml", "statusProcess.running || root.refreshPending"),
    ("panel/PanelSettingsModel.qml", "statusProcess.running || root.refreshPending"),
    ("notifications/NotificationModel.qml",
     'policyState === "loading" || policyState === "defaults" || policySaving'),
    ("systemmanagement/SystemManagementModel.qml",
     "root.settingsVisible && (!root.discoveryReady() || root.snapshotOwned || root.snapshotPending "
     "|| root.requiredPending)"),
    ("appearance/AppearanceModel.qml",
     "snapshotProcess.running || root.snapshotPending || readinessProcess.running "
     "|| root.mutationReadinessPending || previewStatusProcess.running || recoveryStatusProcess.running "
     "|| root.wallpaperStatusBusy || root.fontStatusBusy || root.toolkitStatusBusy "
     "|| root.toolkitStatusPending || root.fontStatusPending || picomModel.statusBusy"),
):
    need(relative, f"readonly property bool initialLoading: {expression}", "initialLoading")
need("system/UpdateModel.qml",
     "readonly property bool initialLoading: versionProcess.running || backupsProcess.running", "the update card's reads")
need("settings/SettingsWindow.qml",
     "dataLoading: root.systemManagementModel.initialLoading || root.updateModel.initialLoading",
     "the System pane waits for the update card")
need("appearance/PicomModel.qml",
     "readonly property bool statusBusy: statusProcess.running || root.pending", "statusBusy")
need("settings/SettingsModel.qml",
     "readonly property bool displayActionBusy: displayActionProcess.running", "displayActionBusy")
need("settings/SettingsModel.qml",
     "readonly property bool inputActionBusy: inputActionProcess.running", "inputActionBusy")

# The rule for a queued-refresh flag lives in one place, core/QueuedRun.qml, and
# no list of files or flags below has to know about a new model.
helper = (root / "core/QueuedRun.qml").read_text()
if not re.search(r"process\.running = true;\s+owner\[flag\] = false;", helper):
    failures.append("core/QueuedRun.qml: the flag must clear right after the start, and nowhere before it")
if not re.search(r"if \(blocked \|\| process\.running\) \{\s+owner\[flag\] = true;\s+return false;", helper):
    failures.append("core/QueuedRun.qml: a blocked or running process must queue and not start")
if helper.count("owner[flag] = false;") != 1:
    failures.append("core/QueuedRun.qml: the flag is cleared in more than one place")

pending = re.compile(r"\w*[Pp]ending")
for path in sorted(root.rglob("*.qml")):
    relative = path.relative_to(root).as_posix()
    if relative == "core/QueuedRun.qml":
        continue
    text = path.read_text()
    # The old hand-written idiom: a start followed by clearing the queue flag. A
    # model that does this again has stopped using the one place that gets it right.
    for match in re.finditer(r"\.running = true;\s*\n\s*root\.(" + pending.pattern + r") = false;", text):
        line = text.count("\n", 0, match.start()) + 1
        failures.append(f"{relative}:{line}: clears `{match.group(1)}` by hand after a start; use QueuedRun.startOrQueue")
    # Every flag handed to the helper is a real property of that model: a typo
    # would create a plain JavaScript property and queue nothing.
    queued = set()
    for match in re.finditer(r'QueuedRun\.startOrQueue\(\s*\w+,\s*root,\s*"(\w+)"', text):
        queued.add(match.group(1))
        if not re.search(r"property bool " + match.group(1) + r"\b", text):
            line = text.count("\n", 0, match.start()) + 1
            failures.append(f"{relative}:{line}: QueuedRun flag `{match.group(1)}` is not a `property bool` of this model")
    # ...and never inside a process's onRunningChanged, which would clear it while
    # the retry that will start the next read is still only scheduled.
    for match in re.finditer(r"onRunningChanged:", text):
        opening = text.find("{", match.end())
        if opening < 0 or "\n" in text[match.end():opening]:
            continue  # a one-line handler has no block to hold a clear
        depth, index = 0, opening
        while index < len(text):
            depth += {"{": 1, "}": -1}.get(text[index], 0)
            index += 1
            if depth == 0:
                break
        block = text[opening:index]
        for found in re.finditer(r"root\.(" + "|".join(sorted(queued) or ["(?!)"]) + r") = false;", block):
            line = text.count("\n", 0, opening) + 1
            failures.append(f"{relative}:{line}: onRunningChanged clears `{found.group(0)}`")

# The two exit handlers that retry a queued inventory read share one named
# function: two closures ran the read twice in a tick and bumped its generation twice.
if re.search(r"Qt\.callLater\(function\(\) \{ root\.refreshInventory", (root / "appearance/AppearanceModel.qml").read_text()):
    failures.append("appearance/AppearanceModel.qml: an anonymous closure retries the inventory read again")

# The window holds each pane until its models report ready.
window = (root / "settings/SettingsWindow.qml").read_text()
panes = window.count("DeferredSettingsPane {")
loading = len(re.findall(r"^\s+dataLoading: ", window, re.M))
if panes != 9 or loading != panes:
    failures.append(f"settings/SettingsWindow.qml: {panes} panes but {loading} dataLoading lines")
if "desktopUpdateModel" in window:
    failures.append("settings/SettingsWindow.qml: names upstream's declined desktopUpdateModel (D-8)")
pane = source("settings/DeferredSettingsPane.qml")
for fragment in ("property bool dataLoading: false", "property bool presented: false", "!dataLoading",
                 "property int loadingTimeoutMs: 5000", "id: loadingCap"):
    if fragment not in pane:
        failures.append(f"settings/DeferredSettingsPane.qml: missing `{fragment}`")
if "fadeIn" in pane or "NumberAnimation" in pane:
    failures.append("settings/DeferredSettingsPane.qml: still animates S3-05's fade-in")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("Settings loading contract: PASS")
PY
