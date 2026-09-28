#!/usr/bin/python3
"""Sync Sprint 12 S12-09 item 6: no watcher outlives a Quickshell that is killed.

Runs dwm on the display xvfb-run provides (inside dbus-run-session, see
`make check-quickshell-watcher-lifetime-xvfb`). dwm's autostart starts the full
managed Quickshell with the repository's helpers, as a real session does. The test
opens Settings and walks every section, so the watchers that start on demand (display,
input, notification owner, appearance inventory, ...) are running too, and records
every process Quickshell has started. Then it SIGKILLs Quickshell (a crash: nothing
of Quickshell's own runs) and checks, after a grace period, that none of those
processes is left. Before S12-09 each resident watcher, and what it ran, lived on
until logout.
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
if not shutil.which('quickshell') or not os.environ.get('DISPLAY') or not (repo / 'dwm').exists():
    print('SKIP: needs quickshell, an X display (xvfb-run) and a built dwm')
    raise SystemExit(77)

GRACE = float(os.environ.get('DWM_WATCHER_LIFETIME_GRACE', '3'))
SECTIONS = ['displays', 'input', 'network', 'bluetooth', 'audio', 'power', 'defaults', 'appearance', 'system']


def stat(pid):
    return Path('/proc/%d/stat' % pid).read_text().rsplit(')', 1)[1].split()


def pids():
    return [int(e) for e in os.listdir('/proc') if e.isdigit()]


def tree(root):
    parents = {}
    for pid in pids():
        try:
            parents[pid] = int(stat(pid)[1])
        except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
            pass
    found, frontier = set(), {root}
    while frontier:
        frontier = {pid for pid, ppid in parents.items() if ppid in frontier} - found
        found |= frontier
    return found


def identity(pid):
    """pid, start time and a readable name, or None once it has gone."""
    try:
        fields = stat(pid)
        args = Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')
    except (FileNotFoundError, ProcessLookupError, IndexError):
        return None
    if fields[0] == 'Z':
        return None
    words = [os.path.basename(a.decode(errors='replace')) for a in args if a][:4]
    return pid, fields[19], ' '.join(words)


def alive(ident):
    now = identity(ident[0])
    return now is not None and now[1] == ident[1]


def carrying(marker):
    out = set()
    for pid in pids():
        if pid == os.getpid():
            continue
        try:
            if marker in Path('/proc/%d/cmdline' % pid).read_bytes() \
                    or marker in Path('/proc/%d/environ' % pid).read_bytes():
                out.add(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return out


with tempfile.TemporaryDirectory(prefix='watcher-lifetime-') as temp:
    base = Path(temp)
    home = base / 'home'
    config = home / '.config'
    shutil.copytree(repo / 'config/quickshell', config / 'quickshell')
    (config / 'lyona').mkdir()
    for toml in (repo / 'config').glob('*.toml'):
        shutil.copy(toml, config / 'lyona' / toml.name)
    shutil.copytree(repo / 'scripts', home / '.local/share/lyona/scripts')
    (home / '.cache').mkdir()
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    env = {
        **os.environ,
        'HOME': str(home), 'XDG_CONFIG_HOME': str(config), 'XDG_DATA_HOME': str(home / '.local/share'),
        'XDG_CACHE_HOME': str(home / '.cache'), 'XDG_RUNTIME_DIR': str(runtime),
        'QSG_RHI_BACKEND': 'software', 'QT_QUICK_BACKEND': 'software', 'QT_QPA_PLATFORMTHEME': '',
        'DWM_AUTOSTART_NO_INPUT_WATCH': '1',
        'PATH': '%s:%s' % (home / '.local/share/lyona/scripts', os.environ['PATH']),
    }
    log = (base / 'session.log').open('w')
    wm = subprocess.Popen([str(repo / 'dwm')], env=env, stdout=log, stderr=log, start_new_session=True)

    def resident():
        for pid in carrying(str(config).encode()):
            try:
                args = Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')
            except FileNotFoundError:
                continue
            if os.path.basename(args[0]) == b'quickshell' and b'--path' in args \
                    and b'ipc' not in args and b'list' not in args:
                return pid
        return None

    def ipc(*args):
        return subprocess.run(['quickshell', 'ipc', '--path', str(config / 'quickshell/shell.qml'), 'call', *args],
                              env=env, capture_output=True, text=True, timeout=10)

    report = {}
    try:
        shell, deadline = None, time.time() + 20
        while shell is None and time.time() < deadline:
            shell = resident()
            time.sleep(0.2)
        if shell is None:
            log.flush()
            print((base / 'session.log').read_text()[-2000:], file=sys.stderr)
            print('FAIL: no resident quickshell for this session', file=sys.stderr)
            raise SystemExit(1)
        time.sleep(6)  # start-up: first snapshots, the always-on watchers attached
        if ipc('settings', 'open').returncode != 0:
            print('FAIL: could not open Settings over IPC', file=sys.stderr)
            raise SystemExit(1)
        started = {}
        for section in SECTIONS:
            ipc('settings', 'select', section)
            time.sleep(1.5)
            for pid in tree(shell):
                ident = identity(pid)
                if ident:
                    started[ident[:2]] = ident
        time.sleep(1)
        for pid in tree(shell):  # what is running now, the section just left included
            ident = identity(pid)
            if ident:
                started[ident[:2]] = ident
        recorded = [ident for ident in started.values() if alive(ident)]
        report['running_under_quickshell'] = len(recorded)

        os.kill(shell, signal.SIGKILL)
        time.sleep(GRACE)
        left = [ident for ident in recorded if alive(ident)]
        report['left_after_sigkill'] = len(left)
        names = {}
        for ident in left:
            names[ident[2]] = names.get(ident[2], 0) + 1
        report['left_by_name'] = names
    finally:
        for pid in tree(wm.pid) | carrying(str(base).encode()):
            try:
                os.kill(pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        wm.wait()
        log.close()

    print('Watcher lifetime: %s' % json.dumps(report))
    if report['running_under_quickshell'] < 5:
        print('FAIL: only %d processes under Quickshell; the watchers did not start'
              % report['running_under_quickshell'], file=sys.stderr)
        raise SystemExit(1)
    if report['left_after_sigkill']:
        print('FAIL: %d processes Quickshell started outlived it by %.0f s' % (report['left_after_sigkill'], GRACE),
              file=sys.stderr)
        raise SystemExit(1)

print('Quickshell watcher lifetime (%d processes, none left %.0f s after SIGKILL): PASS'
      % (report['running_under_quickshell'], GRACE))
