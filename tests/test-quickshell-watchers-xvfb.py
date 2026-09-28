#!/usr/bin/python3
"""Sync Sprint 12 S12-07: the network and media watchers in the real QML models.

Loads the real NetworkModel and ControlsModel in Quickshell (under xvfb-run and
dbus-run-session, see `make check-quickshell-watchers-xvfb`) against stub
dwm-quickshell-network and dwm-quickshell-controls helpers on PATH that log every
call with a timestamp.

1. Media: with playerctl missing, media-watch prints "MEDIA unavailable" and
   exits. The model used to restart it every 3 s for the whole session; it must
   be started once.
2. Network, burst: the monitor prints six lines within 50 ms (one change). They
   must cause one snapshot, after the lines settle.
3. Network, mid-snapshot: a line that arrives while a snapshot is running used to
   be dropped. It must cause a second snapshot once the first ends.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
if not shutil.which('quickshell') or not os.environ.get('DISPLAY'):
    print('SKIP: quickshell or an X display is unavailable')
    raise SystemExit(77)

SHELL = '''import Quickshell
import qs.network
import qs.controls

ShellRoot {
    NetworkModel {}
    ControlsModel {}
}
'''

# Monitor timeline (seconds after the monitor starts; the snapshot takes 1 s):
#   3.0      six lines in 50 ms          -> settle (0.3 s) -> one snapshot, 3.35..4.35
#   8.0      one line                    -> snapshot 8.3..9.3
#   8.8      one line, mid-snapshot      -> settle fires at 9.1, snapshot running
#                                           -> pending -> second snapshot at ~9.3
NETWORK = r'''#!/bin/sh
printf '%s %s\n' "$(date +%s.%N)" "$1" >>"$WATCH_LOG"
case $1 in
monitor)
	sleep 3
	printf '%s phase1\n' "$(date +%s.%N)" >>"$WATCH_LOG"
	for i in 1 2 3 4 5 6; do echo "change $i"; sleep 0.01; done
	sleep 4.95
	printf '%s phase2\n' "$(date +%s.%N)" >>"$WATCH_LOG"
	echo "change a"
	sleep 0.8
	echo "change b"
	exec sleep 1000
	;;
snapshot) sleep 1 ;;
status) echo 'NET offline' ;;
esac
exit 0
'''

CONTROLS = r'''#!/bin/sh
printf '%s %s\n' "$(date +%s.%N)" "$1" >>"$WATCH_LOG"
case $1 in
media-watch) echo 'MEDIA unavailable' ;;
*-watch) exec sleep 1000 ;;
esac
exit 0
'''


def fail(message, log=None):
    print('FAIL: ' + message, file=sys.stderr)
    if log is not None:
        print(log.read_text(), file=sys.stderr)
    raise SystemExit(1)


with tempfile.TemporaryDirectory(prefix='watchers-', dir=os.environ.get('DWM_TEST_TMP_ROOT')) as temp:
    base = Path(temp)
    config = base / 'config'
    qml = config / 'quickshell'
    qml.mkdir(parents=True)
    for name in ('core', 'network', 'controls'):
        shutil.copytree(repo / 'config/quickshell' / name, qml / name)
    (qml / 'shell.qml').write_text(SHELL)
    bindir = base / 'bin'
    bindir.mkdir()
    for name, text in (('dwm-quickshell-network', NETWORK), ('dwm-quickshell-controls', CONTROLS)):
        (bindir / name).write_text(text)
        (bindir / name).chmod(0o755)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    log = base / 'watch.log'
    log.touch()
    env = {
        **os.environ,
        'HOME': str(base),
        'XDG_CONFIG_HOME': str(config),
        'XDG_DATA_HOME': str(base / 'data'),  # no managed helper copy: PATH is used
        'XDG_STATE_HOME': str(base / 'state'),
        'XDG_RUNTIME_DIR': str(runtime),
        'PATH': '%s:%s' % (bindir, os.environ['PATH']),
        'WATCH_LOG': str(log),
        'QT_QPA_PLATFORM': 'xcb',
        'QT_QPA_PLATFORMTHEME': '',
    }
    shell_log = (base / 'quickshell.log').open('w')
    shell = subprocess.Popen(['quickshell', '--no-duplicate'], env=env, stdout=shell_log, stderr=shell_log,
                             start_new_session=True)
    try:
        time.sleep(12)
        if shell.poll() is not None:
            fail('quickshell exited: ' + (base / 'quickshell.log').read_text()[-1500:])
    finally:
        try:
            os.killpg(shell.pid, 9)
        except ProcessLookupError:
            pass
        shell.wait()
        shell_log.close()

    events = []
    for line in log.read_text().splitlines():
        stamp, action = line.split(' ', 1)
        events.append((float(stamp), action))
    marks = {action: stamp for stamp, action in events if action in ('phase1', 'phase2')}
    if set(marks) != {'phase1', 'phase2'}:
        fail('the monitor did not run both phases', log)

    media = [s for s, a in events if a == 'media-watch']
    if len(media) != 1:
        fail('media-watch was started %d times in 12 s; with playerctl missing it must not be restarted' % len(media),
             log)

    burst = [s for s, a in events if a == 'snapshot' and marks['phase1'] <= s < marks['phase2']]
    if len(burst) != 1:
        fail('a burst of six monitor lines caused %d snapshots, not one' % len(burst), log)

    mid = [s for s, a in events if a == 'snapshot' and s >= marks['phase2']]
    if len(mid) != 2:
        fail('a monitor line during a snapshot caused %d snapshots after it, not two (it was dropped)' % len(mid),
             log)

print('Quickshell watchers (media not respawned when unavailable, network burst debounced, mid-snapshot change kept): PASS')
