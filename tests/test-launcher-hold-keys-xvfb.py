#!/usr/bin/python3
"""#391: keys typed straight after Super+R belong to the launcher.

Runs the real dwm and the real managed Quickshell shell on the display
xvfb-run provides, with the shipped hotkeys.toml. A plain client window
(the "keysink") has the focus and records every key press it receives.
Then, in one xdotool run with no pause, Super+R and a query are typed, as
someone who does not wait for the launcher to appear does.

The launcher maps tens of milliseconds after Super+R. Without dwm's
hold_keys, the keys typed in that gap go to the keysink (a terminal, in real
use, where Enter would run them). With it, the keysink gets nothing, the
launcher's query is the whole text typed, and a query typed with Enter in the
same breath launches the application. Super+R that closes the launcher holds
nothing, and a hold whose window never appears lets the keys go after a second.

`--measure N` runs N plain rounds and prints how many key presses went where,
for measuring before and after a change; with LYONA_DWM_BIN another dwm binary
(an older build) can be measured.
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

repo = Path(__file__).resolve().parents[1]
for tool in ('xdotool', 'quickshell'):
    if not shutil.which(tool):
        print('SKIP: %s is unavailable' % tool)
        raise SystemExit(77)
dwm_bin = Path(os.environ.get('LYONA_DWM_BIN') or repo / 'dwm')
if not os.environ.get('DISPLAY') or not dwm_bin.exists():
    print('SKIP: needs an X display (xvfb-run) and a built dwm')
    raise SystemExit(77)
measure = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[1] == '--measure' else 0
temp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT') or os.environ.get('TMPDIR') or Path.home() / 'tmp')
temp_root.mkdir(parents=True, exist_ok=True)

# The keysink: a client window that prints the keysym of every key press it
# gets, one per line, modifiers left out. Its own process, so its event loop
# never waits on ours.
KEYSINK = r'''
import ctypes, ctypes.util, sys
X = ctypes.CDLL(ctypes.util.find_library('X11'))
X.XOpenDisplay.restype = ctypes.c_void_p
X.XOpenDisplay.argtypes = [ctypes.c_char_p]
X.XDefaultRootWindow.restype = ctypes.c_ulong
X.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
X.XCreateSimpleWindow.restype = ctypes.c_ulong
X.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                                  ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_ulong]
X.XSelectInput.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_long]
X.XStoreName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_char_p]
X.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
X.XLookupKeysym.argtypes = [ctypes.c_void_p, ctypes.c_int]
X.XLookupKeysym.restype = ctypes.c_ulong
X.XKeysymToString.argtypes = [ctypes.c_ulong]
X.XKeysymToString.restype = ctypes.c_char_p
d = X.XOpenDisplay(None)
w = X.XCreateSimpleWindow(d, X.XDefaultRootWindow(d), 40, 60, 400, 300, 0, 0, 0x336699)
X.XStoreName(d, w, b'keysink')
X.XSelectInput(d, w, 1)  # KeyPressMask
X.XMapWindow(d, w)
ev = (ctypes.c_long * 24)()
print('ready 0x%x' % w, flush=True)
while True:
    X.XNextEvent(d, ev)
    if ctypes.cast(ev, ctypes.POINTER(ctypes.c_int))[0] != 2:  # KeyPress
        continue
    sym = X.XLookupKeysym(ev, 0)
    # The modifiers of a chord (Super of Super+R) reach the focused window
    # whatever the window manager does; they type nothing.
    if 0xffe1 <= sym <= 0xffee or 0xfe01 <= sym <= 0xfe13:
        continue
    print((X.XKeysymToString(sym) or b'?').decode(), flush=True)
'''

with tempfile.TemporaryDirectory(prefix='lhk-', dir=str(temp_root)) as temp:
    base = Path(temp)
    home = base / 'home'
    config = home / '.config'
    data = home / '.local/share'
    runtime = base / 'runtime'
    (config / 'lyona').mkdir(parents=True)
    (data / 'applications').mkdir(parents=True)
    (data / 'lyona/assets').mkdir(parents=True)
    runtime.mkdir(mode=0o700)
    shutil.copytree(repo / 'config/quickshell', config / 'quickshell', symlinks=True)
    for toml in (repo / 'config').glob('*.toml'):
        shutil.copy(toml, config / 'lyona' / toml.name)
    # A binding that holds the keys for a window that never comes.
    hotkeys = config / 'lyona/hotkeys.toml'
    text = hotkeys.read_text()
    anchor = 'hold_keys="dwm launcher" },\n'
    assert anchor in text, 'the default Super+R binding has no hold_keys'
    hotkeys.write_text(text.replace(anchor, anchor + '  { mod="SUPER", key="F12", func="spawn", exec=["true"], '
                                    'hold_keys="no such window" },\n', 1))
    shutil.copytree(repo / 'assets/logo', data / 'lyona/assets/logo')
    icon = config / 'quickshell/assets/lyona-icon.png'
    icon.unlink(missing_ok=True)
    shutil.copy(repo / 'assets/logo/lyona-icon.png', icon)
    marker = base / 'launched'
    (data / 'applications/hold-keys.desktop').write_text(
        '[Desktop Entry]\nType=Application\nName=Zyxholdkeys\nExec=touch %s\nTerminal=false\nCategories=Utility;\n' % marker)
    env = {
        **os.environ,
        'HOME': str(home),
        'XDG_CONFIG_HOME': str(config),
        'XDG_DATA_HOME': str(data),
        'XDG_DATA_DIRS': str(data),
        'XDG_RUNTIME_DIR': str(runtime),
        'LYONA_DEV_SCRIPTS': str(repo / 'scripts'),
        'PATH': '%s:%s' % (repo / 'scripts', os.environ.get('PATH', '')),
        'DWM_AUTOSTART_NO_INPUT_WATCH': '1',
        'QT_QPA_PLATFORM': 'xcb',
        'QT_QUICK_BACKEND': 'software',
        'QT_QPA_PLATFORMTHEME': '',
    }
    log = (base / 'session.log').open('w+')
    procs = []

    def start(*args, **kw):
        p = subprocess.Popen(list(args), env=env, stdout=kw.get('stdout', log), stderr=log, text=True)
        procs.append(p)
        return p

    def run(*args):
        return subprocess.run(args, env=env, capture_output=True, text=True)

    def ipc(name):
        r = run('quickshell', 'ipc', '--path', str(config / 'quickshell/shell.qml'), 'call', 'launcher', name)
        return r.stdout.strip() if r.returncode == 0 else None

    def wait(predicate, message, seconds=8.0):
        deadline = time.time() + seconds
        while time.time() < deadline:
            value = predicate()
            if value:
                return value
            time.sleep(0.05)
        raise AssertionError(message)

    def launcher_open():
        return run('xdotool', 'search', '--onlyvisible', '--name', '^dwm launcher$').returncode == 0

    def focused():
        r = run('xdotool', 'getwindowfocus')
        return int(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else 0

    sunk = []
    status = 1
    try:
        start(str(dwm_bin))
        start('quickshell', '--no-duplicate')
        wait(lambda: ipc('indexCount') is not None, 'the managed shell never answered IPC', 20)
        sink = start(sys.executable, '-c', KEYSINK, stdout=subprocess.PIPE)
        sink_win = int(sink.stdout.readline().split()[1], 16)
        os.set_blocking(sink.stdout.fileno(), False)

        def drain():
            for line in iter(sink.stdout.readline, ''):
                sunk.append(line.strip())
            return sunk

        def round_trip(text, enter=False):
            """Focus the keysink, then Super+R and TEXT with no pause."""
            wait(lambda: not launcher_open(), 'the launcher did not close')
            run('xdotool', 'windowactivate', '--sync', str(sink_win))
            wait(lambda: focused() == sink_win, 'dwm did not focus the keysink')
            time.sleep(0.2)
            drain()
            del sunk[:]
            # type takes every argument after it as text, so Return is a
            # second xdotool run, started as soon as the first ends.
            run('xdotool', 'key', 'super+r', 'type', '--delay', '4', text).check_returncode()
            if enter:
                run('xdotool', 'key', 'Return').check_returncode()

        # The plain case: the whole query reaches the launcher, none of it
        # the window that had the focus.
        query = 'zyxholdkeys'
        rounds = measure or 1
        totals = []
        for n in range(rounds):
            round_trip(query)
            typed = time.time()
            wait(launcher_open, 'Super+R did not open the launcher')
            if measure:
                # How long after the typing the whole query is there: about
                # the launcher's map time, or the hold's one-second limit.
                while ipc('query') != query and time.time() - typed < 1.5:
                    time.sleep(0.01)
                full = time.time() - typed
                time.sleep(max(0.0, 1.5 - full))
                got = ipc('query') or ''
                drain()
                totals.append((len(sunk), len(got)))
                print('round %d: keysink %d key presses %r, launcher query %r, whole %.0f ms after typing' % (
                    n + 1, len(sunk), ''.join(s if len(s) == 1 else '<%s>' % s for s in sunk), got,
                    full * 1000), flush=True)
            else:
                try:
                    wait(lambda: ipc('query') == query, 'no query', 3)
                except AssertionError:
                    raise AssertionError('the launcher query is %r, not %r (keysink %r)'
                                         % (ipc('query'), query, drain()))
                time.sleep(0.3)
                drain()
                assert not sunk, 'keys typed after Super+R reached the focused window: %r' % sunk
            ipc('close')
        if measure:
            print('total: keysink %d of %d key presses; launcher whole query in %d of %d rounds' % (
                sum(t[0] for t in totals), rounds * len(query),
                sum(1 for t in totals if t[1] == len(query)), rounds))
            log.seek(0)
            for line in log:
                if 'hold_keys' in line:
                    print(line.rstrip())
            status = 0
            raise SystemExit(0)

        # Super+R, the query and Enter in one breath: the application starts.
        round_trip(query, enter=True)
        try:
            wait(marker.exists, 'no launch')
        except AssertionError:
            raise AssertionError('Super+R, a query and Enter typed at once launched nothing '
                                 '(launcher open: %s, query %r, %s applications, keysink %r)'
                                 % (launcher_open(), ipc('query'), ipc('indexCount'), drain()))
        drain()
        assert not sunk, 'keys typed after Super+R reached the focused window: %r' % sunk
        wait(lambda: not launcher_open(), 'the launcher stayed open after launching')

        # Super+R while the launcher is open closes it, and the keyboard is
        # not held: the next keys go straight to the window with the focus.
        run('xdotool', 'key', 'super+r').check_returncode()
        wait(launcher_open, 'Super+R did not open the launcher')
        wait(lambda: focused() != sink_win, 'the launcher did not take the focus')
        run('xdotool', 'key', 'super+r').check_returncode()
        wait(lambda: not launcher_open(), 'Super+R did not close the launcher')
        wait(lambda: focused() == sink_win, 'the focus did not return to the keysink')
        run('xdotool', 'type', '--delay', '4', 'ab').check_returncode()
        wait(lambda: len(drain()) >= 2, 'keys after closing the launcher were held', 0.8)
        assert sunk == ['a', 'b'], sunk

        # A hold whose window never appears ends after its second, and the
        # keys typed meanwhile reach the focused window then, in order.
        del sunk[:]
        typed = time.time()
        run('xdotool', 'key', 'super+F12', 'type', '--delay', '4', 'cd').check_returncode()
        wait(lambda: len(drain()) >= 2, 'the keyboard stayed held after the hold timed out', 3)
        held = time.time() - typed
        assert sunk == ['c', 'd'], sunk
        assert 0.7 < held < 2.0, 'the hold lasted %.2f s, not about one second' % held
        log.seek(0)
        assert "no 'no such window' window within 1000 ms" in log.read(), 'dwm did not report the timeout'
        status = 0
        print('Launcher hold_keys: the query typed straight after Super+R reaches the launcher, '
              'none of it the focused window, Enter launches, closing holds nothing, and a hold ends '
              'after its second: PASS')
    except AssertionError as error:
        log.seek(0)
        print('FAIL: %s\n--- session log ---\n%s' % (error, log.read()[-4000:]), file=sys.stderr)
    finally:
        for p in reversed(procs):
            p.terminate()
        for p in reversed(procs):
            try:
                p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                p.kill()
        # What dwm's autostart and Quickshell started, by their private HOME.
        for entry in Path('/proc').iterdir():
            if not entry.name.isdigit() or int(entry.name) == os.getpid():
                continue
            try:
                if ('HOME=%s' % home).encode() in (entry / 'environ').read_bytes().split(b'\0'):
                    os.kill(int(entry.name), signal.SIGKILL)
            except (OSError, ValueError):
                pass
    raise SystemExit(status)
