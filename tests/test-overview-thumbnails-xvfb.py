#!/usr/bin/python3
"""Sync Sprint 9 S9-01: window previews in the overview, end to end.

Runs the real dwm, Picom, dwm-window-thumb and Quickshell with the real OverviewModel and
WindowOverview. Real windows (feh, each a different picture) sit on a tag that is not
being shown, which is the case previews exist for, next to dozens of stand-in windows.
A wrapper around the helper logs every capture it is asked for. Checks:

1. With Picom running, opening the overview gives the cards on screen a preview (the
   card grows to hold it) while the cards below the fold are not captured at all, and
   scrolling to them captures them. Captures never overlap.
2. Closing the overview deletes every stored preview, and reopening captures again.
3. Without a compositor, without the helper installed, or with previews switched off,
   the overview still opens and lists its windows with the compact icon-and-title
   cards, and nothing is captured.
4. Closed, the shell is idle after all that.

Exits 77 (skip) without Xvfb, picom, feh, xdotool, quickshell or the built programs.
"""
import json
import os
import shutil
import stat
import subprocess
import tempfile
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

FAKE = 45  # stand-in windows that do not exist as X windows: the helper answers "gone"
IDLE_SECONDS = float(os.environ.get('DWM_OVERVIEW_CPU_SECONDS', '6'))

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

    IpcHandler {
        target: "ov"
        function setWindows(json: string): void { dwm.windowStates = JSON.parse(json); }
        function open(): void { model.open(null); }
        function close(): void { model.close(); }
        function state(): string {
            const found = root.cards(popup.overviewFlickable.contentItem, []);
            const info = {};
            for (const card of found) {
                const preview = root.previewOf(card);
                info[card.window.windowId] = { height: card.height, ready: preview ? preview.visible : false };
            }
            return JSON.stringify({
                visible: model.visible,
                available: model.thumbnailsAvailable,
                previews: Object.keys(model.thumbnails),
                cards: info,
                contentY: popup.overviewFlickable.contentY,
                contentHeight: popup.overviewFlickable.contentHeight,
                viewHeight: popup.overviewFlickable.height
            });
        }
    }

    function previewOf(item) {
        if (item.objectName === "overviewPreview") return item;
        for (const child of item.children) {
            const found = root.previewOf(child);
            if (found) return found;
        }
        return null;
    }
}
'''


def ticks(pid):
    fields = Path('/proc/%d/stat' % pid).read_text().rsplit(')', 1)[1].split()
    return int(fields[11]) + int(fields[12])


with tempfile.TemporaryDirectory(prefix='overview-thumbs-', dir=str(temp_root)) as temp:
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

    # A directory on PATH that holds a logging wrapper around the real helper.
    wrapper_dir = base / 'bin'
    wrapper_dir.mkdir()
    capture_log = base / 'captures.log'
    wrapper = wrapper_dir / 'dwm-window-thumb'
    wrapper.write_text('#!/bin/sh\n'
                       'if [ "$1" = capture ]; then printf "start %%s\\n" "$2" >>"%(log)s"; fi\n'
                       '"%(real)s" "$@"; status=$?\n'
                       'if [ "$1" = capture ]; then printf "end %%s %%s\\n" "$2" "$status" >>"%(log)s"; fi\n'
                       'exit $status\n' % {'log': capture_log, 'real': repo / 'dwm-window-thumb'})
    wrapper.chmod(0o755)
    empty_bin = base / 'nothing'
    empty_bin.mkdir()

    pictures = []
    for index, colour in enumerate(((200, 40, 40), (40, 200, 40), (40, 40, 200))):
        picture = base / ('picture%d.png' % index)
        Image.new('RGB', (320, 200), colour).save(picture)
        pictures.append(picture)

    read_fd, write_fd = os.pipe()
    xvfb = subprocess.Popen(
        ['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1024x768x24', '-nolisten', 'tcp', '+extension', 'Composite'],
        pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(write_fd)
    display = ':' + os.read(read_fd, 32).decode().strip()
    os.close(read_fd)
    path_with_helper = '%s:%s' % (wrapper_dir, os.environ['PATH'])
    env = {
        **os.environ,
        'DISPLAY': display,
        'PATH': path_with_helper,
        'XDG_RUNTIME_DIR': str(runtime),
        'HOME': str(base),
        'XDG_CONFIG_HOME': str(config),
        'XDG_DATA_HOME': str(base / 'data'),
        'XDG_STATE_HOME': str(base / 'state'),
        'QT_QPA_PLATFORM': 'xcb',
        'QT_QPA_PLATFORMTHEME': '',
    }
    log = (base / 'runtime.log').open('w+')
    procs = [xvfb]
    picom = None

    def spawn(*args, **kwargs):
        proc = subprocess.Popen(list(args), env=env, **kwargs)
        procs.append(proc)
        return proc

    def run(*args):
        return subprocess.run(args, env=env, capture_output=True, text=True)

    def state():
        result = run('quickshell', 'ipc', 'call', 'ov', 'state')
        return json.loads(result.stdout) if result.returncode == 0 and result.stdout.strip() else {}

    def wait_for(predicate, message, seconds=10):
        deadline = time.time() + seconds
        while time.time() < deadline:
            current = state()
            if current and predicate(current):
                return current
            time.sleep(0.1)
        raise AssertionError(message + ': ' + json.dumps(state())[:1500])

    def key(*names):
        run('xdotool', 'key', '--clearmodifiers', *names).check_returncode()

    def stored():
        directory = runtime / 'lyona' / 'overview-thumbs'
        return sorted(p.name for p in directory.iterdir()) if directory.is_dir() else []

    def captures():
        if not capture_log.exists():
            return []
        return [line.split() for line in capture_log.read_text().splitlines()]

    def close_overview():
        key('Escape')
        wait_for(lambda s: not s['visible'], 'Escape did not close the overview')

    try:
        time.sleep(0.3)
        spawn(str(repo / 'dwm'), stdout=log, stderr=log)
        time.sleep(0.8)
        real_ids = []
        for index, picture in enumerate(pictures):
            spawn('feh', '--auto-zoom', '--zoom', 'fill', '--title', 'thumb%d' % index, str(picture),
                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for _ in range(60):
                found = run('xdotool', 'search', '--name', 'thumb%d' % index).stdout.split()
                if found:
                    real_ids.append('0x%x' % int(found[0]))
                    break
                time.sleep(0.1)
        assert len(real_ids) == 3, real_ids
        # Show another tag: every real window is now mapped but off screen.
        run('xdotool', 'set_desktop', '1').check_returncode()
        time.sleep(0.8)

        # Stand-in windows fill the list. The first and last cards are real windows, so the
        # last is below the fold until the list is scrolled.
        windows = [{'windowId': real_ids[0], 'desktop': 0, 'appClass': 'feh', 'title': 'first picture'}]
        windows += [{'windowId': '0x7f%05x' % i, 'desktop': 1 + i % 7, 'appClass': 'app', 'title': 'stand-in %d' % i}
                    for i in range(FAKE)]
        windows.append({'windowId': real_ids[2], 'desktop': 8, 'appClass': 'feh', 'title': 'last picture'})
        windows.insert(1, {'windowId': real_ids[1], 'desktop': 0, 'appClass': 'feh', 'title': 'second picture'})
        last_real = real_ids[2]

        shell = spawn('quickshell', '--no-duplicate', stdout=log, stderr=log)
        wait_for(lambda s: True, 'IPC unavailable', 15)
        assert run('quickshell', 'ipc', 'call', 'ov', 'setWindows', json.dumps(windows)).returncode == 0
        time.sleep(1.0)

        # Before any capturing, the closed shell is idle.
        idle_before_use = None

        def closed_cpu(seconds):
            before, started = ticks(shell.pid), time.time()
            time.sleep(seconds)
            return (ticks(shell.pid) - before) / os.sysconf('SC_CLK_TCK') / (time.time() - started) * 100

        idle_before_use = closed_cpu(IDLE_SECONDS / 2)

        # --- 1. Picom running -------------------------------------------------------------
        (base / 'picom.conf').write_text('backend = "xrender";\n')
        picom = spawn('picom', '--config', str(base / 'picom.conf'), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)

        assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
        opened = wait_for(lambda s: s['visible'] and s['available'], 'previews did not become available')
        shown = wait_for(lambda s: s['cards'].get(real_ids[0], {}).get('ready') and s['cards'].get(real_ids[1], {}).get('ready'),
                         'the visible real windows did not get a preview')
        assert shown['cards'][real_ids[0]]['height'] > 48, ('cards should grow to hold a preview', shown['cards'][real_ids[0]])
        # A stand-in window has nothing to capture: it keeps its icon.
        stand_in = '0x7f%05x' % 0
        assert not shown['cards'][stand_in]['ready']
        # Below the fold: not requested at all.
        assert shown['contentHeight'] > shown['viewHeight'] * 2, shown
        assert not shown['cards'][last_real]['ready']
        asked = {line[1] for line in captures() if line[0] == 'start'}
        assert last_real not in asked, 'a card below the fold was captured before it was scrolled to'
        assert len(asked) < 25, ('only the cards near the viewport should be captured', len(asked))
        assert stored(), 'no preview file was written'
        # Every stored file is private and a real image of the right colour family.
        for name in stored():
            path = runtime / 'lyona' / 'overview-thumbs' / name
            assert stat.S_IMODE(path.stat().st_mode) == 0o600, path
        red = Image.open(runtime / 'lyona' / 'overview-thumbs' / ('%x.ppm' % int(real_ids[0], 16))).convert('RGB').getpixel((10, 10))
        assert red[0] > 150 and red[1] < 90 and red[2] < 90, ('the first window is red', red)

        # Scrolling to the end captures the last card.
        key('End')
        end = wait_for(lambda s: s['cards'].get(last_real, {}).get('ready'), 'the last card got no preview after scrolling to it')
        assert end['contentY'] + end['viewHeight'] >= end['contentHeight'] - 4, end
        blue = Image.open(runtime / 'lyona' / 'overview-thumbs' / ('%x.ppm' % int(last_real, 16))).convert('RGB').getpixel((10, 10))
        assert blue[2] > 150 and blue[0] < 90, ('the last window is blue', blue)

        # Captures ran one at a time: every start is followed by its end before the next start.
        depth = 0
        for line in captures():
            depth += 1 if line[0] == 'start' else -1
            assert depth in (0, 1), 'two captures overlapped'
        assert depth == 0

        # --- 2. Closing deletes the previews; reopening captures again ----------------------
        close_overview()
        deadline = time.time() + 5
        while stored() and time.time() < deadline:
            time.sleep(0.1)
        assert stored() == [], ('closing the overview left previews behind', stored())
        first_count = len([c for c in captures() if c[0] == 'start'])
        assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
        wait_for(lambda s: s['cards'].get(real_ids[0], {}).get('ready'), 'reopening did not capture again')
        assert len([c for c in captures() if c[0] == 'start']) > first_count
        close_overview()

        # --- 3a. No compositor -------------------------------------------------------------
        picom.terminate()
        picom.wait(timeout=5)
        time.sleep(0.5)
        capture_log.unlink()
        assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
        time.sleep(1.0)
        plain = wait_for(lambda s: s['visible'] and len(s['cards']) > 0, 'the overview did not list windows')
        assert not plain['available'] and plain['previews'] == [], plain
        assert plain['cards'][real_ids[0]]['height'] <= 48 and not plain['cards'][real_ids[0]]['ready'], plain['cards'][real_ids[0]]
        assert captures() == [] and stored() == [], 'nothing should be captured without a compositor'
        close_overview()

        # --- 3b. Previews switched off by the user ---------------------------------------------
        picom = spawn('picom', '--config', str(base / 'picom.conf'), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)
        switch = config / 'lyona' / 'overview-thumbnails'
        switch.write_text('off\n')
        assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
        time.sleep(1.0)
        off = wait_for(lambda s: s['visible'] and len(s['cards']) > 0, 'the overview did not list windows')
        assert not off['available'] and off['previews'] == [] and stored() == [], off
        close_overview()
        switch.unlink()

        # --- 3c. The helper is not installed -----------------------------------------------------
        shell.terminate()
        shell.wait(timeout=5)
        env['PATH'] = '%s:/usr/bin:/bin' % empty_bin
        assert shutil.which('dwm-window-thumb', path=env['PATH']) is None
        shell = spawn('quickshell', '--no-duplicate', stdout=log, stderr=log)
        wait_for(lambda s: True, 'IPC unavailable', 15)
        assert run('quickshell', 'ipc', 'call', 'ov', 'setWindows', json.dumps(windows)).returncode == 0
        assert run('quickshell', 'ipc', 'call', 'ov', 'open').returncode == 0
        time.sleep(1.0)
        missing = wait_for(lambda s: s['visible'] and len(s['cards']) > 0, 'the overview did not list windows without the helper')
        assert not missing['available'] and missing['previews'] == [], missing
        close_overview()

        # --- 4. Idle afterwards ---------------------------------------------------------------
        time.sleep(1.5)
        idle_after_use = closed_cpu(IDLE_SECONDS / 2)
        assert idle_after_use <= idle_before_use + 0.5 and idle_after_use <= 1.0, (idle_before_use, idle_after_use)

        assert shell.poll() is None
        log.seek(0)
        output = log.read()
        assert 'TypeError:' not in output and 'ReferenceError:' not in output, output[-2000:]
        print('Overview previews (Picom, off-tag windows, below the fold, purge, no compositor, off switch, no helper, idle): PASS')
    except BaseException:
        log.seek(0)
        print(log.read()[-4000:])
        raise
    finally:
        for proc in reversed(procs):
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
        log.close()
