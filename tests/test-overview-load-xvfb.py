#!/usr/bin/python3
"""Sync Sprint 9 S9-04: the window overview under load, and what it costs idle.

Runs the real dwm and Quickshell in an isolated X11 session and loads the real
OverviewModel and WindowOverview against a stub dwmState holding MANY windows
(60 across 9 tags, far more than a normal session). It then checks, with real key
events:

1. Idle cost: the Quickshell process's CPU over a window of time with the overview
   never opened, against the same window after opening and closing it several
   times. Opening it must not leave anything running.
2. Load: the overview opens and lays out all its cards within a time budget, type
   to filter and keyboard navigation stay responsive, and the keyboard selection
   scrolls into view (End reaches the bottom of the list, Home the top).

It prints the measurements, which are the data behind the "does the card list need
virtualization" decision (docs/evidence/s9-04-overview-load.md).
DWM_OVERVIEW_CPU_SECONDS sets the length of each idle window (default 10; the plan's
30 is fine for a manual run).
"""
import json
import os
import shutil
import subprocess
import sys
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

WINDOWS = int(os.environ.get('DWM_OVERVIEW_WINDOWS', '60'))
IDLE_SECONDS = float(os.environ.get('DWM_OVERVIEW_CPU_SECONDS', '10'))
OPEN_BUDGET = float(os.environ.get('DWM_OVERVIEW_OPEN_BUDGET', '3.0'))
FILTER_BUDGET = float(os.environ.get('DWM_OVERVIEW_FILTER_BUDGET', '2.0'))
NAVIGATE_BUDGET = float(os.environ.get('DWM_OVERVIEW_NAVIGATE_BUDGET', '8.0'))
# Same budget as check-quickshell-large-surfaces-xvfb: closed CPU stays within half
# a percentage point of where it started.
CPU_BUDGET_POINTS = float(os.environ.get('DWM_OVERVIEW_CPU_BUDGET', '0.5'))

temp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT') or os.environ.get('TMPDIR') or Path.home() / 'tmp')
temp_root.mkdir(parents=True, exist_ok=True)

SHELL = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.overview

