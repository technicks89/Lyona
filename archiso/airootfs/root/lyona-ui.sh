COLOR_ACCENT="#0072ff"
COLOR_SECONDARY="#c8c8cd"
COLOR_OK=2
COLOR_DANGER=1
COLOR_DIM=$COLOR_SECONDARY

export GUM_CHOOSE_CURSOR_FOREGROUND=$COLOR_ACCENT
export GUM_CHOOSE_SELECTED_FOREGROUND=$COLOR_ACCENT
export GUM_CONFIRM_PROMPT_FOREGROUND=$COLOR_ACCENT
export GUM_CONFIRM_SELECTED_FOREGROUND=0
export GUM_CONFIRM_SELECTED_BACKGROUND=$COLOR_OK
export GUM_INPUT_CURSOR_FOREGROUND=$COLOR_ACCENT
export GUM_INPUT_PROMPT_FOREGROUND=$COLOR_ACCENT
export GUM_SPIN_SPINNER_FOREGROUND=$COLOR_ACCENT

log_step() {
	printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$1" >>"$LOG_FILE"
}

# Repaint the console in the active palette, so the installer looks like a
# continuation of the boot splash rather than stock VGA. Generated at ISO build
# time from the same themes.toml the splash comes from; absent elsewhere, which
# is why this is optional.
LYONA_CONSOLE_THEME=${LYONA_CONSOLE_THEME:-/root/lyona-console.sh}
apply_console_theme() {
	[[ -f $LYONA_CONSOLE_THEME ]] || return 0
	# shellcheck source=/dev/null
	source "$LYONA_CONSOLE_THEME"
	lyona_console_colors
}

require_gum() {
	command -v gum >/dev/null 2>&1 ||
		fail "gum is required but not installed on this live medium (archiso/packages.x86_64 should list it)."
}

# The wordmark is 58 columns wide, and everything on screen is centred as one
# block against it rather than each line being centred on its own -- a list
# whose items each re-centre is unreadable.
LOGO_PATH=${LYONA_LOGO_PATH:-/root/lyona-logo.txt}
LOGO_WIDTH=72
PADDING_LEFT=0

# The console has sixteen colours and no truecolor, so the logo is painted in
# palette slots rather than hex. lyona-console-theme repoints those slots at
# the active palette, which is what makes these the theme's colours rather than
# stock VGA. The characters are the logo's own: the four diamond quadrants and
# the white its outline, cross and wordmark share.
declare -A LOGO_COLORS=([g]=2 [b]=4 [t]=6 [v]=5 [w]=15)

# gum's interactive widgets take no --padding argument; each one reads its own
# GUM_<COMMAND>_PADDING instead, which is the only way to indent the widget
# itself rather than just the header above it. Re-measured on every screen so
# a resized console re-centres instead of staying wherever it started.
measure_terminal() {
	local columns
	columns=$(stty size 2>/dev/null </dev/tty | awk '{print $2}') || columns=""
	[[ $columns =~ ^[0-9]+$ ]] && ((columns > 0)) || columns=$(tput cols 2>/dev/null || echo 80)
	[[ $columns =~ ^[0-9]+$ ]] && ((columns > 0)) || columns=80

	PADDING_LEFT=$(((columns - LOGO_WIDTH) / 2))
	((PADDING_LEFT < 0)) && PADDING_LEFT=0

	local padding="0 0 0 $PADDING_LEFT"
	export GUM_CHOOSE_PADDING="$padding"
	# gum confirm draws one column further right than every other widget at the
	# same padding: measured against gum 2.0.0, confirm at 20 and choose at 21
	# both land on column 21. Without this the question sits a column off the
	# answers it is asking about.
	local confirm_padding=$((PADDING_LEFT - 1))
	((confirm_padding < 0)) && confirm_padding=0
	export GUM_CONFIRM_PADDING="0 0 0 $confirm_padding"
	export GUM_FILTER_PADDING="$padding"
	export GUM_INPUT_PADDING="$padding"
	export GUM_SPIN_PADDING="$padding"
	export GUM_TABLE_PADDING="$padding"
	export GUM_WRITE_PADDING="$padding"
}

# Every non-interactive line goes through this so it lands on the same left
# edge as the widgets above and below it.
say() {
	gum style --padding "0 0 0 $PADDING_LEFT" "$@"
}

