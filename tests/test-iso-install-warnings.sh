#!/usr/bin/env bash
set -euo pipefail

# The image install's closing screen says what did not go as chosen.
# - Sync Sprint 16 R16-22:
#   - every fallback the postinstall takes is recorded: CachyOS, the kernels,
#     an NVIDIA driver chosen but not installed, Topgrade;
#   - install.sh's own [WARN] lines are recorded, taken only from what it adds
#     to the log;
#   - with anything recorded, the closing screen waits for Enter rather than
#     rebooting on a timer.
# - R16-29: the progress bar's step count is the number of steps.
# - R16-30: cancelling the wizard says how to start it again.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
wizard=$repo/archiso/airootfs/root/lyona-install.sh

# note_warning: in the log as before, and in the list.
sed -n '/^note_warning() {$/,/^}$/p' "$postinstall" >"$work/note.sh"
[[ -s $work/note.sh ]] || fail 'note_warning not found in the postinstall'
# shellcheck disable=SC1091 # generated above
. "$work/note.sh"
export LYONA_WARNINGS=$work/warnings
out=$(note_warning 'The CachyOS kernels could not be installed.')
[[ $out == 'lyona-postinstall: The CachyOS kernels could not be installed.' ]] || fail "note_warning printed: $out"
[[ $(cat "$LYONA_WARNINGS") == 'The CachyOS kernels could not be installed.' ]] || fail 'note_warning kept nothing'

# Each fallback is recorded, not only printed.
for message in 'CachyOS repository setup failed' 'The CachyOS kernel could not be installed' \
	'No packaged NVIDIA driver supports GPU' 'could not be built; the open-source nouveau driver' \
	'No pinned AUR source for the NVIDIA' 'Topgrade was not installed'; do
	grep -F "$message" "$postinstall" | grep -q 'note_warning' || fail "not recorded for the closing screen: $message"
done
# Steps run in fresh shells: note_warning must reach them.
grep -Eq '^export -f note_warning ' "$postinstall" || fail 'note_warning is not exported to the steps'
# A Retry starts again from an empty list.
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -Fxq ': >"$LYONA_WARNINGS"' "$postinstall" || fail 'the list is not emptied at the start of a run'

# install.sh's warnings: only the lines it added to the log, colours removed.
extract=$(awk '/^tail -n "\+\$\(\(log_mark \+ 1\)\)"/ { f = 1 } f { print } f && /\|\| :$/ { exit }' "$postinstall")
[[ -n $extract ]] || fail 'the install.sh warning extraction was not found'
LOG_FILE=$work/log
printf '[WARN] an earlier warning, before install.sh\n' >"$LOG_FILE"
# shellcheck disable=SC2034 # read by the extracted lines
log_mark=$(wc -l <"$LOG_FILE")
printf '\033[1;33m[WARN]\033[0m Picom is not installed.\nnot a warning\n[WARN] Failed to download wallpapers.\n' >>"$LOG_FILE"
: >"$LYONA_WARNINGS"
eval "$extract"
[[ $(cat "$LYONA_WARNINGS") == $'install.sh: Picom is not installed.\ninstall.sh: Failed to download wallpapers.' ]] ||
	fail "install.sh's warnings were read as: $(cat "$LYONA_WARNINGS")"

# The closing screen waits when there is anything to read.
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -Fq 'read -r -p "Press Enter to reboot. "' "$postinstall" || fail 'the closing screen does not wait for Enter'

# R16-29: one step per run_logged call.
steps=$(grep -cE '^(if ! )?run_logged ' "$postinstall")
declared=$(sed -n 's/^set_total_steps \([0-9]*\)$/\1/p' "$postinstall")
[[ $steps == "$declared" ]] || fail "the progress bar counts $declared steps, but there are $steps"

# R16-30: every cancel goes through cancelled, which names the command.
if grep -n 'fail "aborted' "$wizard" | grep -q .; then
	fail "a cancel without the hint: $(grep -n 'fail "aborted' "$wizard")"
fi
sed -n '/^err() /p; /^cancelled() {$/,/^}$/p' "$wizard" >"$work/cancel.sh"
# shellcheck disable=SC1091 # generated above
out=$( (. "$work/cancel.sh" && cancelled 'no internet connection') 2>&1) && fail 'cancelled did not exit non-zero'
[[ $out == 'lyona-install: cancelled -- no internet connection. Nothing on the disk was changed; run lyona-install to start again.' ]] ||
	fail "cancelling says: $out"

# R16-54: the new user's checkout is a source directory, never lyona's data
# directory (~/.local/share/lyona), which updates back up.
grep -Fqx 'checkout_rel=.local/src/lyona' "$postinstall" || fail 'the checkout is not under ~/.local/src'
if grep -n 'local/share/lyona' "$postinstall" | grep -v '^[0-9]*:#' | grep -q .; then
	fail "the postinstall still uses ~/.local/share/lyona: $(grep -n 'local/share/lyona' "$postinstall")"
fi

# R16-19 (decision D-30): the timezone is detected from several providers, the
# first valid zone wins, and only a zone this system knows is offered.
sed -n '/^detect_timezone() {$/,/^}$/p' "$wizard" >"$work/tz.sh"
[[ -s $work/tz.sh ]] || fail 'detect_timezone is missing'
# curl URL: STUB_TZ_<host> holds the reply, or the call fails.
cat >"$work/bin/curl" <<'EOF'
#!/bin/bash
url=${*: -1}
host=${url#https://}
host=${host%%/*}
var=STUB_TZ_${host//./_}
[[ -n ${!var:-} ]] || exit 22
printf '%s' "${!var}"
EOF
chmod +x "$work/bin/curl"
# shellcheck disable=SC1091 # extracted above
tz() { (PATH="$work/bin:$PATH" && . "$work/tz.sh" && detect_timezone); }
[[ $(STUB_TZ_ipinfo_io=$'Europe/Berlin\n' tz) == Europe/Berlin ]] || fail 'the first provider was not used'
[[ $(STUB_TZ_ipapi_co=America/New_York tz) == America/New_York ]] || fail 'the second provider was not tried'
[[ $(STUB_TZ_ipinfo_io=Mars/Olympus STUB_TZ_ipapi_co=Asia/Tokyo tz) == Asia/Tokyo ]] ||
	fail 'an unknown zone was offered'
[[ $(STUB_TZ_ipinfo_io=../../etc/passwd tz) == '' ]] || fail 'a path was offered as a zone'
if tz >/dev/null; then fail 'detection succeeded with every provider failing'; fi
# The answer is a yes or no; tzselect's menus are gone.
grep -Fq 'gum confirm --affirmative "Yes" --negative "No" "Detected timezone:' "$wizard" ||
	fail 'the detected timezone is not a yes/no question'
if grep -n 'tzselect' "$wizard" | grep -v '^[0-9]*:#' | grep -q .; then fail 'tzselect is still used'; fi

# The CachyOS step, which trusts the CachyOS key on the new system, comes before
# the first sync: the new system already lists those repositories (Sync Sprint
# 16, found in a VM).
cachyos_line=$(grep -n '^run_logged "Adding the CachyOS repositories' "$postinstall" | cut -d: -f1)
update_line=$(grep -n '^run_logged "Updating the new system' "$postinstall" | cut -d: -f1)
if [[ -z $cachyos_line || -z $update_line ]] || ((cachyos_line > update_line)); then
	fail 'the new system is synced before the CachyOS key is trusted'
fi

printf 'ISO install warnings, step count, cancel hint, checkout path and timezone: PASS\n'
