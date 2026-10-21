#!/usr/bin/python3
"""Sync Sprint 12 S12-07: what the shell's always-on watchers cost while idle.

Runs dwm on the display xvfb-run provides (inside dbus-run-session, see
`make check-quickshell-idle-watchers-xvfb`). dwm's autostart starts the full
managed Quickshell, as a real session does, with the repository's helpers. Once
start-up has settled, it measures the CPU of everything Quickshell has started
(the network, audio, media and power watchers and whatever they run), not
Quickshell's own; helpers that exit are counted through Quickshell's
reaped-children time. It also counts the processes that appear in the window.

The plan's check is within 0.5 percentage points of zero. It is judged on the
whole observation period, DWM_IDLE_WATCHERS_WINDOWS (3) samples of
DWM_IDLE_WATCHERS_SECONDS (6) each (#310): a one-off helper, such as a late
start-up read, is spread over all 18 s rather than one 6 s window, while a
polling timer of any interval up to that long is counted in full. (A median
of the samples would hide a timer slower than one sample.) Each sample is
still reported.
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

SECONDS = float(os.environ.get('DWM_IDLE_WATCHERS_SECONDS', '6'))
WINDOWS = max(1, int(os.environ.get('DWM_IDLE_WATCHERS_WINDOWS', '3')))
BUDGET = float(os.environ.get('DWM_IDLE_WATCHERS_BUDGET', '0.5'))
TICK = os.sysconf('SC_CLK_TCK')


def stat(pid):
    return Path('/proc/%d/stat' % pid).read_text().rsplit(')', 1)[1].split()


def stat_state(pid):
    """A process's state letter, or None once it is gone."""
    try:
        return stat(pid)[0]
    except (FileNotFoundError, ProcessLookupError, IndexError):
        return None


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


def cost(root):
    """Ticks used by root's descendants, plus the children root has reaped."""
    fields = stat(root)
    total = int(fields[13]) + int(fields[14])  # cutime + cstime
    for pid in tree(root):
        try:
            fields = stat(pid)
            total += sum(int(fields[k]) for k in (11, 12, 13, 14))
        except (FileNotFoundError, ProcessLookupError, IndexError):
            pass
    return total


def names(found):
    out = {}
    for pid in found:
        try:
            name = os.path.basename(Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')[0].decode(errors='replace'))
        except FileNotFoundError:
            continue
        out[name] = out.get(name, 0) + 1
    return out


def network_monitor(root):
    """Identify the live nmcli monitor under Quickshell by PID and start time."""
    for pid in tree(root):
        try:
            fields = stat(pid)
            args = Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')
            # nmcli itself, or the stand-in script below run by its shell.
            at = 1 if len(args) > 1 and os.path.basename(args[1]) == b'nmcli' else 0
            if fields[0] != 'Z' and os.path.basename(args[at]) == b'nmcli' \
                    and args[at + 1:at + 2] == [b'monitor']:
                return pid, fields[19]
        except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError):
            pass
    return None


def carrying(marker):
    """Every process whose command line or environment mentions marker."""
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


