# Step 4: staleness, measurements and the evidence

Commit: "Measure Picom and window previews on old hardware (#244)", with
`docs/evidence/244-picom-required.md` holding the numbers.

The issue's validation is blocking: if the old machine cannot meet the pass
levels, the issue is not done. Three pieces:

1. **Staleness**: does Picom keep an off-tag window's picture current? An
   automated Xvfb test, written in full below.
2. **The real-session script**, `tests/measure-picom-cost.sh`, written in full
   below: run in a real lyona session on each machine, it records idle and
   normal-use CPU and memory with Picom stopped (before) and running (after), and
   the cost of capturing every open window.
3. **Overview timing under load**, `tests/measure-overview-previews-xvfb.py`:
   time to the first frame and to every on-screen preview with 10, 60 and 200
   real windows, peak CPU and memory, and CPU back at idle after closing. It is
   built from `tests/test-overview-thumbnails-xvfb.py`, whose harness (Xvfb, dwm,
   Picom, the real helper and the real OverviewModel behind an IPC `state`
   call) it reuses; its spec is below and its code is written with this step.

Machines (decision 3):

| Machine | Who | What |
| --- | --- | --- |
| The maintainer's old or low-end machine | Maintainer | Script 2 in a real session; script 3 |
| QEMU/KVM VM with no GPU acceleration (`-vga std`, software rendering) | With this change | Script 2 in a real session (through the guest agent); script 3 |
| This development machine (Ryzen, AMD GPU, 12 threads) | With this change | Script 2 in its own session; script 3 |

## Pass levels

From the issue, proposed for the maintainer to confirm or adjust:

| Measurement | Pass on the old machine |
| --- | --- |
| Idle, overview closed, 5 minutes | Picom plus Quickshell under 1% CPU on average; no extra GPU wakeups against the baseline |
| Normal use (typing, scrolling a page, a video) | Picom adds at most about 5 percentage points of CPU, and no visible lag or tearing |
| Overview open, 60 windows | On-screen previews within about 500 ms; slower falls back to cards, never freezes the shell |
| After closing the overview | CPU back at the idle baseline within a few seconds |
| Quickshell idle CPU | No higher than the S9-04 baseline (0.0% closed, 60 cards) |

The backend question from the README: run script 2 on the old machine twice
with Picom running, once with the Automatic choice (GLX on accelerated Intel or
AMD) and once with `PICOM_BACKEND=xrender`. If GLX costs more, step 1's default
gets `backend = "xrender";`.

## 1. New: `tests/test-window-thumb-staleness-xvfb.py`

Registered in the `check-window-thumb-xvfb` target, next to
`tests/test-window-thumb-xvfb.py`, whose harness it follows.

```python
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
```

If it passes, it stays as a regression test. If Picom keeps an old picture, the
overview's recapture on every opening does not help (the capture itself is
stale): that is a finding for the evidence doc and a decision, for example
showing a small "may be out of date" mark on off-tag previews, or asking the
window to redraw first. It is not fixed in this step without that decision.

## 2. New: `tests/measure-picom-cost.sh`

Not part of `make check`: it runs in a real lyona session and changes Picom's
state while it measures (it restores it at the end). It needs nothing outside
the lyona desktop: CPU comes from `/proc`, not `pidstat`.

