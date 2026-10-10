#!/usr/bin/python3
"""#280 VM, #322: a monitor's bar is the dock that reserves space for it.

Runs the real dwm on the display xvfb-run provides with dock windows, as
Quickshell maps them on X11 (_NET_WM_WINDOW_TYPE_DOCK, no WM_CLASS). The panel
declares itself the bar the EWMH way, with _NET_WM_STRUT_PARTIAL and
_NET_WM_STRUT for its exclusive zone; nothing else about it is guessed (#322):
- the panel becomes the bar: a client starts below it;
- a full-width dock that reserves nothing (a banner, an OSD) is not the bar,
  and is not managed either: shown, not tiled;
- a narrow dock (Quickshell's reload notice) does not take the bar's place, and
  the two are not raised over each other without end (dwm stays near idle);
- the panel stays the bar when that dock goes;
- a new panel mapped before the old one is destroyed (a Quickshell reload)
  becomes the bar once the old one goes;
- a dock that sets its strut after mapping becomes the bar then, and stops
  being it when it clears the strut.
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


class WindowAttributes(ctypes.Structure):
    _fields_ = [('x', ctypes.c_int), ('y', ctypes.c_int), ('width', ctypes.c_int), ('height', ctypes.c_int),
                ('border_width', ctypes.c_int), ('depth', ctypes.c_int), ('visual', ctypes.c_void_p),
                ('root', ctypes.c_ulong), ('c_class', ctypes.c_int), ('bit_gravity', ctypes.c_int),
                ('win_gravity', ctypes.c_int), ('backing_store', ctypes.c_int), ('backing_planes', ctypes.c_ulong),
                ('backing_pixel', ctypes.c_ulong), ('save_under', ctypes.c_int), ('colormap', ctypes.c_ulong),
                ('map_installed', ctypes.c_int), ('map_state', ctypes.c_int), ('all_event_masks', ctypes.c_long),
                ('your_event_mask', ctypes.c_long), ('do_not_propagate_mask', ctypes.c_long),
                ('override_redirect', ctypes.c_int), ('screen', ctypes.c_void_p)]


X.XGetWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(WindowAttributes)]
IS_VIEWABLE = 2

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
        cardinal = X.XInternAtom(display, b'CARDINAL', 0)
        strut_partial = X.XInternAtom(display, b'_NET_WM_STRUT_PARTIAL', 0)
        strut = X.XInternAtom(display, b'_NET_WM_STRUT', 0)

        def set_strut(win, top):
            """The struts Quickshell's exclusiveZone sets: TOP pixels at the top."""
            partial = (ctypes.c_long * 12)(0, 0, top, 0, 0, 0, 0, 0, 0, 1023 if top else 0, 0, 0)
            simple = (ctypes.c_long * 4)(0, 0, top, 0)
            X.XChangeProperty(display, win, strut_partial, cardinal, 32, 0, partial, 12)
            X.XChangeProperty(display, win, strut, cardinal, 32, 0, simple, 4)
            X.XSync(display, 0)

        def window(x, y, width, height, dock, reserve=0):
            win = X.XCreateSimpleWindow(display, root, x, y, width, height, 0, 0, 0x202020)
            if dock:
                X.XChangeProperty(display, win, wtype, atom, 32, 0, ctypes.byref(dock_type), 1)
            if reserve:
                set_strut(win, reserve)
            X.XMapWindow(display, win)
            X.XSync(display, 0)
            return win

        def viewable(win):
            attributes = WindowAttributes()
            return (X.XGetWindowAttributes(display, win, ctypes.byref(attributes)) != 0
                    and attributes.map_state == IS_VIEWABLE)

        panel = window(0, 0, 1024, 30, True, 30)
        client = window(100, 100, 300, 200, False)
        wait(lambda: y_of(client) >= 30, 'a client did not start below the panel (y %d)' % y_of(client))

        # A full-width dock that reserves nothing (a banner): not the bar, not a
        # managed window, but shown. dwm used to take any wide dock for a bar.
        banner = window(0, 0, 1024, 60, True)
        time.sleep(0.5)
        if y_of(client) != 30:
            fail('a full-width dock without a strut moved the work area: client at y %d' % y_of(client))
        if '%#x' % banner in root_prop('_NET_CLIENT_LIST'):
            fail('a dock that reserves nothing was managed: ' + root_prop('_NET_CLIENT_LIST'))
        if not viewable(banner):
            fail('a dock that reserves nothing was not shown')
        X.XDestroyWindow(display, banner)
        X.XSync(display, 0)

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
        new_panel = window(0, 0, 1024, 30, True, 30)
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

        # No bar: the work area is the whole screen. A dock that sets its strut
        # only after it is mapped becomes the bar then, and stops being it when
        # it clears the strut.
        X.XDestroyWindow(display, new_panel)
        X.XSync(display, 0)
        wait(lambda: y_of(client) < 30, 'with no bar left the client stayed below it (y %d)' % y_of(client))
        late = window(0, 0, 1024, 40, True)
        time.sleep(0.5)
        if y_of(client) >= 30:
            fail('a dock without a strut took the bar place (client at y %d)' % y_of(client))
        set_strut(late, 40)
        wait(lambda: y_of(client) >= 40, 'a dock that set its strut late did not become the bar (y %d)' % y_of(client))
        set_strut(late, 0)
        wait(lambda: y_of(client) < 30, 'a dock that cleared its strut stayed the bar (y %d)' % y_of(client))
        X.XDestroyWindow(display, late)
        X.XSync(display, 0)

        if wm.poll() is not None:
            fail('dwm exited')
        print('dwm takes the dock that reserves space for the bar (banner, narrow dock, no raise loop, '
              'panel replaced, strut set late and cleared): PASS')
    finally:
        if display:
            X.XCloseDisplay(display)
        wm.terminate()
        try:
            wm.wait(timeout=5)
        except subprocess.TimeoutExpired:
            wm.kill()
        log.close()
