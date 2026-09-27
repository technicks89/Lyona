#!/usr/bin/python3
"""Sync Sprint 9 S9-03: drive the window overview with real key events only.

Runs the real dwm and Quickshell in an isolated X11 session and loads the real
OverviewModel and WindowOverview against a stub dwmState. Then, with no mouse event
sent at all: open the overview, type a filter, move the selection, close the
selected card with Ctrl+W, activate one with Enter, and dismiss with Escape.
"""
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
for tool in ('xdotool', 'quickshell', 'xvfb-run', 'dbus-run-session'):
    if not shutil.which(tool):
        print('SKIP: %s is unavailable' % tool)
        raise SystemExit(77)
if not (repo / 'dwm').exists():
    print('SKIP: dwm is not built (run make all)')
    raise SystemExit(77)
temp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT') or os.environ.get('TMPDIR') or Path.home() / 'tmp')
temp_root.mkdir(parents=True, exist_ok=True)

SHELL = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.overview

ShellRoot {
    id: root

    property var focused: []
    property var closed: []

    QtObject {
        id: dwm

        property var windowStates: [
            { "windowId": "0x1", "desktop": 0, "appClass": "kitty", "title": "build log" },
            { "windowId": "0x2", "desktop": 0, "appClass": "firefox", "title": "docs" },
            { "windowId": "0x3", "desktop": 1, "appClass": "kitty", "title": "ssh prod" }
        ]
        property var monitorWorkspaceRows: []
        property var workspaceNames: ["1", "2", "3"]

        function monitorCount() { return 1; }
        function focusWindow(windowId) { root.focused = root.focused.concat([windowId]); }
        function closeWindow(windowId) { root.closed = root.closed.concat([windowId]); }
    }

    OverviewModel { id: model; dwmState: dwm }

    PanelWindow {
        id: panel
        implicitHeight: 30
        anchors { top: true; left: true; right: true }
        color: "white"
        exclusiveZone: 30
    }

    WindowOverview { overviewModel: model; panelWindow: panel }

    IpcHandler {
        target: "ov"
        function open(): void { model.open(null); }
        function state(): string {
            return JSON.stringify({
                visible: model.visible,
                query: model.query,
                selected: model.selectedIndex,
                ids: model.flatCards.map(function(c) { return c.windowId; }),
                focused: root.focused,
                closed: root.closed
            });
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix='overview-keys-', dir=str(temp_root)) as temp:
    base = Path(temp)
    config = base / 'config'
    qml = config / 'quickshell'
    qml.mkdir(parents=True)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    for name in ('core', 'overview', 'state'):
        shutil.copytree(repo / 'config/quickshell' / name, qml / name)
    (qml / 'shell.qml').write_text(SHELL)
    env = {
        **os.environ,
        'XDG_RUNTIME_DIR': str(runtime),
        'HOME': str(base),
        'XDG_CONFIG_HOME': str(config),
        'XDG_DATA_HOME': str(base / 'data'),
        'XDG_STATE_HOME': str(base / 'state'),
        'QT_QPA_PLATFORM': 'xcb',
        'QT_QPA_PLATFORMTHEME': '',
    }
    log = (base / 'runtime.log').open('w+')
    wm = subprocess.Popen([str(repo / 'dwm')], env=env, stdout=log, stderr=log)
    shell = subprocess.Popen(['quickshell', '--no-duplicate'], env=env, stdout=log, stderr=log)

    def run(*args):
        return subprocess.run(args, env=env, capture_output=True, text=True)

    def state():
        result = run('quickshell', 'ipc', 'call', 'ov', 'state')
        return json.loads(result.stdout) if result.returncode == 0 and result.stdout.strip() else {}

    def wait_for(predicate, message, seconds=6):
        deadline = time.time() + seconds
        while time.time() < deadline:
            current = state()
            if current and predicate(current):
                return current
            time.sleep(0.08)
        raise AssertionError(message + ': ' + json.dumps(state()))

    def key(*names):
        run('xdotool', 'key', '--clearmodifiers', *names).check_returncode()

    try:
        wait_for(lambda s: True, 'IPC unavailable', 10)
        assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
        opened = wait_for(lambda s: s['visible'], 'the overview did not open')
        assert opened['ids'] == ['0x1', '0x2', '0x3'], opened
        time.sleep(0.5)

        # Navigation: Down moves the selection, End and Home jump, with no mouse.
        key('Down')
        wait_for(lambda s: s['selected'] == 1, 'Down did not move the selection')
        key('End')
        wait_for(lambda s: s['selected'] == 2, 'End did not select the last card')
        key('Home')
        wait_for(lambda s: s['selected'] == 0, 'Home did not select the first card')

        # Type-to-filter goes to the focused search box.
        run('xdotool', 'type', '--delay', '40', 'kit').check_returncode()
        filtered = wait_for(lambda s: s['query'] == 'kit', 'typing did not reach the search box')
        assert filtered['ids'] == ['0x1', '0x3'], filtered

        # Ctrl+W closes the selected card's window and leaves the popup open.
        key('Down')
        wait_for(lambda s: s['selected'] == 1, 'Down did not move within the filtered list')
        key('ctrl+w')
        closed = wait_for(lambda s: s['closed'] == ['0x3'], 'Ctrl+W did not close the selected card')
        assert closed['visible'], 'closing a card must keep the overview open'
        assert closed['ids'] == ['0x1'], closed

        # Enter activates the (now only) card and closes the overview.
        key('Return')
        activated = wait_for(lambda s: not s['visible'], 'Enter did not close the overview')
        assert activated['focused'] == ['0x1'], activated

        # Reopen, and Escape dismisses it.
        assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
        wait_for(lambda s: s['visible'], 'the overview did not reopen')
        time.sleep(0.4)
        key('Escape')
        wait_for(lambda s: not s['visible'], 'Escape did not dismiss the overview')

        assert wm.poll() is None and shell.poll() is None
        log.seek(0)
        output = log.read()
        assert 'TypeError:' not in output and 'ReferenceError:' not in output, output[-2000:]
        print('Overview keyboard-only walkthrough (open, navigate, filter, close, activate, dismiss): PASS')
    except BaseException:
        log.seek(0)
        print(log.read()[-4000:])
        raise
    finally:
        shell.terminate()
        shell.wait(timeout=5)
        wm.terminate()
        wm.wait(timeout=5)
        log.close()
