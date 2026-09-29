#!/usr/bin/python3
"""Sync Sprint 12 S12-09 item 2: a config reload runs theme-apply.sh only when needed.

Runs the real dwm on the display xvfb-run provides (see
`make check-dwm-reload-theme-xvfb`), with a data home whose only script is a stub
theme-apply.sh that logs each run (so no autostart runs), and the default TOML
files in its config home. Checked:

1. Start-up applies the theme once.
2. Rewriting window-rules.toml or hotkeys.toml reloads them (dwm logs it) without
   running theme-apply.sh.
3. Rewriting themes.toml runs it.
4. SIGUSR1, an explicit reload request, runs it.
"""
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
if not os.environ.get('DISPLAY') or not (repo / 'dwm').exists():
    print('SKIP: needs an X display (xvfb-run) and a built dwm')
    raise SystemExit(77)

temp_root = Path(os.environ.get('DWM_TEST_TMP_ROOT') or Path.home() / 'tmp')
temp_root.mkdir(parents=True, exist_ok=True)


def fail(message, log=None):
    print('FAIL: ' + message, file=sys.stderr)
    if log is not None:
        print(log.read_text()[-2000:], file=sys.stderr)
    raise SystemExit(1)


with tempfile.TemporaryDirectory(prefix='reload-theme-', dir=str(temp_root)) as temp:
    base = Path(temp)
    config = base / 'config/lyona'
    config.mkdir(parents=True)
    for toml in ('hotkeys.toml', 'themes.toml', 'window-rules.toml'):
        shutil.copy(repo / 'config' / toml, config / toml)
    scripts = base / 'data/lyona/scripts'
    scripts.mkdir(parents=True)
    runs = base / 'theme-apply.log'
    runs.touch()
    (scripts / 'theme-apply.sh').write_text('#!/bin/sh\nprintf "%s\\n" "$DWM_THEME_APPLY_AUTOMATIC" >>"'
                                            + str(runs) + '"\n')
    (scripts / 'theme-apply.sh').chmod(0o755)
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    env = {**os.environ, 'HOME': str(base), 'XDG_CONFIG_HOME': str(base / 'config'),
           'XDG_DATA_HOME': str(base / 'data'), 'XDG_RUNTIME_DIR': str(runtime),
           # dwm runs theme-apply.sh from the developer override (S12-13).
           'LYONA_DEV_SCRIPTS': str(scripts)}
    log_path = base / 'dwm.log'
    log = log_path.open('w')
    wm = subprocess.Popen([str(repo / 'dwm')], env=env, stdout=log, stderr=log, start_new_session=True)

    def count_runs():
        return len(runs.read_text().splitlines())

    def reloads():
        return log_path.read_text().count('keybinds from hotkeys config')

    def wait_for(predicate, message, seconds=5):
        deadline = time.time() + seconds
        while time.time() < deadline:
            if predicate():
                return
            time.sleep(0.05)
        fail(message, log_path)

    def rewrite(name):
        path = config / name
        path.write_text(path.read_text())

    try:
        wait_for(lambda: count_runs() == 1 and reloads() == 1, 'start-up did not load the config and apply the theme')

        for name in ('window-rules.toml', 'hotkeys.toml'):
            before = reloads()
            rewrite(name)
            wait_for(lambda: reloads() == before + 1, 'rewriting %s did not reload it' % name)
            time.sleep(0.5)  # theme-apply.sh would have been forked with the reload
            if count_runs() != 1:
                fail('rewriting %s ran theme-apply.sh' % name, log_path)

        rewrite('themes.toml')
        wait_for(lambda: count_runs() == 2, 'rewriting themes.toml did not run theme-apply.sh')

        os.kill(wm.pid, signal.SIGUSR1)
        wait_for(lambda: count_runs() == 3, 'SIGUSR1 did not run theme-apply.sh')
        if set(runs.read_text().split()) != {'1'}:
            fail('theme-apply.sh ran without DWM_THEME_APPLY_AUTOMATIC=1')
        if wm.poll() is not None:
            fail('dwm exited', log_path)
    finally:
        try:
            os.killpg(wm.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        wm.wait()
        log.close()

print('dwm reload (theme-apply.sh on start-up, themes.toml and SIGUSR1 only): PASS')
