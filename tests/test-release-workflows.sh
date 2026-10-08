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
# The ISO workflow's own token only reads (the release uses RELEASE_TOKEN);
# promotion edits a release with the workflow's token.
assert build["permissions"]["contents"] == "read", build["permissions"]
assert promote["permissions"]["contents"] == "write"
jobs = build["jobs"]
assert list(jobs) == ["authorize", "build-iso", "sign", "release"], list(jobs)
bi, sg, rl = jobs["build-iso"], jobs["sign"], jobs["release"]
steps = [s.get("name") for s in bi["steps"]]
# The build runs the repository's code and freshly synced packages: a
# read-only token, and it neither signs nor publishes (GHSA-xfhv-7h9c-m966).
assert bi["permissions"] == {"contents": "read"}, bi["permissions"]
assert "Sign the release files" not in steps and "Create the tag and the release" not in steps, steps
assert steps.index("Check the version and the tag") < steps.index("Check the release archive") < steps.index("Build ISO"), steps
uploads = [s["with"]["name"] for s in bi["steps"] if s.get("uses", "").startswith("actions/upload-artifact@")]
assert uploads == ["lyona-iso-${{ env.TAG }}", "lyona-source-${{ env.TAG }}"], uploads
assert bi["outputs"] == {"version": "${{ steps.check.outputs.version }}", "tag": "${{ steps.check.outputs.tag }}"}, bi.get("outputs")
# Signed releases (D-31), in their own job: the only one with the OIDC token,
# running no repository code (no checkout, no run script, only pinned actions),
# on build-iso's files.
for name, job in jobs.items():
    if name != "sign":
        assert "id-token" not in (job.get("permissions") or {}), name
assert sg["permissions"] == {"contents": "read", "id-token": "write", "attestations": "write"}, sg["permissions"]
assert sg["needs"] == "build-iso" and "container" not in sg and "environment" not in sg, sg
for st in sg["steps"]:
    assert "run" not in st and "uses" in st, st
    assert not st["uses"].startswith("actions/checkout@"), st
    assert len(st["uses"].split("@")[1]) == 40, f"not pinned to a commit: {st['uses']}"
sign = next(st for st in sg["steps"] if st.get("name") == "Sign the release files")
assert sign["uses"].startswith("actions/attest-build-provenance@") and sign.get("id") == "sign", sign
for subject in ("iso/*.iso", "source/lyona-*.tar.gz"):
    assert subject in sign["with"]["subject-path"], subject
bundle_up = [st for st in sg["steps"] if st["uses"].startswith("actions/upload-artifact@")]
assert bundle_up and bundle_up[0]["with"]["path"] == "${{ steps.sign.outputs.bundle-path }}", bundle_up
# The release publishes the signed files: after the signing, with the bundle.
assert rl["needs"] == ["build-iso", "sign"], rl["needs"]
assert rl["permissions"] == {"contents": "read"}, rl["permissions"]
publish = next(st for st in rl["steps"] if st.get("name") == "Create the tag and the release")
assert '--bundle "${bundle[0]}"' in publish["run"], publish["run"]
# Both container images pinned by digest.
import re
for name in ("build-iso", "release"):
    image = jobs[name]["container"]["image"]
    assert re.fullmatch(r"archlinux:base-devel@sha256:[0-9a-f]{64}", image), (name, image)
assert bi["container"]["image"] == rl["container"]["image"], "the two jobs use different images"
# Only admins and maintainers: both workflows start with the authorize job, and
# their work waits for it.
for wf in (build, promote):
    assert "authorize" in wf["jobs"], wf["jobs"].keys()
