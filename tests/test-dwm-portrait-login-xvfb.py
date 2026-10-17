#!/usr/bin/python3
"""#376, #387: a portrait layout kept from the last session, applied at login.

autostart applies the kept display layout before the Quickshell panel docks, so
dwm handles the screen-size change while it has no bar yet (bar height 0). That
crashed dwm (#376: an empty drawing pixmap). This runs the real dwm on the
display xvfb-run provides (RandR: a landscape mode, then a portrait one; Xvfb
cannot rotate, so the portrait screen is a 1080x1920 mode, which is what dwm
sees of a rotated output) and checks the whole sequence:
- dwm survives the portrait change made before any panel;
- the panel that docks after it becomes the bar, at the portrait width;
- a window mapped before the change and one mapped after the panel docks are
  tiled into the portrait screen below the panel: nothing is sized from the
  landscape screen or from the bar height of 0;
- the screen turned back to landscape and to portrait again with the panel
  docked: the bar follows the width and the windows still fill the screen.
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
for tool in ('xprop', 'xrandr'):
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
X.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
X.XCloseDisplay.argtypes = [ctypes.c_void_p]
X.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
X.XInternAtom.restype = ctypes.c_ulong
X.XChangeProperty.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_int,
                              ctypes.c_int, ctypes.c_void_p, ctypes.c_int]

PANEL = 30
LANDSCAPE = (1920, 1080)
PORTRAIT = (1080, 1920)


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
    fail(message() if callable(message) else message)


def root_prop(name):
    out = run('xprop', '-root', name).stdout.strip()
    if not out.startswith(name + '('):
        return ''
    return out.split(':', 1)[1] if ':' in out else ''


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
display = X.XOpenDisplay(os.environ['DISPLAY'].encode())
if not display:
    fail('cannot open the display')
root = X.XDefaultRootWindow(display)


def geometry(win):
    """Outer geometry (x, y, width, height), border included. dwm does not
    reparent, so a window's position is on the root."""
    X.XSync(display, 0)
    attributes = WindowAttributes()
    if not X.XGetWindowAttributes(display, win, ctypes.byref(attributes)):
        return None
    border = attributes.border_width
    return (attributes.x, attributes.y, attributes.width + 2 * border, attributes.height + 2 * border)


def screen_size():
    box = geometry(root)
    return box[2:] if box else None


def xrandr(*args):
    result = run('xrandr', *args)
    if result.returncode != 0:
        fail('xrandr %s: %s' % (' '.join(args), result.stderr.strip()))


def set_screen(size):
    """What a kept layout does to dwm: the output's mode and the screen change."""
    mode = '%dx%d' % size
    xrandr('--output', 'screen', '--mode', mode, '--fb', mode)
    wait(lambda: screen_size() == size, 'the screen did not become %s' % mode)