# The map is two characters per cell -- the top pixel's colour then the
# bottom's -- and each cell is drawn as a half block, so one character row
# carries two pixel rows and the artwork comes out square instead of stretched
# to the 1:2 of a terminal cell. Regenerate it from the SVG with
# scripts/lyona-logo-art.
render_logo() {
	local line pad index top bottom out
	pad=$(printf '%*s' "$PADDING_LEFT" '')
	while IFS= read -r line; do
		out=$pad
		for ((index = 0; index + 1 < ${#line}; index += 2)); do
			top=${line:index:1}
			bottom=${line:index+1:1}
			if [[ $top == . && $bottom == . ]]; then
				out+=' '
			elif [[ $bottom == . ]]; then
				out+=$'\033'"[38;5;${LOGO_COLORS[$top]}m▀"$'\033'"[0m"
			elif [[ $top == . ]]; then
				out+=$'\033'"[38;5;${LOGO_COLORS[$bottom]}m▄"$'\033'"[0m"
			else
				out+=$'\033'"[38;5;${LOGO_COLORS[$top]}m"
				out+=$'\033'"[48;5;${LOGO_COLORS[$bottom]}m▀"$'\033'"[0m"
			fi
		done
		printf '%s\n' "$out"
	done <"$LOGO_PATH"
}

show_logo() {
	measure_terminal
	clear
	echo
	if [[ -f $LOGO_PATH ]] && ((PADDING_LEFT > 0 || LOGO_WIDTH <= $(tput cols 2>/dev/null || echo 80))); then
		render_logo
	else
		gum style --foreground $COLOR_ACCENT --bold \
			--padding "0 0 0 $PADDING_LEFT" "LYONA"
	fi
	echo
	say --foreground $COLOR_DIM "Arch Linux Installer"
	echo
}

STEP_TOTAL=0
STEP_CURRENT=0

set_total_steps() { STEP_TOTAL=$1; }

_progress_bar_string() {
	local completed=$1
	local width=20
	local filled=$((completed * width / STEP_TOTAL))
	local percent=$((completed * 100 / STEP_TOTAL))
	local bar="" i
	for ((i = 0; i < filled; i++)); do bar+="█"; done
	for ((i = filled; i < width; i++)); do bar+="░"; done
	echo "[$bar] $percent% (step $((completed + 1))/$STEP_TOTAL)"
}

# Each step's time, one "SECONDS<TAB>STATUS<TAB>DESCRIPTION" line per step,
# for the summary table at the end of the log (#250). One file per script: the
# wizard's archinstall step and the postinstall's steps make one table, and a
# Retry, which re-runs only its own script, starts only its own file again.
LYONA_STEP_TIMES_DIR=${LYONA_STEP_TIMES_DIR:-/run/lyona-step-times}

step_times_file() {
	printf '%s/%s.tsv\n' "$LYONA_STEP_TIMES_DIR" "${1:-$(basename "$0" .sh)}"
}

reset_step_times() {
	mkdir -p -- "$LYONA_STEP_TIMES_DIR" 2>/dev/null || return 0
	{ : >"$(step_times_file)"; } 2>/dev/null || :
}

# format_duration SECONDS: "42s", or "3m 05s".
format_duration() {
	local seconds=$1
	if ((seconds < 60)); then
		printf '%ds' "$seconds"
	else
		printf '%dm %02ds' "$((seconds / 60))" "$((seconds % 60))"
	fi
}

# How many lines the status block took when it was last drawn.
_STEP_STATUS_LINES=0

# The newest line of the step's log, as the console can show it: the last
# redraw of a progress bar that still has text (pacman writes each redraw as
# text, a carriage return and cursor moves), without escape sequences, whose
# remains such as "[3F" were shown, other control and non-ASCII characters as
# single spaces.
_step_log_tail() {
	tail -n 1 -- "$LOG_FILE" 2>/dev/null | tr '\r' '\n' |
		LC_ALL=C sed -E $'s/\x1b\\[[0-9;?]*[ -/]*[@-~]//g; s/\x1b[@-_]//g' |
		LC_ALL=C tr -c '[:print:]\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//' |
		awk 'NF { last = $0 } END { printf "%s", last }'
}

# The live status of a running step (#291): the step, how long it has run, how
# long it usually takes, and the newest line of its log, redrawn every second,
# so a slow step is told from a hung one. On the same left edge as the screen
# above it, and the log line wrapped to that column's width, at most three lines,
# rather than cut at the screen's edge.
_draw_step_status() { # TITLE ELAPSED EXPECT FRAME
	local cols indent width pad last part i drawn
	local -a lines=()
	cols=$(tput cols 2>/dev/null || printf 80)
	[[ $cols =~ ^[0-9]+$ ]] && ((cols > 20)) || cols=80
	indent=${PADDING_LEFT:-0}
	[[ $indent =~ ^[0-9]+$ ]] && ((indent + 30 <= cols)) || indent=0
	width=$((cols - indent - 1))
	((width > LOGO_WIDTH)) && width=$LOGO_WIDTH
	printf -v pad '%*s' "$indent" ''
	part="$4 $1  $(format_duration "$2")${3:+ ($3)}"
	lines+=("${part:0:width}")
	last=$(_step_log_tail)
	if [[ -n $last ]]; then
		while IFS= read -r part; do
			lines+=("  $part")
		done < <(printf '%s\n' "$last" | fold -s -w "$((width - 2))" | head -n 3)
	fi
	printf '\r'
	for ((i = 0; i < ${#lines[@]}; i++)); do
		if ((i == 0)); then
			printf '\033[K%s%s\n' "$pad" "${lines[i]}"
		else
			printf '\033[K\033[2m%s%s\033[0m\n' "$pad" "${lines[i]}"
		fi
	done
	# Lines a longer log line used last time, cleared.
	for ((i = ${#lines[@]}; i < _STEP_STATUS_LINES; i++)); do
		printf '\033[K\n'
	done
	drawn=$((${#lines[@]} > _STEP_STATUS_LINES ? ${#lines[@]} : _STEP_STATUS_LINES))
	printf '\033[%dA\r' "$drawn"
	_STEP_STATUS_LINES=$drawn
}

# The status block cleared, the cursor back where it began and shown again.
_clear_step_status() {
	local i
	printf '\033[?25h'
	((_STEP_STATUS_LINES > 0)) || return 0
	printf '\r'
	for ((i = 0; i < _STEP_STATUS_LINES; i++)); do
		printf '\033[K\n'
	done
	printf '\033[%dA\r' "$_STEP_STATUS_LINES"
	_STEP_STATUS_LINES=0
}

# _stop_step PID: a running step and everything it started, stopped and
# waited for. Without job control a background step ignores SIGINT, so Ctrl+C
# would leave it running after the installer exits. The tree is listed before
# anything is signalled, while every process still has its parent.
_stop_step() {
	local -a tree=("$1")
	local index=0 child
	while ((index < ${#tree[@]})); do
		for child in $(pgrep -P "${tree[index]}" 2>/dev/null); do
			tree+=("$child")
		done
		index=$((index + 1))
	done
	kill -TERM "${tree[@]}" 2>/dev/null || :
	wait "$1" 2>/dev/null || :
}

# run_logged DESCRIPTION COMMAND...: one install step, its output to the log.
# Set LYONA_STEP_EXPECT (such as "usually 5-30 minutes") on the line before for
# a long step; it applies to the next step only.
run_logged() {
	local desc=$1
	shift
	local title=$desc label=$desc expect=${LYONA_STEP_EXPECT:-}
	LYONA_STEP_EXPECT=
	if ((STEP_TOTAL > 0)); then
		title="$(_progress_bar_string "$STEP_CURRENT") $desc"
		label="[step $((STEP_CURRENT + 1))/$STEP_TOTAL] $desc"
	fi
	STEP_CURRENT=$((STEP_CURRENT + 1))
	local start=$SECONDS status=0 elapsed pid frame=0
	# ASCII: the console font has no braille, which drew as a stray glyph.
	local -a frames=('|' '/' '-' "\\")
	log_step "$label"
	local saved_traps
	saved_traps=$(trap -p INT TERM)
	bash -c 'set -Eeuo pipefail; "$@" 2>&1 | tee -a "$LOG_FILE" >/dev/null; exit ${PIPESTATUS[0]}' _ "$@" &
	pid=$!
	# shellcheck disable=SC2064 # the step's PID, fixed now
	trap "_stop_step $pid; [[ -t 1 ]] && _clear_step_status; exit 130" INT
	# shellcheck disable=SC2064
	trap "_stop_step $pid; [[ -t 1 ]] && _clear_step_status; exit 143" TERM
	if [[ -t 1 ]]; then
		# The console's cursor hidden while the status redraws: it blinked at
		# the left edge beside it.
		printf '\033[?25l'
		while kill -0 "$pid" 2>/dev/null; do
			_draw_step_status "$title" "$((SECONDS - start))" "$expect" "${frames[frame % ${#frames[@]}]}"
			frame=$((frame + 1))
			sleep 1
		done
		_clear_step_status
	fi
	wait "$pid" || status=$?
	trap - INT TERM
	eval "$saved_traps"
	elapsed=$((SECONDS - start))
	if ((status == 0)); then
		log_step "$label done in $(format_duration "$elapsed")"
	else
		log_step "$label failed (exit $status) after $(format_duration "$elapsed")"
		# What gum spin --show-error used to show: the step's last output.
		tail -n 20 -- "$LOG_FILE" >&2 2>/dev/null || :
	fi
	{ printf '%s\t%s\t%s\n' "$elapsed" "$status" "$desc" >>"$(step_times_file)"; } 2>/dev/null || :
	return "$status"
}

# write_step_summary SCRIPT...: the step times of each script, in order, as a
# table, with the total. Appended to the log by the caller.
write_step_summary() {
	local script file seconds status desc total=0 note
	printf '\nStep times\n'
	printf '%-10s %s\n' "Time" "Step"
	for script in "$@"; do
		file=$(step_times_file "$script")
		[[ -s $file ]] || continue
		while IFS=$'\t' read -r seconds status desc; do
			[[ $seconds =~ ^[0-9]+$ ]] || continue
			note=
			[[ $status == 0 ]] || note=" (failed, exit $status)"
			printf '%-10s %s: %s%s\n' "$(format_duration "$seconds")" "$script" "$desc" "$note"
			total=$((total + seconds))
		done <"$file"
	done
	printf '%-10s %s\n' "$(format_duration "$total")" "Total of the steps above"
}

# Files a run must never leave behind, however it ends: the postinstall's
# temporary passwordless sudoers rule (Sync Sprint 16 R16-01), and the wizard's
# archinstall directory with the credentials (#266); a directory goes whole. They are removed
# on exit, and before the recovery menu offers anything, because Retry re-runs
# the script with exec, which skips EXIT traps.
LYONA_CLEANUP_FILES=()
# What has already happened to the machine, said when a run fails.
LYONA_RECOVER_HINT=

lyona_cleanup_files() {
	local file
	for file in "${LYONA_CLEANUP_FILES[@]}"; do
		rm -rf -- "$file"
	done
}

_lyona_recover() {
	local exit_code=$?
	trap - ERR
	lyona_cleanup_files
	lyona_recover_menu "$exit_code"
	exec "$SCRIPT_PATH" "${SCRIPT_ARGS[@]}"
}

# lyona_recover_menu EXIT-CODE: the failure, the end of the log and what state
# the machine is in (LYONA_RECOVER_HINT), then Retry, View full log or Exit to
# shell. Returns when Retry is chosen, for the caller to retry its step; exits
# otherwise.
lyona_recover_menu() {
	local exit_code=$1

	echo
	gum style --foreground $COLOR_DANGER --bold "${SCRIPT_NAME:-$(basename "$0")} failed (exit $exit_code)."
	if [[ -n ${LOG_FILE:-} && -f $LOG_FILE ]]; then
		echo
		gum style --foreground $COLOR_DIM "Last lines of $LOG_FILE:"
		tail -n 20 "$LOG_FILE" | while IFS= read -r line; do
			gum style --foreground $COLOR_DIM "  $line"
		done
	fi
	echo
	if [[ -n $LYONA_RECOVER_HINT ]]; then
		gum style --foreground $COLOR_ACCENT "$LYONA_RECOVER_HINT"
		echo
	fi

	while true; do
		local choice
		choice=$(gum choose "Retry" "View full log" "Exit to shell" --header "What would you like to do?") ||
			choice="Exit to shell"
		case $choice in
		Retry)
			return 0
			;;
		"View full log")
			if [[ -n ${LOG_FILE:-} && -f $LOG_FILE ]]; then
				command -v less >/dev/null 2>&1 && less "$LOG_FILE" || cat "$LOG_FILE"
			else
				gum style --foreground $COLOR_DANGER "No log file to show."
			fi
			;;
		*)
			exit "$exit_code"
			;;
		esac
	done
}

install_error_trap() {
	SCRIPT_NAME=$(basename "$0")
	SCRIPT_PATH=$0
	SCRIPT_ARGS=("$@")
	trap _lyona_recover ERR
	# Ctrl+C and a kill end the run through exit, so the EXIT trap still cleans up.
	trap lyona_cleanup_files EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
}
