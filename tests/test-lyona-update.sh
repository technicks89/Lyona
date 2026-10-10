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

# A real notify-send would pop up notifications on the machine running the
# tests, so it is always a stub here.
notify_log=$work/notify.log
: >"$notify_log"
stub_command notify-send <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${DWM_TEST_NOTIFY_LOG:?}"
SH

github_api=https://stub.invalid
github_repo=test/lyona

run_update() {
	HOME="$home" PATH="$bin_dir:$PATH" \
		XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$data_home" \
		XDG_STATE_HOME="$state_home" XDG_CACHE_HOME="$cache_home" \
		DWM_TEST_SYSTEM_RECORD="$system_record" DWM_TEST_SYSTEM_OWNER="$(id -u)" \
		DWM_TEST_USER_RECORD="$user_record" DWM_TEST_NOTIFY_LOG="$notify_log" \
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
	rm -f "$responses_dir/../offline-flag" "$responses_dir/../http-error" 2>/dev/null || :
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
# An HTTP error for every request, as curl --fail reports one.
if [ -f "__RESPONSES__/../http-error" ]; then
	printf 'curl: (22) The requested URL returned error: %s\n' "$(cat "__RESPONSES__/../http-error")" >&2
	exit 22
fi
key=$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')
resp="__RESPONSES__/$key"
if [ ! -f "$resp" ]; then
	# What GitHub answers for a release that does not exist.
	printf 'curl: (22) The requested URL returned error: 404\n' >&2
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

# A cosign stub (decision D-31): a bundle verifies when it reads
# "good-signature", the identity is exactly the release workflow's on main, and
# the file exists. Each call's arguments are logged.
cosign_log=$work/cosign.log
signer=https://github.com/$github_repo/.github/workflows/build-iso.yml@refs/heads/main
stub_command cosign <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>__LOG__
bundle= identity= prev= file=
for a in "$@"; do
	case $prev in
	--bundle) bundle=$a ;;
	--certificate-identity) identity=$a ;;
	esac
	prev=$a
	file=$a
done
if [ "$(cat "$bundle" 2>/dev/null)" = good-signature ] && [ "$identity" = __SIGNER__ ] && [ -f "$file" ]; then
	printf 'Verified OK\n' >&2
	exit 0
fi
printf 'Error: none of the expected identities matched what was in the certificate\n' >&2
exit 1
SH
sed -i -e "s|__LOG__|$cosign_log|" -e "s|__SIGNER__|$signer|" "$bin_dir/cosign"

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
	bundle_url="$github_api/assets/lyona-$version.sigstore.json"
	canned_response "$github_api/repos/$github_repo/releases/latest" <<EOF
{"tag_name":"v$version","published_at":"2026-09-14T09:22:07Z",
 "assets":[
   {"name":"lyona-$version.tar.gz","browser_download_url":"$asset_url","size":4718592},
   {"name":"lyona-$version-SHA256SUMS","browser_download_url":"$sums_url","size":128},
   {"name":"lyona-$version.sigstore.json","browser_download_url":"$bundle_url","size":9000}
 ]}
EOF
	printf 'good-signature\n' | canned_response "$bundle_url"
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

# The real release asset, from the release target (Sync Sprint 12 S12-19),
# installed with `apply --file` the way a published release is. Built once;
# apply_source re-seeds the stubbed release with its checksum, since each case
# resets the canned responses. The archive goes to the workspace, not the
# checkout's release/.
make_source_tarball() { # TREE OUT
	make -s -C "$1" release RELEASE_ARCHIVE="$2" >/dev/null
}
source_version=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$repo/config.mk")
source_tarball=$work/lyona-source.tar.gz
make_source_tarball "$repo" "$source_tarball"
source_sha=$(sha256sum "$source_tarball" | awk '{ print $1 }')
apply_source() {
	seed_release "$source_version" "$source_sha"
	run_update apply --file "$source_tarball" --version "$source_version" "$@"
}

stub_curl
reset_curl_responses

# pacman -T (deptest) prints the arguments that are not installed. Here "not
# installed" is whatever the test lists in pacman-missing; empty by default.
stub_command pacman <<SH
#!/bin/sh
[ "\$1" = -T ] || exit 1
[ ! -e "$work/pacman-fails" ] || exit 1
shift
status=0
for package in "\$@"; do
	if grep -Fqx -- "\$package" "$work/pacman-missing" 2>/dev/null; then
		printf '%s\n' "\$package"
		status=127
	fi
done
exit \$status
SH
: >"$work/pacman-missing"

# ── check: installed matches the channel ────────────────────────────────
valid_user_record 2026.09.0 | write_user_record
seed_release 2026.09.0
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\tcurrent')"
# The developer override is reported only while it is set (Sync Sprint 12 S12-13).
case $status in
*override*)
	printf 'check reported an override that is not set:\n%s\n' "$status" >&2
	exit 1
	;;
esac
[ "$(run_update check --json | jq -r .devScripts)" = null ]
status=$(LYONA_DEV_SCRIPTS="$work/checkout/scripts" run_update check)
assert_string_contains "$status" "$(printf 'override\tdev-scripts\t%s' "$work/checkout/scripts")"
assert_equals "$work/checkout/scripts" \
	"$(LYONA_DEV_SCRIPTS="$work/checkout/scripts" run_update check --json | jq -r .devScripts)"

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
	# The stable channel's fixture, whatever channel a pre-release install
	# would seed (R16-02): this loop is about version order.
	status=$(run_update check --channel stable)
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

