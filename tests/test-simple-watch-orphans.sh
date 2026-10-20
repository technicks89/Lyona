#!/usr/bin/env bash
set -euo pipefail

# #420: a udev watcher stopped while it starts leaves nothing behind. Settings
# starts one per section and stops it on leaving, so a stop can land at any
# point of the start-up. Stopped between forking its monitor and opening the
# fifo it reads, the watcher used to leave that fork waiting to open the fifo
# for good, an orphan with the watcher's command line: about 1 start in 40. The
# display watcher is started and stopped many times at random points, then no
# process of it may be left.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

runs=${LYONA_WATCH_ORPHAN_RUNS:-300}
mkdir -p "$work/bin" "$work/runtime"
chmod 700 "$work/runtime"
# A monitor that stays up and reports nothing, as udevadm does while nothing
# changes.
cat >"$work/bin/udevadm" <<'STUB'
#!/bin/sh
exec sleep 60
STUB
chmod +x "$work/bin/udevadm"

owner_start=$(awk '{print $22}' "/proc/$$/stat")
for ((run = 0; run < runs; run++)); do
	PATH="$work/bin:$PATH" XDG_RUNTIME_DIR=$work/runtime \
		"$repo/scripts/dwm-settings-display" watch "$$" "$owner_start" >/dev/null 2>&1 &
	watcher=$!
	sleep "0.0$((RANDOM % 4))$((RANDOM % 10))"
	kill -TERM "$watcher" 2>/dev/null || true
	wait "$watcher" 2>/dev/null || true
done

# Its processes carry the owner in their command line; the monitor is the stub.
left=()
deadline=$((SECONDS + 3))
while :; do
	left=()
	for proc in /proc/[0-9]*; do
		{ args=$(tr '\0' ' ' <"$proc/cmdline"); } 2>/dev/null || continue
		case $args in
		*"dwm-settings-display watch $$ $owner_start "* | *"$work/bin/udevadm"* | "sleep 60 ")
			[[ $args != "sleep 60 " ]] || grep -qs "XDG_RUNTIME_DIR=$work/runtime" "$proc/environ" ||
				continue
			left+=("${proc#/proc/}: $args")
			;;
		esac
	done
	((${#left[@]} == 0 || SECONDS >= deadline)) && break
	sleep 0.1
done
if ((${#left[@]} > 0)); then
	printf 'test-simple-watch-orphans.sh: %d process(es) left after %d stopped watchers:\n' "${#left[@]}" "$runs" >&2
	for entry in "${left[@]}"; do
		printf '  %s (%s)\n' "$entry" "$(cat "/proc/${entry%%:*}/wchan" 2>/dev/null || printf '?')" >&2
		kill -KILL "${entry%%:*}" 2>/dev/null || true
	done
	exit 1
fi
if find "$work/runtime" -mindepth 1 -print -quit | grep -q .; then
	fail "stopped watchers left their fifo directories: $(find "$work/runtime" -mindepth 1 | head -3)"
fi

printf 'Udev watcher stopped during start-up leaves no process (%d starts): PASS\n' "$runs"
