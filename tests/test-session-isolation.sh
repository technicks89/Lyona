#!/usr/bin/env bash
set -euo pipefail

# #368: a test never acts on the desktop it was started from. Run inside a
# session, the theme tests reloaded the live Picom and wrote the user's
# GSettings, and the whole desktop flashed; the update test reached the real
# root helper through polkit. Every way in strips the session:
# - a check goal of the Makefile (a plain `make check-...`);
# - scripts/run-tests;
# - tests/lib.sh, for a test run straight from a terminal, which keeps a
#   display or bus its recipe started (xvfb-run, dbus-run-session);
# and theme-apply.sh, run from a test inside a session, hands nothing of the
# session to xrdb, GSettings, Xfconf, Picom or the cursor helper.
# #404: the session's XDG base directories went the same way. Helpers prefer
# them to HOME, so a test that gave its helper a HOME of its own still
# replaced the user's kept display layout and emptied the Picom log. Every
# way in now gives a test private ones. HOME stays the session's, so the
# fixture's HOME sits beside them and a fallback to it is caught too.
# #408: the DWM_* and LYONA_* overrides the session exported went the same
# way (CONTRIBUTING.md has a developer export LYONA_DEV_SCRIPTS for the whole
# session). Every way in drops them, but for the knobs a developer passes a
# test, which no helper reads.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

uid=$(id -u)
mkdir -m 700 "$work/session-home"
# A desktop session as a test inherits it: nothing here is a real display or bus.
session_env=(
	DISPLAY=:4242
	XAUTHORITY="$work/Xauthority"
	WAYLAND_DISPLAY=wayland-4242
	DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
	XDG_RUNTIME_DIR="/run/user/$uid"
	GSETTINGS_BACKEND=dconf
	# The user's home, which no way in replaces: a private directory that fell
	# back to it (HOME/.config) is a leak like the four below.
	HOME="$work/session-home"
	# A login session exports these; helpers prefer them to HOME (#404).
	XDG_CONFIG_HOME="$work/session-config"
	XDG_DATA_HOME="$work/session-data"
	XDG_STATE_HOME="$work/session-state"
	XDG_CACHE_HOME="$work/session-cache"
	# Overrides a developer's session exports: helpers would run the scripts,
	# or read the kept layout, these point at (#408).
	LYONA_DEV_SCRIPTS="$work/session-scripts"
	DWM_DISPLAY_KEPT_LAYOUT="$work/session-kept-layout"
)
# The run's own variables, which every way in sets or checks itself.
harness_names=' DWM_TEST_TMP_ROOT DWM_TEST_WORKSPACE DWM_TEST_RUNNER_TOKEN LYONA_TEST_ISOLATED LYONA_NO_TRUSTED_HELPERS '
outside=(env -u LYONA_TEST_ISOLATED -u LYONA_NO_TRUSTED_HELPERS)

cat >"$work/probe.sh" <<'EOF'
#!/bin/sh
printf 'DISPLAY=%s\nXAUTHORITY=%s\nWAYLAND_DISPLAY=%s\nDBUS=%s\nRUNTIME=%s\nGSETTINGS_BACKEND=%s\nNO_HELPERS=%s\n' \
	"${DISPLAY-unset}" "${XAUTHORITY-unset}" "${WAYLAND_DISPLAY-unset}" \
	"${DBUS_SESSION_BUS_ADDRESS-unset}" "${XDG_RUNTIME_DIR-unset}" \
	"${GSETTINGS_BACKEND-unset}" "${LYONA_NO_TRUSTED_HELPERS-unset}"
printf 'XDG_CONFIG_HOME=%s\nXDG_DATA_HOME=%s\nXDG_STATE_HOME=%s\nXDG_CACHE_HOME=%s\n' \
	"${XDG_CONFIG_HOME-unset}" "${XDG_DATA_HOME-unset}" \
	"${XDG_STATE_HOME-unset}" "${XDG_CACHE_HOME-unset}"
env | sed -nE 's/^((DWM|LYONA)_[A-Za-z0-9_]*)=(.*)/VARIABLE \1=\3/p'
EOF
chmod +x "$work/probe.sh"

