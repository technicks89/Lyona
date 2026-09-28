#!/usr/bin/python3
"""Sync Sprint 12 S12-12 item 1: closing a card from the overview asks the window.

Runs the real dwm on the display xvfb-run provides (see
`make check-overview-close-xvfb`) and one Tk window whose WM_DELETE_WINDOW handler
records the request and refuses to close, like an editor with unsaved work.
`dwm-quickshell-state close` must ask it (the handler runs) and leave it open.
`xdotool windowclose`, which the helper used before, is run on a second such
window to show the difference: it destroys the window without asking.
"""
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
for tool in ('xdotool', 'xprop'):
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

# Two windows, each recording a close request in its own file and refusing it.
CLIENT = r'''
import sys, tkinter
root = tkinter.Tk()
root.withdraw()
for name in ('asked', 'destroyed'):
    top = tkinter.Toplevel(root, class_='Closetest')
    top.title('close-' + name)
    top.geometry('200x100')
    top.protocol('WM_DELETE_WINDOW', lambda path=sys.argv[1] + '/' + name: open(path, 'a').write('asked\n'))
root.after(30000, root.destroy)
root.mainloop()
'''


def fail(message, extra=''):
    print('FAIL: ' + message, file=sys.stderr)
    if extra:
        print(extra, file=sys.stderr)
    raise SystemExit(1)


with tempfile.TemporaryDirectory(prefix='overview-close-') as temp:
    base = Path(temp)
    runtime = base / 'rt'
    runtime.mkdir(mode=0o700)
    (base / 'config/lyona').mkdir(parents=True)
    for toml in (repo / 'config').glob('*.toml'):
        shutil.copy(toml, base / 'config/lyona' / toml.name)
    env = {**os.environ, 'HOME': str(base), 'XDG_CONFIG_HOME': str(base / 'config'),
           'XDG_DATA_HOME': str(base / 'data'), 'XDG_RUNTIME_DIR': str(runtime)}
    log = (base / 'session.log').open('w')
    procs = []

    def start(args):
        proc = subprocess.Popen(args, env=env, stdout=log, stderr=log, start_new_session=True)
        procs.append(proc)
        return proc

    def window(name):
        found = subprocess.run(['xdotool', 'search', '--name', '^close-%s$' % name], env=env,
                               capture_output=True, text=True).stdout.split()
        return found[0] if found else None

    def exists(win):
        return subprocess.run(['xprop', '-id', win, 'WM_CLASS'], env=env, capture_output=True).returncode == 0

    try:
        wm = start([str(repo / 'dwm')])
        deadline = time.time() + 10
        while b'=' not in subprocess.run(['xprop', '-root', '_DWM_MONITOR_DESKTOPS'], env=env,
                                         capture_output=True).stdout:
            if time.time() > deadline or wm.poll() is not None:
                fail('dwm did not start', (base / 'session.log').read_text())
            time.sleep(0.1)
        start([sys.executable, '-c', CLIENT, str(base)])
        deadline = time.time() + 10
        while not (window('asked') and window('destroyed')) and time.time() < deadline:
            time.sleep(0.1)
        asked_win, destroyed_win = window('asked'), window('destroyed')
        if not asked_win or not destroyed_win:
            fail('the test windows did not appear', (base / 'session.log').read_text())

        subprocess.run([str(repo / 'scripts/dwm-quickshell-state'), 'close', asked_win], env=env, check=True)
        deadline = time.time() + 5
        while not (base / 'asked').exists() and time.time() < deadline:
            time.sleep(0.05)
        time.sleep(0.5)
        result = {'helper_asked': (base / 'asked').exists(), 'helper_window_kept': exists(asked_win)}
        # Then the old command, on the other window. Destroying a window under Tk
        # can end the whole client, so this comes last.
        subprocess.run(['xdotool', 'windowclose', destroyed_win], env=env, check=True)
        time.sleep(1)
        result['windowclose_asked'] = (base / 'destroyed').exists()
        result['windowclose_window_kept'] = exists(destroyed_win)
        print('Overview close: %s' % result)
        if not result['helper_asked'] or not result['helper_window_kept']:
            fail('dwm-quickshell-state close did not ask the window (it must run its close handler and '
                 'stay open when that refuses)')
        if result['windowclose_asked'] or result['windowclose_window_kept']:
            fail('the comparison did not hold: xdotool windowclose was expected to destroy without asking')
    finally:
        for proc in reversed(procs):
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            proc.wait()
        log.close()

print('Overview close (asks the window, which may refuse; windowclose destroyed it unasked): PASS')
