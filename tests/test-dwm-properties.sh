#!/usr/bin/env bash
set -euo pipefail

# #282: dwm's own root properties are named in four places, which must agree:
# dwm.c sets them, dwm-xwatch.c watches them, dwm-quickshell-state reads them
# into its state lines, and DwmState.qml reads those lines. The reference is
# docs/SHELL-STATE-PROTOCOL.md's two tables: what dwm publishes, and what the
# shell asks of it.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

doc=$repo/docs/SHELL-STATE-PROTOCOL.md
dwm_c=$repo/dwm.c
xwatch_c=$repo/dwm-xwatch.c
state=$repo/scripts/dwm-quickshell-state
qml=$repo/config/quickshell/state/DwmState.qml

names() { grep -oE '_DWM_[A-Z_]+' "$@" | sort -u; }
# The _DWM_ names in the table that follows HEADING in the protocol document.
table() {
	awk -v heading="$1" '
		index($0, heading) == 1 { inside = 1; next }
		inside && /^#/ { exit }
		inside && /^\| `_DWM_/ { match($0, /_DWM_[A-Z_]+/); print substr($0, RSTART, RLENGTH) }
	' "$doc" | sort -u
}

published=$(table '## X root-window properties')
requests=$(table '### Requests from the shell')
[[ -n $published && -n $requests ]] || fail 'the protocol document lists no _DWM_ properties'
documented=$(printf '%s\n%s\n' "$published" "$requests" | sort -u)

same() { # WHAT EXPECTED ACTUAL
	[[ $2 == "$3" ]] || fail "$1 does not match the protocol document:"$'\n'"expected:"$'\n'"$2"$'\n'"found:"$'\n'"$3"
}
same 'the names dwm.c uses' "$documented" "$(names "$dwm_c")"
same 'the names dwm-xwatch watches' "$published" "$(names "$xwatch_c")"
same 'the names dwm-quickshell-state uses' "$documented" "$(names "$state")"

# dwm-quickshell-state reads every published name in its root snapshot, follows
# each in the fallback's root spy, and sets only the requests.
snapshot=$(grep -E '< <\(xprop -root _NET_CURRENT_DESKTOP' "$state")
spy=$(awk '/bound_to_this_shell xprop -root -spy/ { inside = 1 } inside { print } inside && />&3/ { exit }' "$state")
for name in $published; do
	[[ $snapshot == *"$name"* ]] || fail "the state snapshot does not read $name"
	[[ $spy == *"$name"* ]] || fail "the fallback root spy does not follow $name"
done
same 'the properties dwm-quickshell-state sets' "$requests" \
	"$(grep -oE -- '-set _DWM_[A-Z_]+' "$state" | sed 's/^-set //' | sort -u)"

# Each published property becomes one state line, which DwmState.qml reads.
# Each gets its own value from a stub xprop, which must come out on that
# property's line: two swapped mappings would put each value on the other's.
# NAME: the xprop line dwm would give, and the state line it must become.
declare -A root_line=(
	[_DWM_MONITOR_DESKTOPS]='_DWM_MONITOR_DESKTOPS(INTEGER) = 0, 0, 1280, 800, 4'
	[_DWM_SELECTED_MONITOR]='_DWM_SELECTED_MONITOR(CARDINAL) = 3'
	[_DWM_LAYOUT]='_DWM_LAYOUT(CARDINAL) = 2'
	[_DWM_FULLSCREEN_MONITORS]='_DWM_FULLSCREEN_MONITORS(CARDINAL) = 5'
)
declare -A state_line=(
	[_DWM_MONITOR_DESKTOPS]='monitor_desktops=0,0,1280,800,4'
	[_DWM_SELECTED_MONITOR]='focused_monitor=3'
	[_DWM_LAYOUT]='layout=2'
	[_DWM_FULLSCREEN_MONITORS]='fullscreen_monitors=5'
)
mkdir -p "$work/bin"
{
	# shellcheck disable=SC2016 # the stub's own $1
	printf '#!/bin/sh\n[ "$1" = -root ] || exit 0\ncat <<'"'"'ROOT'"'"'\n'
	printf '%s\n' '_NET_CURRENT_DESKTOP(CARDINAL) = 0' '_NET_NUMBER_OF_DESKTOPS(CARDINAL) = 9' \
		'_NET_CLIENT_LIST(WINDOW): window id #' '_NET_ACTIVE_WINDOW(WINDOW): window id # 0x0'
	for name in $published; do
		[[ -n ${root_line[$name]:-} ]] || fail "$name is published but this test gives it no value; add it here"
		printf '%s\n' "${root_line[$name]}"
	done
	printf 'ROOT\n'
} >"$work/bin/xprop"
chmod +x "$work/bin/xprop"
PATH="$work/bin:$PATH" "$state" state >"$work/state.out" 2>"$work/state.err" ||
	fail "the state bridge failed on the stub properties: $(cat "$work/state.err")"
for name in $published; do
	expected=${state_line[$name]}
	grep -Fqx "$expected" "$work/state.out" ||
		fail "$name did not become '$expected':"$'\n'"$(cat "$work/state.out")"
	key=${expected%%=*}
	grep -Fq "key === \"$key\"" "$qml" || fail "DwmState.qml does not read the $key line ($name)"
done

printf 'dwm root property names agree (dwm.c, dwm-xwatch, state bridge, DwmState): PASS\n'
