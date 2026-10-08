#!/usr/bin/python3
"""#244: how long the overview takes to show its window previews, and what it costs.

Not part of `make check`: a measurement, run by hand on the machines in
docs/evidence/244-picom-required.md. Built on tests/test-overview-thumbnails-xvfb.py:
the real dwm, Picom (lyona's default configuration, XRender), the real
dwm-window-thumb, and Quickshell with the real OverviewModel and WindowOverview.

For each count in DWM_PREVIEW_WINDOWS (default 10,60,200) it starts that many real
windows (feh, each a different colour), spread over the nine tags, opens the overview
and records:

  first_frame_ms   from "open" until the overview is visible with its cards
  previews_ms      from "open" until every card on screen shows its preview
  on_screen        how many cards that was
  peak_cpu_pct     highest CPU of Quickshell, Picom and the X server, sampled
                   every 100 ms while it was open
  peak_rss_mib     highest resident memory of Quickshell and Picom meanwhile
  back_to_idle_s   after closing, until Quickshell's CPU over 500 ms is within
                   0.5 points of its idle before opening

It prints one JSON line per count and exits 0. DWM_PREVIEW_STRICT=1 asserts the
pass levels proposed in the issue: previews within 500 ms with 60 windows, and
back to idle within 3 s. Exits 77 (skip) without Xvfb, picom, feh, xdotool,
quickshell or the built programs.
"""
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
for tool in ('Xvfb', 'picom', 'feh', 'xdotool', 'quickshell'):
    if not shutil.which(tool):
        print('SKIP: %s is unavailable' % tool)
        raise SystemExit(77)
if not (repo / 'dwm').exists() or not (repo / 'dwm-window-thumb').exists():
    print('SKIP: dwm or dwm-window-thumb is not built (run make all)')
    raise SystemExit(77)

from PIL import Image  # noqa: E402

temp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT') or os.environ.get('TMPDIR') or Path.home() / 'tmp')
temp_root.mkdir(parents=True, exist_ok=True)
COUNTS = [int(n) for n in os.environ.get('DWM_PREVIEW_WINDOWS', '10,60,200').split(',') if n.strip()]
STRICT = os.environ.get('DWM_PREVIEW_STRICT') == '1'
HZ = os.sysconf('SC_CLK_TCK')

SHELL = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.overview