# ── check: a channel with nothing published is not "offline" (R16-02) ──
# The stable channel answers 404 (curl --fail exits 22) while every release is
# a pre-release: unknown, saying how to switch, not a network failure.
reset_curl_responses
valid_user_record 2026.10.0-beta.1 | write_user_record
printf 'channel=stable\ncheck_on_login=true\nauto_apply=false\nkeep_backups=5\n' |
	install -Dm600 /dev/stdin "$config_home/lyona/update.conf"
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\tunknown')"
assert_string_contains "$status" 'Nothing has been published on the stable channel yet.'
assert_string_contains "$status" 'lyona-update set-channel preview'
# An empty preview channel says so too, without the stable-only hint.
canned_response "$github_api/repos/$github_repo/releases" <<'EOF'
[]
EOF
status=$(run_update check --channel preview)
assert_string_contains "$status" "$(printf 'state\tunknown')"
assert_string_contains "$status" 'Nothing has been published on the preview channel yet.'
case $status in
*set-channel*) fail 'the preview channel suggested switching to preview' ;;
esac
# A real network failure is still offline.
go_offline
status=$(run_update check)
assert_string_contains "$status" "$(printf 'state\toffline')"
go_online
# Only a 404 means nothing is published: a rate limit's 403, or a server
# error, is a failed fetch, never "nothing published".
for http_status in 403 500; do
	printf '%s\n' "$http_status" >"$responses_dir/../http-error"
	status=$(run_update check)
	assert_string_contains "$status" "$(printf 'state\toffline')" "HTTP $http_status"
	case $status in
	*'Nothing has been published'*) fail "HTTP $http_status was read as nothing published" ;;
	esac
done
rm -f "$responses_dir/../http-error"
go_online
# A pre-release install seeds the preview channel on first use.
reset_curl_responses
valid_user_record 2026.10.0-beta.1 | write_user_record
run_update check >/dev/null || :
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

# ── apply: the checksum is the asset's own line, by exact file name ────
# A look-alike name listed first (the "." of the version used to match any
# character, and the match was unanchored) must not be taken for the asset.
reset_curl_responses
valid_user_record 2026.08.0 | write_user_record
seed_release 2026.09.0
asset_sha=$(printf '%s\n' 'not a real tarball, only used where the checksum itself is under test' |
	sha256sum | awk '{ print $1 }')
canned_response "$sums_url" <<EOF
deadbeef00000000000000000000000000000000000000000000000000dead  /build/release/xlyona-2026a09.0.tar.gz
$asset_sha  /build/release/lyona-2026.09.0.tar.gz
EOF
if run_update apply --version 2026.09.0 --yes >"$work/out" 2>&1; then
	fail "apply of a stub tarball unexpectedly succeeded"
fi
if grep -Fq 'checksum mismatch' "$work/out"; then
	lyona_show_file "$work/out"
	fail 'the checksum of a look-alike file name was used'
fi
assert_contains "$work/out" 'failed to unpack'

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

# ── apply --file --sha256: an install with no network (S12-11) ─────────
# The tarball's checksum given on the command line: nothing is looked up.
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
status=$(run_update apply --file "$source_tarball" --version "$source_version" \
	--sha256 "$source_sha" --dry-run 2>"$work/err") || {
	lyona_show_file "$work/err"
	fail 'an offline --file apply with --sha256 failed'
}
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
# The checksum the user gave stands in for the signature, which needs the network.
assert_contains "$work/err" "not checking the signature: --sha256 vouches for $source_tarball"

# #325: the layout comes from /etc/lyona-release, the record install-system
# wrote, as for the root helper; it used to be PREFIX's default, /usr/local.
# shellcheck disable=SC2016 # a line that must be read as text, never run
printf '%s\n' 'LYONA_VERSION=0000.00.0' 'LYONA_PREFIX=/opt/lyona' 'LYONA_MANPREFIX=/opt/lyona/man' \
	'LYONA_DATADIR=/opt/lyona/data' 'LYONA_XSESSIONSDIR=/opt/lyona/xsessions' 'LYONA_EVIL=$(touch x)' \
	>"$system_record"
status=$(run_update apply --file "$source_tarball" --version "$source_version" \
	--sha256 "$source_sha" --dry-run 2>"$work/err") || {
	lyona_show_file "$work/err"
	fail 'a dry run with a recorded layout failed'
}
for line in '  /opt/lyona/bin (system commands and dwm)' '  /opt/lyona/data (cursor and GTK themes)' \
	'  /opt/lyona/man/man1/dwm.1' '  /opt/lyona/xsessions/dwm.desktop'; do
	assert_string_contains "$status" "$line"
done
rm -f "$system_record"
rm -rf "$state_home/lyona/updates/$source_version"
if run_update apply --file "$source_tarball" --version "$source_version" --yes \
	--sha256 "$(printf '%064d' 0)" >"$work/out" 2>&1; then
	fail 'an offline --file apply with the wrong --sha256 succeeded'
fi
assert_contains "$work/out" 'checksum mismatch'
if run_update apply --version "$source_version" --sha256 "$source_sha" --yes >"$work/out" 2>&1; then
	fail '--sha256 without --file was accepted'
fi
assert_contains "$work/out" '--sha256 is for --file'
# The hint for an unreachable server names the option that works offline.
if run_update apply --yes >"$work/out" 2>&1; then
	fail 'an apply with no server and no --file succeeded'
fi
assert_contains "$work/out" '--sha256 HASH'
go_online

# ── apply: the release's signature (decision D-31) ─────────────────────
# A download: the tarball, then its bundle, checked by cosign against the
# release workflow's identity before anything is unpacked.
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
seed_release "$source_version" "$source_sha"
cp "$source_tarball" "$responses_dir/$(printf '%s' "$asset_url" | tr -c 'A-Za-z0-9' '_')"
: >"$cosign_log"
status=$(run_update apply --version "$source_version" --dry-run 2>"$work/err") || {
	lyona_show_file "$work/err"
	fail 'a signed release did not install'
}
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
assert_contains "$work/err" 'verifying signature'
assert_contains "$cosign_log" "--certificate-identity $signer"
assert_contains "$cosign_log" '--certificate-oidc-issuer https://token.actions.githubusercontent.com'
assert_contains "$cosign_log" "$state_home/lyona/updates/lyona-$source_version.tar.gz"
rm -rf "$state_home/lyona/updates/$source_version"
# A forged bundle: refused before the release is unpacked or built.
printf 'forged\n' | canned_response "$bundle_url"
rm -rf "$cache_home/lyona"
if run_update apply --file "$source_tarball" --version "$source_version" --dry-run >"$work/out" 2>&1; then
	fail 'a release with a forged signature was installed'
