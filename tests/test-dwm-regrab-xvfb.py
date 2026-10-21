#!/usr/bin/python3
"""dwm keeps its key grabs while it regrabs them (#411), with the real dwm.

dwm grabs its keys again on every keyboard MappingNotify, and the X server
sends one as the core keyboard switches devices: the first XTest key of a
session, or a second keyboard. dwm used to take every grab back first, and a
key pressed before it grabbed them again went to the focused window: the
desktop smoke test's first Super+R, now and then on a loaded runner.

This changes a spare keycode's keysym many times, each change a MappingNotify
and a regrab, and after each one tries, from a second client, to grab Super+R
on the root window for some milliseconds. dwm holds that grab, so every try
must fail with BadAccess; one that succeeds caught dwm without it.
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
if not shutil.which('xprop'):
    print('SKIP: xprop is unavailable')
    raise SystemExit(77)
if not os.environ.get('DISPLAY') or not (repo / 'dwm').exists():
    print('SKIP: needs an X display (xvfb-run) and a built dwm')
    raise SystemExit(77)
CHANGES = int(os.environ.get('LYONA_REGRAB_CHANGES', '200'))

X = ctypes.CDLL(ctypes.util.find_library('X11'))
X.XOpenDisplay.argtypes = [ctypes.c_char_p]
X.XOpenDisplay.restype = ctypes.c_void_p
X.XCloseDisplay.argtypes = [ctypes.c_void_p]
X.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
X.XDefaultRootWindow.restype = ctypes.c_ulong
X.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
X.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X.XKeysymToKeycode.restype = ctypes.c_ubyte
X.XGrabKey.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_uint, ctypes.c_ulong,
                       ctypes.c_int, ctypes.c_int, ctypes.c_int]
X.XUngrabKey.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_uint, ctypes.c_ulong]
X.XDisplayKeycodes.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
X.XGetKeyboardMapping.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
X.XGetKeyboardMapping.restype = ctypes.POINTER(ctypes.c_ulong)
X.XChangeKeyboardMapping.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                     ctypes.POINTER(ctypes.c_ulong), ctypes.c_int]
X.XFree.argtypes = [ctypes.c_void_p]


class XErrorEvent(ctypes.Structure):
    _fields_ = [('type', ctypes.c_int), ('display', ctypes.c_void_p), ('resourceid', ctypes.c_ulong),
                ('serial', ctypes.c_ulong), ('error_code', ctypes.c_ubyte), ('request_code', ctypes.c_ubyte),
                ('minor_code', ctypes.c_ubyte)]


ERROR_HANDLER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(XErrorEvent))
X.XSetErrorHandler.argtypes = [ERROR_HANDLER]
X.XSetErrorHandler.restype = ctypes.c_void_p
errors = []
handler = ERROR_HANDLER(lambda display, event: errors.append(event.contents.error_code) or 0)
X.XSetErrorHandler(handler)

BAD_ACCESS = 10
MOD4 = 1 << 6
XK_R = 0x72
XK_F20 = 0xffd1


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    raise SystemExit(1)


def root_prop(name):
    return subprocess.run(['xprop', '-root', name], capture_output=True, text=True).stdout


def wait(predicate, message, seconds=8):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    fail(message)


with tempfile.TemporaryDirectory(prefix='dwm-regrab-', dir=os.environ.get('DWM_TEST_TMP_ROOT')) as temp:
    base = Path(temp)
    env = {**os.environ, 'HOME': str(base), 'XDG_CONFIG_HOME': str(base / 'config'),
           'XDG_RUNTIME_DIR': str(base)}
    log = (base / 'dwm.log').open('w')
    wm = subprocess.Popen([str(repo / 'dwm')], env=env, stdout=log, stderr=log)
    display = None
    try:
        wait(lambda: wm.poll() is not None or 'window id #' in root_prop('_NET_SUPPORTING_WM_CHECK'),
             'dwm did not start')
        if wm.poll() is not None:
            log.flush()
            fail('dwm exited at startup (status %d): %s' % (wm.returncode, (base / 'dwm.log').read_text()[-2000:]))
        display = X.XOpenDisplay(os.environ['DISPLAY'].encode())
        root = X.XDefaultRootWindow(display)
        super_r = X.XKeysymToKeycode(display, XK_R)

        def dwm_holds_super_r():
            """Try to grab Super+R; True when dwm holds it (BadAccess)."""
            del errors[:]
            X.XGrabKey(display, super_r, MOD4, root, 1, 1, 1)
            X.XSync(display, 0)
            if BAD_ACCESS in errors:
                return True
            X.XUngrabKey(display, super_r, MOD4, root)
            X.XSync(display, 0)
            return False

        wait(dwm_holds_super_r, 'dwm never grabbed Super+R')

        # A keycode with no keysym at all, to switch between F20 and nothing.
        first, last, per = ctypes.c_int(), ctypes.c_int(), ctypes.c_int()
        X.XDisplayKeycodes(display, ctypes.byref(first), ctypes.byref(last))
        syms = X.XGetKeyboardMapping(display, first.value, last.value - first.value + 1, ctypes.byref(per))
        spare = next((code for code in range(last.value, first.value - 1, -1)
                      if not any(syms[(code - first.value) * per.value + i] for i in range(per.value))), None)
        X.XFree(syms)
        if spare is None:
            print('SKIP: the keymap has no spare keycode')
            raise SystemExit(77)

        free_after = []
        tries = 0
        for change in range(CHANGES):
            keysyms = (ctypes.c_ulong * per.value)()
            keysyms[0] = XK_F20 if change % 2 == 0 else 0
            X.XChangeKeyboardMapping(display, spare, per.value, keysyms, 1)
            X.XSync(display, 0)
            deadline = time.monotonic() + 0.005
            while time.monotonic() < deadline:
                tries += 1
                if not dwm_holds_super_r():
                    free_after.append(change)
                    break
            if free_after:
                break
        keysyms = (ctypes.c_ulong * per.value)()
        X.XChangeKeyboardMapping(display, spare, per.value, keysyms, 1)
        X.XSync(display, 0)
        if free_after:
            fail('dwm let go of Super+R while it grabbed its keys again after keymap change %d '
                 '(%d grab tries): a key pressed then is not dwm\'s' % (free_after[0] + 1, tries))
        if wm.poll() is not None:
            fail('dwm exited during the keymap changes (status %d)' % wm.returncode)
        wait(dwm_holds_super_r, 'dwm does not hold Super+R after the keymap changes')
        print('dwm regrab keeps its grabs: PASS (%d keymap changes, %d grab tries)' % (CHANGES, tries))
    finally:
        if display:
            X.XCloseDisplay(display)
        wm.terminate()
        try:
            wm.wait(5)
        except subprocess.TimeoutExpired:
            wm.kill()
            wm.wait()
        log.close()