assert build["jobs"]["build-iso"]["needs"] == "authorize"
assert build["jobs"]["release"]["needs"] == ["build-iso", "sign"]
assert promote["jobs"]["promote"]["needs"] == "authorize"
# The tag is created with the release environment's admin token, and only in
# the release step; the build checks early that the token exists.
job = build["jobs"]["release"]
assert job["environment"] == "release", job.get("environment")
assert build["jobs"]["build-iso"]["environment"] == "release"
release_step = [s for s in job["steps"] if s.get("name") == "Create the tag and the release"][0]
assert release_step["env"]["GH_TOKEN"] == "${{ secrets.RELEASE_TOKEN }}", release_step.get("env")
assert job["env"]["GH_TOKEN"] == "${{ github.token }}", "the other steps must keep the workflow's own token"
bi = build["jobs"]["build-iso"]
assert bi["env"]["GH_TOKEN"] == "${{ github.token }}", "the build keeps the workflow's own token"
assert bi["env"]["RELEASE_TOKEN_SET"] == "${{ secrets.RELEASE_TOKEN != '' }}", bi["env"]
assert "secrets.RELEASE_TOKEN }}" not in str(bi["steps"]), "the build must not hold the admin token"
# The container jobs' steps are bash scripts; a container defaults to sh.
for name in ("build-iso", "release"):
    assert build["jobs"][name]["defaults"]["run"]["shell"] == "bash", name
PY
step "$build_workflow" 'Check the version and the tag' "$work/check.sh"
step "$build_workflow" 'Create the tag and the release' "$work/release.sh"
step "$promote_workflow" 'Promote the release' "$work/promote.sh"
step "$build_workflow" 'Allow only admins and maintainers' "$work/authorize.sh"
step "$promote_workflow" 'Allow only admins and maintainers' "$work/authorize-promote.sh"
cmp -s "$work/authorize.sh" "$work/authorize-promote.sh" || fail 'the two workflows check who may run them differently'
if command -v shellcheck >/dev/null 2>&1; then
	for script in check release promote authorize; do
		shellcheck -s bash "$work/$script.sh" || fail "the $script step does not pass shellcheck"
	done
fi
# The ISO is built outside the checkout, before the tag exists.
# shellcheck disable=SC2016 # the literal text in the workflow
grep -Fq 'scripts/build-lyona-arch-iso.sh --output "$RUNNER_TEMP/iso"' "$build_workflow" ||
	fail 'the ISO is not built outside the checkout'
python3 - "$build_workflow" <<'PY' || fail 'the version check does not come before the build dependencies'
import sys, yaml
steps = [s.get("name") for s in yaml.safe_load(open(sys.argv[1]))["jobs"]["build-iso"]["steps"]]
assert steps.index("Check the version and the tag") < steps.index("Install build dependencies"), steps
PY

# ---- who may run them -------------------------------------------------------
# gh api repos/R/collaborators/ACTOR/permission --jq .role_name: STUB_ROLE, or a
# failure when it is "error".
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
[ "$STUB_ROLE" != error ] || exit 1
printf '%s\n' "$STUB_ROLE"
EOF
chmod +x "$work/bin/gh"
authorize() { env PATH="$work/bin:$PATH" STUB_ROLE="$1" GH_REPO=owner/lyona ACTOR=someone bash "$work/authorize.sh" >"$work/authorize.out" 2>&1; }
for role in admin maintain; do
	authorize "$role" || fail "a repository $role was refused: $(cat "$work/authorize.out")"
done
for role in write triage read none error ''; do
	if authorize "$role"; then fail "a repository '$role' was allowed to release"; fi
done
grep -Fq "Only the repository's admins and maintainers" "$work/authorize.out" ||
	fail "a refusal does not say who may release: $(cat "$work/authorize.out")"

# ---- the version and tag check ----------------------------------------------
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
# gh api repos/:owner/:repo/commits/TAG --jq .sha: STUB_TAG_SHA, or "head" for
# the checkout's own HEAD; GitHub's 422 for a missing tag when it is unset, and
# a server error when it is "error".
if [ -z "${STUB_TAG_SHA:-}" ]; then
	printf 'gh: No commit found for SHA: v0 (HTTP 422)\n' >&2
	exit 1
elif [ "$STUB_TAG_SHA" = error ]; then
	printf 'gh: Bad Gateway (HTTP 502)\n' >&2
	exit 1
