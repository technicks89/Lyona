#!/usr/bin/python3
"""#280 VM: a monitor keeps one bar while other docks come and go.

Runs the real dwm on the display xvfb-run provides with dock windows, as
Quickshell maps them on X11 (_NET_WM_WINDOW_TYPE_DOCK, no WM_CLASS):
- a full-width panel becomes the bar: a client starts below it;
- a narrow dock (Quickshell's reload notice) does not take the bar's place, and
  the two are not raised over each other without end (dwm stays near idle);
- the panel stays the bar when that dock goes;
- a new panel mapped before the old one is destroyed (a Quickshell reload)
  becomes the bar once the old one goes.
"""
import ctypes
import ctypes.util
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
for tool in ('xprop', 'xdotool'):
    if not shutil.which(tool):
        print('SKIP: %s is unavailable' % tool)
        raise SystemExit(77)
if not os.environ.get('DISPLAY') or not (repo / 'dwm').exists():
    print('SKIP: needs an X display (xvfb-run) and a built dwm')
    raise SystemExit(77)

X = ctypes.CDLL(ctypes.util.find_library('X11'))
X.XOpenDisplay.argtypes = [ctypes.c_char_p]
X.XOpenDisplay.restype = ctypes.c_void_p
X.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
X.XDefaultRootWindow.restype = ctypes.c_ulong
X.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint,
                                  ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong]
X.XCreateSimpleWindow.restype = ctypes.c_ulong
X.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X.XDestroyWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
X.XCloseDisplay.argtypes = [ctypes.c_void_p]
X.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
X.XInternAtom.restype = ctypes.c_ulong
X.XChangeProperty.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int,
                              ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
X.XRaiseWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]

TICK = os.sysconf('SC_CLK_TCK')


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=10)


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    raise SystemExit(1)


def wait(predicate, message, seconds=4):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    fail(message)


def root_prop(name):
    out = run('xprop', '-root', name).stdout.strip()
    return out.split(':', 1)[1] if ':' in out else ''


def y_of(win):
    out = run('xdotool', 'getwindowgeometry', '--shell', str(win)).stdout
    for line in out.splitlines():
        if line.startswith('Y='):
            return int(line[2:])
    return -1


def cpu_ticks(pid):
    fields = Path('/proc/%d/stat' % pid).read_text().rsplit(')', 1)[1].split()
    return int(fields[11]) + int(fields[12])


with tempfile.TemporaryDirectory(prefix='dwm-bar-docks-', dir=os.environ.get('DWM_TEST_TMP_ROOT')) as temp:
    base = Path(temp)
    env = {**os.environ, 'HOME': str(base), 'XDG_CONFIG_HOME': str(base / 'config'),
           'XDG_RUNTIME_DIR': str(base)}
    log = (base / 'dwm.log').open('w')
    wm = subprocess.Popen([str(repo / 'dwm')], env=env, stdout=log, stderr=log)
    display = None
    try:
        wait(lambda: root_prop('_NET_SUPPORTING_WM_CHECK') != '', 'dwm did not start', 8)
        display = X.XOpenDisplay(os.environ['DISPLAY'].encode())
        root = X.XDefaultRootWindow(display)
        wtype = X.XInternAtom(display, b'_NET_WM_WINDOW_TYPE', 0)
        dock_type = ctypes.c_ulong(X.XInternAtom(display, b'_NET_WM_WINDOW_TYPE_DOCK', 0))
        atom = X.XInternAtom(display, b'ATOM', 0)

        def window(x, y, width, height, dock):
            win = X.XCreateSimpleWindow(display, root, x, y, width, height, 0, 0, 0x202020)
            if dock:
                X.XChangeProperty(display, win, wtype, atom, 32, 0, ctypes.byref(dock_type), 1)
            X.XMapWindow(display, win)
            X.XSync(display, 0)
            return win

        panel = window(0, 0, 1024, 30, True)
        client = window(100, 100, 300, 200, False)
        wait(lambda: y_of(client) >= 30, 'a client did not start below the panel (y %d)' % y_of(client))

        # A narrow dock: not the bar, and no raising war while both are mapped.
        notice = window(25, 25, 331, 77, True)
        time.sleep(0.5)
        X.XRaiseWindow(display, notice)
        X.XSync(display, 0)
        before = cpu_ticks(wm.pid)
        time.sleep(2)
        used = cpu_ticks(wm.pid) - before
        if used > TICK // 2:
            fail('dwm used %d ticks in 2 s with two docks mapped: they are raised over each other' % used)
        if y_of(client) < 30:
            fail('the narrow dock took the bar place: the client moved to y %d' % y_of(client))
        X.XDestroyWindow(display, notice)
        X.XSync(display, 0)
        time.sleep(0.5)
        if y_of(client) < 30:
            fail('the panel lost its place when the narrow dock went: client at y %d' % y_of(client))
        if '%#x' % panel not in root_prop('_NET_CLIENT_LIST'):
            fail('the panel is not the bar any more: ' + root_prop('_NET_CLIENT_LIST'))

        # A reload: the new panel maps, then the reload notice (narrower, after
        # it), then the old panel is destroyed: the new panel, the widest one
        # waiting, takes the place, not the notice that came last.
        new_panel = window(0, 0, 1024, 30, True)
        time.sleep(0.3)
        late_notice = window(25, 25, 331, 77, True)
        time.sleep(0.3)
        X.XDestroyWindow(display, panel)
        X.XSync(display, 0)
        wait(lambda: '%#x' % new_panel in root_prop('_NET_CLIENT_LIST'),
             'the new panel did not become the bar: ' + root_prop('_NET_CLIENT_LIST'))
        if y_of(client) < 30:
            fail('after the panel was replaced, the client moved to y %d' % y_of(client))
        if '%#x' % late_notice in root_prop('_NET_CLIENT_LIST'):
            fail('the notice that came last took the bar place')
        X.XDestroyWindow(display, late_notice)
        X.XSync(display, 0)

        if wm.poll() is not None:
            fail('dwm exited')
        print('dwm keeps one bar per monitor (narrow dock, no raise loop, panel replaced): PASS')
    finally:
        if display:
            X.XCloseDisplay(display)
        wm.terminate()
        try:
            wm.wait(timeout=5)
        except subprocess.TimeoutExpired:
            wm.kill()
        log.close()
