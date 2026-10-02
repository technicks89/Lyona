#!/bin/sh

set -eu

# Sync Sprint 12 S12-14 step 3: lyona-toml, the scripts' one reader of the TOML
# files, built on dwm's own parser (decision D-20). It must print what dwm reads,
# in a form a shell can split: one entry per line, fields separated by tabs, and
# tabs, newlines and backslashes inside a value escaped.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

tool=$repo/lyona-toml
[ -x "$tool" ] || {
	printf 'SKIP: lyona-toml is not built (run make all)\n'
	exit 77
}
tab=$(printf '\t')
us=$(printf '\037')

# The grammar S12-05 pinned: a comment after a value, booleans, a same-line
# array, and an inline table array with one table per line.
cat >"$work/sample.toml" <<'EOF'
# a comment line
[active]
theme = "nord"   # the one to use

[theme.nord]
dark_mode = false
term_bg = "#2E3440"
borderpx = 2
ratio = 0.5
label = "tab	and \\back"
fonts = ["Meslo", "Fira"]

keys = [
  { mod="SUPER", key="Return", func="spawn" },
  { mod="SUPER", key="q", func="killclient" },
]
EOF
"$tool" dump "$work/sample.toml" >"$work/dump"
expect_line() {
	grep -Fqx -- "$1" "$work/dump" || fail "dump has no line: $1"
}
expect_line "active$tab-1${tab}theme${tab}nord"
expect_line "theme.nord$tab-1${tab}dark_mode${tab}false"
expect_line "theme.nord$tab-1${tab}term_bg$tab#2E3440"
expect_line "theme.nord$tab-1${tab}borderpx${tab}2"
expect_line "theme.nord$tab-1${tab}ratio${tab}0.5"
# A tab inside the value is written \t and a backslash \\, so the line is one record.
expect_line "theme.nord$tab-1${tab}label${tab}tab\\tand \\\\back"
expect_line "theme.nord$tab-1${tab}fonts${tab}Meslo${us}Fira"
expect_line "keys${tab}0${tab}key${tab}Return"
expect_line "keys${tab}1${tab}func${tab}killclient"
[ "$(wc -l <"$work/dump")" -eq 13 ] || fail "dump has $(wc -l <"$work/dump") lines, not 13"
awk -F'\t' 'NF != 4 { bad = 1 } END { exit bad }' "$work/dump" ||
	fail 'a dump line does not have exactly four fields'

# get: the value alone, as dwm's toml_get finds it.
assert_equals nord "$("$tool" get "$work/sample.toml" active theme)"
assert_equals false "$("$tool" get "$work/sample.toml" theme.nord dark_mode)"
status=0
"$tool" get "$work/sample.toml" theme.nord missing >/dev/null || status=$?
assert_equals 1 "$status" 'an absent key'

# Unreadable, and usage.
status=0
"$tool" dump "$work/missing.toml" >/dev/null 2>&1 || status=$?
assert_equals 3 "$status" 'a missing file'
status=0
"$tool" dump >/dev/null 2>&1 || status=$?
assert_equals 2 "$status" 'no file'
status=0
"$tool" frobnicate "$work/sample.toml" >/dev/null 2>&1 || status=$?
assert_equals 2 "$status" 'an unknown action'

# More entries than dwm keeps: the first 512 are printed, as dwm would see them,
# and the status and stderr say the rest were ignored.
{
	printf '[a]\n'
	i=0
	while [ "$i" -lt 600 ]; do
		printf 'k%d = %d\n' "$i" "$i"
		i=$((i + 1))
	done
} >"$work/long.toml"
status=0
"$tool" dump "$work/long.toml" >"$work/long.dump" 2>"$work/long.err" || status=$?
assert_equals 4 "$status" 'a truncated file'
assert_equals 512 "$(wc -l <"$work/long.dump")" 'entries printed from a truncated file'
grep -Fq 'has more than 512 entries; the rest were ignored' "$work/long.err" ||
	fail 'no truncation message'

# The shipped files read cleanly, one line per entry.
for shipped in hotkeys themes window-rules; do
	"$tool" dump "$repo/config/$shipped.toml" >"$work/$shipped.dump" ||
		fail "config/$shipped.toml did not read cleanly"
	[ -s "$work/$shipped.dump" ] || fail "config/$shipped.toml dumped nothing"
done

# dwm-paths.sh's lyona_toml finds the tool in both layouts: beside an installed
# caller's libraries in PREFIX/lib/lyona, and beside scripts/ in a checkout.
# A caller of lyona_toml, staged as installed, brings dwm-paths.sh and the tool.
stage_helpers prefix "$work/prefix" dwm-settings-theme
# shellcheck disable=SC2016 # expanded by the inner shell
assert_equals nord "$(bash -c '. "$1/dwm-paths.sh"; lyona_lib=$1; lyona_toml get "$2" active theme' \
	sh "$work/prefix/lib/lyona" "$work/sample.toml")" 'lyona_toml, installed'
# shellcheck disable=SC2016 # expanded by the inner shell
assert_equals nord "$(bash -c '. "$1/dwm-paths.sh"; lyona_lib=$1; lyona_toml get "$2" active theme' \
	sh "$repo/scripts" "$work/sample.toml")" 'lyona_toml, checkout'

printf 'lyona-toml reader (dump, get, escaping, exit codes, truncation, lookup): PASS\n'