fi
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
	: >"$work/github-output"
	mkdir -p "$work/runner-temp"
	(cd "$checkout" && env PATH="$work/bin:$PATH" CHANNEL="$1" NOTES="${3:-}" GITHUB_ENV="$work/github-env" \
		GITHUB_OUTPUT="$work/github-output" \
		RUNNER_TEMP="$work/runner-temp" \
		RELEASE_TOKEN_SET="${RELEASE_TOKEN_SET:-true}" \
		bash "$work/check.sh") >"$work/check.out" 2>&1
}
check beta 2026.10.0-beta.1 || fail "a beta VERSION was refused: $(cat "$work/check.out")"
grep -Fqx 'TAG=v2026.10.0-beta.1' "$work/github-env" || fail 'the beta tag was not passed on'
check main 2026.10.0 notes/release.md || fail "a main VERSION was refused: $(cat "$work/check.out")"
grep -Fqx 'TAG=v2026.10.0' "$work/github-env" || fail 'the main tag was not passed on'
grep -Fqx 'VERSION=2026.10.0' "$work/github-env" || fail 'the version was not passed on'
# And to the sign and release jobs, as build-iso's outputs.
grep -Fqx 'version=2026.10.0' "$work/github-output" || fail 'the version is not a job output'
grep -Fqx 'tag=v2026.10.0' "$work/github-output" || fail 'the tag is not a job output'
for refused in 'beta 2026.10.0' 'main 2026.10.0-rc.2' 'stable 2026.10.0' 'main 2026.10'; do
	# shellcheck disable=SC2086 # two words: the channel and the version
	if check $refused; then fail "check accepted '$refused'"; fi
done
if check main 2026.10.0 notes/absent.md; then fail 'check accepted a missing notes file'; fi
# No release token in the release environment: refused before anything is built.
if RELEASE_TOKEN_SET=false check main 2026.10.0; then fail 'check accepted a missing RELEASE_TOKEN'; fi
grep -Fq 'no RELEASE_TOKEN secret' "$work/check.out" || fail "a missing token: $(cat "$work/check.out")"
# A tag at another commit is refused; at this one, it is a rerun.
if STUB_TAG_SHA=0123456789abcdef0123456789abcdef01234567 check main 2026.10.1; then
	fail 'check accepted a tag at another commit'
fi
grep -Fq 'Bump VERSION in config.mk' "$work/check.out" || fail "a tag at another commit: $(cat "$work/check.out")"
# A tag lookup that fails for any other reason stops the release.
if STUB_TAG_SHA=error check main 2026.10.3; then fail 'check passed although the tag could not be looked up'; fi
grep -Fq 'Could not look up v2026.10.3' "$work/check.out" || fail "a failed tag lookup: $(cat "$work/check.out")"
# Nothing the check writes lands in the checkout, which lyona-release needs clean.
[[ -z $(git -C "$checkout" status --porcelain --untracked-files=normal) ]] ||
	fail "the check left files in the checkout: $(git -C "$checkout" status --porcelain)"
STUB_TAG_SHA="head" check main 2026.10.2 ||
	fail "a rerun at the tagged commit was refused: $(cat "$work/check.out")"

# ---- the release step -------------------------------------------------------
mkdir -p "$work/release/scripts" "$work/runner/iso" "$work/runner/bundle"
cat >"$work/release/scripts/lyona-release" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_DIR/release.args"
EOF
chmod +x "$work/release/scripts/lyona-release"
: >"$work/runner/iso/lyona-2026.10.0-x86_64.iso"
# The sign job's bundle, as download-artifact leaves it.
: >"$work/runner/bundle/attestation.jsonl"
release() { (cd "$work/release" && env STUB_DIR="$work" RUNNER_TEMP="$work/runner" VERSION=2026.10.0 NOTES="${1:-}" bash "$work/release.sh"); }
release || fail 'the release step failed'
[[ $(cat "$work/release.args") == "--version 2026.10.0 --iso $work/runner/iso/lyona-2026.10.0-x86_64.iso --bundle $work/runner/bundle/attestation.jsonl --prerelease --skip-checks" ]] ||
	fail "lyona-release was run as: $(cat "$work/release.args")"
release notes/release.md || fail 'the release step with notes failed'
[[ $(cat "$work/release.args") == *' --prerelease --skip-checks --notes notes/release.md' ]] || fail "with notes: $(cat "$work/release.args")"
: >"$work/runner/iso/second.iso"
if release >/dev/null 2>&1; then fail 'the release step accepted two ISOs'; fi
rm "$work/runner/iso/second.iso"
rm "$work/runner/bundle/attestation.jsonl"
if release >/dev/null 2>&1; then fail 'the release step ran without a signature bundle'; fi

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
