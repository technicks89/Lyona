#!/usr/bin/env bash
set -euo pipefail

# Both install paths say how long each step took (#250):
# - the image installer's run_logged logs each step's start and duration, and
#   the postinstall ends its log with one table for the wizard's steps and its
#   own;
# - install.sh says how long each section took and ends with the same table.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

ui=$repo/archiso/airootfs/root/lyona-ui.sh
postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
wizard=$repo/archiso/airootfs/root/lyona-install.sh

# A gum whose spin just runs the command after --.
mkdir -p "$work/bin"
cat >"$work/bin/gum" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == spin ]] || exit 0
while (($# > 0)) && [[ $1 != -- ]]; do shift; done
shift
exec "$@"
EOF
chmod +x "$work/bin/gum"

export PATH="$work/bin:$PATH" LOG_FILE=$work/log LYONA_STEP_TIMES_DIR=$work/times
: >"$LOG_FILE"

# run_as SCRIPT CODE: CODE with lyona-ui.sh loaded, run as the scripts are,
# so that $0 names the times file.
run_as() {
	# shellcheck disable=SC2016 # expanded by the inner shell
	bash -c '. "$1"; eval "$2"' "$1" "$ui" "$2"
}

# The wizard's one step, then two postinstall steps, one of them failing.
run_as lyona-install.sh 'reset_step_times; run_logged "Running archinstall..." true' ||
	fail 'a successful step failed'
status=0
run_as lyona-postinstall.sh '
	reset_step_times
	set_total_steps 2
	run_logged "Updating the new system..." true
	run_logged "Installing GPU drivers..." bash -c "exit 3"' || status=$?
[[ $status == 3 ]] || fail "a failed step returned $status, not its own exit status"

grep -Eq '^\[[0-9:]{8}\] Running archinstall\.\.\. done in [0-9]+s$' "$LOG_FILE" ||
	fail "the wizard's step has no duration in the log: $(cat "$LOG_FILE")"
grep -Eq '^\[[0-9:]{8}\] \[step 1/2\] Updating the new system\.\.\.$' "$LOG_FILE" ||
	fail 'a step does not log its start'
grep -Eq '^\[[0-9:]{8}\] \[step 1/2\] Updating the new system\.\.\. done in [0-9]+s$' "$LOG_FILE" ||
	fail 'a step does not log its duration'
grep -Eq '^\[[0-9:]{8}\] \[step 2/2\] Installing GPU drivers\.\.\. failed \(exit 3\) after [0-9]+s$' "$LOG_FILE" ||
	fail "a failed step's time is not logged"

summary=$(run_as lyona-postinstall.sh 'write_step_summary lyona-install lyona-postinstall')
for row in 'lyona-install: Running archinstall...' 'lyona-postinstall: Updating the new system...' \
	'lyona-postinstall: Installing GPU drivers... (failed, exit 3)' 'Total of the steps above'; do
	grep -Fq "$row" <<<"$summary" || fail "the summary has no row for: $row"$'\n'"$summary"
done
# Wizard first, then the postinstall, in the order they ran.
order=$(grep -n -F -e 'Running archinstall' -e 'Updating the new system' <<<"$summary" | cut -d: -f1 | tr '\n' ' ')
read -r first second <<<"$order"
if [[ -z ${second:-} ]] || ((first > second)); then
	fail "the summary is not in run order: $summary"
fi

# A Retry re-runs only the postinstall, which starts only its own list again.
run_as lyona-postinstall.sh reset_step_times
[[ ! -s $LYONA_STEP_TIMES_DIR/lyona-postinstall.tsv ]] || fail 'a Retry keeps the failed run'"'"'s times'
[[ -s $LYONA_STEP_TIMES_DIR/lyona-install.tsv ]] || fail "a Retry drops the wizard's times"

# No times directory (not writable): the step still runs and passes.
LYONA_STEP_TIMES_DIR=/proc/lyona-no-such-dir run_as lyona-postinstall.sh 'reset_step_times; run_logged "Step" true' ||
	fail 'a step fails when its time cannot be kept'

for duration in '0 0s' '42 42s' '65 1m 05s' '3600 60m 00s'; do
	got=$(run_as x "format_duration ${duration%% *}")
	[[ $got == "${duration#* }" ]] || fail "format_duration ${duration%% *} gave $got"
done

# Each script starts its list, and the postinstall writes the table into the
# log before copying the log to the new system.
grep -Eq '^	reset_step_times$' "$wizard" || fail 'the wizard does not start its step times'
grep -Eq '^reset_step_times$' "$postinstall" || fail 'the postinstall does not start its step times'
summary_line=$(grep -n '^write_step_summary lyona-install lyona-postinstall ' "$postinstall" | cut -d: -f1)
copy_line=$(grep -nF "install -Dm600 \"\$LOG_FILE\"" "$postinstall" | cut -d: -f1)
if [[ -z $summary_line || -z $copy_line ]] || ((summary_line > copy_line)); then
	fail 'the postinstall does not write the step table before copying the log'
fi

# install.sh: each section's time, then the table.
awk '/^STEP_TIMER_LABEL=$/ { f = 1 } f { print } f && /^print_step_timer_summary\(\) \{$/ { g = 1 } g && /^}$/ { exit }' \
	"$repo/install.sh" >"$work/timer.sh"
grep -q '^step_timer() {$' "$work/timer.sh" || fail 'step_timer not found in install.sh'
out=$(
	# shellcheck disable=SC1091 # generated above
	. "$work/timer.sh"
	SECONDS=0
	step_timer 'Required packages'
	SECONDS=65
	step_timer 'Build (make clean; make)'
	SECONDS=72
	print_step_timer_summary
)
expected='[TIME] Required packages: done in 1m 05s
[TIME] Build (make clean; make): done in 7s

Step times
Time       Step
1m 05s     Required packages
7s         Build (make clean; make)
1m 12s     Total of the steps above'
[[ $out == "$expected" ]] || fail "install.sh's timing printed:"$'\n'"$out"

# Nothing timed: no table.
out=$(
	# shellcheck disable=SC1091 # generated above
	. "$work/timer.sh"
	print_step_timer_summary
)
[[ -z $out ]] || fail "an install with no sections printed: $out"

# The summary comes before the closing banner, and the slow sections are timed.
grep -Fxq 'print_step_timer_summary' "$repo/install.sh" || fail 'install.sh never prints the step table'
for section in 'Packages' 'Default apps and AppImages' 'Build (make clean; make)' 'make install-system' \
	'make install-user' 'Wallpapers' 'Herdr' 'yay' 'GRUB theme' 'Topgrade'; do
	grep -Fq "step_timer \"$section\"" "$repo/install.sh" || fail "install.sh does not time: $section"
done

# A long step shows how long it has run, how long it usually takes and the
# newest line of its log while it runs (#291), on a terminal.
if command -v script >/dev/null 2>&1; then
	# shellcheck disable=SC2016 # expanded by the inner bash
	live=$(script -qec "$(printf '%q ' bash -c '. "$1"; LYONA_STEP_EXPECT="usually 5-30 minutes"; run_logged "Installing..." bash -c "echo first line; sleep 2; echo downloading packages; sleep 2"' bash "$ui")" /dev/null 2>&1) ||
		fail "a live step failed: $live"
	live=$(printf '%s' "$live" | tr -d '\r')
	[[ $live == *'Installing...'*'(usually 5-30 minutes)'* ]] || fail "the expected duration was not shown: $live"
	[[ $live == *'Installing...  2s'* || $live == *'Installing...  3s'* ]] || fail "the elapsed time was not shown: $live"
	[[ $live == *'downloading packages'* ]] || fail "the newest log line was not shown: $live"
	# The cursor, hidden while the status redraws, is shown again after the step.
	[[ $live == *$'\033[?25l'*$'\033[?25h'* ]] || fail 'the console cursor is not shown again after a step'
fi

# The status block on a narrow console (#280 VM): pacman redraws its progress with
# carriage returns and cursor moves; only the last redraw shows, without the
# remains of those escapes ("[3F"), wrapped under the screen's left edge
# (PADDING_LEFT) within the screen, not cut at its edge, in at most 4 lines.
mkdir -p "$work/narrow-bin"
printf '#!/bin/sh\necho 60\n' >"$work/narrow-bin/tput"
chmod +x "$work/narrow-bin/tput"
progress_log=$work/progress.log
printf ' old-package 1.0 MiB [###-----] 30%%\r\033[3F\033[K older-redraw 1 MiB\r\033[3F\033[K linux-firmware-intel 9.9 MiB 7.86 MiB/s 00:15 [#----------] 7%%  linux-firmware-nvidia 9.8 MiB 7.85 MiB/s 00:11 [#---------] 9%%  more packages after these ones\r\033[3F\033[K\n' \
	>"$progress_log"
# shellcheck disable=SC2016 # expanded by the inner bash
block=$(PATH="$work/narrow-bin:$PATH" LOG_FILE=$progress_log bash -c '
	. "$1"
	PADDING_LEFT=10
	_draw_step_status "Running archinstall..." 75 "usually 2-10 minutes" "|"
' bash "$ui") || fail 'drawing the step status failed'
plain=$(printf '%s' "$block" | sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g' | tr -d '\r')
[[ $plain != *'[3F'* && $plain != *'old-package'* && $plain != *'older-redraw'* ]] ||
	fail "the status shows escape remains or an earlier redraw: $plain"
lines=0
while IFS= read -r line; do
	[[ -n $line ]] || continue
	lines=$((lines + 1))
	((${#line} < 60)) || fail "a status line is wider than the 60-column screen: '$line'"
	[[ $line == '          '[!\ ]* || $line == '            '[!\ ]* ]] ||
		fail "a status line does not start at the screen's left edge (10): '$line'"
done <<<"$plain"
((lines >= 3 && lines <= 4)) || fail "the long log line was not wrapped to 2-3 lines ($lines lines): $plain"
[[ $plain == *'more packages after these ones'* || $plain == *'linux-firmware-nvidia'* ]] ||
	fail "the wrapped log line lost its text: $plain"
grep -Fq "local -a frames=('|' '/' '-' \"\\\\\")" "$ui" ||
	fail 'the spinner is not ASCII (the console font has no braille)'

# Stopped part-way (Ctrl+C, or a kill), a step takes everything it started
# with it, and the installer's own traps are back once a step ends.
marker=$work/stop-marker
# shellcheck disable=SC2016 # expanded by the inner bash
STOP_MARKER=$marker bash -c '. "$1"; eval "$2"' x "$ui" '
	trap "exit 143" TERM
	run_logged "Kept trap" true
	[[ $(trap -p TERM) == *"exit 143"* ]] || exit 9
	run_logged "Long step" bash -c "(exec -a \"$STOP_MARKER-a\" sleep 300) & (exec -a \"$STOP_MARKER-b\" sleep 300); wait"' >/dev/null 2>&1 &
installer=$!
for _ in $(seq 50); do
	pgrep -f "^$marker-b" >/dev/null && break
	sleep 0.1
done
pgrep -f "^$marker-b" >/dev/null || fail 'the long step never started'
kill -TERM "$installer"
status=0
wait "$installer" || status=$?
[[ $status == 143 ]] || fail "a step stopped by TERM ended the installer with $status, not 143"
sleep 0.2
if pgrep -f "^$marker-" >/dev/null; then
	pkill -f "^$marker-" || :
	fail 'a stopped step left its processes running'
fi

echo "PASS: $test_name"
