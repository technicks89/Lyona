#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
helper=$repo/scripts/lyona-update
make_workspace

home=$work/home
config_home=$home/.config
data_home=$home/.local/share
state_home=$home/.local/state
cache_home=$home/.cache
bin_dir=$work/bin
responses_dir=$work/curl-responses
system_record=$work/etc-lyona-release
user_record=$state_home/lyona/install.state

mkdir -p "$home" "$config_home" "$data_home" "$state_home" "$cache_home" \
	"$bin_dir" "$responses_dir"

github_api=https://stub.invalid
github_repo=test/lyona

run_update() {
	HOME="$home" PATH="$bin_dir:$PATH" \
		XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$data_home" \
		XDG_STATE_HOME="$state_home" XDG_CACHE_HOME="$cache_home" \
		DWM_TEST_SYSTEM_RECORD="$system_record" DWM_TEST_SYSTEM_OWNER="$(id -u)" \
		DWM_TEST_USER_RECORD="$user_record" \
		LYONA_UPDATE_GITHUB_API="$github_api" LYONA_UPDATE_GITHUB_REPO="$github_repo" \
		LYONA_UPDATE_CACHE_TTL="${LYONA_UPDATE_CACHE_TTL:-300}" \
		"$helper" "$@"
}

write_user_record() {
	mkdir -p "$(dirname -- "$user_record")"
	cat >"$user_record"
	chmod 600 "$user_record"
}

valid_user_record() {
	version=$1
	source_kind=${2:-tarball}
	cat <<EOF
LYONA_VERSION=$version
LYONA_COMMIT=b85539b
LYONA_SOURCE=$source_kind
LYONA_DATA_DIR=$data_home/lyona
LYONA_CONFIG_DIR=$config_home
LYONA_SOURCE_TREE=$data_home/lyona
LYONA_INSTALL_DATE=2026-08-29T14:03:11Z
EOF
}

reset_curl_responses() {
	rm -rf "$responses_dir"
	mkdir -p "$responses_dir"
	rm -f "$responses_dir/../offline-flag" 2>/dev/null || :
	# Each scenario seeds its own release fixture; a cache hit -- or a
	# channel left over from the config-seeding scenario -- would otherwise
	# skip the network, or hit an endpoint this scenario never seeded.
	rm -rf "$cache_home/lyona" "$config_home/lyona"
}

# A curl stub good enough for lyona-update's own uses: reads a canned
# response body for the requested URL from $responses_dir, keyed by turning
# the URL into a safe filename. Serves --output requests and plain stdout
# alike, since lyona-update uses both.
stub_curl() {
	stub_command curl <<'SH'
#!/bin/sh
url=
output=
prev=
for a in "$@"; do
	case $prev in --output) output=$a ;; esac
	case $a in http*://*) url=$a ;; esac
	prev=$a
done
[ ! -e "__RESPONSES__/../offline-flag" ] || exit 7
key=$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')
resp="__RESPONSES__/$key"
if [ ! -f "$resp" ]; then
	printf 'curl-stub: no canned response for %s\n' "$url" >&2
	exit 22
fi
if [ -n "$output" ]; then
	cp "$resp" "$output"
else
	cat "$resp"
fi
SH
	sed -i "s|__RESPONSES__|$responses_dir|g" "$bin_dir/curl"
}

canned_response() {
	key=$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')
	cat >"$responses_dir/$key"
}

go_offline() {
	: >"$responses_dir/../offline-flag"
}

go_online() {
	rm -f "$responses_dir/../offline-flag"
}

# Seeds a stable release (default channel) with the given version, asset
# checksum and tag commit, reachable through the stub curl.
seed_release() {
	version=$1
	checksum=${2:-3f9cabc00000000000000000000000000000000000000000000000000000a1}
	sha=${3:-f4a2c8199999999999999999999999999999999}
	asset_url="$github_api/assets/lyona-$version.tar.gz"
	sums_url="$github_api/assets/lyona-$version-SHA256SUMS"
	canned_response "$github_api/repos/$github_repo/releases/latest" <<EOF
{"tag_name":"v$version","published_at":"2026-09-14T09:22:07Z",
 "assets":[
   {"name":"lyona-$version.tar.gz","browser_download_url":"$asset_url","size":4718592},
   {"name":"lyona-$version-SHA256SUMS","browser_download_url":"$sums_url","size":128}
 ]}
EOF
	canned_response "$github_api/repos/$github_repo/git/ref/tags/v$version" <<EOF
{"object":{"sha":"$sha"}}
EOF
	canned_response "$sums_url" <<EOF
$checksum  release/lyona-$version.tar.gz
EOF
	canned_response "$asset_url" <<'EOF'
not a real tarball, only used where the checksum itself is under test
EOF
}

