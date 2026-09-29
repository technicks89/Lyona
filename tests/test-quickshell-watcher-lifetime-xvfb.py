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
# One-shot helpers, bounded by their own timeouts: one still in flight when Quickshell
# dies finishes on its own. They get ONE_SHOT_GRACE; every other process, the resident
# watchers included, must be gone within GRACE. Matched in the full command line.
ONE_SHOT = ('dwm-checked-command', 'dwm-system-management snapshot')
ONE_SHOT_GRACE = 20
SECTIONS = ['displays', 'input', 'network', 'bluetooth', 'audio', 'power', 'defaults', 'appearance', 'system']
# The watcher each section starts on demand (the others have none of their own),
# as it appears in the command line: the helper and its action.
ON_DEMAND = {
    'displays': 'dwm-settings-display watch',
    'input': 'dwm-settings-input watch',
    'appearance': 'busctl --user --no-pager monitor',  # dwm-settings-provider execs it
    'system': 'dwm-system-management watch',
}


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


def command_line(pid):
    try:
        args = Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')
    except (FileNotFoundError, ProcessLookupError):
        return ''
    return ' '.join(os.path.basename(a.decode(errors='replace')) for a in args if a)


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


# Short names: Quickshell's IPC socket lives under XDG_RUNTIME_DIR, and a Unix socket
# path must fit in 107 characters, which scripts/run-tests' deeper workspace reaches.
with tempfile.TemporaryDirectory(prefix='lifetime-') as temp:
    base = Path(temp)
    home = base / 'home'
    config = home / '.config'
    shutil.copytree(repo / 'config/quickshell', config / 'quickshell')
    (config / 'lyona').mkdir()
    for toml in (repo / 'config').glob('*.toml'):
        shutil.copy(toml, config / 'lyona' / toml.name)
    shutil.copytree(repo / 'scripts', home / '.local/share/checkout/scripts')
    (home / '.cache').mkdir()
    runtime = base / 'rt'
    runtime.mkdir(mode=0o700)
    env = {
        **os.environ,
        'HOME': str(home), 'XDG_CONFIG_HOME': str(config), 'XDG_DATA_HOME': str(home / '.local/share'),
        # dwm and the shell run the session scripts and helpers from this copy of
        # the checkout, through the developer override (Sync Sprint 12 S12-13).
        'LYONA_DEV_SCRIPTS': str(home / '.local/share/checkout/scripts'),
        'XDG_CACHE_HOME': str(home / '.cache'), 'XDG_RUNTIME_DIR': str(runtime),
        'QSG_RHI_BACKEND': 'software', 'QT_QUICK_BACKEND': 'software', 'QT_QPA_PLATFORMTHEME': '',
        'DWM_AUTOSTART_NO_INPUT_WATCH': '1',
        'PATH': '%s:%s' % (home / '.local/share/checkout/scripts', os.environ['PATH']),
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
        # Under a loaded machine (the full suite) the shell's IPC can take longer.
        deadline, opened = time.time() + 30, None
        while time.time() < deadline:
            try:
                opened = ipc('settings', 'open')
            except subprocess.TimeoutExpired:
                opened = None
            if opened is not None and opened.returncode == 0:
                break
            time.sleep(0.5)
        if opened is None or opened.returncode != 0:
            print('FAIL: could not open Settings over IPC: %s'
                  % ('exit %d, %s %s' % (opened.returncode, opened.stdout.strip(), opened.stderr.strip())
                     if opened is not None else 'timed out'), file=sys.stderr)
            raise SystemExit(1)
        started = {}
        for section in SECTIONS:
            selected = ipc('settings', 'select', section)
            if selected.returncode != 0:
                print('FAIL: selecting the %s section failed: %s' % (section, selected.stderr.strip()),
                      file=sys.stderr)
                raise SystemExit(1)
            wanted = ON_DEMAND.get(section)
            deadline = time.time() + (5 if wanted else 1.5)
            while True:
                running = tree(shell)
                for pid in running:
                    ident = identity(pid)
                    if ident:
                        started[ident[:2]] = ident
                if not wanted and time.time() >= deadline:
                    break
                if wanted and any(wanted in command_line(pid) for pid in running):
                    break
                if time.time() >= deadline:
                    print('FAIL: the %s section did not start its watcher (%s)' % (section, wanted),
                          file=sys.stderr)
                    raise SystemExit(1)
                time.sleep(0.1)
        # Let one-shot helpers still in flight (a snapshot, a checked command) finish:
        # they end on their own, bounded by their own timeouts. What is left once the
        # set has not changed for 2 s is what stays resident.
        last, since, deadline = None, time.time(), time.time() + 15
        while time.time() < deadline:
            now = frozenset(ident[:2] for ident in map(identity, tree(shell)) if ident)
            if now != last:
                last, since = now, time.time()
            elif time.time() - since >= 2:
                break
            time.sleep(0.25)
        for pid in tree(shell):  # what is running now, the section just left included
            ident = identity(pid)
            if ident:
                started[ident[:2]] = ident
        recorded = [ident for ident in started.values() if alive(ident)]
        report['running_under_quickshell'] = len(recorded)

        commands = {ident[:2]: command_line(ident[0]) for ident in recorded}
        os.kill(shell, signal.SIGKILL)
        killed = time.time()
        time.sleep(GRACE)
        left = [ident for ident in recorded if alive(ident)
                and not any(word in commands[ident[:2]] for word in ONE_SHOT)]
        report['left_after_sigkill'] = len(left)
        one_shots = [ident for ident in recorded if alive(ident) and ident not in left]
        while one_shots and time.time() - killed < ONE_SHOT_GRACE:
            time.sleep(0.25)
            one_shots = [ident for ident in one_shots if alive(ident)]
        report['one_shots_left_after_%ds' % ONE_SHOT_GRACE] = len(one_shots)
        left += one_shots
        names = {}
        for ident in left:
            names[ident[2]] = names.get(ident[2], 0) + 1
        report['left_by_name'] = names
    finally:
        # TERM first, so the shell autostart relaunched and its watchers run their
        # own cleanup (their fifo folders); KILL whatever is left after 3 s.
        for sig, wait in ((signal.SIGTERM, 3), (signal.SIGKILL, 0)):
            for pid in tree(wm.pid) | carrying(str(base).encode()):
                try:
                    os.kill(pid, sig)
                except (ProcessLookupError, PermissionError):
                    pass
            deadline = time.time() + wait
            while time.time() < deadline and (tree(wm.pid) | carrying(str(base).encode())):
                time.sleep(0.1)
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
    if report['one_shots_left_after_%ds' % ONE_SHOT_GRACE]:
        print('FAIL: a one-shot helper Quickshell started was still running %d s after it'
              % ONE_SHOT_GRACE, file=sys.stderr)
        raise SystemExit(1)

print('Quickshell watcher lifetime (%d processes, none left %.0f s after SIGKILL): PASS'
      % (report['running_under_quickshell'], GRACE))
