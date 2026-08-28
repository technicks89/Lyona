#!/usr/bin/env bash
# Covers scripts/lyona-grub-theme, which selects the GRUB boot-menu theme.
#
# Whether the menu actually renders needs a real boot and cannot be proven
# here. What is checkable is the part that edits a root-owned file the machine
# boots from: which keys are rewritten, that the previous contents survive in
# a backup, that a second run changes nothing, and that a machine without GRUB
# is left completely alone.

set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace

helper="$repo/scripts/lyona-grub-theme"
assert_executable "$helper"
assert_file "$repo/assets/grub/CyberRe/theme.txt" 'the vendored theme'
assert_file "$repo/assets/grub/LICENSE" 'the vendored theme licence'

bin="$work/bin"
cat >"$bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat >"$bin/grub-mkconfig" <<'EOF'
#!/bin/sh
printf 'grub-mkconfig %s\n' "$*" >>"${LYONA_TEST_LOG:?}"
exit "${LYONA_TEST_MKCONFIG_STATUS:-0}"
EOF
chmod +x "$bin"/*

case_count=0

# A fresh case: a themes root holding CyberRe, a /boot/grub, a defaults file
# with the contents given on stdin, and an empty call log.
new_case() {
	local name=$1 dir
	case_count=$((case_count + 1))
	dir="$work/case-$case_count-$name"
	mkdir -p "$dir/themes/CyberRe" "$dir/boot/grub"
	cp "$repo/assets/grub/CyberRe/theme.txt" "$dir/themes/CyberRe/theme.txt"
	cat >"$dir/default-grub"
	: >"$dir/calls.log"
	printf '%s\n' "$dir"
}

# Runs the helper against a case directory, capturing output for assertions.
run_helper() {
	local dir=$1
	shift
	PATH="$bin:$PATH" \
		LYONA_TEST_LOG="$dir/calls.log" \
		LYONA_GRUB_DEFAULTS="$dir/default-grub" \
		LYONA_GRUB_THEME_DIR="$dir/themes" \
		LYONA_GRUB_BOOT_DIR="$dir/boot" \
		"$helper" "$@" >"$dir/out" 2>&1
}

backup_of() {
	find "$1" -maxdepth 1 -name 'default-grub.lyona-backup-*' | head -n 1
}

default_grub_fixture() {
	cat <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"
EOF
}

# ── apply rewrites exactly the three keys a theme needs ──────────────────

case_dir=$(default_grub_fixture | new_case apply)
run_helper "$case_dir" apply || fail 'apply failed on a GRUB machine'

assert_line "$case_dir/default-grub" \
	"GRUB_THEME=\"$case_dir/themes/CyberRe/theme.txt\""

# GRUB draws themes only on gfxterm, so a console output left in place would
# leave the theme installed and invisible. It is commented, not deleted, so
# the previous value stays readable in the file itself.
assert_no_line "$case_dir/default-grub" 'GRUB_TERMINAL_OUTPUT="console"'
assert_contains "$case_dir/default-grub" \
	'# Commented by lyona-grub-theme: GRUB_TERMINAL_OUTPUT="console"'

# The 640x480 fallback would letterbox a 1920x1080 background.
assert_line "$case_dir/default-grub" 'GRUB_GFXMODE="auto"'

# Unrelated keys are the ones a user is most likely to have edited.
assert_line "$case_dir/default-grub" 'GRUB_DEFAULT=0'
assert_line "$case_dir/default-grub" 'GRUB_TIMEOUT=5'
assert_line "$case_dir/default-grub" 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"'

assert_contains "$case_dir/calls.log" "grub-mkconfig -o $case_dir/boot/grub/grub.cfg"

# The backup is what makes the edit reversible, so it must hold the original.
backup=$(backup_of "$case_dir")
[ -n "$backup" ] || fail 'apply did not back up the defaults file'
assert_line "$backup" 'GRUB_TERMINAL_OUTPUT="console"'
assert_no_line "$backup" "GRUB_THEME=\"$case_dir/themes/CyberRe/theme.txt\""

run_helper "$case_dir" status || fail 'status failed after apply'
assert_line "$case_dir/out" "grub-theme: $case_dir/themes/CyberRe/theme.txt"

# ── applying twice is a no-op ────────────────────────────────────────────

before=$(cat "$case_dir/default-grub")
: >"$case_dir/calls.log"
run_helper "$case_dir" apply || fail 'the second apply failed'
assert_equals "$before" "$(cat "$case_dir/default-grub")" \
	'a second apply rewrote the defaults file'
[ ! -s "$case_dir/calls.log" ] ||
	fail 'a second apply regenerated the GRUB configuration for no reason'

# ── remove puts the menu back ────────────────────────────────────────────

run_helper "$case_dir" remove || fail 'remove failed'
assert_no_line "$case_dir/default-grub" \
	"GRUB_THEME=\"$case_dir/themes/CyberRe/theme.txt\""
assert_contains "$case_dir/calls.log" "grub-mkconfig -o $case_dir/boot/grub/grub.cfg"
run_helper "$case_dir" status || fail 'status failed after remove'
assert_line "$case_dir/out" 'grub-theme: none'

# ── an existing GRUB_THEME is replaced, not duplicated ───────────────────

case_dir=$(
	new_case replace <<'EOF'
GRUB_TIMEOUT=5
GRUB_THEME="/usr/share/grub/themes/starfield/theme.txt"
EOF
)
run_helper "$case_dir" apply || fail 'apply failed over an existing theme'
assert_equals 1 \
	"$(grep -c '^GRUB_THEME=' "$case_dir/default-grub")" \
	'apply left more than one active GRUB_THEME assignment'
assert_line "$case_dir/default-grub" \
	"GRUB_THEME=\"$case_dir/themes/CyberRe/theme.txt\""
assert_contains "$case_dir/default-grub" \
	'# Commented by lyona-grub-theme: GRUB_THEME="/usr/share/grub/themes/starfield/theme.txt"'

# ── a GRUB_GFXMODE the user chose is left alone ──────────────────────────

case_dir=$(
	new_case keep-gfxmode <<'EOF'
GRUB_GFXMODE="1280x1024x32"
EOF
)
run_helper "$case_dir" apply || fail 'apply failed with a preset GRUB_GFXMODE'
assert_line "$case_dir/default-grub" 'GRUB_GFXMODE="1280x1024x32"'
assert_no_line "$case_dir/default-grub" 'GRUB_GFXMODE="auto"'

# ── a machine without GRUB is not touched, and does not fail the caller ──
#
# The installer calls apply unconditionally, so a systemd-boot machine has to
# come back successfully rather than aborting an otherwise good install.

case_dir=$(default_grub_fixture | new_case no-grub)
mv "$case_dir/default-grub" "$case_dir/elsewhere"
run_helper "$case_dir" apply || fail 'apply failed on a machine without GRUB'
assert_contains "$case_dir/out" 'No GRUB installation found'
[ ! -s "$case_dir/calls.log" ] || fail 'apply ran grub-mkconfig without GRUB'
assert_no_file "$case_dir/default-grub" 'apply created a defaults file from nothing'

run_helper "$case_dir" status || fail 'status failed on a machine without GRUB'
assert_line "$case_dir/out" 'grub-theme: no-grub'

run_helper "$case_dir" remove || fail 'remove failed on a machine without GRUB'
[ ! -s "$case_dir/calls.log" ] || fail 'remove ran grub-mkconfig without GRUB'

# ── an uninstalled theme is an error, not a broken boot menu ─────────────
#
# Selecting a theme.txt that does not exist gives a menu that silently falls
# back to plain text, so it has to fail loudly instead of being written out.

case_dir=$(default_grub_fixture | new_case missing-theme)
if run_helper "$case_dir" apply Nonexistent; then
	fail 'apply accepted a theme that is not installed'
fi
assert_contains "$case_dir/out" 'is not installed'
assert_no_line "$case_dir/default-grub" 'GRUB_THEME="Nonexistent"'
[ ! -s "$case_dir/calls.log" ] || fail 'apply regenerated GRUB for a missing theme'

# ── a theme name cannot escape the theme root ────────────────────────────
#
# The name becomes a path in a file GRUB parses as root at boot.
for bad in ../../etc/passwd 'a b' '' /abs; do
	case_dir=$(default_grub_fixture | new_case "reject")
	if run_helper "$case_dir" apply "$bad"; then
		fail "apply accepted the unsafe theme name '$bad'"
	fi
	assert_not_contains "$case_dir/default-grub" 'GRUB_THEME='
done

# ── a failed grub-mkconfig is reported ───────────────────────────────────

case_dir=$(default_grub_fixture | new_case mkconfig-fails)
if PATH="$bin:$PATH" LYONA_TEST_MKCONFIG_STATUS=1 \
	LYONA_TEST_LOG="$case_dir/calls.log" \
	LYONA_GRUB_DEFAULTS="$case_dir/default-grub" \
	LYONA_GRUB_THEME_DIR="$case_dir/themes" \
	LYONA_GRUB_BOOT_DIR="$case_dir/boot" \
	"$helper" apply >"$case_dir/out" 2>&1; then
	fail 'apply reported success after grub-mkconfig failed'
fi
assert_contains "$case_dir/out" 'grub-mkconfig failed'
[ -n "$(backup_of "$case_dir")" ] ||
	fail 'a failed apply left no backup to restore from'

# ── list reports what install-grub-theme put on disk ─────────────────────

case_dir=$(default_grub_fixture | new_case list)
run_helper "$case_dir" list || fail 'list failed'
assert_line "$case_dir/out" 'CyberRe'

# ── the installer wiring stays in step with the helper ───────────────────
#
# The theme is meant to be on by default; a silently dropped call or a renamed
# flag would leave that claim in the docs and nowhere else.
assert_contains "$repo/install.sh" 'apply_grub_theme'
assert_contains "$repo/install.sh" 'DWM_INSTALL_GRUB_THEME:-true'
assert_contains "$repo/Makefile" 'install-grub-theme'

# --dry-run resolves the flags without touching anything, so the three modes
# can be asserted against the installer's own summary. An earlier revision had
# --skip-grub-theme setting the mode to true, which the name alone hides.
grub_summary() {
	(cd "$repo" && ./install.sh --dry-run "$@" 2>&1) |
		sed -n 's/^  GRUB theme: //p'
}

assert_string_contains "$(grub_summary --skip-grub-theme)" \
	'bootloader left unchanged' '--skip-grub-theme did not skip the bootloader edit'
assert_string_contains "$(DWM_INSTALL_GRUB_THEME=false grub_summary)" \
	'bootloader left unchanged' 'DWM_INSTALL_GRUB_THEME=false did not skip the bootloader edit'

# The default has to stay on, since that is the whole feature. Both branches
# are forced rather than left to whatever the machine running the tests boots
# with, so the assertion means the same thing everywhere.
case_dir=$(default_grub_fixture | new_case installer-summary)
default_summary=$(LYONA_GRUB_DEFAULTS="$case_dir/default-grub" grub_summary)
assert_string_contains "$default_summary" 'CyberRe' \
	'the GRUB theme is not selected by default on a GRUB machine'

no_grub_summary=$(LYONA_GRUB_DEFAULTS="$case_dir/absent" grub_summary)
assert_string_contains "$no_grub_summary" 'does not boot with GRUB' \
	'the installer did not report a machine without GRUB'
case $no_grub_summary in
*'backed up'*) fail 'the installer offered to edit a bootloader that is not GRUB' ;;
esac

if (cd "$repo" && DWM_INSTALL_GRUB_THEME=maybe ./install.sh --dry-run >/dev/null 2>&1); then
	fail 'the installer accepted a non-boolean DWM_INSTALL_GRUB_THEME'
fi

printf 'test-lyona-grub-theme.sh: ok\n'
