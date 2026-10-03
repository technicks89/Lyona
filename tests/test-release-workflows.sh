#!/usr/bin/env bash
set -euo pipefail

# The release workflows' own scripts, taken from the YAML and run against stub
# gh and lyona-release: .github/workflows/build-iso.yml checks the channel
# against config.mk VERSION and refuses a tag at another commit, then releases
# through scripts/lyona-release as a pre-release; promote-releases.yml, run by
# hand for a tag, makes a main release a normal one (never a beta), and the
# latest only when nothing newer is.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
python3 -c 'import yaml' 2>/dev/null || {
	printf 'SKIP: PyYAML is unavailable\n'
	exit 77
}

build_workflow=$repo/.github/workflows/build-iso.yml
promote_workflow=$repo/.github/workflows/promote-releases.yml

# step WORKFLOW NAME OUT: one step's run script.
step() {
	python3 - "$1" "$2" "$3" <<'PY'
import sys, yaml
workflow, name, out = sys.argv[1:]
doc = yaml.safe_load(open(workflow))
for job in doc["jobs"].values():
    for s in job["steps"]:
        if s.get("name") == name:
            open(out, "w").write(s["run"])
            sys.exit(0)
sys.exit(f"no step named {name!r} in {workflow}")
PY
}

# The shape: a manual run asking beta or main, and a manual promotion of one tag.
python3 - "$build_workflow" "$promote_workflow" <<'PY' || fail 'a workflow does not have the expected triggers'
import sys, yaml
build = yaml.safe_load(open(sys.argv[1]))
promote = yaml.safe_load(open(sys.argv[2]))
# PyYAML reads the bare key "on" as True.
trigger = build[True]["workflow_dispatch"]["inputs"]["channel"]
assert trigger["type"] == "choice" and trigger["options"] == ["beta", "main"], trigger
assert "tag" not in build[True]["workflow_dispatch"]["inputs"], "the tag is still an input"
assert "schedule" not in promote[True], "promotion must not run on a schedule"
assert promote[True]["workflow_dispatch"]["inputs"]["tag"]["required"] is True, promote[True]
assert build["permissions"]["contents"] == "write" and promote["permissions"]["contents"] == "write"
PY
step "$build_workflow" 'Check the version and the tag' "$work/check.sh"
step "$build_workflow" 'Create the tag and the release' "$work/release.sh"
step "$promote_workflow" 'Promote the release' "$work/promote.sh"
if command -v shellcheck >/dev/null 2>&1; then
	for script in check release promote; do
		shellcheck -s bash "$work/$script.sh" || fail "the $script step does not pass shellcheck"
	done
fi
# The ISO is built outside the checkout, before the tag exists.
# shellcheck disable=SC2016 # the literal text in the workflow
grep -Fq 'scripts/build-lyona-arch-iso.sh --output "$RUNNER_TEMP/iso"' "$build_workflow" ||
	fail 'the ISO is not built outside the checkout'
python3 - "$build_workflow" <<'PY' || fail 'the release is created before the ISO is built'
import sys, yaml
steps = [s.get("name") for s in yaml.safe_load(open(sys.argv[1]))["jobs"]["build-iso"]["steps"]]
assert steps.index("Build ISO") < steps.index("Create the tag and the release"), steps
assert steps.index("Check the version and the tag") < steps.index("Install build dependencies"), steps
PY

# ---- the version and tag check ----------------------------------------------
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
# gh api repos/:owner/:repo/commits/TAG --jq .sha: STUB_TAG_SHA, or "head" for
# the checkout's own HEAD; no tag when it is unset.
[ -n "${STUB_TAG_SHA:-}" ] || exit 1
if [ "$STUB_TAG_SHA" = head ]; then git rev-parse HEAD; else printf '%s\n' "$STUB_TAG_SHA"; fi
EOF
chmod +x "$work/bin/gh"
checkout=$work/checkout
mkdir -p "$checkout/notes"
git -C "$checkout" init -q
: >"$checkout/notes/release.md"
check() { # CHANNEL VERSION [NOTES]
	printf 'VERSION = %s\n' "$2" >"$checkout/config.mk"
	git -C "$checkout" add -A
	git -C "$checkout" -c user.name=t -c user.email=t@example.invalid commit -q -m "v$2" --allow-empty
	: >"$work/github-env"
	(cd "$checkout" && env PATH="$work/bin:$PATH" CHANNEL="$1" NOTES="${3:-}" GITHUB_ENV="$work/github-env" \
		bash "$work/check.sh") >"$work/check.out" 2>&1
}
check beta 2026.10.0-beta.1 || fail "a beta VERSION was refused: $(cat "$work/check.out")"
grep -Fqx 'TAG=v2026.10.0-beta.1' "$work/github-env" || fail 'the beta tag was not passed on'
check main 2026.10.0 notes/release.md || fail "a main VERSION was refused: $(cat "$work/check.out")"
grep -Fqx 'TAG=v2026.10.0' "$work/github-env" || fail 'the main tag was not passed on'
grep -Fqx 'VERSION=2026.10.0' "$work/github-env" || fail 'the version was not passed on'
for refused in 'beta 2026.10.0' 'main 2026.10.0-rc.2' 'stable 2026.10.0' 'main 2026.10'; do
	# shellcheck disable=SC2086 # two words: the channel and the version
	if check $refused; then fail "check accepted '$refused'"; fi
