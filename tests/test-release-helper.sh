#!/bin/sh

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
helper=$repo/scripts/lyona-release
make_workspace

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$work/bin/gh"
: >"$work/lyona.iso"

output=$(
	PATH="$work/bin:$PATH" "$helper" \
		--dry-run \
		--skip-checks \
		--iso "$work/lyona.iso"
)

printf '%s\n' "$output" | grep -Fq '+ make release'
printf '%s\n' "$output" | grep -Fq '+ gh api -X POST repos/:owner/:repo/git/refs'
build_line=$(printf '%s\n' "$output" | grep -nF '+ make release' | cut -d: -f1)
tag_line=$(printf '%s\n' "$output" |
	grep -nF '+ gh api -X POST repos/:owner/:repo/git/refs' | cut -d: -f1)
if [ "$build_line" -ge "$tag_line" ]; then
	printf '%s\n' 'release validation must run before remote tag creation' >&2
	exit 1
fi

if PATH="$work/bin:$PATH" "$helper" \
	--dry-run --skip-checks --iso "$work/lyona.iso" \
	--version 2099.01.0 >"$work/mismatch.out" 2>"$work/mismatch.err"; then
	printf '%s\n' 'release helper accepted a version not committed in config.mk' >&2
	exit 1
fi
grep -Fq 'does not match committed config.mk VERSION' "$work/mismatch.err"

# --prerelease publishes a stable version as a pre-release (the ISO workflow's,
# until it is promoted); without it a stable version is a normal release. In a scratch
# repository whose config.mk VERSION is stable.
stable=$work/stable
mkdir -p "$stable/scripts"
cp "$helper" "$stable/scripts/lyona-release"
printf 'VERSION = 2026.10.0\n' >"$stable/config.mk"
# As in the real repository, the release output is not part of the worktree.
printf '/release\n' >"$stable/.gitignore"
git -C "$stable" init -q
git -C "$stable" add -A
git -C "$stable" -c user.name=t -c user.email=t@example.invalid commit -qm stable
plan() { PATH="$work/bin:$PATH" "$stable/scripts/lyona-release" --dry-run --skip-checks --iso "$work/lyona.iso" "$@"; }
plan --prerelease | grep -E '^\+ gh release create v2026\.10\.0 .* --prerelease( |$)' >/dev/null || {
	printf '%s\n' 'release helper did not plan a pre-release with --prerelease' >&2
	exit 1
}
if plan | grep -Fq -- '--prerelease'; then
	printf '%s\n' 'release helper planned a stable version as a pre-release without --prerelease' >&2
	exit 1
fi