```bash
#!/usr/bin/env bash
set -euo pipefail

# #244: what Picom and the window previews cost on this machine. Run it in a
# real lyona X session, with the desktop as you normally use it, and nothing
# heavy running. It measures, with Picom stopped (before) and running (after):
#
#   idle     the desktop with the overview closed, nothing changing on screen
#   use      while you type, scroll a page and play a video (it asks you)
#   capture  dwm-window-thumb on every open window, as the overview would
#
# It restores Picom to how it found it. Results go to a new directory (default
# ./picom-cost-<date>), with a summary in summary.txt.
#
# Usage: tests/measure-picom-cost.sh [--seconds N] [--use-seconds N] [--out DIR] [--no-use]
#   --seconds N      length of each idle sample (default 300, the issue's 5 minutes)
#   --use-seconds N  length of each normal-use sample (default 60)
#   --no-use         skip the interactive normal-use samples
#
# PICOM_BACKEND=xrender (or glx) in the environment measures that backend
# instead of the Automatic choice.

seconds=300
use_seconds=60
use=true
out="picom-cost-$(date +%Y%m%d-%H%M%S)"
while (($#)); do
	case $1 in
	--seconds) seconds=$2; shift 2 ;;
	--use-seconds) use_seconds=$2; shift 2 ;;
	--no-use) use=false; shift ;;
	--out) out=$2; shift 2 ;;
	*) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
	esac
done
[[ -n ${DISPLAY:-} ]] || { printf 'Run this in your lyona X session (DISPLAY is not set).\n' >&2; exit 2; }
for tool in dwm-settings-picom picom quickshell; do
	command -v "$tool" >/dev/null 2>&1 || { printf '%s is not installed.\n' "$tool" >&2; exit 2; }
done
mkdir -p "$out"
summary=$out/summary.txt
: >"$summary"
say() { printf '%s\n' "$*" | tee -a "$summary"; }

clk=$(getconf CLK_TCK)
pid_of() { pgrep -x -u "$(id -u)" "$1" | head -n 1; }
xorg_pid() { pgrep -x Xorg | head -n 1 || pgrep -x Xlibre | head -n 1 || true; }
ticks() { # PID: utime + stime, or nothing if it is gone
	local fields
	[[ -r /proc/$1/stat ]] || return 0
	fields=$(sed 's/^.*) //' "/proc/$1/stat")
	awk '{ print $12 + $13 }' <<<"$fields"
}
rss_kib() { awk '/^VmRSS:/ { print $2 }' "/proc/$1/status" 2>/dev/null || printf '0\n'; }
total_ticks() { awk '/^cpu / { t = 0; for (i = 2; i <= NF; i++) t += $i; print t, $5 + $6 }' /proc/stat; }

# sample NAME SECONDS: average CPU % of Picom, Quickshell and Xorg, and of the
# whole machine, over SECONDS, and their memory at the end.
sample() {
	local name=$1 length=$2 who pid start_t end_t start_sys end_sys line
	local -A pids=() before=()
	pids[picom]=$(pid_of picom || true)
	pids[quickshell]=$(pid_of quickshell || true)
	pids[xorg]=$(xorg_pid)
	for who in "${!pids[@]}"; do
		[[ -z ${pids[$who]} ]] || before[$who]=$(ticks "${pids[$who]}")
	done
	start_sys=$(total_ticks)
	start_t=$(date +%s.%N)
	sleep "$length"
	end_t=$(date +%s.%N)
	end_sys=$(total_ticks)
	line="$name:"
	for who in picom quickshell xorg; do
		pid=${pids[$who]}
		if [[ -z $pid || -z ${before[$who]:-} || ! -r /proc/$pid/stat ]]; then
			line+=" $who=-"
			continue
		fi
		line+=$(awk -v a="${before[$who]}" -v b="$(ticks "$pid")" -v hz="$clk" -v t0="$start_t" -v t1="$end_t" \
			-v rss="$(rss_kib "$pid")" -v w="$who" \
			'BEGIN { printf " %s=%.2f%%cpu,%.1fMiB", w, (b - a) / hz / (t1 - t0) * 100, rss / 1024 }')
	done
	line+=$(awk -v s="$start_sys" -v e="$end_sys" 'BEGIN {
		split(s, a, " "); split(e, b, " ")
		printf " machine=%.2f%%busy", 100 * (1 - (b[2] - a[2]) / (b[1] - a[1]))
	}')
	say "$line"
}

picom_was_running=false
pid_of picom >/dev/null && picom_was_running=true
restore() {
	if $picom_was_running; then
		dwm-settings-picom start >/dev/null 2>&1 || :
	else
		dwm-settings-picom stop >/dev/null 2>&1 || :
	fi
}
trap restore EXIT

say "# Picom and window preview cost, $(date -u +%FT%TZ)"
say "cpu: $(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo), $(nproc) threads"
say "memory: $(awk '/^MemTotal/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo)"
say "gpu: $(lspci 2>/dev/null | grep -E 'VGA|3D|Display' | sed 's/^[^ ]* //' | paste -sd ';' -)"
say "kernel: $(uname -r); picom: $(picom --version 2>/dev/null | head -n 1)"
say "screen: $(xrandr --current 2>/dev/null | awk '/\*/ { print $1 }' | paste -sd ' ' -)"
say "windows: $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' | wc -l)"
say "PICOM_BACKEND=${PICOM_BACKEND:-} (empty: the Automatic choice)"

say ""
say "## Before: Picom stopped"
dwm-settings-picom stop >/dev/null 2>&1 || :
sleep 10
sample idle-before "$seconds"
if $use; then
	printf '\nFor the next %s s: type in a terminal, scroll a web page, and play a video. Press Enter to start.' "$use_seconds"
	read -r _
	sample use-before "$use_seconds"
fi

say ""
say "## After: Picom running"
dwm-settings-picom start >"$out/picom-start.txt" 2>&1 || { say "Picom did not start: $(cat "$out/picom-start.txt")"; exit 1; }
dwm-settings-picom status >"$out/picom-status.json" 2>/dev/null || :
say "picom: $(python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); print("policy", s.get("policy"), "renderer", s.get("renderer"), "config", s.get("path"))' "$out/picom-status.json" 2>/dev/null || printf 'status unavailable')"
say "picom command: $(pgrep -a -x -u "$(id -u)" picom | cut -d' ' -f2- | head -n 1)"
sleep 10
sample idle-after "$seconds"
if $use; then
	printf '\nAgain, %s s: type, scroll, play a video. Press Enter to start.' "$use_seconds"
	read -r _
	sample use-after "$use_seconds"
fi

say ""
say "## Capture: every open window, one at a time, as the overview does"
if command -v dwm-window-thumb >/dev/null 2>&1; then
	captured=0 failed=0 total_ms=0 worst_ms=0
	for window in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*'); do
		started=$(date +%s%N)
		if dwm-window-thumb capture "$window" >/dev/null 2>&1; then
			captured=$((captured + 1))
		else
			failed=$((failed + 1))
		fi
		ms=$((($(date +%s%N) - started) / 1000000))
		total_ms=$((total_ms + ms))
		((ms <= worst_ms)) || worst_ms=$ms
	done
	dwm-window-thumb purge >/dev/null 2>&1 || :
	say "captured=$captured failed=$failed total=${total_ms}ms worst=${worst_ms}ms"
else
	say "dwm-window-thumb is not installed; skipped"
fi

say ""
say "GPU: if one of these is installed, run it for a minute with the overview closed, Picom stopped and then running,"
say "and add what it shows: sudo intel_gpu_top, radeontop, nvidia-smi dmon."
printf '\nResults: %s\n' "$summary"
```

