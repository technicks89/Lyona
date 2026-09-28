#!/bin/sh

set -eu

# Sync Sprint 12 S12-05: builds and runs tests/test-tomlparser.c against the real
# tomlparser.c. The table counts for the shipped files come from this script's own
# line count (every "{ ... }" line inside an array), so the parser has to find
# exactly what is written there.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

work=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/tomlparser.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# tables FILE ARRAY: how many "{" lines sit between "ARRAY = [" and its "]".
tables() {
	awk -v want="$2" '
		$0 ~ "^" want "[[:space:]]*=[[:space:]]*\\[[[:space:]]*$" { inside = 1; next }
		inside && /^[[:space:]]*\]/ { inside = 0 }
		inside && /^[[:space:]]*\{/ { n++ }
		END { print n + 0 }' "$1"
}

hotkeys=$repo/config/hotkeys.toml
rules=$repo/config/window-rules.toml
keys=$(tables "$hotkeys" keys)
tag_keys=$(tables "$hotkeys" tag_keys)
buttons=$(tables "$hotkeys" buttons)
rule_count=$(tables "$rules" rules)
[ "$keys" -gt 0 ] && [ "$tag_keys" -gt 0 ] && [ "$rule_count" -gt 0 ] || {
	printf 'could not count the shipped tables (keys=%s tag_keys=%s rules=%s)\n' \
		"$keys" "$tag_keys" "$rule_count" >&2
	exit 1
}

# shellcheck disable=SC2086 # CFLAGS is a list of flags
${CC:-cc} ${CFLAGS:--O2 -std=c99 -pedantic -Wall -Wextra} -D_XOPEN_SOURCE=700L -D_DEFAULT_SOURCE \
	-o "$work/test-tomlparser" "$tests_dir/test-tomlparser.c" "$repo/tomlparser.c" "$repo/util.c"
"$work/test-tomlparser" "$work" "$hotkeys" "$keys" "$tag_keys" "$buttons" \
	"$rules" "$rule_count" "$repo/config/themes.toml"