# A real run against a release that already exists: --prerelease replaces a
# pre-release's assets, but refuses a release already promoted to a normal one.
mkdir -p "$work/live-bin"
cat >"$work/live-bin/gh" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
*git/ref/tags/*)
	# The remote tag: STUB_TAG_SHA, or GitHub's 404 when it is unset.
	if [ -n "${STUB_TAG_SHA:-}" ]; then
		printf 'commit %s\n' "$STUB_TAG_SHA"
		exit 0
	fi
	printf 'gh: Not Found (HTTP 404)\n' >&2
	exit 1
	;;
esac
case "$1 $2" in
'release view')
	case "$*" in
	*isPrerelease*) printf '%s\n' "$STUB_IS_PRERELEASE" ;;
	esac
	;;
'release upload') printf '%s\n' "$*" >>"$STUB_DIR/uploads" ;;
'release create') printf '%s\n' "$*" >>"$STUB_DIR/uploads" ;;
esac
exit 0
EOF
cat >"$work/live-bin/make" <<'EOF'
#!/bin/sh
set -eu
mkdir -p release && : >release/lyona-2026.10.0.tar.gz
EOF
chmod +x "$work/live-bin/gh" "$work/live-bin/make"
live() { (cd "$stable" && env PATH="$work/live-bin:$PATH" STUB_DIR="$work" "$stable/scripts/lyona-release" --skip-checks --iso "$work/lyona.iso" "$@"); }
rm -f "$work/uploads"
STUB_IS_PRERELEASE=true live --prerelease >/dev/null 2>&1 || {
	printf '%s\n' 'release helper refused to replace a pre-release'"'"'s assets' >&2
	exit 1
}
grep -q '^release upload v2026.10.0 ' "$work/uploads" || {
	printf '%s\n' 'release helper did not replace the pre-release'"'"'s assets' >&2
	exit 1
}
rm -f "$work/uploads"
if STUB_IS_PRERELEASE=false live --prerelease >/dev/null 2>"$work/promoted.err"; then
	printf '%s\n' 'release helper replaced the assets of a promoted release' >&2
	exit 1
fi
grep -Fq 'already a normal release' "$work/promoted.err"
[ ! -e "$work/uploads" ] || {
	printf '%s\n' 'release helper uploaded to a promoted release' >&2
	exit 1
}
# Without --prerelease, a manual rerun keeps replacing assets as before.
STUB_IS_PRERELEASE=false live >/dev/null 2>&1
grep -q '^release upload v2026.10.0 ' "$work/uploads"

# SHA256SUMS names each file by its name, so it checks the downloaded files.
sums=$stable/release/lyona-2026.10.0-SHA256SUMS
[ -f "$sums" ] || {
	printf '%s\n' 'release helper wrote no SHA256SUMS' >&2
	exit 1
}
if grep -q '/' "$sums"; then
	printf 'SHA256SUMS lists paths, not file names: %s\n' "$(cat "$sums")" >&2
	exit 1
fi
mkdir -p "$work/downloads"
command cp "$stable/release/lyona-2026.10.0.tar.gz" "$work/lyona.iso" "$sums" "$work/downloads/"
(cd "$work/downloads" && sha256sum -c --quiet "$(basename "$sums")") || {
	printf '%s\n' 'sha256sum -c failed on the downloaded assets' >&2
	exit 1
}

# A tag at another commit: refused, and nothing is uploaded or created.
rm -f "$work/uploads"
if STUB_TAG_SHA=0123456789abcdef0123456789abcdef01234567 STUB_IS_PRERELEASE=true live --prerelease \
	>/dev/null 2>"$work/other-commit.err"; then
	printf '%s\n' 'release helper published under a tag that names another commit' >&2
	exit 1
fi
grep -Fq 'already exists at 0123456789abcdef0123456789abcdef01234567' "$work/other-commit.err"
[ ! -e "$work/uploads" ] || {
	printf '%s\n' 'release helper uploaded under a tag at another commit' >&2
	exit 1
}
# The tag at this very commit: a rerun, which replaces the assets.
STUB_TAG_SHA=$(git -C "$stable" rev-parse HEAD) STUB_IS_PRERELEASE=true live --prerelease >/dev/null 2>&1
grep -q '^release upload v2026.10.0 ' "$work/uploads"

# --bundle (decision D-31): published as lyona-VERSION.sigstore.json, but only
# when its statement signs exactly the archive and the ISO being published.
printf 'an image\n' >"$work/lyona.iso"
digest() { sha256sum "$1" | awk '{ print $1 }'; }
make_bundle() { # OUT DIGEST...
	out=$1
	shift
	subjects=$(for d in "$@"; do printf '{"digest":{"sha256":"%s"}}\n' "$d"; done | jq -sc .)
	payload=$(jq -cn --argjson s "$subjects" '{_type: "https://in-toto.io/Statement/v1", subject: $s}' | base64 -w0)
	jq -n --arg p "$payload" '{dsseEnvelope: {payload: $p}}' >"$out"
}
archive_digest=$(digest "$stable/release/lyona-2026.10.0.tar.gz")
make_bundle "$work/good.json" "$archive_digest" "$(digest "$work/lyona.iso")"
make_bundle "$work/partial.json" "$archive_digest"
rm -f "$work/uploads"
STUB_IS_PRERELEASE=true live --prerelease --bundle "$work/good.json" >/dev/null 2>&1 || {
	printf '%s\n' 'release helper refused a bundle that signs what it publishes' >&2
	exit 1
}
grep -Fq 'release/lyona-2026.10.0.sigstore.json' "$work/uploads" || {
	printf '%s\n' 'release helper did not publish the signature bundle' >&2
	exit 1
}
cmp -s "$work/good.json" "$stable/release/lyona-2026.10.0.sigstore.json"
rm -f "$work/uploads"
if STUB_IS_PRERELEASE=true live --prerelease --bundle "$work/partial.json" >/dev/null 2>"$work/partial.err"; then
	printf '%s\n' 'release helper published a bundle that does not sign the ISO' >&2
	exit 1
fi
grep -Fq 'does not sign lyona.iso' "$work/partial.err"
[ ! -e "$work/uploads" ] || {
	printf '%s\n' 'release helper uploaded with a bundle that does not sign the ISO' >&2
	exit 1
}

printf '%s\n' 'Release helper preflight and remote-write ordering: PASS'