What it does not measure, and how:

- **Input lag and tearing:** by eye, during the `use` samples, with Picom running.
  The evidence doc records "none seen" or what was seen.
- **GPU use and wakeups:** the tools need root or are vendor-specific, so the
  script names them and the result is added by hand.

## 3. `tests/measure-overview-previews-xvfb.py` (spec)

Built on `tests/test-overview-thumbnails-xvfb.py`: same Xvfb, dwm, Picom (lyona's
default config from step 1, backend `xrender`), real `dwm-window-thumb`, and
Quickshell with the real `OverviewModel` and `WindowOverview` behind its `ov`
IPC target (`setWindows`, `open`, `state`).

- `DWM_PREVIEW_WINDOWS` (default `10,60,200`): for each count, start that many
  real `feh` windows, each a different picture, spread over the nine tags, and
  pass them to the overview with `setWindows`.
- Per count, record:
  - `first_frame_ms`: from `ov open` to `state.visible` with cards laid out;
  - `previews_ms`: from `ov open` until every on-screen card that is a real window
    reports `ready` (the existing `state` call reports it per card);
  - `peak_cpu_pct` for Quickshell, Picom and Xorg, sampled every 100 ms from
    `/proc` while the overview is open, and `peak_rss_mib`;
  - `back_to_idle_s`: after `Escape`, how long until Quickshell's CPU over a
    500 ms window is within 0.5 points of its pre-open idle.
