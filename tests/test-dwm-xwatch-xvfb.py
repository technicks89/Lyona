#!/usr/bin/python3
"""#280: dwm-xwatch reports a client's _NET_WM_WINDOW_TYPE change.

The state bridge leaves docks out of the window list and caches them as left
out; only a "window 0xID" line from dwm-xwatch makes it read such a window
again. So a window that stops being a dock (or becomes one) must produce that
line. Runs the real dwm-xwatch on the display xvfb-run provides, with a client
listed in the root's _NET_CLIENT_LIST, as dwm lists it.
"""
import ctypes
import ctypes.util
import os
import select
import subprocess
import sys
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
xwatch = repo / 'dwm-xwatch'
if not os.environ.get('DISPLAY') or not xwatch.exists():
    print('SKIP: needs an X display (xvfb-run) and a built dwm-xwatch')
    raise SystemExit(77)

X = ctypes.CDLL(ctypes.util.find_library('X11'))
X.XOpenDisplay.argtypes = [ctypes.c_char_p]
X.XOpenDisplay.restype = ctypes.c_void_p
X.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
X.XDefaultRootWindow.restype = ctypes.c_ulong
X.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_uint,
                                  ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong]
X.XCreateSimpleWindow.restype = ctypes.c_ulong
X.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
X.XCloseDisplay.argtypes = [ctypes.c_void_p]
X.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
X.XInternAtom.restype = ctypes.c_ulong
X.XChangeProperty.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int,
                              ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
XA_ATOM, XA_WINDOW, PROP_MODE_REPLACE = 4, 33, 0


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    raise SystemExit(1)


def read_line(proc, seconds):
    """The watcher's next line, or None when none comes in time."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], max(0.0, deadline - time.time()))
        if ready:
            line = proc.stdout.readline()
            return line.strip() if line else None
    return None


def set_long(dpy, win, name, kind, value):
    data = (ctypes.c_long * 1)(value)
    X.XChangeProperty(dpy, win, X.XInternAtom(dpy, name, False), kind, 32, PROP_MODE_REPLACE, data, 1)
    X.XSync(dpy, False)


dpy = X.XOpenDisplay(None)
if not dpy:
    fail('cannot open the display')
root = X.XDefaultRootWindow(dpy)
win = X.XCreateSimpleWindow(dpy, root, 0, 0, 100, 100, 0, 0, 0)
set_long(dpy, win, b'_NET_WM_WINDOW_TYPE', XA_ATOM, X.XInternAtom(dpy, b'_NET_WM_WINDOW_TYPE_DOCK', False))
set_long(dpy, root, b'_NET_CLIENT_LIST', XA_WINDOW, win)

proc = subprocess.Popen([str(xwatch)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
try:
    if read_line(proc, 5) != 'ready':
        fail('dwm-xwatch did not say ready')
    # The dock becomes a normal window.
    set_long(dpy, win, b'_NET_WM_WINDOW_TYPE', XA_ATOM, X.XInternAtom(dpy, b'_NET_WM_WINDOW_TYPE_NORMAL', False))
    want = 'window 0x%x' % win
    line = read_line(proc, 3)
    if line != want:
        fail('a _NET_WM_WINDOW_TYPE change was not reported (wanted "%s", got %r)' % (want, line))
finally:
    proc.terminate()
    proc.wait(timeout=5)
    X.XCloseDisplay(dpy)
print('dwm-xwatch reports a client window type change: PASS')
