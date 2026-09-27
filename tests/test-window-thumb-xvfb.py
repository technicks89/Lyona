#!/usr/bin/python3
"""Sync Sprint 9 S9-01: dwm-window-thumb against a real X server, dwm and Picom.

A window with a known gradient is captured on the visible tag and again after dwm has
moved it to another tag (showhide() puts it at x = -2 * width, mapped but off screen),
which is the case the overview exists for. Checks, against the real helper:

1. Without a compositor nothing is captured (exit 3): an off-screen window cannot be
   read, and a covered one would return the wrong pixels.
2. With Picom the visible and the off-tag capture are real images of the right size and
   colour (red rises left to right, green rises top to bottom), and they agree.
3. The preview is private: under $XDG_RUNTIME_DIR only, directory 0700, file 0600, no
   fallback to /tmp when the runtime directory is missing, and it refuses a directory
   that is a symlink or open to other users. `purge` removes it.
4. WINDOW is validated before anything is written, a missing window is exit 5, and the
   "off" file switches the helper off (exit 4) for `available` and `capture`.

Exits 77 (skip) without Xvfb, picom, feh, xdotool or a built helper.
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
for tool in ('Xvfb', 'picom', 'feh', 'xdotool'):
    if not shutil.which(tool):
        print('SKIP: %s is unavailable' % tool)
        raise SystemExit(77)
helper = repo / 'dwm-window-thumb'
dwm = repo / 'dwm'
if not helper.exists() or not dwm.exists():
    print('SKIP: dwm-window-thumb is not built (run make all)')
    raise SystemExit(77)

from PIL import Image, ImageChops, ImageStat  # noqa: E402

temp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT') or os.environ.get('TMPDIR') or Path.home() / 'tmp')
temp_root.mkdir(parents=True, exist_ok=True)
SRC_W, SRC_H = 300, 200
BOX_W, BOX_H = 256, 160  # the helper's largest preview

NOCOMP, OFF, GONE, FAIL, USAGE = 3, 4, 5, 6, 2

with tempfile.TemporaryDirectory(prefix='window-thumb-', dir=str(temp_root)) as temp:
    base = Path(temp)
    runtime = base / 'runtime'
    config = base / 'config'
    runtime.mkdir(mode=0o700)
    (config / 'lyona').mkdir(parents=True)
    for toml in (repo / 'config').glob('*.toml'):
        shutil.copy(toml, config / 'lyona' / toml.name)

    stripes = base / 'stripes.png'
    image = Image.new('RGB', (SRC_W, SRC_H))
    pixels = image.load()
    for x in range(SRC_W):
        for y in range(SRC_H):
            pixels[x, y] = ((x * 255) // (SRC_W - 1), (y * 255) // (SRC_H - 1), 128 if (x // 30 + y // 20) % 2 else 40)
    image.save(stripes)

    read_fd, write_fd = os.pipe()
    xvfb = subprocess.Popen(
        ['Xvfb', '-displayfd', str(write_fd), '-screen', '0', '1024x768x24', '-nolisten', 'tcp', '+extension', 'Composite'],
        pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(write_fd)
    display = ':' + os.read(read_fd, 32).decode().strip()
    os.close(read_fd)
    env = {
        **os.environ,
        'DISPLAY': display,
        'HOME': str(base),
        'XDG_CONFIG_HOME': str(config),
        'XDG_RUNTIME_DIR': str(runtime),
    }
    procs = [xvfb]

    def run(*args, extra_env=None, drop=()):
        merged = {**env, **(extra_env or {})}
        for name in drop:
            merged.pop(name, None)
        return subprocess.run([str(helper), *args], env=merged, capture_output=True, text=True)

    def start(*args):
        proc = subprocess.Popen(list(args), env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        procs.append(proc)
        return proc

    def stored():
        directory = runtime / 'lyona' / 'overview-thumbs'
        return sorted(p.name for p in directory.iterdir()) if directory.is_dir() else []

    def mean(img, box):
        crop = img.crop(box).resize((1, 1))
        return crop.getpixel((0, 0))

    def expected_size(win_w, win_h):
        """The window scaled to fit the box, aspect ratio kept, never enlarged."""
        if win_w <= BOX_W and win_h <= BOX_H:
            return win_w, win_h
        if win_w * BOX_H > win_h * BOX_W:
            return BOX_W, win_h * BOX_W // win_w
        return win_w * BOX_H // win_h, BOX_H

    def window_size(win):
        text = subprocess.run(['xdotool', 'getwindowgeometry', win], env=env, capture_output=True, text=True).stdout
        size = text.split('Geometry:')[1].split()[0]
        return tuple(int(v) for v in size.split('x'))

    def looks_like_stripes(path, win):
        img = Image.open(path).convert('RGB')
        want = expected_size(*window_size(win))
        assert abs(img.width - want[0]) <= 1 and abs(img.height - want[1]) <= 1, (img.size, want)
        assert img.width <= BOX_W and img.height <= BOX_H, img.size
        assert len(img.getcolors(maxcolors=1 << 20)) > 50, 'the preview is uniform, not the window'
        w, h = img.size
        left, right = mean(img, (0, 0, w // 6, h)), mean(img, (w - w // 6, 0, w, h))
        top, bottom = mean(img, (0, 0, w, h // 6)), mean(img, (0, h - h // 6, w, h))
        assert right[0] > left[0] + 100, ('red does not rise left to right', left, right)
        assert bottom[1] > top[1] + 90, ('green does not rise top to bottom', top, bottom)
        return img

    try:
        time.sleep(0.3)
        start(str(dwm))
        time.sleep(0.8)
        start('feh', '--auto-zoom', '--zoom', 'fill', '--title', 'thumbtest', str(stripes))
        window = ''
        for _ in range(60):
            found = subprocess.run(['xdotool', 'search', '--name', 'thumbtest'], env=env, capture_output=True, text=True)
            if found.stdout.split():
                window = found.stdout.split()[0]
                break
            time.sleep(0.1)
        assert window, 'the test window did not appear'
        time.sleep(0.5)

        # 1. No compositor: refused, and nothing is stored.
        assert run('available').returncode == NOCOMP
        result = run('capture', window)
        assert result.returncode == NOCOMP and result.stdout == '', (result.returncode, result.stdout)
        assert stored() == []

        # 2. Picom running.
        (base / 'picom.conf').write_text('backend = "xrender";\n')
        start('picom', '--config', str(base / 'picom.conf'))
        for _ in range(60):
            if run('available').returncode == 0:
                break
            time.sleep(0.1)
        assert run('available').returncode == 0, 'available should succeed once a compositor runs'
        time.sleep(0.5)

        result = run('capture', window)
        assert result.returncode == 0, (result.returncode, result.stderr)
        visible_path = Path(result.stdout.strip())
        assert visible_path == runtime / 'lyona' / 'overview-thumbs' / (format(int(window), 'x') + '.ppm'), visible_path
        visible = looks_like_stripes(visible_path, window)

        # 3. Privacy of what was written.
        assert stat.S_IMODE((runtime / 'lyona').stat().st_mode) == 0o700
        assert stat.S_IMODE(visible_path.parent.stat().st_mode) == 0o700
        assert stat.S_IMODE(visible_path.stat().st_mode) == 0o600
        assert stored() == [visible_path.name], stored()  # no stray temporary file

        # The same window on another tag, where dwm has moved it off screen.
        subprocess.run(['xdotool', 'set_desktop', '1'], env=env, check=True)
        for _ in range(60):
            geometry = subprocess.run(['xdotool', 'getwindowgeometry', window], env=env, capture_output=True, text=True).stdout
            if 'Position: -' in geometry:
                break
            time.sleep(0.1)
        assert 'Position: -' in geometry, ('dwm did not move the window off screen', geometry)
        visible_path.unlink()
        result = run('capture', window)
        assert result.returncode == 0, ('off-tag capture failed', result.returncode, result.stderr)
        off = looks_like_stripes(Path(result.stdout.strip()), window)
        assert visible.size == off.size
        differ = sum(ImageStat.Stat(ImageChops.difference(visible, off)).mean) / 3
        assert differ < 6, ('the off-tag capture differs from the visible one', differ)

        # Purge deletes it, and is fine when there is nothing to delete.
        assert stored() != []
        assert run('purge').returncode == 0
        assert stored() == []
        assert run('purge').returncode == 0

        # 4. Arguments are validated before anything is written, and there is no other way to name a path.
        for bad in ('', '0', '-1', '+5', ' 5', '0x', 'abc', '0x1zz', '../../etc/passwd', '0x100000000', '5 6'):
            result = run('capture', bad)
            assert result.returncode == USAGE and result.stdout == '', (bad, result.returncode, result.stdout)
        assert run('capture').returncode == USAGE and run('capture', '1', '2').returncode == USAGE
        assert run('bogus').returncode == USAGE
        assert stored() == []
        assert run('capture', '0x7ffffff0').returncode == GONE, 'a window that does not exist is exit 5'

        # No fallback to /tmp: without a runtime directory there is nowhere private to write.
        before = set(os.listdir('/tmp'))
        result = run('capture', window, drop=('XDG_RUNTIME_DIR',))
        assert result.returncode == FAIL and result.stdout == '', (result.returncode, result.stdout)
        result = run('capture', window, extra_env={'XDG_RUNTIME_DIR': 'relative/dir'})
        assert result.returncode == FAIL and result.stdout == ''
        assert set(os.listdir('/tmp')) == before, 'the helper wrote into /tmp'

        # A storage directory that is open to others, or a symlink, is refused and left alone.
        thumbs = runtime / 'lyona' / 'overview-thumbs'
        thumbs.mkdir(parents=True, exist_ok=True)
        thumbs.chmod(0o755)
        (thumbs / 'keep.ppm').write_text('x')
        assert run('capture', window).returncode == FAIL
        assert run('purge').returncode == 0
        assert (thumbs / 'keep.ppm').exists(), 'purge touched a directory that is not private'
        (thumbs / 'keep.ppm').unlink()
        thumbs.chmod(0o700)
        elsewhere = base / 'elsewhere'
        elsewhere.mkdir(mode=0o700)  # private and ours, so only the symlink itself is grounds to refuse
        shutil.rmtree(runtime / 'lyona')
        (runtime / 'lyona').symlink_to(elsewhere)
        assert run('capture', window).returncode == FAIL
        assert list(elsewhere.iterdir()) == [], 'the helper followed a symlink out of the runtime directory'
        (runtime / 'lyona').unlink()

        # The user's off switch.
        switch = config / 'lyona' / 'overview-thumbnails'
        switch.write_text('off\n')
        assert run('available').returncode == OFF
        result = run('capture', window)
        assert result.returncode == OFF and stored() == []
        switch.write_text('on\n')
        assert run('available').returncode == 0
        switch.unlink()
        result = run('capture', window)
        assert result.returncode == 0, (result.returncode, result.stderr)

        # A window that is not mapped has no pixels to read: exit 5, not a capture error.
        subprocess.run(['xdotool', 'windowunmap', window], env=env, check=True)
        time.sleep(0.4)
        result = run('capture', window)
        assert result.returncode == GONE and result.stdout == '', (result.returncode, result.stdout)

        # A compositor that goes away takes the capability with it.
        picom = procs[-1]
        picom.terminate()
        picom.wait(timeout=5)
        for _ in range(60):
            if run('available').returncode == NOCOMP:
                break
            time.sleep(0.1)
        assert run('available').returncode == NOCOMP

        print('dwm-window-thumb (no compositor, Picom, off-tag capture, privacy, arguments, off switch): PASS')
    finally:
        for proc in reversed(procs):
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
