#!/bin/sh

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

test_repo="$work/repo"
test_home="$work/user home"
prefix="$work/prefix with space"
manprefix="$prefix/share/man"
xsessions_dir="$work/xsessions"
data_root="$work/system data"
config_home="$test_home/.config"
xdg_data_home="$test_home/.local/share"
state_home="$test_home/.local/state"
data_dir="$xdg_data_home/lyona"
output="$work/output"
install_sources="$work/install-sources"
privileged_helpers="$work/privileged-helpers"

mkdir -p "$test_repo" "$prefix/bin" "$prefix/libexec/lyona" \
	"$manprefix/man1" "$xsessions_dir" \
	"$data_root/icons" "$data_root/licenses/lyona/capitaine-cursors" \
	"$config_home/systemd/user" "$data_dir"
cp -a \
	"$repo/Makefile" \
	"$repo/config.mk" \
	"$repo/dwm.1" \
	"$repo/dwm.desktop" \
	"$repo/config" \
	"$repo/scripts" \
	"$repo/assets" \
	"$test_repo/"
printf '%s\n' 'test dwm binary' >"$test_repo/dwm"
printf '%s\n' 'test lyona-toml binary' >"$test_repo/lyona-toml"
chmod 755 "$test_repo/dwm" "$test_repo/lyona-toml"

# shellcheck disable=SC2016
make -s -C "$test_repo" --no-print-directory \
	--eval='test-print-install-sources: ; @printf "%s\n" $(INSTALL_COMMANDS)' \
	test-print-install-sources >"$install_sources"
# shellcheck disable=SC2016
make -s -C "$test_repo" --no-print-directory \
	--eval='test-print-lib-sources: ; @printf "%s\n" $(INSTALL_LIBS)' \
	test-print-lib-sources >"$work/lib-sources"
# shellcheck disable=SC2016
make -s -C "$test_repo" --no-print-directory \
	--eval='test-print-python-sources: ; @printf "%s\n" $(INSTALL_PYTHON)' \
	test-print-python-sources >"$work/python-sources"
# shellcheck disable=SC2016
make -s -C "$test_repo" --no-print-directory \
	--eval='test-print-session-sources: ; @printf "%s\n" $(INSTALL_SESSION_SCRIPTS)' \
	test-print-session-sources >"$work/session-sources"
# shellcheck disable=SC2016
make -s -C "$test_repo" --no-print-directory \
	--eval='test-print-default-sources: ; @printf "%s\n" $(INSTALL_DEFAULTS)' \
	test-print-default-sources >"$work/default-sources"
# shellcheck disable=SC2016
make -s -C "$test_repo" --no-print-directory \
	--eval='test-print-privileged-helpers: ; @printf "%s\n" $(PRIVILEGED_HELPERS)' \
	test-print-privileged-helpers >"$privileged_helpers"

install -Dm755 "$test_repo/dwm" "$prefix/bin/dwm"
install -Dm755 "$test_repo/lyona-toml" "$prefix/lib/lyona/lyona-toml"
while IFS= read -r privileged_helper; do
	[ -n "$privileged_helper" ] || continue
	sed "s|@PREFIX@|$prefix|g" "$test_repo/$privileged_helper" |
		install -Dm755 /dev/stdin "$prefix/libexec/lyona/${privileged_helper##*/}"
done <"$privileged_helpers"
while IFS= read -r install_source; do
	[ -n "$install_source" ] || continue
	install -Dm755 "$test_repo/$install_source" \
		"$prefix/bin/${install_source##*/}"
done <"$install_sources"
while IFS= read -r lib_source; do
	[ -n "$lib_source" ] || continue
	install -Dm644 "$test_repo/$lib_source" \
		"$prefix/lib/lyona/${lib_source##*/}"
done <"$work/lib-sources"
python_dir="$prefix/lib/lyona/python/lyona_system_management"
while IFS= read -r python_source; do
	[ -n "$python_source" ] || continue
	install -Dm644 "$test_repo/$python_source" "$python_dir/${python_source##*/}"
done <"$work/python-sources"
while IFS= read -r session_source; do
	[ -n "$session_source" ] || continue
	install -Dm755 "$test_repo/$session_source" \
		"$prefix/lib/lyona/${session_source##*/}"
