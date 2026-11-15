#!/usr/bin/env bash
set -euo pipefail

# scripts/dwm-clipboard-history (#469): capture and saving are separate
# opt-ins, both off by default; the history file is private and exists only
# while saving is on; symlinks are refused; observe runs only with capture on.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper=$repo/scripts/dwm-clipboard-history
config=$work/config
state=$work/state
settings=$config/lyona/clipboard-history.conf
history=$state/lyona/clipboard-history.json
run() {
	env HOME="$work/home" XDG_CONFIG_HOME="$config" XDG_STATE_HOME="$state" DISPLAY= "$helper" "$@"
}
expect_fail() { # MESSAGE ARGS...
	local message=$1
	shift
	if run "$@" </dev/null >"$work/out" 2>"$work/err"; then
		fail "accepted: $*"
	fi
	grep -Fq -- "$message" "$work/err" || fail "for $*: expected '$message', got: $(cat "$work/err")"
}
status_of() { run status | awk -F '\t' -v key="$1" '$1 == key { print $2 }'; }
mkdir -p "$work/home"

# Off by default, with nothing written.
run status >"$work/status"
diff -u - "$work/status" <<'EOF'
clipboard-history-protocol	1
state	available	Clipboard history settings
capture	off
persist	off
complete	status
EOF
[[ ! -e $settings && ! -e $history ]] || fail 'status wrote something'
[[ -z $(run load) ]] || fail 'load printed history with saving off'
expect_fail 'saving to disk needs capture on' set persist on
expect_fail 'capture is off' observe
expect_fail 'saving to disk is off' save

# Capture on; saving is still off and nothing is saved.
[[ $(run set capture on) == $'clipboard-history-result\tset\tcapture\ton' ]] || fail 'set capture on'
[[ $(status_of capture) == on && $(status_of persist) == off ]] || fail "after capture on: $(run status)"
[[ $(stat -c %a "$settings") == 600 ]] || fail "the settings file is mode $(stat -c %a "$settings")"

# Saving on: the history from stdin, private, and read back as it was.
run set persist on >/dev/null
printf '{"version":1,"entries":[{"text":"hello","timestamp":1}]}' | run save
[[ $(stat -c %a "$history") == 600 ]] || fail "the history file is mode $(stat -c %a "$history")"
[[ $(stat -c %a "${history%/*}") == 700 ]] || fail "its directory is mode $(stat -c %a "${history%/*}")"
[[ $(run load) == '{"version":1,"entries":[{"text":"hello","timestamp":1}]}' ]] || fail "load: $(run load)"
# No temporary file is left beside it.
[[ $(find "${history%/*}" -mindepth 1 | wc -l) == 1 ]] || fail "files left: $(ls -a "${history%/*}")"
# Too large: refused, and the saved history stays as it was.
head -c $((4 * 1024 * 1024 + 1)) /dev/zero | tr '\0' 'x' >"$work/big"
if run save <"$work/big" 2>"$work/err"; then fail 'an oversized history was saved'; fi
grep -Fq 'larger than' "$work/err" || fail "the reason: $(cat "$work/err")"
[[ $(run load) == '{"version":1,"entries":[{"text":"hello","timestamp":1}]}' ]] || fail 'an oversized save replaced the history'

# Saving off removes the file; capture off turns saving off too.
run set persist off >/dev/null
[[ ! -e $history ]] || fail 'saving off left the history file'
run set persist on >/dev/null
printf '{"version":1,"entries":[]}' | run save
run set capture off >/dev/null
[[ $(status_of capture) == off && $(status_of persist) == off ]] || fail "after capture off: $(run status)"
[[ ! -e $history ]] || fail 'capture off left the history file'
# clear removes it too.
run set capture on >/dev/null
run set persist on >/dev/null
printf '{"version":1,"entries":[]}' | run save
[[ $(run clear) == $'clipboard-history-result\tclear' && ! -e $history ]] || fail 'clear left the history file'

# Anything but the two lines reads as off; saving needs capture there too.
printf 'persist=on\ncapture=yes\n' >"$settings"
[[ $(status_of capture) == off && $(status_of persist) == off ]] || fail "odd settings did not read as off: $(run status)"

# Symlinks are refused, never written through.
run set capture on >/dev/null
run set persist on >/dev/null
rm -f "$history"
ln -s "$work/elsewhere.json" "$history"
if printf '{}' | run save 2>"$work/err"; then fail 'a symlinked history file was written'; fi
[[ ! -e $work/elsewhere.json ]] || fail 'the save went through the symlink'
expect_fail 'not a regular file' load
rm -f "$history"
mv "$settings" "$work/real.conf"
ln -s "$work/real.conf" "$settings"
[[ $(status_of state) == unavailable ]] || fail "a symlinked settings file read as available: $(run status)"
expect_fail 'not a regular file' set capture off
rm -f "$settings"
mv "$work/real.conf" "$settings"

# A symlinked settings directory: nothing in it is believed, so capture reads
# as off and the source does not start.
run set capture on >/dev/null
mv "$config/lyona" "$work/real-lyona"
ln -s "$work/real-lyona" "$config/lyona"
[[ $(status_of capture) == off && $(status_of state) == unavailable ]] || fail "settings through a symlinked directory: $(run status)"
expect_fail 'capture is off' observe
rm "$config/lyona"
mv "$work/real-lyona" "$config/lyona"

# A symlinked history directory: load and clear refuse it, and create nothing.
run set persist on >/dev/null
mkdir -p "$work/elsewhere-state"
printf 'secret history' >"$work/elsewhere-state/clipboard-history.json"
rm -rf "$state/lyona"
ln -s "$work/elsewhere-state" "$state/lyona"
expect_fail 'refusing a symlinked path' load
expect_fail 'refusing a symlinked path' clear
[[ -f $work/elsewhere-state/clipboard-history.json ]] || fail 'clear removed a file through a symlinked directory'
rm "$state/lyona"
run load >/dev/null
[[ ! -e $state/lyona ]] || fail 'load created the history directory'

# A save still reading when the history is cleared, or saving turned off, puts
# nothing back.
run set capture on >/dev/null
run set persist on >/dev/null
printf '{"version":1,"entries":[]}' | run save
for change in 'clear' 'set persist off'; do
	run set persist on >/dev/null
	rm -f "$work/save-in"
	mkfifo "$work/save-in"
	status=0
	run save <"$work/save-in" 2>"$work/save.err" &
	save_pid=$!
	exec 7>"$work/save-in"
	sleep 0.3
	# shellcheck disable=SC2086 # one word per argument
	run $change >/dev/null
	printf '{"version":1,"entries":[{"text":"restored after %s","timestamp":1}]}' "$change" >&7
	exec 7>&-
	wait "$save_pid" || status=$?
	[[ $status != 0 ]] || fail "a save begun before '$change' succeeded"
	[[ ! -e $history ]] || fail "a save begun before '$change' put the history back: $(cat "$history")"
done

# Bad input.
expect_fail 'the value must be on or off' set capture maybe
expect_fail 'set takes capture|persist on|off' set volume on
expect_fail 'status takes no arguments' status extra

# observe runs dwm-clipboard-observer, built at the checkout's root; without a
# display it says history is unavailable.
if [[ -x $repo/dwm-clipboard-observer ]]; then
	run set capture on >/dev/null
	if run observe >"$work/out" 2>"$work/err"; then fail 'the observer ran without a display'; fi
	grep -Fq 'Clipboard history unavailable' "$work/err" || fail "observe: $(cat "$work/err")"
fi

printf 'dwm-clipboard-history: PASS\n'
