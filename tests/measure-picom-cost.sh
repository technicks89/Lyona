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
	--seconds)
		seconds=$2
		shift 2
		;;
	--use-seconds)
		use_seconds=$2
		shift 2
		;;
	--no-use)
		use=false
		shift
		;;
	--out)
		out=$2
		shift 2
		;;
	*)
		printf 'Unknown option: %s\n' "$1" >&2
		exit 2
		;;
	esac
done
[[ -n ${DISPLAY:-} ]] || {
	printf 'Run this in your lyona X session (DISPLAY is not set).\n' >&2
	exit 2
}
for tool in dwm-settings-picom picom quickshell; do
	command -v "$tool" >/dev/null 2>&1 || {
		printf '%s is not installed.\n' "$tool" >&2
		exit 2
	}
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

# Whether Picom runs on this display, which the helper reports; a process
# search would also see a Picom on another display.
picom_was_running=false
if dwm-settings-picom status 2>/dev/null |
	python3 -c 'import json, sys; sys.exit(0 if json.load(sys.stdin).get("running") else 1)'; then
	picom_was_running=true
fi
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
	printf '\n'
	sample use-before "$use_seconds"
fi

say ""
say "## After: Picom running"
dwm-settings-picom start >"$out/picom-start.txt" 2>&1 || {
	say "Picom did not start: $(cat "$out/picom-start.txt")"
	exit 1
}
dwm-settings-picom status >"$out/picom-status.json" 2>/dev/null || :
say "picom: $(python3 -c 'import json, sys; s = json.load(open(sys.argv[1])); print("policy", s.get("policy"), "renderer", s.get("renderer"), "config", s.get("path"))' "$out/picom-status.json" 2>/dev/null || printf 'status unavailable')"
say "picom command: $(pgrep -a -x -u "$(id -u)" picom | cut -d' ' -f2- | head -n 1)"
sleep 10
sample idle-after "$seconds"
if $use; then
	printf '\nAgain, %s s: type, scroll, play a video. Press Enter to start.' "$use_seconds"
	read -r _
	printf '\n'
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