ShellRoot {
    id: root

    QtObject {
        id: dwm

        property var windowStates: {
            const list = [];
            for (let i = 0; i < __COUNT__; i++) {
                list.push({ "windowId": "0x" + (i + 1).toString(16), "desktop": i % 9, "appClass": "app" + (i % 7),
                            "title": "window number " + i });
            }
            return list;
        }
        property var monitorWorkspaceRows: []
        property var workspaceNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

        function monitorCount() { return 1; }
        function focusWindow(windowId) {}
        function closeWindow(windowId) {}
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

    IpcHandler {
        target: "ov"
        function open(): void { model.open(null); }
        function close(): void { model.close(); }
        function metrics(): string {
            const flick = popup.overviewFlickable;
            return JSON.stringify({
                visible: model.visible,
                query: model.query,
                selected: model.selectedIndex,
                cards: model.flatCards.length,
                contentHeight: flick.contentHeight,
                viewHeight: flick.height,
                contentY: flick.contentY
            });
        }
    }
}
'''.replace('__COUNT__', str(WINDOWS))


def rss_mib(pid):
    for line in Path('/proc/%d/status' % pid).read_text().splitlines():
        if line.startswith('VmRSS:'):
            return int(line.split()[1]) / 1024
    return 0.0


def ticks(pid):
    fields = Path('/proc/%d/stat' % pid).read_text().rsplit(')', 1)[1].split()
    return int(fields[11]) + int(fields[12])  # utime + stime


with tempfile.TemporaryDirectory(prefix='overview-load-', dir=str(temp_root)) as temp:
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

    def metrics():
        result = run('quickshell', 'ipc', 'call', 'ov', 'metrics')
        return json.loads(result.stdout) if result.returncode == 0 and result.stdout.strip() else {}

    def wait_for(predicate, message, seconds=10):
        deadline = time.time() + seconds
        while time.time() < deadline:
            current = metrics()
            if current and predicate(current):
                return current
            time.sleep(0.05)
        raise AssertionError(message + ': ' + json.dumps(metrics()))

    def key(*names):
        run('xdotool', 'key', '--clearmodifiers', *names).check_returncode()

    def cpu_percent(seconds):
        before, started = ticks(shell.pid), time.time()
        time.sleep(seconds)
        used = ticks(shell.pid) - before
        return used / os.sysconf('SC_CLK_TCK') / (time.time() - started) * 100

    report = {}
    try:
        state = wait_for(lambda s: True, 'IPC unavailable', 15)
        assert state['cards'] == WINDOWS, state
        time.sleep(1.5)  # let start-up settle before measuring anything
        report['rss_closed_mib'] = rss_mib(shell.pid)

        # 1. Idle cost, closed: never opened, then opened and closed several times.
        report['closed_before_pct'] = cpu_percent(IDLE_SECONDS)
        for _ in range(5):
            assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
            wait_for(lambda s: s['visible'], 'the overview did not open')
            time.sleep(0.3)
            key('Escape')
            wait_for(lambda s: not s['visible'], 'Escape did not close the overview')
        time.sleep(1.5)
        report['closed_after_pct'] = cpu_percent(IDLE_SECONDS)
        assert report['closed_after_pct'] <= report['closed_before_pct'] + CPU_BUDGET_POINTS, report
        assert report['closed_after_pct'] <= 1.0, report

        # 2. Load: open with every card in the list, and time it.
        started = time.time()
        assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
        laid_out = wait_for(lambda s: s['visible'] and s['contentHeight'] > s['viewHeight'] * 3,
                            'the cards did not lay out', 15)
        report['open_seconds'] = time.time() - started
        assert report['open_seconds'] <= OPEN_BUDGET, report
        assert laid_out['cards'] == WINDOWS, laid_out
        time.sleep(0.6)

        # Type to filter: only windows whose title has "number 5" remain.
        started = time.time()
        run('xdotool', 'type', '--delay', '10', 'number 5').check_returncode()
        filtered = wait_for(lambda s: s['query'] == 'number 5' and 0 < s['cards'] < WINDOWS,
                            'filtering did not settle')
        report['filter_seconds'] = time.time() - started
        assert report['filter_seconds'] <= FILTER_BUDGET, report
        report['filtered_cards'] = filtered['cards']
        run('xdotool', 'key', '--clearmodifiers', 'ctrl+a', 'BackSpace').check_returncode()
        wait_for(lambda s: s['query'] == '' and s['cards'] == WINDOWS, 'clearing the filter did not restore every card')

        # Keyboard navigation across the whole list, fast, and the selection scrolls.
        started = time.time()
        for _ in range(WINDOWS - 1):
            key('Down')
        reached = wait_for(lambda s: s['selected'] == WINDOWS - 1, 'Down presses were lost')
        report['navigate_seconds'] = time.time() - started
        assert report['navigate_seconds'] <= NAVIGATE_BUDGET, report
        time.sleep(0.5)
        bottom = metrics()
        assert bottom['contentY'] + bottom['viewHeight'] >= bottom['contentHeight'] - 4, (
            'the last card is not scrolled into view', bottom)
        key('Home')
        wait_for(lambda s: s['selected'] == 0, 'Home did not select the first card')
        time.sleep(0.5)
        top = metrics()
        assert top['contentY'] <= 2, ('the first card is not scrolled into view', top)
        key('End')
        wait_for(lambda s: s['selected'] == WINDOWS - 1, 'End did not select the last card')
        time.sleep(0.5)
        end = metrics()
        assert end['contentY'] + end['viewHeight'] >= end['contentHeight'] - 4, ('End did not scroll to the bottom', end)

        key('Escape')
        wait_for(lambda s: not s['visible'], 'Escape did not dismiss the overview')
        assert wm.poll() is None and shell.poll() is None
        log.seek(0)
        output = log.read()
        assert 'TypeError:' not in output and 'ReferenceError:' not in output, output[-2000:]
        print('Overview under load (%d windows on 9 tags): %s' % (WINDOWS, json.dumps({k: round(v, 3) for k, v in report.items()})))
        print('Overview idle cost and load: PASS')
    except BaseException:
        log.seek(0)
        print(log.read()[-4000:])
        print('measurements so far:', json.dumps(report))
        raise
    finally:
        shell.terminate()
        shell.wait(timeout=5)
        wm.terminate()
        wm.wait(timeout=5)
        log.close()
