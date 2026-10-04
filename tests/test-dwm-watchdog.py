#!/usr/bin/python3
"""Sync Sprint 12 S12-07: scripts/dwm-watchdog.sh's run_parent_bound, by behaviour.

A fake parent (standing in for Quickshell) starts a helper script that sources
dwm-watchdog.sh and runs a long child through run_parent_bound, exactly as
dwm-quickshell-network, -controls and -controlcenter do. Checks:

1. the child's exit status comes back from run_parent_bound;
2. SIGKILL on the helper (what a killed QProcess does) ends the child within a
   second, with no polling involved (setpriv --pdeathsig);
3. the parent dying without the helper (a crash) ends the child through the
   backstop loop;
4. a shell-function child (power_watch_sources) is still cleaned up on SIGTERM;
5. idle, the watchdog starts no processes: the old loop ran sed, awk and sleep
   every 0.25 s, about 12 process starts a second per watcher;
6. the startup guard runs a bound command only while its parent is still the
   process that started it (setpriv arms the signal before exec, so a parent that
   died first would never send it);
7. an interval that is zero or malformed falls back to 5 s instead of spinning.
"""
import atexit
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
watchdog = repo / 'scripts/dwm-watchdog.sh'
if not shutil.which('setpriv'):
    print('SKIP: setpriv (util-linux) is unavailable')
    raise SystemExit(77)


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    raise SystemExit(1)


def alive(pid):
    try:
        state = Path('/proc/%d/stat' % pid).read_text().rsplit(')', 1)[1].split()[0]
    except (FileNotFoundError, ProcessLookupError, IndexError):
        return False
    return state != 'Z'


