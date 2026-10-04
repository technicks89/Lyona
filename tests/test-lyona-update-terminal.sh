#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 15 S15-03 and S15-04 (decision D-26): scripts/lyona-update-terminal
# against a stub terminal and stub yay, sudo, pacman and flatpak.
#
# - Packages use yay -Syu when yay is installed, otherwise sudo pacman -Syu,
#   and nothing is ever confirmed for the user.
# - Flatpak updates each installation on its own; one failing is "not updated"
#   and the other still runs.
# - The result comes from the command: a failure (a declined plan included) is
#   not-updated, a terminal closed mid-update is interrupted, and a terminal
#   that never ran it is not-started.
# - The window class follows the float setting.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

export XDG_CONFIG_HOME=$work/config
export STUB_DIR=$work
export TMPDIR=$work/tmp
mkdir -p "$TMPDIR"
stage_helpers checkout "$work/scripts" lyona-update-terminal lyona-update-indicator dwm-terminal
helper=$work/scripts/lyona-update-terminal

# The terminal: logs its arguments, then runs the command after -e (or, for
# kitty, after its options). STUB_TERMINAL=close sends the command SIGHUP while
# it runs, as closing the window does; STUB_TERMINAL=broken runs nothing.
cat >"$work/bin/alacritty" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_DIR/terminal.log"
[[ ${STUB_TERMINAL:-} != broken ]] || exit 1
# Hands the command to the background and returns at once, as gnome-terminal
# and wezterm do (Sync Sprint 16 R16-06).
if [[ ${STUB_TERMINAL:-} == detach ]]; then
	while (($# > 0)) && [[ $1 != -e ]]; do shift; done
	shift
	(sleep 1 && "$@" </dev/null >/dev/null 2>&1) &
	exit 0
fi
while (($# > 0)) && [[ $1 != -e ]]; do shift; done
shift
if [[ ${STUB_TERMINAL:-} == close ]]; then
	"$@" </dev/null &
	command_pid=$!
	until [[ -e $STUB_DIR/running ]]; do sleep 0.05; done
	kill -HUP "$command_pid"
	wait "$command_pid" || :
	exit 0
fi
"$@" </dev/null
EOF
chmod +x "$work/bin/alacritty"
# Each tool logs its arguments and exits with STUB_STATUS (default 0).
for tool in yay sudo pacman; do
	cat >"$work/bin/$tool" <<EOF
#!/bin/sh
printf '$tool %s\n' "\$*" >>"\$STUB_DIR/tools.log"
if [ "\${STUB_TERMINAL:-}" = close ]; then : >"\$STUB_DIR/running"; sleep 30; fi
exit "\${STUB_STATUS:-0}"
EOF
	chmod +x "$work/bin/$tool"
done
cat >"$work/bin/flatpak" <<'EOF'
#!/bin/sh
printf 'flatpak %s\n' "$*" >>"$STUB_DIR/tools.log"
case $2 in
--system) exit "${FLATPAK_SYSTEM_STATUS:-0}" ;;
--user) exit "${FLATPAK_USER_STATUS:-0}" ;;
esac
exit 9
EOF
chmod +x "$work/bin/flatpak"

reset() { rm -f "$work/terminal.log" "$work/tools.log" "$work/running"; }
launch() { PATH="$work/bin:$base_path" DWM_TERMINAL=alacritty "$helper" launch "$@"; }
result_line() { printf '%s\n' "$1" | sed -n 2p; }
# A PATH with the system tools but none of the stubbed ones.
mkdir -p "$work/base"
for cmd in bash sh awk sed grep mktemp rm cat sleep kill mkdir chmod mv dirname tr cut head flock; do
	ln -sf "$(command -v "$cmd")" "$work/base/$cmd"
done
base_path=$work/base

# yay installed: it updates everything, AUR packages included.
reset
out=$(launch system)
[[ $out == $'update-terminal-protocol\t1\t0\nresult\tsystem\tsucceeded\t0\tUpdated\ncomplete\tlaunch' ]] ||
	fail "yay update: $out"
[[ $(cat "$work/tools.log") == 'yay -Syu' ]] || fail "yay was run as: $(cat "$work/tools.log")"
grep -Fq -- '--class lyona-update,lyona-update --title lyona update -e' "$work/terminal.log" ||
	fail "the terminal was started as: $(cat "$work/terminal.log")"

# No yay: sudo pacman -Syu.
reset
rm "$work/bin/yay"
out=$(launch system)
[[ $(result_line "$out") == $'result\tsystem\tsucceeded\t0\tUpdated' ]] || fail "pacman update: $out"
[[ $(cat "$work/tools.log") == 'sudo pacman -Syu' ]] || fail "pacman was run as: $(cat "$work/tools.log")"

# A failure, or a declined plan, is "not updated" with the status.
reset
out=$(STUB_STATUS=1 launch system)
[[ $(result_line "$out") == $'result\tsystem\tnot-updated\t1\tNot updated: the command exited with status 1' ]] ||
	fail "a declined plan: $out"

# The terminal closed mid-update: interrupted, never succeeded.
reset
out=$(STUB_TERMINAL=close launch system)
[[ $(result_line "$out") == $'result\tsystem\tinterrupted\t-1\tThe terminal closed before the update finished' ]] ||
	fail "an early close: $out"

# A terminal that returns at once, before the update even starts: the result is
# still the update's, after it ends.
reset
out=$(STUB_TERMINAL=detach launch system)
[[ $(result_line "$out") == $'result\tsystem\tsucceeded\t0\tUpdated' ]] ||
	fail "a terminal that returns at once: $out"
reset
out=$(STUB_TERMINAL=detach STUB_STATUS=1 launch system)
[[ $(result_line "$out") == $'result\tsystem\tnot-updated\t1\tNot updated: the command exited with status 1' ]] ||
	fail "a failed update in a terminal that returns at once: $out"

# A terminal that never ran the update.
reset
out=$(STUB_TERMINAL=broken launch system)
[[ $(result_line "$out") == $'result\tsystem\tnot-started\t-1\tThe terminal did not start the update' ]] ||
	fail "a broken terminal: $out"

# No terminal at all.
reset
out=$(PATH="$work/base" DWM_TERMINAL=none "$helper" launch system)
[[ $(result_line "$out") == $'result\tsystem\tnot-started\t-1\tNo supported terminal is installed' ]] ||
	fail "no terminal: $out"

# Nothing ever confirms for the user.
if grep -Eq -- '--noconfirm|(^| )-y( |$)|--assumeyes|--yes' "$work/tools.log" 2>/dev/null; then
	fail "an update was confirmed for the user: $(cat "$work/tools.log")"
fi

# Flatpak: each installation on its own; the user one still runs when the
# system one fails.
reset
out=$(launch flatpak)
[[ $(result_line "$out") == $'result\tflatpak\tsucceeded\t0\tUpdated' ]] || fail "flatpak update: $out"
[[ $(cat "$work/tools.log") == $'flatpak update --system\nflatpak update --user' ]] ||
	fail "flatpak was run as: $(cat "$work/tools.log")"
reset
out=$(FLATPAK_SYSTEM_STATUS=1 launch flatpak)
[[ $(result_line "$out") == $'result\tflatpak\tnot-updated\t1\tNot updated: the command exited with status 1' ]] ||
	fail "a failed system installation: $out"
grep -Fqx 'flatpak update --user' "$work/tools.log" || fail 'the user installation was skipped after a failure'

# Floating: the class the shipped rule floats.
reset
PATH="$work/bin:$base_path" "$work/scripts/lyona-update-indicator" set-float-terminal yes >/dev/null
launch system >/dev/null
grep -Fq -- '--class lyona-update-float,lyona-update-float' "$work/terminal.log" ||
	fail "a floating terminal was started as: $(cat "$work/terminal.log")"

# Usage, and no leftover result files.
if "$helper" launch pacman >/dev/null 2>&1; then fail 'launch accepted an unknown provider'; fi
if "$helper" run system "$work/no-such-file" >/dev/null 2>&1; then fail 'run accepted a missing result file'; fi
[[ -z $(ls -A "$TMPDIR") ]] || fail "result files were left: $(ls -A "$TMPDIR")"

# Sync Sprint 16 R16-31: each update helper's --help says what every command
# does, on stdout; a wrong call shows it on stderr and fails.
for helper in lyona-update-terminal lyona-update-indicator lyona-update; do
	help=$("$repo/scripts/$helper" --help) || fail "$helper --help failed"
	case $helper in
	lyona-update-terminal) words=('launch system' 'launch flatpak' 'AUR' 'pacman through sudo') ;;
	lyona-update-indicator) words=('set-interval' 'How often, in hours' 'set-float-terminal') ;;
	lyona-update) words=('Updates lyona itself' 'rollback     Restores a backup' 'set-channel  stable') ;;
	esac
	for word in "${words[@]}"; do
		[[ $help == *"$word"* ]] || fail "$helper --help does not describe: $word"
	done
done
for helper in lyona-update-terminal lyona-update-indicator; do
	status=0
	"$repo/scripts/$helper" bogus >/dev/null 2>"$work/usage.err" || status=$?
	[[ $status == 2 && -s $work/usage.err ]] || fail "$helper with a wrong command: status $status"
done

printf 'lyona-update-terminal: PASS\n'
