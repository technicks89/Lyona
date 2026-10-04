#!/usr/bin/python3
"""Sync Sprint 12 S12-08: what the state bridge does per event, with real windows.

Runs the real dwm on the display xvfb-run provides (see
`make check-quickshell-state-bridge-xvfb`), opens real windows (Tk toplevels, one
process) and runs `dwm-quickshell-state watch`, which prints one state block per
rebuild. It counts the blocks, and the CPU of the watcher and everything it runs:

1. Opening 10 windows one after another: each used to restart one `xprop -spy`
   per window, whose initial lines each caused a full rebuild (work growing with
   the square of the window count).
2. A tag switch: one rebuild, not one per property dwm writes.
3. A window title changing once a second: one rebuild per change.
4. The last block is still right: the current tag and all 10 windows.
5. dwm's own writes: a tag switch changes each spied root property at most once,
   and moving a window to the tag it is on writes nothing.
6. One resident watcher for every window, dwm-xwatch (Sync Sprint 16 R16-40),
   where there used to be one `xprop -spy` per window plus the root's; SIGTERM,
   which is how Quickshell stops it, ends the watcher and everything it runs.

Case 1 measures CPU over DWM_STATE_BRIDGE_SECONDS from the first window (default
10; the plan's check is 30). DWM_STATE_BRIDGE_SCRIPT runs another copy of the
script (to measure the old one).
"""
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import lyona_tmp  # noqa: F401,E402  (workspaces under the test root, not /tmp)

repo = Path(__file__).resolve().parents[1]
for tool in ('xprop', 'xdotool'):
    if not shutil.which(tool):
        print('SKIP: %s is unavailable' % tool)
        raise SystemExit(77)
if not os.environ.get('DISPLAY') or not (repo / 'dwm').exists():
    print('SKIP: needs an X display (xvfb-run) and a built dwm')
    raise SystemExit(77)
try:
    import tkinter  # noqa: F401
except ImportError:
    print('SKIP: python tkinter is unavailable')
    raise SystemExit(77)

SCRIPT = os.environ.get('DWM_STATE_BRIDGE_SCRIPT', str(repo / 'scripts/dwm-quickshell-state'))
WINDOWS = 10
SECONDS = float(os.environ.get('DWM_STATE_BRIDGE_SECONDS', '10'))
TICK = os.sysconf('SC_CLK_TCK')

# One process, one toplevel per line on stdin: "open", "title N TEXT".
CLIENTS = r'''
import sys, threading, tkinter
root = tkinter.Tk()
root.withdraw()
windows = []
def handle(line):
    word = line.split(' ', 2)
    if word[0] == 'open':
        top = tkinter.Toplevel(root, class_='Bridgetest')
        top.title('window %d' % len(windows))
        top.geometry('200x100')
        windows.append(top)
    elif word[0] == 'title':
        windows[int(word[1])].title(word[2])
    root.update()
    print('ok', flush=True)
def reader():
    for line in sys.stdin:
        root.after(0, handle, line.strip())
threading.Thread(target=reader, daemon=True).start()
root.mainloop()
'''


def stat(pid):
    return Path('/proc/%d/stat' % pid).read_text().rsplit(')', 1)[1].split()


def tree(root):
    parents = {}
    for entry in os.listdir('/proc'):
        if entry.isdigit():
            try:
                parents[int(entry)] = int(stat(int(entry))[1])
            except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
                pass
    found, frontier = set(), {root}
    while frontier:
        frontier = {pid for pid, ppid in parents.items() if ppid in frontier} - found
        found |= frontier
    return found


def cost(root):
    """Ticks of root, its descendants, and every child they reaped."""
    total = 0
    for pid in tree(root) | {root}:
        try:
            total += sum(int(v) for v in stat(pid)[11:15])
        except (FileNotFoundError, ProcessLookupError, IndexError):
            pass
    return total


def fail(message, extra=''):
    print('FAIL: ' + message, file=sys.stderr)
    if extra:
        print(extra, file=sys.stderr)
    raise SystemExit(1)