ShellRoot {
    id: root

    QtObject {
        id: dwm

        property var windowStates: []
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

    function cards(item, found) {
        if (item.objectName === "overviewCard") found.push(item);
        for (const child of item.children) root.cards(child, found);
        return found;
    }

    function previewOf(item) {
        if (item.objectName === "overviewPreview") return item;
        for (const child of item.children) {
            const found = root.previewOf(child);
            if (found) return found;
        }
        return null;
    }

    IpcHandler {
        target: "ov"
        function setWindows(payload: string): void { dwm.windowStates = JSON.parse(payload).windows; }
        function open(): void { model.open(null); }
        function close(): void { model.close(); }
        function state(): string {
            const flick = popup.overviewFlickable;
            const found = root.cards(flick.contentItem, []);
            let onScreen = 0, ready = 0;
            for (const card of found) {
                const top = card.mapToItem(flick, 0, 0).y;
                if (top + card.height <= 0 || top >= flick.height) continue;
                onScreen++;
                const preview = root.previewOf(card);
                if (preview && preview.visible) ready++;
            }
            return JSON.stringify({ visible: model.visible, cards: found.length,
                                    onScreen: onScreen, ready: ready });
        }
    }
}
'''


def ticks(pid):
    try:
        fields = Path('/proc/%d/stat' % pid).read_text().rsplit(')', 1)[1].split()
    except OSError:
        return 0
    return int(fields[11]) + int(fields[12])


def rss_mib(pid):
    try:
        for line in Path('/proc/%d/status' % pid).read_text().splitlines():
            if line.startswith('VmRSS:'):
                return int(line.split()[1]) / 1024
    except OSError:
        pass
    return 0.0


def measure(count):
    with tempfile.TemporaryDirectory(prefix='overview-previews-', dir=str(temp_root)) as temp:
        base = Path(temp)
        config = base / 'config'
        qml = config / 'quickshell'
        qml.mkdir(parents=True)
        runtime = base / 'runtime'
        runtime.mkdir(mode=0o700)
        (config / 'lyona').mkdir()
        for name in ('core', 'overview', 'state'):
            shutil.copytree(repo / 'config/quickshell' / name, qml / name)
        (qml / 'shell.qml').write_text(SHELL)
        helper_dir = base / 'bin'
        helper_dir.mkdir()
        (helper_dir / 'dwm-window-thumb').symlink_to(repo / 'dwm-window-thumb')

        pictures = []
        for index in range(count):
            picture = base / ('p%d.png' % index)
            Image.new('RGB', (64, 40), ((index * 53) % 256, (index * 97) % 256, (index * 151) % 256)).save(picture)
            pictures.append(picture)

        read_fd, write_fd = os.pipe()
        xvfb = subprocess.Popen(
            ['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1920x1080x24', '-nolisten', 'tcp',
             '+extension', 'Composite'],
            pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(write_fd)
        display = ':' + os.read(read_fd, 32).decode().strip()
        os.close(read_fd)
        env = {**os.environ, 'DISPLAY': display, 'PATH': '%s:%s' % (helper_dir, os.environ['PATH']),
               'XDG_RUNTIME_DIR': str(runtime), 'HOME': str(base), 'XDG_CONFIG_HOME': str(config),
               'XDG_DATA_HOME': str(base / 'data'), 'XDG_STATE_HOME': str(base / 'state'),
               'QT_QPA_PLATFORM': 'xcb', 'QT_QPA_PLATFORMTHEME': ''}
        log = (base / 'runtime.log').open('w+')
        procs = [xvfb]

        def spawn(*args, **kwargs):
            proc = subprocess.Popen(list(args), env=env, **kwargs)
            procs.append(proc)
            return proc

        def run(*args):
            return subprocess.run(args, env=env, capture_output=True, text=True)

        def state():
            result = run('quickshell', 'ipc', 'call', 'ov', 'state')
            return json.loads(result.stdout) if result.returncode == 0 and result.stdout.strip() else {}

        def wait_for(predicate, message, seconds):
            deadline = time.time() + seconds
            while time.time() < deadline:
                current = state()
                if current and predicate(current):
                    return current
                time.sleep(0.02)
            raise AssertionError(message + ': ' + json.dumps(state()))

        def all_windows():
            return set(run('xdotool', 'search', '--name', '^pw[0-9]+$').stdout.split())

        try:
            time.sleep(0.3)
            spawn(str(repo / 'dwm'), stdout=log, stderr=log)
            time.sleep(0.8)
            lyona_default = repo / 'config/picom/picom.conf'
            picom = spawn('picom', '--config', str(lyona_default), '--backend', 'xrender',
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(1.0)

            # The windows, a ninth on each tag: dwm puts a new window on the tag shown.
            windows, seen = [], set()
            for tag in range(9):
                run('xdotool', 'set_desktop', str(tag)).check_returncode()
                share = [i for i in range(count) if i % 9 == tag]
                for index in share:
                    spawn('feh', '--auto-zoom', '--zoom', 'fill', '--title', 'pw%d' % index, str(pictures[index]),
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                deadline = time.time() + 30
                while time.time() < deadline and len(all_windows() - seen) < len(share):
                    time.sleep(0.1)
                new = all_windows() - seen
                assert len(new) == len(share), ('windows did not appear on tag %d' % tag, len(new), len(share))
                seen |= new
                windows += [{'windowId': '0x%x' % int(w), 'desktop': tag, 'appClass': 'feh',
                             'title': 'window %s' % w} for w in sorted(new)]
            # Show the first tag: the rest are mapped but off screen.
            run('xdotool', 'set_desktop', '0').check_returncode()
            time.sleep(1.0)

            shell = spawn('quickshell', '--no-duplicate', stdout=log, stderr=log)
            wait_for(lambda s: True, 'IPC unavailable', 20)
            assert run('quickshell', 'ipc', 'call', 'ov', 'setWindows', json.dumps({'windows': windows})).returncode == 0
            time.sleep(2.0)

            def cpu(pid, seconds):
                before, started = ticks(pid), time.time()
                time.sleep(seconds)
                return (ticks(pid) - before) / HZ / (time.time() - started) * 100

            idle = cpu(shell.pid, 3.0)

            # Peak CPU and memory while open, sampled every 100 ms.
            watched = {'quickshell': shell.pid, 'picom': picom.pid, 'xserver': xvfb.pid}
            peak_cpu = {name: 0.0 for name in watched}
            peak_rss = {'quickshell': 0.0, 'picom': 0.0}
            sampling = threading.Event()

            def sampler():
                last = {name: ticks(pid) for name, pid in watched.items()}
                then = time.time()
                while not sampling.wait(0.1):
                    now = time.time()
                    for name, pid in watched.items():
                        current = ticks(pid)
                        peak_cpu[name] = max(peak_cpu[name], (current - last[name]) / HZ / (now - then) * 100)
                        last[name] = current
                    for name in peak_rss:
                        peak_rss[name] = max(peak_rss[name], rss_mib(watched[name]))
                    then = now

            thread = threading.Thread(target=sampler, daemon=True)
            thread.start()
            started = time.time()
            assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
            framed = wait_for(lambda s: s['visible'] and s['cards'] == count, 'the overview did not open', 30)
            first_frame_ms = (time.time() - started) * 1000
            done = wait_for(lambda s: s['onScreen'] > 0 and s['ready'] == s['onScreen'],
                            'the on-screen previews did not all arrive', 60)
            previews_ms = (time.time() - started) * 1000
            time.sleep(1.0)
            sampling.set()
            thread.join()

            # Closed through IPC: Escape reaches whichever feh window has the focus, and
            # keyboard closing is covered by the overview's own tests.
            assert run('quickshell', 'ipc', 'call', 'ov', 'close').returncode == 0
            wait_for(lambda s: not s['visible'], 'the overview did not close', 10)
            closed = time.time()
            back_to_idle_s = None
            while time.time() - closed < 15:
                if cpu(shell.pid, 0.5) <= idle + 0.5:
                    back_to_idle_s = time.time() - closed
                    break

            report = {
                'windows': count,
                'first_frame_ms': round(first_frame_ms),
                'previews_ms': round(previews_ms),
                'on_screen': done['onScreen'],
                'idle_cpu_pct': round(idle, 2),
                'peak_cpu_pct': {k: round(v, 1) for k, v in peak_cpu.items()},
                'peak_rss_mib': {k: round(v, 1) for k, v in peak_rss.items()},
                'back_to_idle_s': None if back_to_idle_s is None else round(back_to_idle_s, 2),
            }
            print(json.dumps(report), flush=True)
            assert framed['cards'] == count
            if STRICT:
                if count == 60:
                    assert previews_ms <= 500, report
                assert back_to_idle_s is not None and back_to_idle_s <= 3, report
            return report
        finally:
            for proc in reversed(procs):
                proc.terminate()
            for proc in procs:
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
            log.close()


for count in COUNTS:
    measure(count)
print('Overview previews measured: %s' % ', '.join(str(c) for c in COUNTS))