fi
assert_contains "$work/out" "the signature of lyona-$source_version does not verify"
assert_contains "$work/out" 'none of the expected identities matched'
assert_no_file "$state_home/lyona/updates/$source_version"
# No bundle published: refused, never installed on its checksum alone.
reset_curl_responses
seed_release "$source_version" "$source_sha"
canned_response "$github_api/repos/$github_repo/releases/latest" <<EOF
{"tag_name":"v$source_version","published_at":"2026-09-14T09:22:07Z",
 "assets":[
   {"name":"lyona-$source_version.tar.gz","browser_download_url":"$asset_url","size":4718592},
   {"name":"lyona-$source_version-SHA256SUMS","browser_download_url":"$sums_url","size":128}
 ]}
EOF
if run_update apply --file "$source_tarball" --version "$source_version" --dry-run >"$work/out" 2>&1; then
	fail 'a release without a signature was installed'
fi
assert_contains "$work/out" "release $source_version has no signature"
# --bundle: the signature given with the tarball, nothing downloaded for it.
reset_curl_responses
seed_release "$source_version" "$source_sha"
rm -f "$responses_dir/$(printf '%s' "$bundle_url" | tr -c 'A-Za-z0-9' '_')"
printf 'good-signature\n' >"$work/given.sigstore.json"
status=$(run_update apply --file "$source_tarball" --version "$source_version" \
	--bundle "$work/given.sigstore.json" --dry-run 2>"$work/err") || {
	lyona_show_file "$work/err"
	fail 'an apply with --bundle failed'
}
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
assert_contains "$cosign_log" "--bundle $work/given.sigstore.json"
rm -rf "$state_home/lyona/updates/$source_version"
# --bundle with --sha256: both are checked, the signature too.
: >"$cosign_log"
status=$(run_update apply --file "$source_tarball" --version "$source_version" \
	--bundle "$work/given.sigstore.json" --sha256 "$source_sha" --dry-run 2>"$work/err") || {
	lyona_show_file "$work/err"
	fail 'an apply with --bundle and --sha256 failed'
}
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
assert_contains "$cosign_log" "--bundle $work/given.sigstore.json"
rm -rf "$state_home/lyona/updates/$source_version"
printf 'forged\n' >"$work/forged.sigstore.json"
if run_update apply --file "$source_tarball" --version "$source_version" \
	--bundle "$work/forged.sigstore.json" --sha256 "$source_sha" --dry-run >"$work/out" 2>&1; then
	fail 'a forged --bundle was accepted because --sha256 was given'
fi
assert_contains "$work/out" "the signature of lyona-$source_version does not verify"
for refused in \
	"--bundle $work/given.sigstore.json --version $source_version:--bundle is for --file" \
	"--file $source_tarball --version $source_version --bundle $work/missing.json:signature bundle not found"; do
	# shellcheck disable=SC2086 # the arguments are split on purpose
	if run_update apply ${refused%%:*} --dry-run >"$work/out" 2>&1; then
		fail "apply ${refused%%:*} was accepted"
	fi
	assert_contains "$work/out" "${refused#*:}"
done
# A release from before signing is installed on its checksum, and says so.
reset_curl_responses
valid_user_record 2026.08.0 | write_user_record
seed_release 2026.09.0 "$asset_sha"
: >"$cosign_log"
run_update apply --version 2026.09.0 --yes >"$work/out" 2>&1 || :
assert_contains "$work/out" '2026.09.0 was released before releases were signed'
[ ! -s "$cosign_log" ] || fail 'a release from before signing was checked for a signature'
# Without cosign, a signed release is refused, and the message says how to get
# it. Only where the machine has no cosign of its own.
if ! command -v cosign >/dev/null 2>&1; then
	reset_curl_responses
	valid_user_record 0000.00.0 | write_user_record
	mv "$bin_dir/cosign" "$work/cosign.off"
	if apply_source --dry-run >"$work/out" 2>&1; then
		fail 'a signed release was installed without cosign'
	fi
	mv "$work/cosign.off" "$bin_dir/cosign"
	assert_contains "$work/out" 'sudo pacman -S cosign'
fi

# ── apply --file: builds with the user's own config.h (S12-02, D-18) ───
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
mkdir -p "$config_home/lyona"
{
	cat "$repo/config.def.h"
	printf '/* lyona-test: the user config.h */\n'
} >"$config_home/lyona/config.h"
status=$(apply_source --dry-run 2>"$work/err")
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
assert_contains "$work/err" "building with compile-time options from $config_home/lyona/config.h"
assert_equals "$(cat "$config_home/lyona/config.h")" \
	"$(cat "$state_home/lyona/updates/$source_version/config.h")" "the staged build uses the user's config.h"
staged_tarball=$state_home/lyona/updates/lyona-$source_version.tar.gz
cmp -s "$source_tarball" "$staged_tarball" || fail '--file did not stage the source archive'
staged_inode=$(stat -c %i "$staged_tarball")
status=$(run_update apply --file "$staged_tarball" --version "$source_version" --dry-run)
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
assert_equals "$staged_inode" "$(stat -c %i "$staged_tarball")" \
	"an already staged --file archive was not copied again"
rm -f "$config_home/lyona/config.h"
rm -rf "$state_home/lyona/updates/$source_version"

