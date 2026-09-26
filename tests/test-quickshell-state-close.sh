#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper="$repo/scripts/dwm-quickshell-state"
bin="$work/bin"
mkdir -p "$bin"

fail() {
	printf 'dwm-quickshell-state close: %s\n' "$1" >&2
	[[ -n ${2:-} ]] && cat "$2" >&2
	exit 1
}

# Sync Sprint 8 S8-04 (docs/SYNC-SPRINT-8-OVERVIEW-INTERACTION.md, part of the
# cross-tag window overview, issue #350): the `close` action closing a card
# that is not the focused window, the exact gap dwm.c's own killclient()
# leaves (it only ever closes selmon->sel). No stub for xprop/dwm here --
# close_window() never queries state, only sends a request, the same shape
# switch_workspace()/focus_window() already have.
#
# PATH is set to *only* $bin below (never "$bin:$PATH"): this machine's own
# real xdotool is on the outer PATH, and "command -v xdotool" would find it
# the moment a case here deletes the local stub to exercise the wmctrl
# fallback -- which would send a real WM_DELETE_WINDOW/XDestroyWindow at
# this session's real, live X display. An isolated PATH is the only way to
# actually test "xdotool is unavailable" without that.

cat >"$bin/xdotool" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$work/xdotool.log"
[ "\$1" = "windowclose" ] && exit 0
exit 1
EOF
chmod +x "$bin/xdotool"

PATH="$bin" "$helper" close 0xdeadbeef >"$work/out" 2>"$work/err" ||
	fail 'close exited non-zero for a valid window id' "$work/err"
grep -Fqx 'windowclose 0xdeadbeef' "$work/xdotool.log" ||
	fail 'close did not call xdotool windowclose with the target id' "$work/xdotool.log"

# A decimal window id (xprop -root sometimes reports one, and DwmState.qml's
# own windowId is passed through verbatim) is accepted the same way
# focus_window() already accepts one.
: >"$work/xdotool.log"
PATH="$bin" "$helper" close 123456 >"$work/out" 2>"$work/err" ||
	fail 'close exited non-zero for a decimal window id' "$work/err"
grep -Fqx 'windowclose 123456' "$work/xdotool.log" ||
	fail 'close did not call xdotool windowclose with a decimal id' "$work/xdotool.log"

# A missing or malformed argument is a usage error, not an xdotool call.
: >"$work/xdotool.log"
PATH="$bin" "$helper" close >"$work/out" 2>"$work/err" &&
	fail 'close accepted a missing window id' "$work/out"
[[ -s "$work/xdotool.log" ]] && fail 'close called xdotool despite a missing window id' "$work/xdotool.log"

: >"$work/xdotool.log"
PATH="$bin" "$helper" close "not-a-window-id" >"$work/out" 2>"$work/err" &&
	fail 'close accepted a malformed window id' "$work/out"
[[ -s "$work/xdotool.log" ]] && fail 'close called xdotool despite a malformed window id' "$work/xdotool.log"

# Falls back to wmctrl the same way focus_window()/switch_workspace() do,
# once xdotool is genuinely unavailable -- not just missing from this test's
# own stub directory, which the isolated PATH above guarantees.
rm -f "$bin/xdotool"
cat >"$bin/wmctrl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$work/wmctrl.log"
exit 0
EOF
chmod +x "$bin/wmctrl"
PATH="$bin" "$helper" close 0xdeadbeef >"$work/out" 2>"$work/err" ||
	fail 'close exited non-zero on the wmctrl fallback' "$work/err"
grep -Fqx -- '-ic 0xdeadbeef' "$work/wmctrl.log" ||
	fail 'close did not fall back to wmctrl -ic' "$work/wmctrl.log"

# Neither xdotool nor wmctrl available: a clear error, not a silent no-op.
rm -f "$bin/wmctrl"
PATH="$bin" "$helper" close 0xdeadbeef >"$work/out" 2>"$work/err" &&
	fail 'close exited zero with neither xdotool nor wmctrl available' "$work/out"

printf 'dwm-quickshell-state close: PASS\n'