- Prints one JSON line per count, like `tests/test-overview-load-xvfb.py`, and
  exits 0. It asserts nothing by default; `DWM_PREVIEW_STRICT=1` asserts the pass
  levels above (500 ms previews at 60 windows, back to idle within 3 s).
- Not part of `make check` (200 real windows is minutes of work); run by hand
  and listed in `docs/evidence/244-picom-required.md`.

## Old-hardware runbook (for the maintainer)

On the old machine, with lyona installed from this branch (or the files from
steps 1 and 2 copied in), logged in to a normal session:

1. Close everything heavy. Open what you usually have (a terminal, a browser
   with a page, a file manager): the capture test uses the open windows.
2. `tests/measure-picom-cost.sh` from the checkout. It takes about 12 minutes and
   asks twice for 60 seconds of typing, scrolling and a video.
3. If the machine has an accelerated Intel or AMD GPU (the summary's `policy` line
   shows `glx`), run it again as `PICOM_BACKEND=xrender tests/measure-picom-cost.sh
   --no-use --seconds 120`, to compare the backends.
4. `DWM_TEST_TMP_ROOT=~/tmp python3 tests/measure-overview-previews-xvfb.py`
   (needs `make all` in the checkout, plus Xvfb).
5. Send the `summary.txt` files and the JSON lines back, with the machine's model
   if known, and anything you saw: lag, tearing, a slow overview.

## The evidence: `docs/evidence/244-picom-required.md`

One section per machine (CPU, GPU, RAM, screen, backend chosen, Picom version),
with:

| Measurement | Before (Picom stopped) | After (Picom running) | Pass level | Result |
| --- | --- | --- | --- | --- |
| Idle 5 min: Picom + Quickshell CPU | | | < 1% (old machine) | |
| Idle: Xorg CPU | | | no rise | |
| Normal use: added Picom CPU | | | <= ~5 points | |
| Normal use: lag or tearing | | | none | |
| Capture: every open window (n, total, worst) | n/a | | | |
| Overview, 10 / 60 / 200 windows: first frame, all previews | | | 500 ms at 60 | |
| Overview: peak CPU, peak RSS | | | | |
| After close: back to idle | | | a few seconds | |
| Memory: Picom + Quickshell RSS | | | reported | |

Then the staleness result, the backend comparison, the hardware not tested, and
the outcome: pass, or the numbers that need a decision.

## Found while implementing

- `tests/measure-picom-cost.sh` is as above, formatted by `shfmt` (one `case`
  branch per line), and prints a newline after each "Press Enter", so the
  `use-` lines start on a line of their own.
- The staleness test's feh needs `--auto-zoom --zoom fill`: dwm tiles the window
  to the whole screen, and an unzoomed picture in a dark window averages to
  neither red nor blue.
- `tests/measure-overview-previews-xvfb.py` closes the overview through its IPC
  `close`: Escape reaches whichever feh window has the focus. Its `state` call
  also reports which cards are on screen, so "all on-screen previews" means the
  cards the overview actually captures.
- Results so far: `docs/evidence/244-picom-required.md`.
