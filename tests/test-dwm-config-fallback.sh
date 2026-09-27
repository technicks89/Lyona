#!/bin/sh

set -eu

# Sync Sprint 12 S12-04: dwm always starts with working keys, and a config file
# cannot hang it. For each kind of unusable ~/.config/lyona/hotkeys.toml, a fresh
# dwm on an isolated Xvfb must fall back to the shipped default (Super+2 switches
# to the second tag), report it once through a captured notify-send, and quit
# promptly on SIGUSR2. With no usable default either, the built-in emergency keys
# still quit dwm.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

for cmd in Xvfb xprop xdotool; do
	command -v "$cmd" >/dev/null 2>&1 || {
		printf 'SKIP: %s is unavailable\n' "$cmd"
		exit 77
	}
done
[ -x "$repo/dwm" ] || {
	printf 'SKIP: dwm is not built (run make all)\n'
	exit 77
}

work=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/dwm-config-fallback.XXXXXX")
dwm_pid=
xvfb_pid=
cleanup() {
	[ -z "$dwm_pid" ] || kill "$dwm_pid" 2>/dev/null || :
	[ -z "$xvfb_pid" ] || kill "$xvfb_pid" 2>/dev/null || :
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	[ ! -f "$work/dwm.log" ] || tail -20 "$work/dwm.log" >&2
	exit 1
}

display=":$((($$ % 500) + 700))"
Xvfb "$display" -screen 0 1024x768x24 -nolisten tcp >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
until DISPLAY=$display xprop -root >/dev/null 2>&1; do
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'Xvfb did not start'
	sleep 0.05
done

home=$work/home
user_hotkeys=$home/.config/lyona/hotkeys.toml
default_dir=$home/.local/share/lyona/config
mkdir -p "$work/bin" "$(dirname "$user_hotkeys")"
cat >"$work/bin/notify-send" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${DWM_TEST_NOTIFICATION_LOG:?}"
EOF
chmod 755 "$work/bin/notify-send"

seed_defaults() {
	rm -rf "$default_dir"
	mkdir -p "$default_dir"
	cp "$repo/config/hotkeys.toml" "$repo/config/themes.toml" "$repo/config/window-rules.toml" "$default_dir/"
}

current_desktop() {
	DISPLAY=$display xprop -root _NET_CURRENT_DESKTOP 2>/dev/null | sed -n 's/.*= //p'
}

start_dwm() {
	: >"$work/notifications.log"
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
		PATH="$work/bin:$PATH" DWM_TEST_NOTIFICATION_LOG="$work/notifications.log" \
		"$repo/dwm" >"$work/dwm.log" 2>&1 &
	dwm_pid=$!
	i=0
	until [ "$(current_desktop)" = 0 ]; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail "dwm did not start ($1)"
		kill -0 "$dwm_pid" 2>/dev/null || fail "dwm exited at startup ($1)"
		sleep 0.05
	done
}

wait_exit() { # LABEL: dwm must be gone within 5 s
	i=0
	while kill -0 "$dwm_pid" 2>/dev/null; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail "dwm did not exit ($1)"
		sleep 0.05
	done
	wait "$dwm_pid" 2>/dev/null || :
	dwm_pid=
}

expect_defaults() { # LABEL: the shipped keys work, and the fallback was reported
	DISPLAY=$display xdotool key Super+2
	i=0
	until [ "$(current_desktop)" = 1 ]; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail "the shipped keys are not grabbed ($1)"
		sleep 0.05
	done
	i=0
	until grep -Fxq -- '-u critical dwm: bad config hotkeys.toml: invalid config - loaded defaults' \
		"$work/notifications.log"; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail "no 'loaded defaults' notification ($1): $(cat "$work/notifications.log")"
		sleep 0.05
	done
	kill -USR2 "$dwm_pid"
	wait_exit "$1"
}

seed_defaults

# An empty file, and one that is only comments, used to leave dwm with no keys.
: >"$user_hotkeys"
start_dwm empty
expect_defaults empty

printf '# nothing but comments\n# keys = []\n' >"$user_hotkeys"
start_dwm comments
expect_defaults comments

# Entries, but not one binding dwm could grab (and a tag outside 0-8).
printf '[meta]\nversion = 1\ntag_keys = [\n  { key="1", tag=40 },\n]\n' >"$user_hotkeys"
start_dwm unusable
expect_defaults unusable

# A device used to hang dwm in the parser (about 54% CPU, no new windows).
rm -f "$user_hotkeys"
ln -s /dev/zero "$user_hotkeys"
start_dwm /dev/zero
expect_defaults /dev/zero

# A FIFO would block dwm at open.
rm -f "$user_hotkeys"
mkfifo "$user_hotkeys"
start_dwm fifo
expect_defaults fifo
rm -f "$user_hotkeys"

# Neither the user's file nor the default loads: the emergency keys still quit.
printf '=\n' >"$user_hotkeys"
rm -rf "$default_dir"
start_dwm emergency
grep -Fq 'no usable hotkeys' "$work/notifications.log" ||
	fail "no emergency-keys notification: $(cat "$work/notifications.log")"
DISPLAY=$display xdotool key Super+shift+q
wait_exit 'emergency Super+Shift+q'
seed_defaults

printf 'dwm config fallback (empty, comments, unusable, /dev/zero, FIFO, emergency keys): PASS\n'
