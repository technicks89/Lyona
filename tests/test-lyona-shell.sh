#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 16 R16-47: keybinds open the shell through lyona-shell, an
# installed command, not Quickshell's IPC from the seeded hotkeys.toml. It
# passes on only its listed TARGET ACTION pairs, to the managed shell's path.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

# quickshell: logs the call (the readiness probe, "call tray count", apart),
# and answers unless STUB_LOG.down exists. The Control Center's restart action
# brings it back, unless STUB_LOG.norestart exists. xmessage and notify-send
# log what they are told; notify-send must never be the recovery path (#338).
cat >"$work/bin/quickshell" <<'STUB'
#!/bin/sh
case $* in
*' call tray count') printf '%s\n' "$*" >>"$STUB_LOG.probe" ;;
*) printf '%s\n' "$*" >"$STUB_LOG" ;;
esac
[ ! -e "$STUB_LOG.down" ]
STUB
cat >"$work/bin/dwm-quickshell-controlcenter" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_LOG.restart"
[ -e "$STUB_LOG.norestart" ] || rm -f "$STUB_LOG.down"
STUB
cat >"$work/bin/xmessage" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_LOG.xmessage"
STUB
cat >"$work/bin/notify-send" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_LOG.notify"
exit 1
STUB
chmod +x "$work/bin/quickshell" "$work/bin/dwm-quickshell-controlcenter" "$work/bin/xmessage" "$work/bin/notify-send"
mkdir -p "$work/config/quickshell"
: >"$work/config/quickshell/shell.qml"
run() {
	env PATH="$work/bin:$PATH" XDG_CONFIG_HOME="$work/config" STUB_LOG="$work/log" LYONA_SHELL_RESTART_WAIT=1 \
		"$repo/scripts/lyona-shell" "$@"
}
# xmessage is started in the background: wait (bounded, 5s) for its log.
xmessage_log() {
	local i
	for ((i = 0; i < 50; i++)); do
		[[ -s $work/log.xmessage ]] && break
		sleep 0.1
	done
	cat "$work/log.xmessage" 2>/dev/null || :
}

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

# A running shell: no probe, no restart, nothing shown.
[[ ! -e $work/log.probe && ! -e $work/log.restart && ! -e $work/log.xmessage && ! -e $work/log.notify ]] ||
	fail 'a working call probed, restarted or notified'

# #320, #338: with no shell answering, a key that opens part of it brings the
# shell back (the Control Center's restart action), waits for it, and asks
# again, so the key does what it says. The one probe that found it down is the
# tray call.
touch "$work/log.down"
rm -f "$work/log"
run power confirm logout 2>"$work/err" || fail "a call with the shell down was not retried after the restart: $(cat "$work/err")"
[[ $(cat "$work/log") == "ipc --path $work/config/quickshell/shell.qml call power confirm logout" ]] ||
	fail "the call was not asked again after the restart: $(cat "$work/log" 2>/dev/null)"
[[ $(cat "$work/log.restart") == 'action restart-quickshell' ]] || fail "the shell was not restarted: $(cat "$work/log.restart" 2>/dev/null)"
grep -Fq 'the lyona shell is not running; starting it' "$work/err" || fail "the restart was not announced: $(cat "$work/err")"
grep -Fqx "ipc --path $work/config/quickshell/shell.qml call tray count" "$work/log.probe" || fail "the shell was not probed: $(cat "$work/log.probe")"
[[ ! -e $work/log.xmessage && ! -e $work/log.notify ]] || fail 'a shell that came back was reported as down'
rm -f "$work/log.restart" "$work/log.probe"

# A shell the running instance refuses (a bad call) is not "down": no restart.
cat >"$work/bin/quickshell" <<'STUB'
#!/bin/sh
case $* in
*' call tray count') exit 0 ;;
*) printf '%s\n' "$*" >"$STUB_LOG"; exit 1 ;;
esac
STUB
status=0
run launcher toggle 2>/dev/null || status=$?
[[ $status != 0 ]] || fail 'a refused call succeeded'
[[ ! -e $work/log.restart ]] || fail 'a refused call restarted a shell that answers'
cat >"$work/bin/quickshell" <<'STUB'
#!/bin/sh
case $* in
*' call tray count') printf '%s\n' "$*" >>"$STUB_LOG.probe" ;;
*) printf '%s\n' "$*" >"$STUB_LOG" ;;
esac
[ ! -e "$STUB_LOG.down" ]
STUB

# A shell that cannot be started: the key fails, and the user is told by a
# path that needs no shell (xmessage; the shell is the notification server, so
# notify-send would reach nothing), naming the keys to try again and, for the
# power keys, to quit the session without it.
touch "$work/log.down" "$work/log.norestart"
status=0
run power confirm logout 2>"$work/err" || status=$?
[[ $status != 0 ]] || fail 'a call no shell could answer succeeded'
[[ $(cat "$work/log.restart") == 'action restart-quickshell' ]] || fail 'no restart was tried'
[[ $(xmessage_log) == '-center -timeout 30 -buttons OK -default OK The lyona shell could not be started. Super+Shift+R tries again; Super+Ctrl+Shift+Q quits the session now.' ]] ||
	fail "the power key gave no recovery hint: $(cat "$work/log.xmessage" 2>/dev/null)"
grep -Fq 'The lyona shell could not be started. Super+Shift+R tries again; Super+Ctrl+Shift+Q quits the session now.' "$work/err" ||
	fail "the hint was not printed: $(cat "$work/err")"
[[ ! -e $work/log.notify ]] || fail 'the hint went through notify-send, which the shell serves'
rm -f "$work/log.xmessage" "$work/log.restart"
run launcher toggle 2>/dev/null || :
[[ $(xmessage_log) == '-center -timeout 30 -buttons OK -default OK The lyona shell could not be started. Super+Shift+R tries again.' ]] ||
	fail "the launcher key gave no recovery hint: $(cat "$work/log.xmessage" 2>/dev/null)"
rm -f "$work/log.xmessage" "$work/log.restart"

# The chords come from the user's hotkeys.toml: a rebound key is named right.
mkdir -p "$work/config/lyona"
cat >"$work/config/lyona/hotkeys.toml" <<'TOML'
[vars]
terminal = "alacritty"

keys = [
  { mod="SUPER ALT",        key="z", desc="Restart Quickshell", func="spawn", cmd="dwm-quickshell-controlcenter action restart-quickshell" },
  { mod="SUPER CTRL SHIFT", key="x", desc="Quit dwm now",       func="quit" },
]
TOML
run power confirm logout 2>/dev/null || :
[[ $(xmessage_log) == *'Super+Alt+Z tries again; Super+Ctrl+Shift+X quits the session now.' ]] ||
	fail "the rebound chords were not read from hotkeys.toml: $(cat "$work/log.xmessage" 2>/dev/null)"
rm -rf "$work/config/lyona" "$work/log.down" "$work/log.norestart" "$work/log.xmessage" "$work/log.restart" "$work/log.probe"

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