stub_curl
reset_curl_responses

# ── check: installed matches the channel ────────────────────────────────
valid_user_record 2026.09.0 | write_user_record
seed_release 2026.09.0
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\tcurrent')"

# ── check: installed is older ───────────────────────────────────────────
reset_curl_responses
valid_user_record 2026.08.0 | write_user_record
seed_release 2026.09.0
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\tbehind')"
assert_string_contains "$status" "$(printf 'available\t2026.09.0')"

# ── check: installed is newer (dev checkout ahead of any release) ──────
reset_curl_responses
valid_user_record 2026.10.0 checkout | write_user_record
seed_release 2026.09.0
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\tahead')"

# ── check: installed is a real release newer than the channel offers ───
reset_curl_responses
valid_user_record 2026.10.0 tarball | write_user_record
seed_release 2026.09.0
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\tdowngrade-offered')"

# ── check: no provenance record ─────────────────────────────────────────
reset_curl_responses
rm -f "$user_record"
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\tunknown')"

# ── check: network unreachable ──────────────────────────────────────────
reset_curl_responses
valid_user_record 2026.08.0 | write_user_record
seed_release 2026.09.0
go_offline
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\toffline')"
assert_string_contains "$status" "$(printf 'installed\t2026.08.0')"
go_online

# ── check --channel preview: a pre-release the stable channel skipped ──
reset_curl_responses
valid_user_record 2026.09.0 | write_user_record
canned_response "$github_api/repos/$github_repo/releases" <<'EOF'
[{"tag_name":"v2026.10.0-beta.1","published_at":"2026-09-20T00:00:00Z",
  "assets":[{"name":"lyona-2026.10.0-beta.1.tar.gz","browser_download_url":"https://stub.invalid/assets/x.tar.gz","size":1}]}]
EOF
status=$(run_update check --channel preview)
assert_string_contains "$status" "$(printf 'state\tbehind')"
assert_string_contains "$status" "$(printf 'available\t2026.10.0-beta.1')"