# ── apply: the release's required packages are checked first (S12-11) ─
# From the release's own package map. A missing required package stops the
# update before anything is built or installed, and says how to install it.
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
printf 'xdotool\n' >"$work/pacman-missing"
if apply_source --dry-run >"$work/out" 2>&1; then
	fail 'an update with a missing required package went ahead'
fi
assert_contains "$work/out" 'needs packages that are not installed: xdotool'
assert_contains "$work/out" 'sudo pacman -S --needed xdotool'
if grep -Fq "building $source_version" "$work/out"; then
	fail 'the release was built despite a missing required package'
fi
# A missing desktop package only warns.
printf 'picom\n' >"$work/pacman-missing"
status=$(apply_source --dry-run 2>"$work/err") || {
	lyona_show_file "$work/err"
	fail 'a missing desktop package blocked the update'
}
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
assert_contains "$work/err" 'desktop packages not installed (features that use them stay unavailable): picom'
: >"$work/pacman-missing"
# A failed query is an error, never read as "nothing is missing".
: >"$work/pacman-fails"
if apply_source --dry-run >"$work/out" 2>&1; then
	fail 'an update went ahead although pacman -T failed'
fi
assert_contains "$work/out" 'could not check which packages are installed'
rm -f "$work/pacman-fails"
rm -rf "$state_home/lyona/updates/$source_version"

# ── apply --from-checkout: removed, and says what to use instead ───────
reset_curl_responses
if run_update apply --from-checkout "$repo" --dry-run >"$work/out" 2>&1; then
	fail "apply --from-checkout unexpectedly succeeded"
fi
assert_contains "$work/out" '--from-checkout was removed'
assert_contains "$work/out" 'sudo make install-system'

# ── apply: downgrade refused without --allow-downgrade ─────────────────
# Installed is newer than any config.mk VERSION the source can carry, so this
# stays a downgrade whatever the release being cut.
reset_curl_responses
valid_user_record 2099.01.0 | write_user_record
if apply_source --dry-run >"$work/out" 2>&1; then
	fail "downgrade apply unexpectedly succeeded without --allow-downgrade"
fi
assert_contains "$work/out" 'pass --allow-downgrade to proceed'
# #327: an older release goes through install-downgrade, which verifies its
# signature: one vouched for by --sha256 alone is refused, before any build.
if apply_source --allow-downgrade --sha256 "$source_sha" --dry-run >"$work/out" 2>&1; then
	fail "an unverified downgrade was accepted"
fi
assert_contains "$work/out" 'an older release is installed only with its signature checked'
assert_not_contains "$work/out" "building $source_version"

# ── apply --dry-run: lists privileged paths, installs nothing ──────────
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
status=$(apply_source --allow-downgrade --dry-run)
assert_string_contains "$status" 'would back up the live install'
assert_string_contains "$status" "$(printf 'complete\tapply-dry-run')"
assert_no_file "$state_home/lyona/live-update-backups"

# ── apply: build failure exits before any privileged call ──────────────
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
broken_checkout=$work/broken-checkout
rm -rf "$broken_checkout"
cp -a "$repo" "$broken_checkout"
# The release archive takes git's file list and the working tree's contents, so
# the copy keeps .git and the broken dwm.c is what gets archived.
printf 'this is not valid C\n' >"$broken_checkout/dwm.c"
make_source_tarball "$broken_checkout" "$work/broken.tar.gz"
seed_release "$source_version" "$(sha256sum "$work/broken.tar.gz" | awk '{ print $1 }')"
if run_update apply --file "$work/broken.tar.gz" --version "$source_version" --allow-downgrade --yes \
	>"$work/out" 2>&1; then
	fail "apply with a broken build unexpectedly succeeded"
fi
assert_contains "$work/out" 'build failed'
assert_no_file "$state_home/lyona/live-update-backups"

# ── apply: privileged step unavailable leaves the staged update in place,
#    live install untouched, non-zero exit (no root helper exists here) ─
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
if apply_source --allow-downgrade --yes \
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

# ── rollback: a bad user archive stops before anything is restored ────
# The checksums match and the environment does, but quickshell.tar is not an
# archive of quickshell/: refused before the privileged system restore (S12-11).
printf 'version=2026.01.0\n' >"$backup_dir2/checkout.txt"
if run_update rollback --backup 20260101T000000Z-1 --yes >"$work/out" 2>&1; then
	fail 'rollback with an unreadable user archive unexpectedly succeeded'
fi
assert_contains "$work/out" 'quickshell.tar is unreadable or holds more than quickshell/; nothing was restored'
if grep -Fq 'privileged' "$work/out"; then
	lyona_show_file "$work/out"
	fail 'the privileged restore was reached with a bad user archive'
fi

# ── set-channel: seeds, persists, preserves other keys, rejects garbage ──
reset_curl_responses
status=$(run_update set-channel stable)
assert_string_contains "$status" "$(printf 'complete\tset-channel\tstable')"
assert_contains "$config_home/lyona/update.conf" 'channel=stable'
status=$(run_update set-channel preview)
assert_string_contains "$status" "$(printf 'complete\tset-channel\tpreview')"
assert_contains "$config_home/lyona/update.conf" 'channel=preview'
assert_contains "$config_home/lyona/update.conf" 'check_on_login=true'
assert_contains "$config_home/lyona/update.conf" 'keep_backups=5'
if run_update set-channel bogus >"$work/out" 2>&1; then
	fail "set-channel with a bogus value unexpectedly succeeded"
fi
assert_contains "$work/out" 'channel must be stable or preview'
assert_contains "$config_home/lyona/update.conf" 'channel=preview'
run_update set-channel stable >/dev/null

# ── apply: writes update.status at each unprivileged phase, and reports
#    failure (not a stale "pending") once the privileged step is reached ──
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
status_file="$state_home/lyona/update.status"
rm -f "$status_file"
: >"$notify_log"
if apply_source --allow-downgrade --yes \
	>"$work/out" 2>&1; then
	fail "apply unexpectedly succeeded with no privileged helper installed"