done
if check main 2026.10.0 notes/absent.md; then fail 'check accepted a missing notes file'; fi
# A tag at another commit is refused; at this one, it is a rerun.
if STUB_TAG_SHA=0123456789abcdef0123456789abcdef01234567 check main 2026.10.1; then
	fail 'check accepted a tag at another commit'
fi
grep -Fq 'Bump VERSION in config.mk' "$work/check.out" || fail "a tag at another commit: $(cat "$work/check.out")"
STUB_TAG_SHA="head" check main 2026.10.2 ||
	fail "a rerun at the tagged commit was refused: $(cat "$work/check.out")"

# ---- the release step -------------------------------------------------------
mkdir -p "$work/release/scripts" "$work/runner/iso"
cat >"$work/release/scripts/lyona-release" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_DIR/release.args"
EOF
chmod +x "$work/release/scripts/lyona-release"
: >"$work/runner/iso/lyona-2026.10.0-x86_64.iso"
release() { (cd "$work/release" && env STUB_DIR="$work" RUNNER_TEMP="$work/runner" VERSION=2026.10.0 NOTES="${1:-}" bash "$work/release.sh"); }
release || fail 'the release step failed'
[[ $(cat "$work/release.args") == "--version 2026.10.0 --iso $work/runner/iso/lyona-2026.10.0-x86_64.iso --prerelease" ]] ||
	fail "lyona-release was run as: $(cat "$work/release.args")"
release notes/release.md || fail 'the release step with notes failed'
[[ $(cat "$work/release.args") == *' --prerelease --notes notes/release.md' ]] || fail "with notes: $(cat "$work/release.args")"
: >"$work/runner/iso/second.iso"
if release >/dev/null 2>&1; then fail 'the release step accepted two ISOs'; fi

# ---- promotion --------------------------------------------------------------
# gh: the named release (STUB_RELEASE: prerelease, draft, published; none when
# unset), the latest release's publish time (STUB_LATEST; GitHub's 404 when
# unset, a server error when "error"), and edits.
cat >"$work/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
'release view')
	[[ -n ${STUB_RELEASE:-} ]] || exit 1
	printf '%s\n' "$STUB_RELEASE"
	;;
api\ *)
	if [[ -z ${STUB_LATEST:-} ]]; then
		printf 'gh: Not Found (HTTP 404)\n' >&2
		exit 1
	elif [[ $STUB_LATEST == error ]]; then
		printf 'gh: Bad Gateway (HTTP 502)\n' >&2
		exit 1
	fi
	printf '%s\n' "$STUB_LATEST"
	;;
'release edit') printf '%s\n' "$*" >>"$STUB_DIR/edits" ;;
*) exit 9 ;;
esac
EOF
chmod +x "$work/bin/gh"
ago() { date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%SZ; }
tab=$'\t'
promote() { # TAG
	rm -f "$work/edits"
	(cd "$work" && env PATH="$work/bin:$PATH" STUB_DIR="$work" GH_REPO=owner/lyona TAG="$1" bash "$work/promote.sh") \
		>"$work/promote.out" 2>&1
}
# A main pre-release with no stable release yet: promoted and made the latest.
STUB_RELEASE="true${tab}false${tab}$(ago 2)" promote v2026.10.0 || fail "the promotion failed: $(cat "$work/promote.out")"
[[ $(cat "$work/edits") == 'release edit v2026.10.0 --prerelease=false --latest=true' ]] ||
	fail "the promotion was: $(cat "$work/edits" 2>/dev/null)"
# Newer than the latest stable release: made the latest.
STUB_LATEST=$(ago 30) STUB_RELEASE="true${tab}false${tab}$(ago 2)" promote v2026.10.0 || fail 'the promotion failed'
[[ $(cat "$work/edits") == *'--latest=true' ]] || fail "beside an older latest: $(cat "$work/edits")"
# Older than the latest stable release: promoted, but not made the latest.
STUB_LATEST=$(ago 1) STUB_RELEASE="true${tab}false${tab}$(ago 10)" promote v2026.09.0 || fail 'the promotion failed'
[[ $(cat "$work/edits") == 'release edit v2026.09.0 --prerelease=false --latest=false' ]] ||
	fail "beside a newer latest: $(cat "$work/edits")"
# The latest release cannot be looked up (anything but a 404): nothing is edited.
if STUB_LATEST=error STUB_RELEASE="true${tab}false${tab}$(ago 2)" promote v2026.10.0; then
	fail 'promoted although the latest release could not be looked up'
fi
[[ ! -e $work/edits ]] || fail "a failed lookup still edited: $(cat "$work/edits")"
grep -Fq 'Could not look up the latest release' "$work/promote.out" || fail "a failed lookup: $(cat "$work/promote.out")"
# Already a normal release: nothing to do.
STUB_RELEASE="false${tab}false${tab}$(ago 10)" promote v2026.09.0 || fail 'promoting a normal release failed'
[[ ! -e $work/edits ]] || fail "a normal release was edited: $(cat "$work/edits")"
# Refused: a beta, a malformed tag, no release, and a draft.
for refused in v2026.10.0-beta.1 2026.10.0 v2026.10; do
	if STUB_RELEASE="true${tab}false${tab}$(ago 2)" promote "$refused"; then fail "promoted '$refused'"; fi
	[[ ! -e $work/edits ]] || fail "'$refused' was edited"
done
if promote v2026.10.0; then fail 'promoted a tag with no release'; fi
if STUB_RELEASE="true${tab}true${tab}" promote v2026.10.0; then fail 'promoted a draft'; fi
[[ ! -e $work/edits ]] || fail 'a draft was edited'

printf 'Release workflows: PASS\n'