with tempfile.TemporaryDirectory(prefix='dwm-portrait-login-', dir=os.environ.get('DWM_TEST_TMP_ROOT')) as temp:
    base = Path(temp)
    env = {**os.environ, 'HOME': str(base), 'XDG_CONFIG_HOME': str(base / 'config'),
           'XDG_RUNTIME_DIR': str(base)}

    # The login screen: landscape. Xvfb's screen is made 1920x1920 so either
    # orientation fits; its one output starts at that size, and has no other
    # mode until one is added.
    for width, height in (LANDSCAPE, PORTRAIT):
        name = '%dx%d' % (width, height)
        xrandr('--newmode', name, '0', str(width), str(width), str(width), str(width),
               str(height), str(height), str(height), str(height))
        xrandr('--addmode', 'screen', name)
    set_screen(LANDSCAPE)

    log = (base / 'dwm.log').open('w')
    wm = subprocess.Popen([str(repo / 'dwm')], env=env, stdout=log, stderr=log)

    def alive(step):
        if wm.poll() is not None:
            log.flush()
            fail('dwm exited %s (status %d): %s'
                 % (step, wm.returncode, (base / 'dwm.log').read_text()[-2000:]))

    try:
        wait(lambda: wm.poll() is not None or root_prop('_NET_SUPPORTING_WM_CHECK') != '', 'dwm did not start', 8)
        alive('at startup')
        wtype = X.XInternAtom(display, b'_NET_WM_WINDOW_TYPE', 0)
        dock_type = ctypes.c_ulong(X.XInternAtom(display, b'_NET_WM_WINDOW_TYPE_DOCK', 0))
        atom = X.XInternAtom(display, b'ATOM', 0)
        cardinal = X.XInternAtom(display, b'CARDINAL', 0)
        strut_partial = X.XInternAtom(display, b'_NET_WM_STRUT_PARTIAL', 0)
        strut = X.XInternAtom(display, b'_NET_WM_STRUT', 0)

        def window(x, y, width, height, dock=False):
            win = X.XCreateSimpleWindow(display, root, x, y, width, height, 0, 0, 0x202020)
            if dock:
                X.XChangeProperty(display, win, wtype, atom, 32, 0, ctypes.byref(dock_type), 1)
                partial = (ctypes.c_long * 12)(0, 0, height, 0, 0, 0, 0, 0, 0, width - 1, 0, 0)
                simple = (ctypes.c_long * 4)(0, 0, height, 0)
                X.XChangeProperty(display, win, strut_partial, cardinal, 32, 0, partial, 12)
                X.XChangeProperty(display, win, strut, cardinal, 32, 0, simple, 4)
            X.XMapWindow(display, win)
            X.XSync(display, 0)
            return win

        def tiled(wins, size, top):
            """The windows tile the screen below TOP: a master column on the
            left, a stack on the right, no part off screen, no strip left
            over (gaps are allowed, the same on every side of the area)."""
            width, height = size
            boxes = [geometry(win) for win in wins]
            if None in boxes:
                return False
            left = min(box[0] for box in boxes)
            right = max(box[0] + box[2] for box in boxes)
            upper = min(box[1] for box in boxes)
            lower = max(box[1] + box[3] for box in boxes)
            gap = left
            return (0 <= gap <= 40 and upper >= top and right <= width and lower <= height
                    and abs((width - right) - gap) <= 1 and abs((upper - top) - gap) <= 1
                    and abs((height - lower) - gap) <= 1)

        def where(wins):
            return ', '.join('%#x at %s' % (win, geometry(win)) for win in wins)

        # A window autostart opened before the layout is applied.
        early = window(100, 100, 400, 300)
        wait(lambda: tiled([early], LANDSCAPE, 0),
             lambda: 'the first window does not fill the landscape screen: ' + where([early]))

        # The kept portrait layout, before the panel docks: dwm has no bar.
        set_screen(PORTRAIT)
        time.sleep(0.3)
        alive('when the screen turned portrait before the panel docked (#376)')
        wait(lambda: tiled([early], PORTRAIT, 0),
             lambda: 'with no panel yet, the window does not fill the portrait screen: ' + where([early]))

        # The panel docks, at the portrait width, and becomes the bar.
        panel = window(0, 0, PORTRAIT[0], PANEL, dock=True)
        wait(lambda: '%#x' % panel in root_prop('_NET_CLIENT_LIST'),
             lambda: 'the panel did not become the bar: ' + root_prop('_NET_CLIENT_LIST'))
        wait(lambda: tiled([early], PORTRAIT, PANEL),
             lambda: 'after the panel docked, the window does not fill the portrait screen below it: '
             + where([early]))
        if geometry(panel) != (0, 0, PORTRAIT[0], PANEL):
            fail('the panel is at %s, not across the top of the portrait screen' % (geometry(panel),))

        # A window opened after the panel docked.
        late = window(50, 50, 300, 200)
        wait(lambda: tiled([early, late], PORTRAIT, PANEL),
             lambda: 'the windows do not tile the portrait screen below the panel: ' + where([early, late]))
        alive('after the panel docked')
        print('portrait, panel docked: panel %s; %s' % (geometry(panel), where([early, late])))

        # The layout changed again with the panel docked: dwm sets the bar to
        # the screen's width, and the windows follow.
        for size in (LANDSCAPE, PORTRAIT):
            set_screen(size)
            wait(lambda: geometry(panel) == (0, 0, size[0], PANEL),
                 lambda: 'after the screen became %dx%d the panel is at %s' % (size + (geometry(panel),)))
            wait(lambda: tiled([early, late], size, PANEL),
                 lambda: 'after the screen became %dx%d the windows do not tile it below the panel: %s'
                 % (size + (where([early, late]),)))
            alive('when the screen changed with the panel docked')
            print('%dx%d: panel %s; %s' % (size + (geometry(panel), where([early, late]))))

        print('dwm survives a portrait layout applied before the panel docks; the panel and the windows '
              'take the portrait screen, and follow it after: PASS')
    finally:
        wm.terminate()
        try:
            wm.wait(timeout=5)
        except subprocess.TimeoutExpired:
            wm.kill()
        log.close()
X.XCloseDisplay(display)