done <"$work/session-sources"
while IFS= read -r default_source; do
	[ -n "$default_source" ] || continue
	install -Dm644 "$test_repo/$default_source" \
		"$prefix/share/lyona/config/${default_source##*/}"
done <"$work/default-sources"

version=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$test_repo/config.mk")
sed "s/VERSION/$version/g" "$test_repo/dwm.1" >"$manprefix/man1/dwm.1"
sed "s|@PREFIX@|$prefix|g" "$test_repo/dwm.desktop" >"$xsessions_dir/dwm.desktop"
# Mirror `make install-user`, which dereferences so the managed shell holds
# real files rather than links back into the repo checkout.
cp -aL "$test_repo/config/quickshell" "$config_home/quickshell"
printf '%s\n' '# preserved custom user unit' \
	>"$config_home/systemd/user/wm-graphical-session.service"
for cursor_source in "$test_repo"/assets/cursors/Capitaine-Cursors*; do
	cp -a "$cursor_source" "$data_root/icons/"
done
install -Dm644 "$test_repo/assets/cursors/COPYING" \
	"$data_root/licenses/lyona/capitaine-cursors/COPYING"

run_check() {
	DWM_DEV_SYNC_SKIP_RUNTIME=1 \
		DWM_DEV_SYNC_SKIP_PRIVILEGED_TRUST=1 \
		USER_HOME="$test_home" \
		PREFIX="$prefix" \
		MANPREFIX="$manprefix" \
		XSESSIONSDIR="$xsessions_dir" \
		DATADIR="$data_root" \
		XDG_CONFIG_HOME="$config_home" \
		XDG_DATA_HOME="$xdg_data_home" \
		XDG_STATE_HOME="$state_home" \
		"$test_repo/scripts/dev-sync-install.sh" --check
}

run_check >"$output"
grep -Fqx 'All managed files match the checkout.' "$output"
grep -Fqx 'Runtime validation skipped by DWM_DEV_SYNC_SKIP_RUNTIME=1.' "$output"

printf '%s\n' '// stale live marker' >>"$config_home/quickshell/shell.qml"
if run_check >"$output" 2>&1; then
	printf '%s\n' 'Managed Quickshell mismatch unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'MISMATCH TREE: managed Quickshell' "$output"
cp "$test_repo/config/quickshell/shell.qml" "$config_home/quickshell/shell.qml"

rm -f "$prefix/bin/dwm-status"
if run_check >"$output" 2>&1; then
	printf '%s\n' 'Missing installed command unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'MISSING INSTALL: installed command dwm-status' "$output"
install -Dm755 "$test_repo/scripts/dwm-status" "$prefix/bin/dwm-status"

# A library belongs in lib/lyona; one missing there, or left in bin by an older
# install, fails the check (Sync Sprint 12 S12-13).
mv "$prefix/lib/lyona/dwm-paths.sh" "$prefix/bin/dwm-paths.sh"
if run_check >"$output" 2>&1; then
	printf '%s\n' 'Library installed in bin unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'MISSING INSTALL: installed library dwm-paths.sh' "$output"
grep -Fq 'STALE: library dwm-paths.sh is still installed in' "$output"
mv "$prefix/bin/dwm-paths.sh" "$prefix/lib/lyona/dwm-paths.sh"
run_check >"$output"

# The system-management package is verified module by module, and a module the
# checkout no longer ships is reported (Sync Sprint 12 S12-16).
mv "$python_dir/cli.py" "$python_dir/retired.py"
if run_check >"$output" 2>&1; then
	printf '%s\n' 'A missing and a retired module unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'MISSING INSTALL: system-management module cli.py' "$output"
grep -Fq 'STALE: system-management module retired.py is no longer shipped' "$output"
mv "$python_dir/retired.py" "$python_dir/cli.py"
run_check >"$output"

# The shipped defaults are verified in share/lyona, and a per-user copy an older
# install left is reported until install-user removes it (S12-13 step 4).
rm "$prefix/share/lyona/config/themes.toml"
if run_check >"$output" 2>&1; then
	printf '%s\n' 'Missing shipped default unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'MISSING INSTALL: shipped default themes.toml' "$output"
