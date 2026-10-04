#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 16 R16-47: keybinds open the shell through lyona-shell, an
# installed command, not Quickshell's IPC from the seeded hotkeys.toml. It
# passes on only its listed TARGET ACTION pairs, to the managed shell's path.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

cat >"$work/bin/quickshell" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_LOG"
STUB
chmod +x "$work/bin/quickshell"
run() { env PATH="$work/bin:$PATH" XDG_CONFIG_HOME="$work/config" STUB_LOG="$work/log" "$repo/scripts/lyona-shell" "$@"; }

for pair in 'launcher toggle' 'overview toggle' 'controlcenter open' 'controlcenter toggle' \
	'controlcenter openKeybinds' 'power toggle' 'power confirm logout' 'power confirm reboot'; do
	rm -f "$work/log"
	# shellcheck disable=SC2086 # one word per argument
	run $pair || fail "lyona-shell $pair failed"
	[[ $(cat "$work/log") == "ipc --path $work/config/quickshell/shell.qml call $pair" ]] ||
		fail "lyona-shell $pair ran: $(cat "$work/log" 2>/dev/null)"
done
for pair in '' 'launcher' 'launcher open' 'power confirm shutdown' 'power confirm' 'settingsTest status' \
	'launcher toggle extra'; do
	rm -f "$work/log"
	status=0
	# shellcheck disable=SC2086 # one word per argument
	run $pair 2>/dev/null || status=$?
	[[ $status == 2 && ! -e $work/log ]] || fail "lyona-shell accepted: '$pair' (status $status)"
done

# No default keybind calls the IPC itself, and the wrapper is installed.
if grep -n 'quickshell ipc' "$repo/config/hotkeys.toml" | grep -q .; then
	fail "hotkeys.toml still calls Quickshell IPC: $(grep -n 'quickshell ipc' "$repo/config/hotkeys.toml")"
fi
grep -Eq '^[[:space:]]+scripts/lyona-shell[[:space:]]' "$repo/Makefile" || fail 'lyona-shell is not installed'

printf 'lyona-shell: PASS\n'