fi
assert_file "$status_file"
assert_contains "$status_file" "$(printf 'outcome\tfailed')"
assert_not_contains "$status_file" "$(printf 'outcome\tpending')"

# The failed apply left a log a person can read after Quickshell has restarted,
# readable only by its owner, and told them so.
log_file="$state_home/lyona/update.log"
assert_file "$log_file"
assert_equals 600 "$(stat -c %a "$log_file")" "update.log mode"
assert_contains "$log_file" ' apply started'
assert_contains "$log_file" 'privileged'
assert_equals 1 "$(grep -c . "$notify_log")" "notifications after one failed apply"
assert_contains "$notify_log" '--urgency=critical'
assert_contains "$notify_log" 'Lyona: update failed'
assert_contains "$notify_log" "$log_file"

# A dry run installs nothing: it keeps the last real log and notifies no one.
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
before=$(cksum <"$log_file")
apply_source --allow-downgrade --dry-run >/dev/null
assert_equals "$before" "$(cksum <"$log_file")" "update.log after a dry run"
assert_equals 1 "$(grep -c . "$notify_log")" "notifications after a dry run"

# check only reads; it never notifies or replaces the log.
run_update check >/dev/null 2>&1 || true
assert_equals "$before" "$(cksum <"$log_file")" "update.log after check"
assert_equals 1 "$(grep -c . "$notify_log")" "notifications after check"

# ── apply --dry-run: leaves no status file (nothing to report) ─────────
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
rm -f "$status_file"
apply_source --allow-downgrade --dry-run >/dev/null
assert_no_file "$status_file"

# ── apply: deferring leaves the system exactly as it was ────────────────
#
# Issue #311: declining the confirmation must not change anything. The build
# happens before the prompt, so this is the point where a careless "n" could
# still cost something.
reset_curl_responses
valid_user_record 0000.00.0 | write_user_record
rm -rf "$state_home/lyona/live-update-backups"
cp "$user_record" "$work/record.before"
# A real user's update.conf exists by now (the first check seeds it).
run_update check >/dev/null 2>&1 || true
assert_file "$config_home/lyona/update.conf"
conf_before=$(cksum <"$config_home/lyona/update.conf")
: >"$notify_log"
if printf 'n\n' | apply_source --allow-downgrade \
	>"$work/out" 2>&1; then
	fail "declining the confirmation unexpectedly succeeded"
fi
assert_contains "$work/out" 'not confirmed'
assert_no_file "$state_home/lyona/live-update-backups"
cmp "$work/record.before" "$user_record" || fail "declining changed the install record"
assert_equals "$conf_before" "$(cksum <"$config_home/lyona/update.conf")" "update.conf after declining"
# The status ends terminal, so a progress surface does not spin on "pending"...
assert_contains "$state_home/lyona/update.status" "$(printf 'outcome\tfailed')"
# ...but a deliberate "no" is not announced as a failure.
assert_equals 0 "$(grep -c . "$notify_log")" "notifications after declining"

# ── completion notifications, by outcome ────────────────────────────────
#
# A successful apply needs the root helper, which does not exist here, so the
# success path is exercised through the same functions the script calls.

extract_function() {
	sed -n "/^$1() {\$/,/^}\$/p" "$helper"
}
probe=$work/status-probe.sh
{
	printf 'set -eu\nself=lyona-update\nlog_file=/state/lyona/update.log\nstatus_file=%s\n' "$work/probe.status"
	extract_function write_status_file
	extract_function notify_outcome
	extract_function write_status
} >"$probe"
[ -s "$probe" ] || fail 'could not extract the status functions from lyona-update'
run_status_probe() {
	PATH="$bin_dir:$PATH" DWM_TEST_NOTIFY_LOG="$notify_log" bash -c '. "$1"; shift; write_status "$@"' bash "$probe" "$@"
}

: >"$notify_log"
run_status_probe restarting 'Update complete' 2026.10.0 succeeded ''
assert_equals 1 "$(grep -c . "$notify_log")" "notifications after a successful update"
assert_contains "$notify_log" 'Lyona: Update complete'
assert_contains "$notify_log" 'Version 2026.10.0 is installed.'
assert_contains "$notify_log" '--urgency=normal'

: >"$notify_log"
run_status_probe restarting 'Rollback complete' 20260301T000000Z-2 succeeded ''
assert_contains "$notify_log" 'Lyona: Rollback complete'
assert_contains "$notify_log" 'Restored backup 20260301T000000Z-2.'

: >"$notify_log"
run_status_probe installing 'Installing' 2026.10.0 failed 'the privileged install step failed (exit 3)'
assert_contains "$notify_log" '--urgency=critical'
assert_contains "$notify_log" 'the privileged install step failed (exit 3)'
assert_contains "$notify_log" 'Details: /state/lyona/update.log'

# Progress is never announced, only how it ended.
: >"$notify_log"
run_status_probe downloading 'Downloading' 2026.10.0 pending ''
assert_equals 0 "$(grep -c . "$notify_log")" "notifications for a pending phase"

# No notification daemon or notify-send: the status still writes, nothing fails.
if ! PATH="$work/no-such-bin" /usr/bin/bash -c '. "$1"; write_status restarting "Update complete" 2026.10.0 succeeded ""' bash "$probe" 2>/dev/null; then
	fail 'a missing notify-send made the status write fail'
fi

# ── one authorization per privileged step ───────────────────────────────
#
# apply asks once (its two call sites are release vs. checkout mode, never
# both) and rollback asks once. A step that ran and failed is not retried
# through a second prompt; only a polkit that could not run at all falls back.