# ── Version ordering: release > patch > base > rc > beta > alpha ───────
reset_curl_responses
for pair in \
	'2026.08.0:2026.09.0:behind' \
	'2026.08.0:2026.08.1:behind' \
	'2026.08.0-rc.1:2026.08.0:behind' \
	'2026.08.0-beta.2:2026.08.0-rc.1:behind' \
	'2026.08.0-beta.1:2026.08.0-beta.2:behind' \
	'2026.08.0-alpha.1:2026.08.0-beta.1:behind'; do
	installed=${pair%%:*}
	rest=${pair#*:}
	available=${rest%%:*}
	expected=${rest#*:}
	reset_curl_responses
	valid_user_record "$installed" | write_user_record
	seed_release "$available"
	status=$(run_update check)
	assert_string_contains "$status" "$(printf 'state\t%s' "$expected")" \
		"$installed vs $available"
done

# ── check: config seeded on first use, never overwritten ───────────────
reset_curl_responses
valid_user_record 2026.09.0 | write_user_record
seed_release 2026.09.0
rm -f "$config_home/lyona/update.conf"
run_update check >/dev/null
assert_file "$config_home/lyona/update.conf"
assert_contains "$config_home/lyona/update.conf" 'channel=stable'
printf 'channel=preview\ncheck_on_login=true\nauto_apply=false\nkeep_backups=5\n' \
	>"$config_home/lyona/update.conf"
run_update check >/dev/null
assert_contains "$config_home/lyona/update.conf" 'channel=preview'

# ── apply: checksum mismatch aborts before unpacking ────────────────────
reset_curl_responses
valid_user_record 2026.08.0 | write_user_record
seed_release 2026.09.0 deadbeef00000000000000000000000000000000000000000000000000dead
if run_update apply --version 2026.09.0 --yes >"$work/out" 2>&1; then
	fail "checksum-mismatched apply unexpectedly succeeded"
fi
assert_contains "$work/out" 'checksum mismatch'
assert_no_file "$state_home/lyona/updates/2026.09.0"

# ── apply --file: unverifiable tarball is refused outright ─────────────
reset_curl_responses
valid_user_record 2026.08.0 | write_user_record
go_offline
printf 'not a tarball\n' >"$work/local.tar.gz"
if run_update apply --file "$work/local.tar.gz" --version 2026.09.0 --yes \
	>"$work/out" 2>&1; then
	fail "unverified --file apply unexpectedly succeeded"
fi
assert_contains "$work/out" 'refusing to install an unverified tarball'
go_online

# ── apply: downgrade refused without --allow-downgrade ─────────────────
reset_curl_responses
valid_user_record 2026.09.0 | write_user_record
if run_update apply --from-checkout "$repo" --dry-run >"$work/out" 2>&1; then
	fail "downgrade apply unexpectedly succeeded without --allow-downgrade"
fi
assert_contains "$work/out" 'pass --allow-downgrade to proceed'

# ── apply --dry-run: lists privileged paths, installs nothing ──────────
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
status=$(run_update apply --from-checkout "$repo" --allow-downgrade --dry-run)
assert_string_contains "$status" 'would back up the live install'
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
assert_no_file "$state_home/lyona/live-update-backups"

# ── apply: build failure exits before any privileged call ──────────────
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
broken_checkout=$work/broken-checkout
rm -rf "$broken_checkout"
cp -a "$repo" "$broken_checkout"
rm -rf "$broken_checkout/.git"
printf 'this is not valid C\n' >"$broken_checkout/dwm.c"
if run_update apply --from-checkout "$broken_checkout" --allow-downgrade --yes \
	>"$work/out" 2>&1; then
	fail "apply with a broken build unexpectedly succeeded"
fi
assert_contains "$work/out" 'build failed'
assert_no_file "$state_home/lyona/live-update-backups"

# ── apply: privileged step unavailable leaves the staged update in place,
#    live install untouched, non-zero exit (no root helper exists here) ─
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
if run_update apply --from-checkout "$repo" --allow-downgrade --yes \
	>"$work/out" 2>&1; then
	fail "apply unexpectedly succeeded with no privileged helper installed"
fi
assert_contains "$work/out" 'privileged'
assert_dir "$state_home/lyona/live-update-backups"

# ── backups: none yet ────────────────────────────────────────────────
reset_curl_responses
rm -rf "$state_home/lyona/live-update-backups"
status=$(run_update backups)
assert_string_contains "$status" "$(printf 'complete\tbackups')"
json=$(run_update backups --json)
assert_equals '[]' "$json" "empty backups --json"

# ── rollback: no backups available ──────────────────────────────────────
if run_update rollback >"$work/out" 2>&1; then
	fail "rollback with no backups unexpectedly succeeded"
fi
assert_contains "$work/out" 'no backups are available'

# ── rollback --list: newest first, with version and date ───────────────
backups_root=$state_home/lyona/live-update-backups
rm -rf "$backups_root"
mkdir -p "$backups_root/20260101T000000Z-1" "$backups_root/20260301T000000Z-2"
printf 'version=2026.01.0\n' >"$backups_root/20260101T000000Z-1/checkout.txt"
printf 'version=2026.03.0\n' >"$backups_root/20260301T000000Z-2/checkout.txt"
status=$(run_update rollback --list)
newest_line=$(printf '%s\n' "$status" | grep '^backup' | head -n1)
assert_string_contains "$newest_line" '20260301T000000Z-2'
assert_string_contains "$newest_line" '2026.03.0'

# ── rollback: checksum mismatch restores nothing ────────────────────────
backup_dir=$backups_root/20260301T000000Z-2
printf 'v1\n' >"$backup_dir/quickshell.tar"
printf 'deadbeef00000000000000000000000000000000000000000000000000dead  %s\n' \
	"$backup_dir/quickshell.tar" >"$backup_dir/SHA256SUMS"
if run_update rollback --backup 20260301T000000Z-2 --yes >"$work/out" 2>&1; then
	fail "rollback with a bad checksum manifest unexpectedly succeeded"
fi
assert_contains "$work/out" 'checksum'

# ── rollback: prefix mismatch refuses rather than restoring blind ──────
backup_dir2=$backups_root/20260101T000000Z-1
printf 'v1\n' >"$backup_dir2/quickshell.tar"
sha256sum "$backup_dir2/quickshell.tar" >"$backup_dir2/SHA256SUMS"
printf 'prefix=/some/other/prefix\nconfig_home=/some/other/config\nxdg_data_home=/some/other/data\n' \
	>"$backup_dir2/checkout.txt"
if PREFIX=/usr/local run_update rollback --backup 20260101T000000Z-1 --yes \
	>"$work/out" 2>&1; then
	fail "rollback into a mismatched environment unexpectedly succeeded"
fi
assert_contains "$work/out" 'different environment'

# ── --help / usage ───────────────────────────────────────────────────────
status=$(run_update --help)
assert_string_contains "$status" 'Usage: lyona-update'
if run_update bogus-command >"$work/out" 2>&1; then
	fail "unknown subcommand unexpectedly succeeded"
fi
assert_contains "$work/out" 'Usage: lyona-update'

printf 'lyona-update contract: PASS\n'
