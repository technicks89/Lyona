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

run_logged() {
	local desc=$1
	shift
	local title=$desc label=$desc
	if ((STEP_TOTAL > 0)); then
		title="$(_progress_bar_string "$STEP_CURRENT") $desc"
		label="[step $((STEP_CURRENT + 1))/$STEP_TOTAL] $desc"
	fi
	STEP_CURRENT=$((STEP_CURRENT + 1))
	local start=$SECONDS status=0 elapsed
	log_step "$label"
	gum spin --spinner dot --title "$title" --show-error -- \
		bash -c 'set -Eeuo pipefail; "$@" 2>&1 | tee -a "$LOG_FILE"; exit ${PIPESTATUS[0]}' _ "$@" ||
		status=$?
	elapsed=$((SECONDS - start))
	if ((status == 0)); then
		log_step "$label done in $(format_duration "$elapsed")"
	else
		log_step "$label failed (exit $status) after $(format_duration "$elapsed")"
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