# ── The list of DWM_*/LYONA_* variables a test keeps (#408) ──────────────
# One list, written three times: the Makefile's LYONA_TEST_KEPT, the kept
# string of scripts/run-tests and lyona_kept in tests/lib.sh.
# shellcheck disable=SC2016 # make expands it
printf 'print-kept:\n\t@printf "%%s\\n" $(LYONA_TEST_KEPT)\n' >"$work/kept.mk"
kept_make=$(make -s --no-print-directory -C "$repo" -f Makefile -f "$work/kept.mk" print-kept | sort | paste -sd' ')
kept_run=$(sed -n "s/^kept=' \(.*\) '\$/\1/p" "$repo/scripts/run-tests" | tr ' ' '\n' | sort | paste -sd' ')
kept_lib=$(sed -n "s/^\tlyona_kept=' \(.*\) '\$/\1/p" "$repo/tests/lib.sh" | tr ' ' '\n' | sort | paste -sd' ')
[[ -n $kept_make && $kept_run == "$kept_make" && $kept_lib == "$kept_make" ]] ||
	fail "the kept DWM_*/LYONA_* lists differ: Makefile [$kept_make], scripts/run-tests [$kept_run], tests/lib.sh [$kept_lib]"
# The rest are knobs a developer passes a test. A helper that read one would
# take it from the session, so none may.
knobs=()
for name in $kept_make; do
	[[ $harness_names == *" $name "* ]] || knobs+=("$name")