with tempfile.TemporaryDirectory(prefix='idle-watchers-', dir=os.environ.get('DWM_TEST_TMP_ROOT')) as temp:
    base = Path(temp)
    marker = str(base).encode()
    home = base / 'home'
    config = home / '.config'
    shutil.copytree(repo / 'config/quickshell', config / 'quickshell')
    (config / 'lyona').mkdir()
    for toml in (repo / 'config').glob('*.toml'):
        shutil.copy(toml, config / 'lyona' / toml.name)
    # The one update check after login (15-60 s in, at random) is not a watcher:
    # left on, it lands in the sample or not by chance.
    (config / 'lyona' / 'update.conf').write_text(
        'channel=preview\ncheck_on_login=false\nauto_apply=false\nkeep_backups=5\n')
    shutil.copytree(repo / 'scripts', home / '.local/share/checkout/scripts')
    # The checkout layout: the built TOML reader beside scripts/ (S12-14).
    shutil.copy2(repo / 'lyona-toml', home / '.local/share/checkout/lyona-toml')
    (home / '.cache').mkdir()
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    path = '%s:%s' % (repo / 'scripts', os.environ['PATH'])
    # Without NetworkManager (a CI container has no system bus), nmcli monitor
    # exits at once and the shell restarts it every 3 s, so there is no watcher
    # to measure. A stand-in that stays up, as the real one does, keeps the
    # watcher under test; everything else still goes to the real nmcli.
    # A NetworkManager that does not answer counts as none.
    try:
        nm = subprocess.run(['nmcli', '-t', '-f', 'RUNNING', 'general'], capture_output=True, text=True,
                            timeout=10) if shutil.which('nmcli') else None
    except subprocess.TimeoutExpired:
        nm = None
    if nm is None or nm.returncode != 0 or nm.stdout.strip() != 'running':
        stubs = base / 'stubs'
        stubs.mkdir()
        (stubs / 'nmcli').write_text(
            '#!/bin/sh\n'
            'if [ "${1:-}" = monitor ]; then\n'
            '\twhile :; do sleep 3600; done\n'
            'fi\n'
            'exec %s "$@"\n' % (shutil.which('nmcli') or 'false'))
        (stubs / 'nmcli').chmod(0o755)
        path = '%s:%s' % (stubs, path)
    env = {
        **os.environ,
        'HOME': str(home), 'XDG_CONFIG_HOME': str(config), 'XDG_DATA_HOME': str(home / '.local/share'),
        # dwm and the shell run the session scripts and helpers from this copy of
        # the checkout, through the developer override (Sync Sprint 12 S12-13).
        'LYONA_DEV_SCRIPTS': str(home / '.local/share/checkout/scripts'),
        'XDG_CACHE_HOME': str(home / '.cache'), 'XDG_RUNTIME_DIR': str(runtime),
        'QSG_RHI_BACKEND': 'software', 'QT_QUICK_BACKEND': 'software', 'QT_QPA_PLATFORMTHEME': '',
        'DWM_AUTOSTART_NO_INPUT_WATCH': '1', 'PATH': path,
    }
    log = (base / 'session.log').open('w')
    wm = subprocess.Popen([str(repo / 'dwm')], env=env, stdout=log, stderr=log, start_new_session=True)

    def resident():
        """The long-lived shell for this config (not autostart's ipc/list checks).
        Autostart detaches it, so it is found by its path, not under dwm."""
        for pid in carrying(str(config).encode()):
            try:
                args = Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')
            except FileNotFoundError:
                continue
            if os.path.basename(args[0]) == b'quickshell' and b'--path' in args \
                    and b'ipc' not in args and b'list' not in args:
                return pid
        return None

    def fail_session(message):
        log.flush()
        print((base / 'session.log').read_text()[-2000:], file=sys.stderr)
        print('FAIL: ' + message, file=sys.stderr)
        raise SystemExit(1)

    try:
        shell = None
        deadline = time.time() + 20
        while shell is None and time.time() < deadline:
            shell = resident()
            time.sleep(0.2)
        # Start-up: the first snapshots and the watchers attaching. At least 8 s,
        # then until no new process has appeared under the shell for 3 s, at most
        # 30 s: on a busy machine a fixed 8 s let late start-up helpers land in
        # the first sample and read just over the budget now and then (#280).
        settle_started = time.time()
        quiet_since = time.time()
        known = tree(shell) if shell else set()
        while shell is not None and time.time() - settle_started < 30:
            now = tree(shell)
            if now - known:
                quiet_since = time.time()
            known |= now
            if time.time() - settle_started >= 8 and time.time() - quiet_since >= 3:
                break
            time.sleep(0.1)
        if shell is None or resident() != shell:
            fail_session('no resident quickshell for this session')
        monitor = network_monitor(shell)
        if monitor is None:
            fail_session('network watcher (nmcli monitor) is not running before the idle sample')
        samples = []
        for _ in range(WINDOWS):
            before = tree(shell)
            seen = set(before)
            started_names = {}
            start_ticks, started = cost(shell), time.time()
            while time.time() - started < SECONDS:
                now = tree(shell)
                new = now - seen
                for name, count in names(new).items():  # named while they are alive
                    started_names[name] = started_names.get(name, 0) + count
                seen |= now
                time.sleep(0.05)
            end_ticks, elapsed = cost(shell), time.time() - started
            samples.append({
                'ticks': end_ticks - start_ticks,
                'elapsed': elapsed,
                'seconds': round(elapsed, 1),
                'watcher_cpu_percent': round((end_ticks - start_ticks) / TICK / elapsed * 100, 2),
                'processes_started': len(seen - before),
                'started_by_name': started_names,
            })
        resident_names = names(tree(shell))
        if network_monitor(shell) != monitor:
            fail_session('network watcher (nmcli monitor) did not stay running through the idle sample')
    finally:
        # Until a look finds none: what a process started while the others were
        # being killed is not in the first look. The nmcli stand-in's loop, its
        # sleep killed first, started another before the loop itself was
        # killed, and that sleep ran on for an hour after the test (#427).
        # Bounded.
        for _ in range(50):
            left = {pid for pid in tree(wm.pid) | carrying(marker)
                    if stat_state(pid) not in (None, 'Z')}
            if not left:
                break
            for pid in left:
                try:
                    os.kill(pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
            time.sleep(0.1)
        wm.wait()
        log.close()

    elapsed = sum(sample.pop('elapsed') for sample in samples)
    percent = round(sum(sample.pop('ticks') for sample in samples) / TICK / elapsed * 100, 2)
    report = {
        'watcher_cpu_percent': percent,
        'samples': samples,
        'resident_under_quickshell': resident_names,
    }
    print('Idle watchers: %s' % json.dumps(report))
    if percent > BUDGET:
        print('FAIL: the watchers used %.2f%% of a core idle (over %d samples), over %.2f%%'
              % (percent, len(samples), BUDGET), file=sys.stderr)
        raise SystemExit(1)

print('Quickshell idle watchers (%.0f s, %.2f%% CPU, within %.1f points of zero): PASS'
      % (elapsed, percent, BUDGET))
