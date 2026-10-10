#!/usr/bin/python3
"""#280 VM: _NET_ACTIVE_WINDOW and _DWM_MONITOR_WINDOWS, with the real dwm.

Runs dwm on the display xvfb-run provides, with real client windows:
- a request with source indication 2 (a pager: the overview, the panel's
  running apps, `xdotool windowactivate`) switches to a window on another tag
  and focuses it;
- an application's own request (source 1) marks the window urgent and leaves
  the focus where it is;
- closing a window returns the focus to the window focused before it, not to
  the master;
- _DWM_MONITOR_WINDOWS names each monitor's selected window: run once on one
  screen, and with DWM_TEST_MONITORS=2 on Xvfb's two Xinerama screens.
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
for tool in ('xdotool', 'xprop'):
    if not shutil.which(tool):
        print('SKIP: %s is unavailable' % tool)
        raise SystemExit(77)
MONITORS = int(os.environ.get('DWM_TEST_MONITORS', '1'))
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
X.XFlush.argtypes = [ctypes.c_void_p]
X.XCloseDisplay.argtypes = [ctypes.c_void_p]
X.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
X.XInternAtom.restype = ctypes.c_ulong


class WMHints(ctypes.Structure):
    _fields_ = [('flags', ctypes.c_long), ('input', ctypes.c_int), ('initial_state', ctypes.c_int),
                ('icon_pixmap', ctypes.c_ulong), ('icon_window', ctypes.c_ulong), ('icon_x', ctypes.c_int),
                ('icon_y', ctypes.c_int), ('icon_mask', ctypes.c_ulong), ('window_group', ctypes.c_ulong)]


X.XSetWMHints.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(WMHints)]


class ClientMessage(ctypes.Structure):
    _fields_ = [('type', ctypes.c_int), ('serial', ctypes.c_ulong), ('send_event', ctypes.c_int),
                ('display', ctypes.c_void_p), ('window', ctypes.c_ulong), ('message_type', ctypes.c_ulong),
                ('format', ctypes.c_int), ('l', ctypes.c_long * 5)]


class XEvent(ctypes.Union):
    _fields_ = [('xclient', ClientMessage), ('pad', ctypes.c_long * 24)]


X.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.POINTER(XEvent)]


class SetWindowAttributes(ctypes.Structure):
    _fields_ = [('background_pixmap', ctypes.c_ulong), ('background_pixel', ctypes.c_ulong),
                ('border_pixmap', ctypes.c_ulong), ('border_pixel', ctypes.c_ulong),
                ('bit_gravity', ctypes.c_int), ('win_gravity', ctypes.c_int), ('backing_store', ctypes.c_int),
                ('backing_planes', ctypes.c_ulong), ('backing_pixel', ctypes.c_ulong), ('save_under', ctypes.c_int),
                ('event_mask', ctypes.c_long), ('do_not_propagate_mask', ctypes.c_long),
                ('override_redirect', ctypes.c_int), ('colormap', ctypes.c_ulong), ('cursor', ctypes.c_ulong)]


X.XChangeWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong,
                                      ctypes.POINTER(SetWindowAttributes)]
X.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
CW_OVERRIDE_REDIRECT = 1 << 9


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, timeout=10)


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    raise SystemExit(1)


def root_prop(name):
    out = run('xprop', '-root', name).stdout.strip()
    return out.split('=', 1)[1].strip() if '=' in out else (out.split(':', 1)[1].strip() if ':' in out else '')


def ids(text):
    return [int(word.strip(','), 16) for word in text.replace('window id #', '').split() if word.startswith('0x')]


def focused():
    out = run('xdotool', 'getwindowfocus').stdout.strip()
    return int(out) if out.isdigit() else 0


def wait(predicate, message, seconds=4):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    fail(message)


with tempfile.TemporaryDirectory(prefix='dwm-activate-', dir=os.environ.get('DWM_TEST_TMP_ROOT')) as temp:
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

        def window():
            win = X.XCreateSimpleWindow(display, root, 10, 40, 300, 200, 0, 0, 0x336699)
            # WM_HINTS, as applications set them: dwm marks urgency in them.
            hints = WMHints(flags=1, input=1)  # InputHint
            X.XSetWMHints(display, win, ctypes.byref(hints))
            X.XMapWindow(display, win)
            X.XSync(display, 0)
            wait(lambda: win in ids(root_prop('_NET_CLIENT_LIST')), 'dwm did not manage a window')
            return win

        first = window()
        wait(lambda: focused() == first, 'the first window was not focused')
        wait(lambda: ids(root_prop('_DWM_MONITOR_WINDOWS')) == [first] + [0] * (MONITORS - 1),
             '_DWM_MONITOR_WINDOWS does not name the focused window: ' + root_prop('_DWM_MONITOR_WINDOWS'))

        second = window()
        wait(lambda: focused() == second, 'the second window was not focused')

        def request(win, source):
            event = XEvent()
            event.xclient.type = 33  # ClientMessage
            event.xclient.window = win
            event.xclient.message_type = X.XInternAtom(display, b'_NET_ACTIVE_WINDOW', 0)
            event.xclient.format = 32
            event.xclient.l[0] = source
            X.XSendEvent(display, root, 0, (1 << 20) | (1 << 19), ctypes.byref(event))
            X.XFlush(display)

        # Closing a window goes back to the one focused before, not the master
        # (the first window): focus the second, then a third, close the third.
        third = window()
        request(second, 2)
        wait(lambda: focused() == second, 'a pager request did not focus the second window')
        request(third, 2)
        wait(lambda: focused() == third, 'a pager request did not focus the third window')
        X.XDestroyWindow(display, third)
        X.XSync(display, 0)
        wait(lambda: focused() == second,
             'closing a window did not return the focus to the window focused before it '
             '(focus 0x%x, before 0x%x, master 0x%x)' % (focused(), second, first))

        # A popup (an override-redirect window, as Quickshell maps one on X11)
        # asks for the keyboard and gets it; once a client has the focus again,
        # the popup taking it back by itself is corrected (#318: dwm used to
        # keep treating the popup as the focus owner until it unmapped).
        popup = X.XCreateSimpleWindow(display, root, 400, 300, 200, 100, 0, 0, 0x993366)
        attributes = SetWindowAttributes(override_redirect=1)
        X.XChangeWindowAttributes(display, popup, CW_OVERRIDE_REDIRECT, ctypes.byref(attributes))
        X.XMapWindow(display, popup)
        X.XSync(display, 0)
        time.sleep(0.3)
        request(popup, 1)
        wait(lambda: focused() == popup, 'a popup asking for the keyboard did not get it')
        request(second, 2)
        wait(lambda: focused() == second, 'a pager request did not take the focus back from the popup')
        X.XSetInputFocus(display, popup, 1, 0)  # RevertToPointerRoot, CurrentTime
        X.XSync(display, 0)
        wait(lambda: focused() == second,
             'a popup took the focus back by itself after a client had it, and dwm left it there '
             '(focus 0x%x, client 0x%x)' % (focused(), second))
        X.XDestroyWindow(display, popup)
        X.XSync(display, 0)

        # An application asking for itself: urgent, and the focus stays.
        request(first, 1)
        time.sleep(0.5)
        if focused() != second:
            fail('an application request (source 1) moved the focus')
        hints = run('xprop', '-id', hex(first), 'WM_HINTS').stdout
        if 'urgency hint bit is set' not in hints:
            fail('an application request (source 1) did not mark the window urgent: ' + hints)

        # A pager (source 2) on the same tag: the focus moves. Before #280 dwm only
        # marked it urgent, so the overview could not switch windows.
        request(first, 2)
        wait(lambda: focused() == first, 'a pager request (source 2) did not focus a window on the same tag')
        wait(lambda: ids(root_prop('_DWM_MONITOR_WINDOWS')) == [first] + [0] * (MONITORS - 1),
             '_DWM_MONITOR_WINDOWS did not follow the focus: ' + root_prop('_DWM_MONITOR_WINDOWS'))

        # On another tag: send the first window to tag 3 (dwm follows it), go back
        # to tag 1, then the overview's own path, xdotool windowactivate.
        run('xdotool', 'key', '--clearmodifiers', 'super+shift+3')
        wait(lambda: root_prop('_NET_CURRENT_DESKTOP') == '2', 'Super+Shift+3 did not move to tag 3')
        run('xdotool', 'key', '--clearmodifiers', 'super+1')
        wait(lambda: root_prop('_NET_CURRENT_DESKTOP') == '0', 'Super+1 did not return to tag 1')
        wait(lambda: focused() == second, 'tag 1 did not focus the second window')
        request(first, 2)
        wait(lambda: root_prop('_NET_CURRENT_DESKTOP') == '2',
             'a pager request (source 2) did not switch to the window tag')
        wait(lambda: focused() == first, 'a pager request (source 2) did not focus the window on its tag')

        if MONITORS == 2:
            # Two monitors (Xvfb's two Xinerama screens): each names its own
            # selected window, and the one with none is None (0).
            def monitor_windows():
                return [int(v.strip(), 16) for v in
                        root_prop('_DWM_MONITOR_WINDOWS').replace('window id #', '').split(',') if v.strip()]

            wait(lambda: monitor_windows() == [first, 0],
                 'with two monitors, expected [first, None]: %r' % monitor_windows())
            run('xdotool', 'key', '--clearmodifiers', 'super+period')
            wait(lambda: root_prop('_DWM_SELECTED_MONITOR') == '1', 'Super+period did not select monitor 2')
            third = window()
            wait(lambda: monitor_windows() == [first, third],
                 'each monitor should name its own window: %r' % monitor_windows())

            # A window closing on the monitor you are not on leaves your focus
            # alone (#318): it used to go to the root (when that monitor had no
            # window left) or to that monitor's next window.
            def stays_on_first(message):
                time.sleep(0.5)
                if (focused() != first or root_prop('_DWM_SELECTED_MONITOR') != '0'
                        or ids(root_prop('_NET_ACTIVE_WINDOW')) != [first]):
                    fail('%s: focus 0x%x, selected monitor %s, _NET_ACTIVE_WINDOW %s (expected 0x%x on 0)'
                         % (message, focused(), root_prop('_DWM_SELECTED_MONITOR'),
                            root_prop('_NET_ACTIVE_WINDOW'), first))

            run('xdotool', 'key', '--clearmodifiers', 'super+comma')
            wait(lambda: root_prop('_DWM_SELECTED_MONITOR') == '0' and focused() == first,
                 'Super+comma did not go back to monitor 1 and its window')
            X.XDestroyWindow(display, third)
            X.XSync(display, 0)
            stays_on_first('closing the only window on the other monitor moved the focus')
            wait(lambda: monitor_windows() == [first, 0],
                 'the other monitor still names its closed window: %r' % monitor_windows())

            run('xdotool', 'key', '--clearmodifiers', 'super+period')
            wait(lambda: root_prop('_DWM_SELECTED_MONITOR') == '1', 'Super+period did not select monitor 2 again')
            fourth = window()
            fifth = window()
            wait(lambda: monitor_windows() == [first, fifth], 'monitor 2 does not name its newest window')
            run('xdotool', 'key', '--clearmodifiers', 'super+comma')
            wait(lambda: root_prop('_DWM_SELECTED_MONITOR') == '0' and focused() == first,
                 'Super+comma did not go back to monitor 1 and its window')
            X.XDestroyWindow(display, fifth)
            X.XSync(display, 0)
            stays_on_first('closing one of two windows on the other monitor moved the focus')
            wait(lambda: monitor_windows() == [first, fourth],
                 'the other monitor does not name its remaining window: %r' % monitor_windows())
        if wm.poll() is not None:
            fail('dwm exited')
        print('dwm activation (pager switches, application is urgent), focus after close (on this and another '
              'monitor), popup focus and per-monitor windows, %d monitor(s): PASS' % MONITORS)
    finally:
        if display:
            X.XCloseDisplay(display)
        wm.terminate()
        try:
            wm.wait(timeout=5)
        except subprocess.TimeoutExpired:
            wm.kill()
        log.close()
