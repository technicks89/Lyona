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

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

uid=$(id -u)
# A desktop session as a test inherits it: nothing here is a real display or bus.
session_env=(
	DISPLAY=:4242
	XAUTHORITY="$work/Xauthority"
	WAYLAND_DISPLAY=wayland-4242
	DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
	XDG_RUNTIME_DIR="/run/user/$uid"
	GSETTINGS_BACKEND=dconf
)
outside=(env -u LYONA_TEST_ISOLATED -u LYONA_NO_TRUSTED_HELPERS)

cat >"$work/probe.sh" <<'EOF'
#!/bin/sh
printf 'DISPLAY=%s\nXAUTHORITY=%s\nWAYLAND_DISPLAY=%s\nDBUS=%s\nRUNTIME=%s\nGSETTINGS_BACKEND=%s\nNO_HELPERS=%s\n' \
	"${DISPLAY-unset}" "${XAUTHORITY-unset}" "${WAYLAND_DISPLAY-unset}" \
	"${DBUS_SESSION_BUS_ADDRESS-unset}" "${XDG_RUNTIME_DIR-unset}" \
	"${GSETTINGS_BACKEND-unset}" "${LYONA_NO_TRUSTED_HELPERS-unset}"
EOF
chmod +x "$work/probe.sh"

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
# xvfb-run, the private runtime directory), and are kept.
mkdir -m 700 "$work/private-runtime"
env "${session_env[@]}" LYONA_TEST_ISOLATED=1 DBUS_SESSION_BUS_ADDRESS="unix:path=$work/private-bus" \
	XDG_RUNTIME_DIR="$work/private-runtime" "$work/lib-probe.sh" >"$work/lib-isolated.out"
assert_line "$work/lib-isolated.out" 'DISPLAY=:4242'
assert_line "$work/lib-isolated.out" "DBUS=unix:path=$work/private-bus"
assert_line "$work/lib-isolated.out" "RUNTIME=$work/private-runtime"

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

printf 'Tests never reach the desktop session (make, run-tests, lib.sh, theme-apply): PASS\n'
