#!/bin/sh
set -eu

# #335: the published release and the record agree. CHANGELOG.md keeps an
# Unreleased section, and when the tag for config.mk's VERSION exists, the
# changelog has a dated section for that version and its release notes file
# exists: v2026.10.0-beta.6 was tagged at a commit whose changelog still listed
# its changes as Unreleased. Without the tag (a checkout before the release, or
# a clone without tags) only the Unreleased check applies.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

changelog=$repo/CHANGELOG.md
version=$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' "$repo/config.mk")
[ -n "$version" ] || fail 'config.mk has no VERSION'
grep -q '^## \[Unreleased\]$' "$changelog" || fail 'CHANGELOG.md has no Unreleased section'

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
	[ -z "$(git -C "$repo" tag -l "v$version")" ]; then
	printf 'Changelog record: PASS (no tag v%s here, so the dated-section check did not apply)\n' "$version"
	exit 0
fi

escaped=$(printf '%s' "$version" | sed 's/[.+]/\\&/g')
grep -Eq "^## \[$escaped\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$changelog" ||
	fail "v$version is tagged, but CHANGELOG.md has no dated section for $version"
[ -f "$repo/docs/RELEASE-NOTES-$version.md" ] ||
	fail "v$version is tagged, but docs/RELEASE-NOTES-$version.md is missing"
printf 'Changelog record: PASS\n'