with tempfile.TemporaryDirectory(prefix='state-bridge-', dir=os.environ.get('DWM_TEST_TMP_ROOT')) as temp:
    base = Path(temp)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    (base / 'config/lyona').mkdir(parents=True)
    for toml in (repo / 'config').glob('*.toml'):
        shutil.copy(toml, base / 'config/lyona' / toml.name)
    # No autostart (empty data home), so the session is dwm and these windows only.
    env = {**os.environ, 'HOME': str(base), 'XDG_CONFIG_HOME': str(base / 'config'),
           'XDG_DATA_HOME': str(base / 'data'), 'XDG_RUNTIME_DIR': str(runtime)}
    log = (base / 'session.log').open('w')
    procs = []

    def start(args, **kw):
        proc = subprocess.Popen(args, env=env, start_new_session=True, **kw)
        procs.append(proc)
        return proc

    report = {}
    try:
        wm = start([str(repo / 'dwm')], stdout=log, stderr=log)
        deadline = time.time() + 10
        # As in a session, where autostart runs after dwm has published its state.
        while b'=' not in subprocess.run(['xprop', '-root', '_DWM_MONITOR_DESKTOPS'], env=env,
                                         capture_output=True).stdout:
            if time.time() > deadline or wm.poll() is not None:
                fail('dwm did not start', (base / 'session.log').read_text())
            time.sleep(0.1)

        clients = start([sys.executable, '-c', CLIENTS], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=log, text=True)

        def client(command):
            clients.stdin.write(command + '\n')
            clients.stdin.flush()
            clients.stdout.readline()

        out_path = base / 'watch.out'
        out = out_path.open('w')
        watch = start([SCRIPT, 'watch'], stdout=out, stderr=log)

        def blocks():
            text = out_path.read_text()
            return [b for b in text.split('\n\n') if b.strip()], text.endswith('\n\n')

        def settle(quiet=1.0, limit=30):
            """Wait until no block has been printed for `quiet` seconds."""
            last, since, deadline = -1, time.time(), time.time() + limit
            while time.time() < deadline:
                count = len(blocks()[0])
                if count != last:
                    last, since = count, time.time()
                elif time.time() - since >= quiet:
                    return count
                time.sleep(0.05)
            return last

        settle()
        if watch.poll() is not None:
            fail('the watcher exited', (base / 'session.log').read_text())

        # 1. Open 10 windows, one every 0.3 s.
        count0, ticks0, started = len(blocks()[0]), cost(watch.pid), time.time()
        for _ in range(WINDOWS):
            client('open')
            time.sleep(0.3)
        settle()
        time.sleep(max(0.0, started + SECONDS - time.time()))
        elapsed = time.time() - started
        report['open_10_rebuilds'] = len(blocks()[0]) - count0
        report['open_10_seconds'] = round(elapsed, 1)
        report['open_10_cpu_percent'] = round((cost(watch.pid) - ticks0) / TICK / elapsed * 100, 2)

        # 5. What dwm writes for one tag switch, raw.
        spy_path = base / 'spy.out'
        spy = start(['xprop', '-root', '-spy', 'DWM_TAG_UPDATE', '_DWM_MONITOR_DESKTOPS', '_DWM_SELECTED_MONITOR',
                     '_DWM_LAYOUT', '_NET_NUMBER_OF_DESKTOPS', '_NET_DESKTOP_NAMES', '_NET_ACTIVE_WINDOW',
                     '_NET_CLIENT_LIST', '_DWM_FULLSCREEN_MONITORS', 'WM_NAME'],
                    stdout=spy_path.open('w'), stderr=subprocess.DEVNULL)
        time.sleep(1)
        spy_before = len(spy_path.read_text().splitlines())

        # 2. A tag switch and back.
        before = len(blocks()[0])
        subprocess.run(['xdotool', 'set_desktop', '3'], env=env, check=True)
        settle()
        report['tag_switch_rebuilds'] = len(blocks()[0]) - before
        spy_lines = spy_path.read_text().splitlines()[spy_before:]
        report['tag_switch_root_events'] = [line.split('(')[0].split(':')[0] for line in spy_lines]
        spy.kill()
        switched = blocks()[0][-1]
        before = len(blocks()[0])
        subprocess.run(['xdotool', 'set_desktop', '0'], env=env, check=True)
        settle()
        report['tag_switch_back_rebuilds'] = len(blocks()[0]) - before

        # 5. Moving a window to the tag it is already on publishes nothing.
        window = subprocess.run(['xdotool', 'search', '--class', 'Bridgetest'], env=env, capture_output=True,
                                text=True).stdout.split()[-1]
        moves_path = base / 'moves.out'
        moves = start(['sh', '-c', 'xprop -root -spy DWM_TAG_UPDATE & exec xprop -id "$0" -spy _NET_WM_DESKTOP', window],
                      stdout=moves_path.open('w'), stderr=subprocess.DEVNULL)
        time.sleep(1)
        seen = len(moves_path.read_text().splitlines())
        subprocess.run(['xdotool', 'set_desktop_for_window', window, '1'], env=env, check=True)
        time.sleep(1)
        report['move_writes'] = len(moves_path.read_text().splitlines()) - seen
        seen += report['move_writes']
        subprocess.run(['xdotool', 'set_desktop_for_window', window, '1'], env=env, check=True)
        time.sleep(1)
        report['same_tag_move_writes'] = len(moves_path.read_text().splitlines()) - seen
        os.killpg(moves.pid, signal.SIGKILL)
        subprocess.run(['xdotool', 'set_desktop_for_window', window, '0'], env=env, check=True)
        settle()

        # 3. One title change a second, for 10 s.
        before, ticks0 = len(blocks()[0]), cost(watch.pid)
        for i in range(10):
            client('title 0 changing title %d' % i)
            time.sleep(1)
        settle()
        report['title_changes'] = 10
        report['title_rebuilds'] = len(blocks()[0]) - before
        report['title_cpu_seconds'] = round((cost(watch.pid) - ticks0) / TICK, 2)

        # 4. The last block is right.
        final, complete = blocks()
        fields = dict(line.split('=', 1) for line in final[-1].splitlines() if '=' in line)
        windows = [w for w in fields.get('windows', '').split('|') if 'bridgetest' in w]
        report['final_windows'] = len(windows)

        # 6. Stopped the way Quickshell stops it.
        watchers = tree(watch.pid)

        def resident(name):
            return sum(1 for pid in watchers if Path('/proc/%d/comm' % pid).exists()
                       and Path('/proc/%d/comm' % pid).read_text().strip() == name)
        report['resident_xprops'] = resident('xprop')
        report['resident_xwatch'] = resident('dwm-xwatch')
        watch.send_signal(signal.SIGTERM)
        watch.wait(timeout=5)
        time.sleep(0.3)
        report['left_after_sigterm'] = sum(1 for pid in watchers if Path('/proc/%d' % pid).exists())
        print('State bridge: %s' % json.dumps(report))
        if os.environ.get('DWM_STATE_BRIDGE_DEBUG'):
            print(out_path.read_text()[-3000:], (base / 'session.log').read_text()[-3000:])

        if report['resident_xwatch'] != 1 or report['resident_xprops'] or report['left_after_sigterm']:
            fail('%d dwm-xwatch and %d xprop watchers for %d windows; %d processes left after SIGTERM'
                 % (report['resident_xwatch'], report['resident_xprops'], WINDOWS, report['left_after_sigterm']))
        if not complete:
            fail('the last block is incomplete')
        if 'current=3' not in switched.splitlines() and not any(
                line.startswith('monitor_desktops=') and line.endswith(',3') for line in switched.splitlines()):
            fail('the block after the tag switch does not show tag 4', switched)
        if len(windows) != WINDOWS or 'changing title 9' not in fields.get('windows', ''):
            fail('the last block does not list the %d windows with the last title' % WINDOWS, final[-1])
        if report['tag_switch_rebuilds'] != 1 or report['tag_switch_back_rebuilds'] != 1:
            fail('a tag switch caused %d and %d rebuilds, not one each'
                 % (report['tag_switch_rebuilds'], report['tag_switch_back_rebuilds']))
        names = report['tag_switch_root_events']
        if len(names) != len(set(names)) or '_DWM_FULLSCREEN_MONITORS' in names:
            fail('dwm rewrote a root property that did not change for one tag switch: %s' % names)
        if report['move_writes'] != 2 or report['same_tag_move_writes'] != 0:
            fail('moving a window wrote %d properties, and moving it to the same tag %d (want 2 and 0)'
                 % (report['move_writes'], report['same_tag_move_writes']))
        if report['title_rebuilds'] > 10:
            fail('10 title changes caused %d rebuilds' % report['title_rebuilds'])
        # At most two rebuilds per window opened: the client list, and the new
        # window's own watcher reporting its first properties.
        if report['open_10_rebuilds'] > 2 * WINDOWS:
            fail('opening %d windows caused %d rebuilds' % (WINDOWS, report['open_10_rebuilds']))
    finally:
        for proc in reversed(procs):
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            proc.wait()
        log.close()

print('State bridge (%d windows: coalesced rebuilds, one per tag switch): PASS' % WINDOWS)
