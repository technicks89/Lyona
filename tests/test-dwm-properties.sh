#!/usr/bin/env bash
set -euo pipefail

# #282: dwm's own root properties are named in four places, which must agree:
# dwm.c sets them, dwm-xwatch.c watches them, dwm-quickshell-state reads them
# into its state lines, and DwmState.qml reads those lines. The reference is
# docs/SHELL-STATE-PROTOCOL.md's two tables: what dwm publishes, and what the
# shell asks of it.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

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
declare -A line_key=(
	[_DWM_MONITOR_DESKTOPS]=monitor_desktops
	[_DWM_SELECTED_MONITOR]=focused_monitor
	[_DWM_LAYOUT]=layout
	[_DWM_FULLSCREEN_MONITORS]=fullscreen_monitors
)
for name in $published; do
	key=${line_key[$name]:-}
	[[ -n $key ]] || fail "$name is published but this test does not know its state line; add it here"
	grep -Fq "printf '$key=" "$state" || fail "dwm-quickshell-state prints no $key= line for $name"
	grep -Fq "key === \"$key\"" "$qml" || fail "DwmState.qml does not read the $key line ($name)"
done

printf 'dwm root property names agree (dwm.c, dwm-xwatch, state bridge, DwmState): PASS\n'