body_of() {
	sed -n "/^$1() {\$/,/^}\$/p" "$helper"
}
# Sync Sprint 12 S12-11: rollback swaps a user tree in whole. Run on its own
# (a real rollback needs the privileged helper).
body_of restore_user_tree >"$work/restore.sh"
[ -s "$work/restore.sh" ] || fail 'restore_user_tree not found'
restore() { # ARCHIVE TARGET
	bash -c 'warn() { printf "%s\n" "$*" >&2; }; . "$1"; restore_user_tree "$2" "$3"' \
		sh "$work/restore.sh" "$1" "$2"
}
mkdir -p "$work/restore/saved/quickshell" "$work/restore/live/quickshell"
printf 'old shell\n' >"$work/restore/saved/quickshell/shell.qml"
tar -C "$work/restore/saved" -cpf "$work/restore/quickshell.tar" quickshell
printf 'new shell\n' >"$work/restore/live/quickshell/shell.qml"
printf 'added by the newer version\n' >"$work/restore/live/quickshell/NewerPane.qml"
restore "$work/restore/quickshell.tar" "$work/restore/live/quickshell" ||
	fail 'restore_user_tree failed'
assert_equals 'old shell' "$(cat "$work/restore/live/quickshell/shell.qml")" 'the backup content is restored'
assert_no_file "$work/restore/live/quickshell/NewerPane.qml" 'a file the newer version added is gone'
[ "$(find "$work/restore/live" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ] ||
	fail 'restore_user_tree left its staging behind'
restore "$work/restore/quickshell.tar" "$work/restore/fresh/quickshell" ||
	fail 'restore_user_tree into a missing target failed'
assert_file "$work/restore/fresh/quickshell/shell.qml"
# An archive that does not hold exactly the tree is refused, the current tree kept.
mkdir -p "$work/restore/other/stray"
tar -C "$work/restore/saved" -cpf "$work/restore/two.tar" quickshell -C "$work/restore/other" stray
if restore "$work/restore/two.tar" "$work/restore/live/quickshell" 2>/dev/null; then
	fail 'restore_user_tree accepted an archive with more than the tree'
fi
assert_equals 'old shell' "$(cat "$work/restore/live/quickshell/shell.qml")" 'a refused restore keeps the tree'
# The swap fails and so does moving the old tree back: the old tree is kept
# (in the staging folder) rather than deleted with it.
cat >"$work/restore-mv.sh" <<'EOF'
mv() {
	calls=$(($(cat "$MV_COUNT" 2>/dev/null || printf 0) + 1))
	printf '%s\n' "$calls" >"$MV_COUNT"
	[ "$calls" -eq 1 ] || return 1
	command mv "$@"
}
EOF
rm -f "$work/restore/mv.count"
if MV_COUNT=$work/restore/mv.count bash -c 'warn() { printf "%s\n" "$*" >&2; }; . "$1"; . "$2"; restore_user_tree "$3" "$4"' \
	sh "$work/restore.sh" "$work/restore-mv.sh" "$work/restore/quickshell.tar" "$work/restore/live/quickshell" \
	2>"$work/restore/mv.err"; then
	fail 'restore_user_tree reported success although both moves failed'
fi
kept=$(find "$work/restore/live" -path '*/.previous/shell.qml' | head -n1)
[ -n "$kept" ] || fail 'the old tree was deleted when it could not be put back'
assert_equals 'old shell' "$(cat "$kept")" 'the kept copy is the old tree'
assert_contains "$work/restore/mv.err" 'the previous copy is kept in'
rm -rf "$work/restore/live"

# valid_user_archive: readable, and everything under the one expected folder.
body_of valid_user_archive >"$work/valid-archive.sh"
[ -s "$work/valid-archive.sh" ] || fail 'valid_user_archive not found'
valid_archive() { bash -c '. "$1"; valid_user_archive "$2" "$3"' sh "$work/valid-archive.sh" "$1" "$2"; }
valid_archive "$work/restore/quickshell.tar" quickshell || fail 'a good user archive was refused'
if valid_archive "$work/restore/two.tar" quickshell; then fail 'an archive with a stray top-level entry was accepted'; fi
mkdir -p "$work/restore/dotdot/quickshell"
printf 'x\n' >"$work/restore/dotdot/escape"
tar -C "$work/restore/dotdot" -cpf "$work/restore/dotdot.tar" quickshell/../escape
if valid_archive "$work/restore/dotdot.tar" quickshell; then fail 'an archive with .. entries was accepted'; fi
printf 'not an archive\n' >"$work/restore/bogus.tar"
if valid_archive "$work/restore/bogus.tar" quickshell; then fail 'an unreadable archive was accepted'; fi

# GHSA-x538-46gg-v37h: a release whose signature was verified goes to the root
# helper's install-system, which checks the signature again itself; anything
# else to install-unverified, on its own explicit polkit prompt.
assert_equals 2 "$(body_of cmd_apply | grep -c 'run_privileged ')" "run_privileged sites in cmd_apply"
# shellcheck disable=SC2016 # the literal text of the script
assert_equals 1 "$(body_of cmd_apply | grep -c 'run_privileged "$install_subcommand" release')" "verified release site"
# #327: that subcommand is install-system, or install-downgrade for an older release.
assert_equals 1 "$(body_of cmd_apply | grep -c 'install_subcommand=install-system')" "verified release default"
assert_equals 1 "$(body_of cmd_apply | grep -c 'install_subcommand=install-downgrade')" "verified older release"
assert_equals 1 "$(body_of cmd_apply | grep -c 'run_privileged install-unverified release')" "unverified release site"
# shellcheck disable=SC2016 # the patterns match the literal source text
body_of cmd_apply | grep -A3 'if \[\[ $signature_verified == true \]\]; then' | grep -q 'run_privileged "$install_subcommand" release' ||
	fail 'install-system is not reserved for a verified signature'
# shellcheck disable=SC2016
body_of cmd_apply | grep -A1 'run_privileged "$install_subcommand" release' | grep -q '"$bundle_path"' ||
	fail 'install-system is not given the signature bundle'
# shellcheck disable=SC2016
[ "$(body_of cmd_apply | grep -c 'signature_verified=true')" = 1 ] ||
	fail 'signature_verified is set somewhere other than after verify_signature'
body_of cmd_apply | grep -B1 'signature_verified=true' | grep -q 'verify_signature ' ||
	fail 'signature_verified=true does not follow verify_signature'

# The root helper checks the signature itself, against a fixed identity.
root_helper=$repo/scripts/lyona-update-root
grep -Fxq 'readonly release_signer=https://github.com/technicks89/Lyona/.github/workflows/build-iso.yml@refs/heads/main' "$root_helper" ||
	fail 'the root helper does not fix the release signer identity'
grep -Fxq 'readonly release_issuer=https://token.actions.githubusercontent.com' "$root_helper" ||
	fail 'the root helper does not fix the release signer issuer'
if grep -q 'LYONA_UPDATE_GITHUB\|github_repo' "$root_helper"; then
	fail 'the root helper takes the signer from the environment'
fi
# shellcheck disable=SC2016
grep -q 'install-system release requires .* the release.s signature bundle' "$root_helper" ||
	fail 'install-system does not require the signature bundle'
# shellcheck disable=SC2016
grep -B3 'verify_release_signature "$verified_tarball" "$verified_bundle"' "$root_helper" |
	grep -q 'if \[\[ $install_mode != install-unverified \]\]; then' ||
	fail 'install-system does not verify the signature on root'"'"'s own copy'
# One polkit action per subcommand, none for the bare helper path.
policy=$repo/config/polkit/com.lyona.update.policy
assert_equals 4 "$(grep -c '<action id=' "$policy")" "update polkit actions"
assert_equals 4 "$(grep -c 'policykit.exec.argv1' "$policy")" "update polkit actions tied to a subcommand"
for sub in install-system restore-system install-unverified install-downgrade; do
	grep -Fq "exec.argv1\">$sub</annotate>" "$policy" || fail "no polkit action for $sub"
done
grep -A2 'com.lyona.update.unverified' "$policy" | grep -q 'NOT verified' ||
	fail 'the unverified action does not say so'
grep -A2 'com.lyona.update.downgrade' "$policy" | grep -q 'OLDER' ||
	fail 'the downgrade action does not say so (#327)'
# #280 VM: the privileged helpers carry no install path but @PREFIX@. The update
# check of a release before 2026.10.0-beta.6 fills in only @PREFIX@ in its
# expected copy, so any other placeholder made every update a "MISMATCH";
# lyona-update-root reads the rest of its layout from /etc/lyona-release.
for privileged in lyona-update-root dwm-settings-display-root dwm-system-health-root; do
	placeholders=$(grep -o '@[A-Z_]*@' "$repo/scripts/$privileged" | sort -u | tr '\n' ' ')
	assert_equals '@PREFIX@ ' "$placeholders" "install placeholders in $privileged"
done
grep -Fq 'install_stamp=/etc/lyona-release' "$root_helper" ||
	fail 'the root helper does not read its layout from /etc/lyona-release'
for field in LYONA_MANPREFIX LYONA_DATADIR LYONA_XSESSIONSDIR; do
	grep -Fq "printf '$field=%s" "$repo/Makefile" || fail "stamp-system does not record $field"
done
# Sync Sprint 12 S12-03 (decision D-15): no checkout mode, on either side.
assert_equals 0 "$(body_of cmd_apply | grep -c 'install-system checkout')" "checkout site"
assert_equals 0 "$(grep -c 'checkout)' "$repo/scripts/lyona-update-root")" "root helper checkout mode"
assert_equals 1 "$(body_of cmd_rollback | grep -c 'run_privileged ')" "run_privileged sites in cmd_rollback"
# #324 VM: the account's install record goes back with the rest, or lyona-version
# calls the restored install inconsistent.
# shellcheck disable=SC2016 # the literal source text
assert_equals 1 "$(body_of cmd_rollback | grep -c '"$backup_dir/install.state" "$state_home/lyona/.install.state.restore"')" \
	"install.state restore in cmd_rollback"
# Sync Sprint 12 S12-01: root keeps its own system backups. A rollback names one
# by id and never passes root a path into the user's backup directory, and the
# install passes the id so root backs up the live files before installing.
# shellcheck disable=SC2016 # the patterns match the literal source text
assert_equals 1 "$(body_of cmd_rollback | grep -c 'run_privileged restore-system "$backup_id"')" \
	"rollback passes the privileged helper a backup id"
# shellcheck disable=SC2016
assert_equals 0 "$(body_of cmd_rollback | grep -c 'run_privileged restore-system "$backup_dir"')" \
	"rollback never passes the privileged helper a backup path"
# shellcheck disable=SC2016
assert_equals 1 "$(body_of cmd_apply | grep -A1 'run_privileged "$install_subcommand"' | grep -c '"$backup_id"')" \
	"the install passes the backup id"
outside=$(grep -n 'pkexec "\|sudo "' "$helper" | grep -v '^[0-9]*:[[:space:]]*#' || true)
assert_equals 2 "$(printf '%s\n' "$outside" | grep -c .)" "pkexec/sudo invocations in lyona-update"
first_escalation=$(sed -n "$(printf '%s\n' "$outside" | head -n1 | cut -d: -f1)p" "$helper")
case $first_escalation in
*pkexec*) ;;
*) fail 'the first escalation is not pkexec' ;;
esac