done
((${#knobs[@]})) || fail 'LYONA_TEST_KEPT lists no test knobs'
for name in "${knobs[@]}"; do
	if readers=$(cd "$repo" && grep -rlw --exclude=run-tests -- "$name" scripts config install.sh ./*.c); then
		fail "$name is kept for tests, but a helper reads it: ${readers//$'\n'/ }. Drop it from LYONA_TEST_KEPT (Makefile, scripts/run-tests, tests/lib.sh)."
	fi
	session_env+=("$name=session-knob")
done

# assert_isolated FILE WHAT: FILE holds a probe's output with no session left.
assert_isolated() {
	assert_line "$1" 'DISPLAY=unset'
	assert_line "$1" 'XAUTHORITY=unset'
	assert_line "$1" 'WAYLAND_DISPLAY=unset'
	assert_line "$1" 'GSETTINGS_BACKEND=memory'
	assert_line "$1" 'NO_HELPERS=1'
	assert_not_contains "$1" "/run/user/$uid"
	assert_not_contains "$1" ':4242'
	grep -q '^RUNTIME=/' "$1" || fail "$2: no private runtime directory: $(cat "$1")"
	# #404: a test that sets only HOME, or nothing, must not reach the user's
	# files: every XDG base directory is a private one, under neither the
	# session's nor its HOME. Every leak is named, with where it is cut.
	local leaked='' name value
	for name in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME; do
		value=$(sed -n "s/^$name=//p" "$1")
		case $value in
		"$work"/session-*) leaked="$leaked $name=$value (the session's)" ;;
		/*) ;;
		*) leaked="$leaked $name=${value:-empty} (not a private directory)" ;;
		esac
	done
	[[ -z $leaked ]] || fail "$2 still hands the session's XDG base directories to a test:$leaked. They are swapped in the check block of the Makefile, in scripts/run-tests before the run starts, and in the isolation section of tests/lib.sh."
	# #408: no DWM_*/LYONA_* override of the session's, and every knob.
	leaked=''
	while read -r name; do
		[[ " $kept_make " == *" $name "* ]] || leaked="$leaked $name"
	done < <(sed -n 's/^VARIABLE \([^=]*\)=.*/\1/p' "$1")
	[[ -z $leaked ]] || fail "$2 still hands the session's DWM_*/LYONA_* overrides to a test:$leaked. They are dropped in the check block of the Makefile, in scripts/run-tests before the run starts, and in the isolation section of tests/lib.sh, but for LYONA_TEST_KEPT."
	for name in "${knobs[@]}"; do
		assert_line "$1" "VARIABLE $name=session-knob"
	done
}

# ── A check goal of the Makefile ─────────────────────────────────────────
printf 'check-session-probe:\n\t@%s\nsession-probe:\n\t@%s\n' "$work/probe.sh" "$work/probe.sh" >"$work/probe.mk"
"${outside[@]}" "${session_env[@]}" TMPDIR="$work" \
	make -s --no-print-directory -C "$repo" -f Makefile -f "$work/probe.mk" check-session-probe \
	>"$work/make-check.out"
assert_isolated "$work/make-check.out" 'make check-...'
# Any other goal keeps the session: installing restarts the live shell.
"${outside[@]}" "${session_env[@]}" TMPDIR="$work" \
	make -s --no-print-directory -C "$repo" -f Makefile -f "$work/probe.mk" session-probe \
	>"$work/make-other.out"
assert_line "$work/make-other.out" 'DISPLAY=:4242'
assert_line "$work/make-other.out" 'GSETTINGS_BACKEND=dconf'
# install-user puts the managed Quickshell tree under the user's own.
assert_line "$work/make-other.out" "XDG_CONFIG_HOME=$work/session-config"
assert_line "$work/make-other.out" "VARIABLE LYONA_DEV_SCRIPTS=$work/session-scripts"
# A value given on make's command line is the developer's for this run.
"${outside[@]}" "${session_env[@]}" TMPDIR="$work" \
	make -s --no-print-directory -C "$repo" -f Makefile -f "$work/probe.mk" check-session-probe \
	DWM_DISPLAY_KEPT_LAYOUT="$work/command-line-layout" >"$work/make-command-line.out"
assert_line "$work/make-command-line.out" "VARIABLE DWM_DISPLAY_KEPT_LAYOUT=$work/command-line-layout"
# A runtime directory outside /run/user (startx without logind) is replaced too.
"${outside[@]}" "${session_env[@]}" XDG_RUNTIME_DIR="$work/session-runtime" TMPDIR="$work" \
	make -s --no-print-directory -C "$repo" -f Makefile -f "$work/probe.mk" check-session-probe \
	>"$work/make-elsewhere.out"
assert_not_contains "$work/make-elsewhere.out" "RUNTIME=$work/session-runtime"

# ── scripts/run-tests ────────────────────────────────────────────────────
"${outside[@]}" "${session_env[@]}" DWM_TEST_TMP_ROOT="$work" \
	"$repo/scripts/run-tests" "$work/probe.sh" >"$work/run-tests.out"
assert_isolated "$work/run-tests.out" 'scripts/run-tests'

# ── tests/lib.sh, a test run straight from a terminal ────────────────────
cat >"$work/lib-probe.sh" <<EOF
#!/bin/sh
. "$repo/tests/lib.sh"
"$work/probe.sh"
EOF
chmod +x "$work/lib-probe.sh"
"${outside[@]}" "${session_env[@]}" "$work/lib-probe.sh" >"$work/lib.out"
assert_isolated "$work/lib.out" 'tests/lib.sh'
private_runtime=$(sed -n 's/^RUNTIME=//p' "$work/lib.out")
[[ ! -e $private_runtime ]] || fail "tests/lib.sh left its private runtime directory: $private_runtime"
private_state=$(sed -n 's/^XDG_STATE_HOME=//p' "$work/lib.out")
[[ ! -e $private_state ]] || fail "tests/lib.sh left its private XDG base directories: $private_state"
# Run from a terminal, any inherited bus and runtime directory are the
# session's, whatever their address: an abstract socket from dbus-launch, a
# runtime directory outside /run/user.
for bus in "unix:abstract=/tmp/dbus-lyona-session" "unix:path=$work/session-bus"; do
	"${outside[@]}" "${session_env[@]}" DBUS_SESSION_BUS_ADDRESS="$bus" \
		XDG_RUNTIME_DIR="$work/session-runtime" "$work/lib-probe.sh" >"$work/lib-bus.out"
	assert_line "$work/lib-bus.out" 'DBUS=unix:path=/nonexistent/lyona-tests-have-no-session-bus'
	assert_not_contains "$work/lib-bus.out" "RUNTIME=$work/session-runtime"
done
# Under make or scripts/run-tests (LYONA_TEST_ISOLATED), the bus, display and
# runtime directory a test sees are its recipe's own (dbus-run-session,
# xvfb-run, the private runtime directory), and are kept, as are the overrides
# it set: make and scripts/run-tests dropped the session's before it ran.
mkdir -m 700 "$work/private-runtime"
env "${session_env[@]}" LYONA_TEST_ISOLATED=1 DBUS_SESSION_BUS_ADDRESS="unix:path=$work/private-bus" \
	XDG_RUNTIME_DIR="$work/private-runtime" DWM_DISPLAY_KEPT_LAYOUT="$work/recipe-layout" \
	LYONA_DEV_SCRIPTS="$work/recipe-scripts" \
	"$work/lib-probe.sh" >"$work/lib-isolated.out"
assert_line "$work/lib-isolated.out" 'DISPLAY=:4242'
assert_line "$work/lib-isolated.out" "DBUS=unix:path=$work/private-bus"
assert_line "$work/lib-isolated.out" "RUNTIME=$work/private-runtime"
# An override the recipe set is the test's own (#408).
assert_line "$work/lib-isolated.out" "VARIABLE DWM_DISPLAY_KEPT_LAYOUT=$work/recipe-layout"
assert_line "$work/lib-isolated.out" "VARIABLE LYONA_DEV_SCRIPTS=$work/recipe-scripts"
# The configuration, data and state directories are the test's own on this
# path too, so a kept layout one test writes is not applied by the next.
assert_not_contains "$work/lib-isolated.out" "$work/session-"
grep -q '^XDG_STATE_HOME=/' "$work/lib-isolated.out" ||
	fail "tests/lib.sh under make or run-tests: no private XDG_STATE_HOME: $(cat "$work/lib-isolated.out")"

# ── theme-apply.sh from a test run inside a session ──────────────────────
# Every command that acts on a session records what it was handed, and does
# nothing else, so a leak is caught here rather than reaching a desktop.
sentinel_bin=$work/sentinel-bin
mkdir -p "$sentinel_bin"
for name in xrdb gsettings xfconf-query picom xsetroot dbus-update-activation-environment systemctl; do
	cat >"$sentinel_bin/$name" <<EOF
#!/bin/sh
printf '%s DISPLAY=%s GSETTINGS_BACKEND=%s DBUS=%s\n' "$name" "\${DISPLAY-unset}" \
	"\${GSETTINGS_BACKEND-unset}" "\${DBUS_SESSION_BUS_ADDRESS-unset}" >>"$work/sentinel.log"
EOF
	chmod +x "$sentinel_bin/$name"
done
for helper in picom-helper cursor-helper; do
	cat >"$sentinel_bin/$helper" <<EOF
#!/bin/sh
printf '%s %s DISPLAY=%s\n' "$helper" "\$*" "\${DISPLAY-unset}" >>"$work/sentinel.log"
EOF
	chmod +x "$sentinel_bin/$helper"
done
: >"$work/sentinel.log"
theme_home=$work/theme-home
mkdir -p "$theme_home/config/lyona" "$theme_home/data" "$theme_home/state"
cp "$repo/config/themes.toml" "$theme_home/config/lyona/themes.toml"
cat >"$work/theme-test.sh" <<EOF
#!/bin/sh
. "$repo/tests/lib.sh"
HOME=$theme_home XDG_CONFIG_HOME=$theme_home/config XDG_DATA_HOME=$theme_home/data \\
	XDG_STATE_HOME=$theme_home/state \\
	DWM_APPEARANCE_THEMES_FILE=$theme_home/config/lyona/themes.toml \\
	DWM_APPEARANCE_MANAGED_THEMES_FILE=$theme_home/config/lyona/themes.toml \\
	DWM_APPEARANCE_PICOM_HELPER=$sentinel_bin/picom-helper \\
	DWM_APPEARANCE_CURSOR_HELPER=$sentinel_bin/cursor-helper \\
	PATH=$sentinel_bin:\$PATH "$repo/scripts/theme-apply.sh"
EOF
chmod +x "$work/theme-test.sh"
"${outside[@]}" "${session_env[@]}" "$work/theme-test.sh" >"$work/theme.out" 2>&1 ||
	fail "theme-apply.sh failed: $(cat "$work/theme.out")"
assert_contains "$work/theme.out" 'applied theme'
assert_not_contains "$work/sentinel.log" ':4242'
assert_not_contains "$work/sentinel.log" "/run/user/$uid"
assert_not_contains "$work/sentinel.log" 'GSETTINGS_BACKEND=dconf'
assert_not_contains "$work/sentinel.log" 'picom-helper reload'
# GSettings was still written, to memory: the path ran, it reached nothing.
assert_contains "$work/sentinel.log" 'gsettings DISPLAY=unset GSETTINGS_BACKEND=memory'

printf 'Tests never reach the desktop session or its overrides (make, run-tests, lib.sh, theme-apply): PASS\n'
