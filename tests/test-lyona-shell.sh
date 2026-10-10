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
[ ! -e "$STUB_LOG.down" ]
STUB
cat >"$work/bin/notify-send" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_LOG.notify"
STUB
chmod +x "$work/bin/quickshell" "$work/bin/notify-send"
mkdir -p "$work/config/quickshell"
: >"$work/config/quickshell/shell.qml"
run() { env PATH="$work/bin:$PATH" XDG_CONFIG_HOME="$work/config" STUB_LOG="$work/log" "$repo/scripts/lyona-shell" "$@"; }

for pair in 'launcher toggle' 'overview toggle' 'controlcenter open' 'controlcenter toggle' \
	'controlcenter openKeybinds' 'power toggle' 'power confirm logout' 'power confirm reboot' \
	'settings open' 'settings close' 'settings toggle' 'settings refresh' 'settings status'; do
	rm -f "$work/log"
	# shellcheck disable=SC2086 # one word per argument
	run $pair || fail "lyona-shell $pair failed"
	[[ $(cat "$work/log") == "ipc --path $work/config/quickshell/shell.qml call $pair" ]] ||
		fail "lyona-shell $pair ran: $(cat "$work/log" 2>/dev/null)"
done
for pair in '' 'launcher' 'launcher open' 'power confirm shutdown' 'power confirm' 'settingsTest status' \
	'launcher toggle extra' 'settings quit'; do
	rm -f "$work/log"
	status=0
	# shellcheck disable=SC2086 # one word per argument
	run $pair 2>/dev/null || status=$?
	[[ $status == 2 && ! -e $work/log ]] || fail "lyona-shell accepted: '$pair' (status $status)"
done

# #320: with no shell answering, a key that opens part of it says how to get it
# back (and the power keys how to quit without it), and fails, instead of
# doing nothing at all. A running shell gives no notification.
[[ ! -e $work/log.notify ]] || fail "a working call notified: $(cat "$work/log.notify")"
touch "$work/log.down"
status=0
run power confirm logout 2>/dev/null || status=$?
[[ $status != 0 ]] || fail 'a call no shell answered succeeded'
[[ $(cat "$work/log.notify" 2>/dev/null) == '-u critical The lyona shell is not running Super+Shift+R restarts it; Super+Ctrl+Shift+Q quits the session now.' ]] ||
	fail "the power key gave no recovery hint: $(cat "$work/log.notify" 2>/dev/null)"
rm -f "$work/log.notify"
run launcher toggle 2>/dev/null || :
[[ $(cat "$work/log.notify" 2>/dev/null) == '-u critical The lyona shell is not running Super+Shift+R restarts it.' ]] ||
	fail "the launcher key gave no recovery hint: $(cat "$work/log.notify" 2>/dev/null)"
rm -f "$work/log.down" "$work/log.notify"

# Without the managed shell's config, it says so and runs nothing.
rm -f "$work/config/quickshell/shell.qml" "$work/log"
status=0
run launcher toggle 2>"$work/err" || status=$?
[[ $status == 1 && ! -e $work/log ]] || fail "a missing config ran the IPC (status $status)"
grep -Fq 'managed Quickshell configuration not found' "$work/err" || fail "no missing-config message: $(cat "$work/err")"

# The old wrappers go through lyona-shell, not the IPC directly.
for wrapper in dwm-controlcenter dwm-keybinds dwm-settings; do
	grep -q 'quickshell ipc' "$repo/scripts/$wrapper" && fail "$wrapper still calls the Quickshell IPC itself"
	# shellcheck disable=SC2016 # the literal text of the wrapper
	grep -Fq 'exec "$shell"' "$repo/scripts/$wrapper" || fail "$wrapper does not go through lyona-shell"
done

# No default keybind calls the IPC itself, and the wrapper is installed.
if grep -n 'quickshell ipc' "$repo/config/hotkeys.toml" | grep -q .; then
	fail "hotkeys.toml still calls Quickshell IPC: $(grep -n 'quickshell ipc' "$repo/config/hotkeys.toml")"
fi
grep -Eq '^[[:space:]]+scripts/lyona-shell[[:space:]]' "$repo/Makefile" || fail 'lyona-shell is not installed'

printf 'lyona-shell: PASS\n'