# #326: a successful apply removes its staged tree and tarball, after the
# install is verified, never before (a failed one keeps them).
verified_at=$(body_of cmd_apply | grep -n 'verify_install ||' | head -n1 | cut -d: -f1)
# shellcheck disable=SC2016 # the literal text of the script
cleaned_at=$(body_of cmd_apply | grep -n 'rm -rf -- "${staging_dir:?}" "$tarball"' | head -n1 | cut -d: -f1)
[ -n "$verified_at" ] && [ -n "$cleaned_at" ] && [ "$cleaned_at" -gt "$verified_at" ] ||
	fail "apply does not remove its staged update after verifying the install ($verified_at, $cleaned_at)"

priv_probe=$work/priv-probe.sh
priv_log=$work/priv.log
{
	printf "warn() { printf '%%s\\n' \"\$*\" >&2; }\ndie() { warn \"\$*\"; exit 1; }\n"
	printf "trusted_root_helper() { printf '%%s\\n' /bin/true; }\n"
	printf "write_status_file() { printf 'status %%s %%s\\n' \"\$4\" \"\$5\" >>\"\$DWM_TEST_PRIV_LOG\"; }\n"
	extract_function run_privileged
	extract_function cancel_privileged
} >"$priv_probe"
for tool in pkexec sudo; do
	stub_command "$tool" <<'SH'
