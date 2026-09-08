#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
helper=$repo/scripts/lyona-version
make_workspace

home=$work/home
state_home=$home/.local/state
bin_dir=$work/bin
mkdir -p "$home" "$state_home" "$bin_dir"

system_record=$work/etc-lyona-release
user_record=$state_home/lyona/install.state

run_helper() {
	HOME="$home" XDG_STATE_HOME="$state_home" PATH="$bin_dir:$PATH" \
		DWM_TEST_SYSTEM_RECORD="$system_record" DWM_TEST_SYSTEM_OWNER="$(id -u)" \
		DWM_TEST_USER_RECORD="$user_record" \
		"$helper" "$@"
}

stub_dwm() {
	stub_command dwm <<SH
#!/bin/sh
printf 'dwm-%s\n' "$1" >&2
exit 1
SH
}

write_system_record() {
	mkdir -p "$(dirname -- "$system_record")"
	cat >"$system_record"
	chmod 644 "$system_record"
}

write_user_record() {
	mkdir -p "$(dirname -- "$user_record")"
	cat >"$user_record"
	chmod 600 "$user_record"
}

valid_system_record() {
	cat <<EOF
LYONA_VERSION=$1
LYONA_COMMIT=abc1234
LYONA_SOURCE=iso
LYONA_PREFIX=/usr/local
LYONA_INSTALL_DATE=2026-08-29T14:03:11Z
EOF
}

valid_user_record() {
	cat <<EOF
LYONA_VERSION=$1
LYONA_COMMIT=abc1234
LYONA_SOURCE=iso
LYONA_DATA_DIR=$home/.local/share/lyona
LYONA_CONFIG_DIR=$home/.config
LYONA_SOURCE_TREE=$home/.local/share/lyona
LYONA_INSTALL_DATE=2026-08-29T14:03:11Z
EOF
}

stub_dwm 2026.08.0-beta.1

# ── No records ───────────────────────────────────────────────────────────
status=$(run_helper status)
assert_string_contains "$status" "$(printf 'state\tdefaults')"
run_helper status >/dev/null
assert_no_file "$system_record"
assert_no_file "$user_record"

# ── print, no records ───────────────────────────────────────────────────
printed=$(run_helper print)
assert_equals unknown "$printed" "print with no records"

# ── Both records, agreeing with each other and the binary ──────────────
valid_system_record 2026.08.0-beta.1 | write_system_record
valid_user_record 2026.08.0-beta.1 | write_user_record
status=$(run_helper status)
assert_string_contains "$status" "$(printf 'state\tavailable')"
assert_string_contains "$status" "$(printf 'consistent\tyes')"
printed=$(run_helper print)
assert_equals 2026.08.0-beta.1 "$printed" "print with agreeing records"

# ── System only (user record absent) ────────────────────────────────────
rm -f "$user_record"
status=$(run_helper status)
assert_string_contains "$status" "$(printf 'state\tpartial')"
assert_string_contains "$status" "$(printf 'user\tnone\tnone\tnone\tnone\tnone')"
valid_user_record 2026.08.0-beta.1 | write_user_record

# ── Version mismatch, system vs. user ───────────────────────────────────
valid_user_record 2026.09.0-beta.1 | write_user_record
status=$(run_helper status)
assert_string_contains "$status" "$(printf 'consistent\tno')"
assert_string_contains "$status" "$(printf 'system\t2026.08.0-beta.1')"
assert_string_contains "$status" "$(printf 'user\t2026.09.0-beta.1')"
valid_user_record 2026.08.0-beta.1 | write_user_record

# ── Binary mismatch (the half-applied-install case) ─────────────────────
stub_dwm 2026.09.0-beta.1
status=$(run_helper status)
assert_string_contains "$status" "$(printf 'consistent\tno')"
assert_string_contains "$status" "$(printf 'binary\t2026.09.0-beta.1')"
stub_dwm 2026.08.0-beta.1

# ── Malformed record: unavailable, file preserved byte-for-byte ────────
printf 'not a valid record\n' >"$system_record"
chmod 644 "$system_record"
before=$(cat "$system_record")
status=$(run_helper status)
assert_string_contains "$status" "$(printf 'state\tunavailable')"
after=$(cat "$system_record")
assert_equals "$before" "$after" "malformed record was rewritten"
valid_system_record 2026.08.0-beta.1 | write_system_record

# ── Symlinked record: unavailable, target never read or written ────────
target=$work/symlink-target
valid_user_record 2026.08.0-beta.1 | write_user_record
cp -a "$user_record" "$target"
before_target=$(cat "$target")
rm -f "$user_record"
ln -s "$target" "$user_record"
status=$(run_helper status)
assert_string_contains "$status" "$(printf 'user\tnone\tnone\tnone\tnone\tnone')"
after_target=$(cat "$target")
assert_equals "$before_target" "$after_target" "symlink target content changed"
rm -f "$user_record"
valid_user_record 2026.08.0-beta.1 | write_user_record

# ── World-writable record: unavailable ──────────────────────────────────
chmod 666 "$user_record"
status=$(run_helper status)
assert_string_contains "$status" "$(printf 'state\tunavailable')"
chmod 600 "$user_record"

# ── --json: valid JSON with the same values as the tab-separated form ──
json=$(run_helper status --json)
case $json in
'{'*'}') ;;
*) fail "--json output is not a single JSON object: $json" ;;
esac
assert_string_contains "$json" '"state":"available"'
assert_string_contains "$json" '"consistent":true'
assert_string_contains "$json" '"version":"2026.08.0-beta.1"'

printf 'lyona-version contract: PASS\n'