def wait_gone(pid, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if not alive(pid):
            return True
        time.sleep(0.05)
    return not alive(pid)


def descendants(root):
    """Every live pid under root, found through /proc's parent fields."""
    parents = {}
    for entry in os.listdir('/proc'):
        if entry.isdigit():
            try:
                fields = Path('/proc/%s/stat' % entry).read_text().rsplit(')', 1)[1].split()
                parents[int(entry)] = int(fields[1])
            except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
                pass
    found, frontier = set(), {root}
    while frontier:
        frontier = {pid for pid, ppid in parents.items() if ppid in frontier} - found
        found |= frontier
    return found


groups = []


@atexit.register
def kill_groups():
    for group in groups:
        try:
            os.killpg(group, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


with tempfile.TemporaryDirectory(prefix='dwm-watchdog-') as temp:
    work = Path(temp)
    helper = work / 'helper.sh'
    helper.write_text('''#!/bin/sh
. "%s"
long_function() { sleep 1000 & fn_child=$!; trap 'kill "$fn_child"; exit 0' TERM; wait "$fn_child"; }
case $1 in
status) run_parent_bound sh -c 'exit 3'; echo "status=$?" >"$2" ;;
program) echo $$ >"$2"; run_parent_bound sleep 1000 ;;
function) echo $$ >"$2"; run_parent_bound long_function ;;
bound) echo $$ >"$2"; LYONA_PARENT_BOUND_SELF=$$; export LYONA_PARENT_BOUND_SELF; run_parent_bound sleep 1000 ;;
elsewhere) echo $$ >"$2"; LYONA_PARENT_BOUND_SELF=1; export LYONA_PARENT_BOUND_SELF; run_parent_bound sleep 1000 ;;
esac
''' % watchdog)
    helper.chmod(0o755)

    def start(kind, interval='5'):
        """A fake parent that starts the helper; returns (parent, helper pid, child pid)."""
        info = work / ('%s.pid' % kind)
        info.unlink(missing_ok=True)
        env = dict(os.environ, LYONA_PARENT_BOUND_INTERVAL=interval)
        # The parent outlives the helper, as Quickshell does: exec keeps its pid and
        # start time, so the helper's view of its parent does not change.
        # Its own session: nothing it starts can hold this test's output open, and
        # the whole group is killed at exit whatever happens.
        parent = subprocess.Popen(['sh', '-c', '"$0" "$1" "$2" & exec sleep 1000', str(helper), kind, str(info)],
                                  env=env, start_new_session=True, stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        groups.append(parent.pid)
        deadline = time.time() + 5
        while not (info.exists() and info.read_text().strip()) and time.time() < deadline:
            time.sleep(0.02)
        helper_pid = int(info.read_text())
        child = None
        while child is None and time.time() < deadline:
            for pid in descendants(helper_pid):
                try:
                    cmd = Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')
                except FileNotFoundError:
                    continue
                if cmd[:2] == [b'sleep', b'1000']:
                    child = pid
            time.sleep(0.02)
        if child is None:
            fail('%s: the long child did not start' % kind)
        return parent, helper_pid, child

    # 1. The child's status comes back.
    out = work / 'status.out'
    subprocess.run(['sh', '-c', '"$0" status "$1"', str(helper), str(out)], check=True, timeout=10)
    if out.read_text().strip() != 'status=3':
        fail('run_parent_bound did not return the child status: ' + out.read_text())

    # 2. SIGKILL on the helper ends the child at once (pdeathsig, no polling).
    parent, helper_pid, child = start('program', interval='60')
    loop_group = [pid for pid in descendants(helper_pid) if pid != child]
    os.kill(helper_pid, signal.SIGKILL)
    if not wait_gone(child, 1.5):
        fail('the child outlived a SIGKILLed helper')
    # The backstop loop and its sleep go too: nothing of the helper is left.
    for pid in loop_group:
        if not wait_gone(pid, 1.5):
            fail('a watchdog process outlived the helper: %s' % pid)
    parent.kill()
    parent.wait()

    # 3. The parent crashes, the helper survives: the backstop loop ends the child.
    parent, helper_pid, child = start('program', interval='0.2')
    parent.kill()
    parent.wait()
    if not wait_gone(child, 3):
        fail('the child outlived its crashed parent')
    if not wait_gone(helper_pid, 3):
        fail('the helper outlived its crashed parent')

    # 4. A function child is cleaned up when the helper is stopped.
    parent, helper_pid, child = start('function', interval='60')
    os.kill(helper_pid, signal.SIGTERM)
    if not wait_gone(child, 3):
        fail("a function child's process outlived SIGTERM on the helper")
    parent.kill()
    parent.wait()

    # 5. Idle: no process starts at all over three seconds.
    parent, helper_pid, child = start('program')
    time.sleep(0.5)
    before = descendants(helper_pid)
    seen = set(before)
    deadline = time.time() + 3
    while time.time() < deadline:
        seen |= descendants(helper_pid)
        time.sleep(0.02)
    os.kill(helper_pid, signal.SIGTERM)
    wait_gone(child, 3)
    parent.kill()
    parent.wait()
    started = seen - before
    if started:
        fail('the idle watchdog started %d processes in 3 s' % len(started))

    # 6. The guard: the command runs only under the expected parent.
    guard = subprocess.run(['sh', '-c', '. "$0"; printf %s "$parent_bound_guard"', str(watchdog)],
                           capture_output=True, text=True, check=True).stdout
    # "; :" keeps the outer shell from exec'ing the inner one, so it really is the parent.
    here = subprocess.run(['sh', '-c', 'sh -c "$1" sh "$$" echo ran; :', 'sh', guard], capture_output=True, text=True)
    if here.stdout.strip() != 'ran':
        fail('the guard refused its real parent: %r' % here.stdout)
    wrong = subprocess.run(['sh', '-c', 'sh -c "$1" sh 1 echo ran; :', 'sh', guard], capture_output=True, text=True)
    if wrong.stdout.strip() or wrong.returncode != 0:
        fail('the guard ran a command whose parent is not the one it was given: %r' % wrong.stdout)

    # 7. Intervals: the backstop loop's own argument shows what it was given.
    def loop_interval(helper_pid):
        deadline = time.time() + 5
        while time.time() < deadline:
            for pid in descendants(helper_pid):
                try:
                    cmd = Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')
                except FileNotFoundError:
                    continue
                if len(cmd) > 7 and cmd[0] == b'sh' and cmd[1] == b'-c' and b'parent_identity' in cmd[2]:
                    return cmd[7].decode()
            time.sleep(0.05)
        fail('the backstop loop did not start')

    for given, want in (('0', '5'), ('0.0', '5'), ('00', '5'), ('1.2.3', '5'), ('5.', '5'), ('.5', '5'),
                        ('abc', '5'), ('', '5'), ('0.2', '0.2'), ('10', '10')):
        parent, helper_pid, child = start('program', interval=given)
        got = loop_interval(helper_pid)
        os.kill(helper_pid, signal.SIGTERM)
        wait_gone(child, 3)
        parent.kill()
        parent.wait()
        if got != want:
            fail('LYONA_PARENT_BOUND_INTERVAL=%r ran the loop with %r, not %r' % (given, got, want))

    # 8. Sync Sprint 16 R16-43: a helper that Quickshell's watchCommand bound
    # (LYONA_PARENT_BOUND_SELF is its own pid) starts no backstop loop; one that
    # names another process, as a subshell would see, still does.
    def has_loop(helper_pid):
        time.sleep(0.5)
        for pid in descendants(helper_pid):
            try:
                cmd = Path('/proc/%d/cmdline' % pid).read_bytes().split(b'\0')
            except FileNotFoundError:
                continue
            if len(cmd) > 2 and cmd[1] == b'-c' and b'parent_identity' in cmd[2]:
                return True
        return False

    for kind, want in (('bound', False), ('elsewhere', True)):
        parent, helper_pid, child = start(kind)
        got = has_loop(helper_pid)
        os.kill(helper_pid, signal.SIGTERM)
        wait_gone(child, 3)
        parent.kill()
        parent.wait()
        if got != want:
            fail('%s: the backstop loop %s' % (kind, 'ran' if got else 'did not run'))

print('dwm-watchdog run_parent_bound (status, helper SIGKILL, parent crash, function child, idle, guard, '
      'intervals, no backstop when bound): PASS')