#!/bin/sh
name=$(basename "$0")
if [ "$name" = sudo ] && [ "$1" = -n ]; then
	printf 'sudo -n\n' >>"${DWM_TEST_PRIV_LOG:?}"
	exit "${DWM_TEST_SUDO_N_STATUS:-1}"
fi
printf '%s\n' "$name" >>"${DWM_TEST_PRIV_LOG:?}"
if [ "$name" = pkexec ]; then exit "${DWM_TEST_PKEXEC_STATUS:-0}"; fi
exit 0
SH
done
# run_priv STATUS DISPLAY [tty]: run_privileged with pkexec exiting STATUS, on a
# terminal when the third argument is "tty", else with none (as from Settings).
run_priv() {
	: >"$priv_log"
	if [ "${3:-}" = tty ]; then
		# shellcheck disable=SC2016 # expanded by the inner bash
		PATH="$bin_dir:$PATH" DWM_TEST_PRIV_LOG="$priv_log" DWM_TEST_PKEXEC_STATUS="$1" DISPLAY="$2" \
			script -qec "bash -c '. \"\$1\"; run_privileged install-system release' bash $priv_probe" /dev/null \
			>/dev/null 2>&1
	else
		PATH="$bin_dir:$PATH" DWM_TEST_PRIV_LOG="$priv_log" DWM_TEST_PKEXEC_STATUS="$1" DISPLAY="$2" \
			bash -c '. "$1"; run_privileged install-system release' bash "$priv_probe" </dev/null >/dev/null 2>&1
	fi
}
run_priv 0 ':0'
assert_equals pkexec "$(cat "$priv_log")" "escalation when polkit authorizes"
if run_priv 1 ':0'; then fail 'a failed privileged step was reported as success'; fi
assert_equals pkexec "$(cat "$priv_log")" "a failed step must not prompt a second time"
run_priv 126 ':0' tty
assert_equals "$(printf 'pkexec\nsudo')" "$(cat "$priv_log")" "fallback to sudo on a terminal when polkit cannot run"
# #326: no terminal (started from Settings): a dismissed or refused prompt is a
# cancel, recorded as such, with nothing tried after it and exit status 4.
for pkexec_status in 126 127; do
	status=0
	run_priv "$pkexec_status" ':0' || status=$?
	assert_equals 4 "$status" "the exit status of a cancel (pkexec $pkexec_status)"
	assert_equals "$(printf 'pkexec\nstatus cancelled Update cancelled: authorization was not given. Nothing was changed.')" \
		"$(cat "$priv_log")" "a cancel with no terminal (pkexec $pkexec_status)"
done
run_priv 0 '' tty
assert_equals sudo "$(cat "$priv_log")" "escalation with no graphical session"
# No graphical session and no terminal: sudo cannot ask, so it is not tried,
# unless it needs no password.
if run_priv 0 ''; then fail 'an escalation with no agent and no terminal succeeded'; fi
assert_equals 'sudo -n' "$(cat "$priv_log")" "no sudo prompt without a terminal"

# ── --help / usage ───────────────────────────────────────────────────────
status=$(run_update --help)
assert_string_contains "$status" 'Usage: lyona-update'
if run_update bogus-command >"$work/out" 2>&1; then
	fail "unknown subcommand unexpectedly succeeded"
fi
assert_contains "$work/out" 'Usage: lyona-update'

# #325: lyona_install_layout's defaults follow the Makefile (DATADIR is
# /usr/share for PREFIX /usr and /usr/local, else PREFIX/share), an explicit
# PREFIX is used when no record names one, and a record value with ".." is not.
layout_of() { # RECORD [VAR=VALUE...]
	layout_record=$1
	shift
	# shellcheck disable=SC2016 # expanded by the inner bash
	env -u PREFIX -u MANPREFIX -u DATADIR -u XSESSIONSDIR "$@" DWM_TEST_SYSTEM_RECORD="$layout_record" bash -c \
		'. "$1/scripts/dwm-paths.sh"; lyona_install_layout; printf "%s %s %s %s" "$PREFIX" "$MANPREFIX" "$DATADIR" "$XSESSIONSDIR"' \
		bash "$repo"
}
[ "$(layout_of /nonexistent)" = '/usr/local /usr/local/share/man /usr/share /usr/share/xsessions' ] ||
	fail "default layout: $(layout_of /nonexistent)"
[ "$(layout_of /nonexistent PREFIX=/opt/x)" = '/opt/x /opt/x/share/man /opt/x/share /usr/share/xsessions' ] ||
	fail "PREFIX-only layout: $(layout_of /nonexistent PREFIX=/opt/x)"
printf 'LYONA_PREFIX=/usr\nLYONA_DATADIR=/srv/../etc\n' >"$work/layout-record"
[ "$(layout_of "$work/layout-record")" = '/usr /usr/share/man /usr/share /usr/share/xsessions' ] ||
	fail "a record value with .. was used: $(layout_of "$work/layout-record")"

printf 'lyona-update contract: PASS\n'
