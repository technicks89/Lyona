#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 12 S12-14 step 4: every script that reads themes.toml sees the
# active theme dwm sees. lyona-toml is dwm's own parser (D-20), so it gives the
# answer; theme-apply.sh, the control center and the appearance provider must
# match it on files the old per-script readers disagreed on.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

[[ -x $repo/lyona-toml ]] || {
	printf 'SKIP: lyona-toml is not built (run make all)\n'
	exit 77
}

home=$work/home
config_home=$home/.config
mkdir -p "$config_home/lyona" "$home/.local/share" "$home/.local/state"
without_active=$work/themes-without-active.toml
awk '/^\[active\]/ { skip = 1; next } /^\[/ { skip = 0 } !skip' \
	"$repo/config/themes.toml" >"$without_active"

run_env() {
	env -i HOME="$home" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$config_home" \
		XDG_DATA_HOME="$home/.local/share" XDG_STATE_HOME="$home/.local/state" \
		XDG_RUNTIME_DIR="$work/runtime" DWM_APPEARANCE_CURSOR_HELPER=/usr/bin/true \
		DWM_APPEARANCE_PICOM_HELPER=/usr/bin/true "$@"
}
mkdir -p "$work/runtime"
chmod 700 "$work/runtime"

check_case() { # NAME ACTIVE-SECTION-TEXT
	local name=$1 expected got
	{
		printf '%b' "$2"
		cat "$without_active"
	} >"$config_home/lyona/themes.toml"
	expected=$("$repo/lyona-toml" get "$config_home/lyona/themes.toml" active theme)
	[[ -n $expected ]] || fail "$name: dwm reads no active theme"

	got=$(run_env "$repo/scripts/dwm-quickshell-controlcenter" themes 2>/dev/null |
		awk -F'\t' '$1 == "active" && !seen++ { print $2 }')
	[[ $got == "$expected" ]] || fail "$name: the control center read '$got', dwm reads '$expected'"

	got=$(run_env "$repo/scripts/dwm-settings-appearance" snapshot 2>/dev/null |
		awk -F'\t' '$1 == "active" && !seen++ { print $2 }')
	[[ $got == "$expected" ]] || fail "$name: Settings read '$got', dwm reads '$expected'"

	got=$(run_env "$repo/scripts/theme-apply.sh" 2>&1 |
		sed -n "s/^theme-apply: applied theme '\\(.*\\)'\$/\\1/p")
	[[ $got == "$expected" ]] || fail "$name: theme-apply.sh applied '$got', dwm reads '$expected'"
}

# No spaces around "=": the control center's old reader needed one.
check_case no-spaces '[active]\ntheme="dracula"\n\n'
# A comment after the value, and a # inside the quoted string.
check_case trailing-comment '[active]\ntheme = "dracula"   # the one to use\n\n'
check_case comment-header '[active] # selected theme\ntheme = "gruvbox"\n\n'

# The readers that stay (S12-14): the two ISO-build generators and the Makefile's
# theme ids read only the shipped file, when lyona-toml may not be built. They
# must read it exactly as dwm does.
shipped=$repo/config/themes.toml
"$repo/lyona-toml" dump "$shipped" >"$work/shipped.dump"
for generator in lyona-plymouth-theme lyona-console-theme; do
	sed -n '/^toml_get() {$/,/^}$/p' "$repo/scripts/$generator" >"$work/$generator.reader"
	[[ -s $work/$generator.reader ]] || fail "$generator has no toml_get to compare"
	# shellcheck disable=SC2016 # expanded by the inner shell
	mismatches=$(bash -c '
		. "$1"
		while IFS= read -r line; do
			section=${line%%$'"'"'\t'"'"'*}; rest=${line#*$'"'"'\t'"'"'}
			index=${rest%%$'"'"'\t'"'"'*}; rest=${rest#*$'"'"'\t'"'"'}
			key=${rest%%$'"'"'\t'"'"'*}; want=${rest#*$'"'"'\t'"'"'}
			[[ $index == -1 && $section == theme.* ]] || continue
			got=$(toml_get "$section" "$key" "$2")
			[[ $got == "$want" ]] || printf "%s %s: %s, dwm reads %s\n" "$section" "$key" "$got" "$want"
		done <"$3"' sh "$work/$generator.reader" "$shipped" "$work/shipped.dump")
	[[ -z $mismatches ]] || fail "$generator reads the shipped themes unlike dwm:
$mismatches"
done
make_ids=$(awk '/^\[theme\./ { id = $0; sub(/^\[theme\./, "", id); sub(/\].*$/, "", id); print id; }' "$shipped")
dwm_ids=$(awk -F'\t' '$2 == -1 && $1 ~ /^theme\./ { id = $1; sub(/^theme\./, "", id); if (!seen[id]++) print id }' \
	"$work/shipped.dump")
[[ $make_ids == "$dwm_ids" ]] || fail "the Makefile's theme ids differ from dwm's:
$(diff <(printf '%s\n' "$make_ids") <(printf '%s\n' "$dwm_ids") || true)"
grep -Fq "awk '/^\\[theme\\./ { id = \$\$0; sub(/^\\[theme\\./, \"\", id); sub(/\\].*\$\$/, \"\", id); print id; }' config/themes.toml" \
	"$repo/Makefile" || fail 'the Makefile no longer lists theme ids this way; update this pin'

printf 'Theme readers agree with dwm (no spaces, trailing comment, commented header; the build-time readers): PASS\n'