install -Dm644 "$test_repo/config/themes.toml" "$prefix/share/lyona/config/themes.toml"
mkdir -p "$data_dir/scripts"
if run_check >"$output" 2>&1; then
	printf '%s\n' 'A leftover per-user copy unexpectedly passed.' >&2
	exit 1
fi
grep -Fq "STALE: per-user copy $data_dir/scripts is still present" "$output"
rmdir "$data_dir/scripts"
run_check >"$output"

"$test_repo/scripts/dev-sync-install.sh" --help >"$output"
grep -Fq 'Usage: scripts/dev-sync-install.sh [--check]' "$output"
if "$test_repo/scripts/dev-sync-install.sh" --unknown >"$output" 2>&1; then
	printf '%s\n' 'Unknown option unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'unknown option: --unknown' "$output"

# An atomic reinstall unlinks the old executable even when its bytes match.
# Exercise that kernel state with a private child, never the host window manager.
runtime_bin="$work/runtime-bin"
runtime_probe="$work/runtime-probe"
mkdir "$runtime_bin"
sed -n '/^runtime_verify() {$/,/^}$/p' "$test_repo/scripts/lyona-install-verify.sh" >"$runtime_probe"
cat >"$runtime_bin/pgrep" <<'EOF'
#!/bin/sh
case "$*" in
'-xo dwm') printf '%s\n' "$DWM_TEST_DWM_PID" ;;
'-xc quickshell') printf '1\n' ;;
*) exit 2 ;;
esac
EOF
printf '#!/bin/sh\nprintf "0\\n"\n' >"$runtime_bin/quickshell"
printf '#!/bin/sh\nexit 0\n' >"$runtime_bin/systemctl"
chmod +x "$runtime_bin/pgrep" "$runtime_bin/quickshell" "$runtime_bin/systemctl"
cp /usr/bin/sleep "$work/runtime-dwm"
cp "$work/runtime-dwm" "$prefix/bin/dwm"
# Registered before the child exists, so a failure at any later point still
# kills it; the stack runs last-registered-first, ahead of the workspace removal.
runtime_pid=
# shellcheck disable=SC2016 # expanded when the cleanup runs, not now
cleanup_add 'if [ -n "${runtime_pid:-}" ]; then kill "$runtime_pid" 2>/dev/null || true; fi'
"$work/runtime-dwm" 60 &
runtime_pid=$!
runtime_try=0
while [ "$(readlink "/proc/$runtime_pid/exe" 2>/dev/null || true)" != "$work/runtime-dwm" ]; do
	runtime_try=$((runtime_try + 1))
	[ "$runtime_try" -lt 50 ] || exit 1
	sleep 0.02
done
rm "$work/runtime-dwm"
case $(readlink "/proc/$runtime_pid/exe") in
*" (deleted)") ;;
*) exit 1 ;;
esac
runtime_check() {
	DWM_TEST_DWM_PID="$runtime_pid" PATH="$runtime_bin:$PATH" DISPLAY=:fixture \
		DWM_DEV_SYNC_SKIP_RUNTIME=0 sh -c '
		set -eu
		. "$1"
		prefix=$2
		binary_target=$prefix/bin/dwm
		quickshell_dir=$3
		runtime_verify 0
	' sh "$runtime_probe" "$prefix" "$config_home/quickshell"
}
runtime_check >"$output" 2>&1
grep -Fqx 'Running dwm matches the installed binary.' "$output"
cp /usr/bin/true "$prefix/bin/dwm"
if runtime_check >"$output" 2>&1; then
	printf '%s\n' 'Different running executable unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'running dwm does not match the installed binary' "$output"
rm "$prefix/bin/dwm"
if runtime_check >"$output" 2>&1; then
	printf '%s\n' 'Missing installed executable unexpectedly passed.' >&2
	exit 1
fi
grep -Fq 'running dwm does not match the installed binary' "$output"
kill "$runtime_pid"
wait "$runtime_pid" 2>/dev/null || true
runtime_pid=

printf '%s\n' 'Developer live-install synchronization: PASS'
