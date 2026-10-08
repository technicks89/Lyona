#!/usr/bin/python3
"""#244: does Picom keep an off-tag window's picture current?

dwm moves a window on a hidden tag off screen; Picom still composites it, and
dwm-window-thumb reads it from there. This checks that a window which redraws
while off screen is captured as it is now, not as it was when it left the
screen. feh shows a picture and reloads it every second (--reload 1): the test
captures it red, replaces the file with blue while the window is off screen,
and captures again.

Exits 77 (skip) without Xvfb, picom, feh, xdotool or the built programs.
"""
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
helper = repo / 'dwm-window-thumb'
dwm = repo / 'dwm'
for tool in ('Xvfb', 'picom', 'feh', 'xdotool'):
    if not shutil.which(tool):
        print('SKIP: %s is unavailable' % tool)
        raise SystemExit(77)
if not dwm.exists() or not helper.exists():
    print('SKIP: dwm or dwm-window-thumb is not built (run make all)')
    raise SystemExit(77)

from PIL import Image  # noqa: E402

temp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT') or os.environ.get('TMPDIR') or Path.home() / 'tmp')
temp_root.mkdir(parents=True, exist_ok=True)
RED, BLUE = (220, 20, 20), (20, 20, 220)


def paint(path, colour):
    """Replace the picture whole, so feh never reads half a file."""
    partial = path.with_suffix('.part.png')
    Image.new('RGB', (300, 200), colour).save(partial)
    os.replace(partial, path)


def mean(path):
    return Image.open(path).convert('RGB').resize((1, 1)).getpixel((0, 0))


with tempfile.TemporaryDirectory(prefix='thumb-staleness-', dir=str(temp_root)) as temp:
    base = Path(temp)
    runtime = base / 'runtime'
    config = base / 'config'
    runtime.mkdir(mode=0o700)
    (config / 'lyona').mkdir(parents=True)
    for toml in (repo / 'config').glob('*.toml'):
        shutil.copy(toml, config / 'lyona' / toml.name)
    picture = base / 'picture.png'
    paint(picture, RED)
    (base / 'picom.conf').write_text('backend = "xrender";\n')

    read_fd, write_fd = os.pipe()
    xvfb = subprocess.Popen(
        ['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1024x768x24', '-nolisten', 'tcp', '+extension', 'Composite'],
        pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(write_fd)
    display = ':' + os.read(read_fd, 32).decode().strip()
    os.close(read_fd)
    env = {**os.environ, 'DISPLAY': display, 'HOME': str(base),
           'XDG_CONFIG_HOME': str(config), 'XDG_RUNTIME_DIR': str(runtime)}
    procs = [xvfb]

    def start(*args):
        proc = subprocess.Popen(list(args), env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        procs.append(proc)
        return proc

    def capture(window):
        result = subprocess.run([str(helper), 'capture', window], env=env, capture_output=True, text=True)
        assert result.returncode == 0, ('capture failed', result.returncode, result.stderr)
        return mean(Path(result.stdout.strip()))

    try:
        time.sleep(0.3)
        start(str(dwm))
        time.sleep(0.8)
        start('picom', '--config', str(base / 'picom.conf'))
        time.sleep(1.0)
        start('feh', '--auto-zoom', '--zoom', 'fill', '--reload', '1', '--title', 'staletest', str(picture))
        window = ''
        for _ in range(60):
            found = subprocess.run(['xdotool', 'search', '--name', 'staletest'], env=env, capture_output=True, text=True)
            if found.stdout.split():
                window = found.stdout.split()[0]
                break
            time.sleep(0.1)
        assert window, 'the test window did not appear'
        time.sleep(0.8)

        # Another tag: dwm moves the window off screen.
        subprocess.run(['xdotool', 'set_desktop', '1'], env=env, check=True)
        geometry = ''
        for _ in range(60):
            geometry = subprocess.run(['xdotool', 'getwindowgeometry', window], env=env, capture_output=True, text=True).stdout
            if 'Position: -' in geometry:
                break
            time.sleep(0.1)
        assert 'Position: -' in geometry, ('dwm did not move the window off screen', geometry)

        before = capture(window)
        assert before[0] > 150 and before[2] < 90, ('the off-tag window is red', before)

        # It redraws while off screen: feh reloads the replaced picture.
        paint(picture, BLUE)
        time.sleep(2.5)
        after = capture(window)
        fresh = after[2] > 150 and after[0] < 90
        print('Off-tag preview after the window redrew off screen: %s (before %s, after %s)'
              % ('current' if fresh else 'STALE', before, after))
        assert fresh, 'Picom kept an old picture of the off-tag window'
        print('Off-tag preview staleness: PASS')
    finally:
        for proc in reversed(procs):
            proc.terminate()
        for proc in procs:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
