#!/usr/bin/python3
"""Sync Sprint 12 S12-08: the shell side of a state update.

Loads the real DwmState, OverviewModel and WindowOverview in Quickshell (under
xvfb-run and dbus-run-session, see `make check-quickshell-state-model-xvfb`)
against a stub `dwm-quickshell-state watch` on PATH that sends a state, the same
state again, then the same state with one window's title changed. Checked:

1. An identical state notifies nothing: no list is reassigned, so no view of it
   rebuilds.
2. A title change notifies the window list and the title, not the running apps,
   the monitor rows or the status segments.
3. The closed overview holds no cards, while its window count stays live (the
   windowCount IPC reads it); opening it shows a card per window.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import lyona_tmp  # noqa: F401,E402  (workspaces under the test root, not /tmp)

repo = Path(__file__).resolve().parents[1]
if not shutil.which('quickshell') or not os.environ.get('DISPLAY'):
    print('SKIP: quickshell or an X display is unavailable')
    raise SystemExit(77)

WINDOWS = 6

SHELL = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.overview
import qs.state

ShellRoot {
    id: root

    property var counts: ({ "windowStates": 0, "runningApps": 0, "monitorWorkspaceRows": 0,
                            "statusSegments": 0, "activeWindowTitle": 0, "workspaceNames": 0 })

    function bump(name) {
        const next = Object.assign({}, root.counts);
        next[name]++;
        root.counts = next;
    }

    DwmState {
        id: dwm

        onWindowStatesChanged: root.bump("windowStates")
        onRunningAppsChanged: root.bump("runningApps")
        onMonitorWorkspaceRowsChanged: root.bump("monitorWorkspaceRows")
        onStatusSegmentsChanged: root.bump("statusSegments")
        onActiveWindowTitleChanged: root.bump("activeWindowTitle")
        onWorkspaceNamesChanged: root.bump("workspaceNames")
    }

    OverviewModel { id: model; dwmState: dwm }

    PanelWindow {
        id: panel
        implicitHeight: 30
        anchors { top: true; left: true; right: true }
        color: "white"
        exclusiveZone: 30
    }

    WindowOverview { id: popup; overviewModel: model; panelWindow: panel }

    function cardCount() {
        let cards = 0;
        for (const group of popup.overviewFlickable.contentItem.children[0].children) {
            for (const card of group.children) {
                if (card.objectName === "overviewCard") {
                    cards++;
                }
            }
        }
        return cards;
    }

    IpcHandler {
        target: "t"
        function metrics(): string {
            return JSON.stringify({ counts: root.counts, windows: dwm.windowStates.length,
                                    title: dwm.windowStates.length ? dwm.windowStates[0].title : "",
                                    liveCards: model.flatCards.length, cards: root.cardCount(),
                                    visible: model.visible });
        }
        function open(): void { model.open(null); }
        function close(): void { model.close(); }
    }
}
'''



def window_list(first_title):
    return '|'.join('0x%x:%d:app%d:%s' % (0x100 + i, i % 3, i % 2, first_title if i == 0 else 'window %d a' % i)
                    for i in range(WINDOWS))


STUB = r'''#!/bin/sh
[ "$1" = watch ] || exit 0
block() {
	printf 'current=0\nmonitor_desktops=0,0,640,480,0\nfocused_monitor=0\nlayout=0\ncount=9\n'
	printf 'names=1|2|3|4|5|6|7|8|9\noccupied=0|1|2\nfullscreen_monitors=\n'
	printf 'apps=0x100:app0|0x101:app1\nwindows=%s\n' "$1"
	printf 'active_window=0x100\ntitle=window 0\nclass=app0\nstatus=CPU 3%%  |  MEM 20%%\n\n'
}
block "__FIRST__"
while [ ! -e "$STUB_DIR/again" ]; do sleep 0.05; done
block "__FIRST__"
while [ ! -e "$STUB_DIR/title" ]; do sleep 0.05; done
block "__SECOND__"
exec sleep 1000
'''.replace('__FIRST__', window_list('window 0 a')).replace('__SECOND__', window_list('window 0 b'))


def fail(message, extra=''):
    print('FAIL: ' + message, file=sys.stderr)
    if extra:
        print(extra, file=sys.stderr)
    raise SystemExit(1)


with tempfile.TemporaryDirectory(prefix='state-model-', dir=os.environ.get('DWM_TEST_TMP_ROOT')) as temp:
    base = Path(temp)
    config = base / 'config'
    qml = config / 'quickshell'
    qml.mkdir(parents=True)
    for name in ('core', 'overview', 'state'):
        shutil.copytree(repo / 'config/quickshell' / name, qml / name)
    (qml / 'shell.qml').write_text(SHELL)
    bindir = base / 'bin'
    bindir.mkdir()
    (bindir / 'dwm-quickshell-state').write_text(STUB)
    (bindir / 'dwm-quickshell-state').chmod(0o755)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    env = {**os.environ, 'HOME': str(base), 'XDG_CONFIG_HOME': str(config), 'XDG_DATA_HOME': str(base / 'data'),
           'XDG_STATE_HOME': str(base / 'state'), 'XDG_RUNTIME_DIR': str(runtime),
           'PATH': '%s:%s' % (bindir, os.environ['PATH']), 'STUB_DIR': str(base),
           'QT_QPA_PLATFORM': 'xcb', 'QT_QPA_PLATFORMTHEME': ''}
    log = (base / 'quickshell.log').open('w+')
    shell = subprocess.Popen(['quickshell', '--no-duplicate'], env=env, stdout=log, stderr=log,
                             start_new_session=True)

    def call(*args):
        result = subprocess.run(['quickshell', 'ipc', 'call', 't', *args], env=env, capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else ''

    def metrics():
        text = call('metrics')
        return json.loads(text) if text else {}

    def wait_for(predicate, message, seconds=10):
        deadline = time.time() + seconds
        while time.time() < deadline:
            current = metrics()
            if current and predicate(current):
                return current
            time.sleep(0.05)
        log.seek(0)
        fail(message + ': ' + json.dumps(metrics()), log.read()[-2000:])

    try:
        first = wait_for(lambda m: m['windows'] == WINDOWS, 'the first state did not arrive', 15)
        time.sleep(0.5)
        first = metrics()

        (base / 'again').touch()
        time.sleep(1)
        again = metrics()
        if again['counts'] != first['counts']:
            fail('an identical state notified %s (was %s)' % (again['counts'], first['counts']))

        (base / 'title').touch()
        changed = wait_for(lambda m: m['title'] == 'window 0 b', 'the title change did not arrive')
        delta = {k: changed['counts'][k] - first['counts'][k] for k in first['counts']}
        want = {'windowStates': 1, 'runningApps': 0, 'monitorWorkspaceRows': 0, 'statusSegments': 0,
                'activeWindowTitle': 0, 'workspaceNames': 0}
        if delta != want:
            fail('a title change notified %s, not %s' % (delta, want))

        if changed['cards'] != 0 or changed['liveCards'] != WINDOWS:
            fail('closed, the overview holds %d cards and counts %d windows (want 0 and %d)'
                 % (changed['cards'], changed['liveCards'], WINDOWS))
        call('open')
        opened = wait_for(lambda m: m['visible'] and m['cards'] == WINDOWS, 'opening did not show every card')
        call('close')
        wait_for(lambda m: not m['visible'] and m['cards'] == 0, 'closing did not drop the cards')
        log.seek(0)
        output = log.read()
        if 'TypeError:' in output or 'ReferenceError:' in output:
            fail('QML errors', output[-2000:])
        print('State model: %s' % json.dumps({'title_change': delta, 'cards_closed': changed['cards'],
                                              'cards_open': opened['cards']}))
    finally:
        try:
            os.killpg(shell.pid, 9)
        except ProcessLookupError:
            pass
        shell.wait()
        log.close()

print('Quickshell state model (identical state notifies nothing, closed overview holds no cards): PASS')
