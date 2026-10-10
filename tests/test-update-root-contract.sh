#!/bin/sh
set -eu

# #337: an update is installed by the root helper already on the system, which
# reads the new release's tree through its Makefile. What it reads is a contract
# (SPEC.md section 6, "The release-tree contract"): the previous release's
# helper, taken from the newest tag reachable from HEAD, must still find every
# variable and target it names in the current tree. Without a reachable tag (a
# clone without tags) the current helper stands in, so its reads are checked
# against the tree all the same.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

make_workspace
helper_src=$work/previous-helper
tag=$(git -C "$repo" describe --tags --abbrev=0 HEAD 2>/dev/null || true)
if [ -n "$tag" ] && git -C "$repo" show "$tag:scripts/lyona-update-root" >"$helper_src" 2>/dev/null; then
	printf 'previous release: %s\n' "$tag"
else
	cp "$repo/scripts/lyona-update-root" "$helper_src"
	printf 'no previous release tag reachable; checking the current helper against the tree\n'
fi

make_values() { # EXPR: the words the tree's Makefile expands EXPR to, as the helper reads them
	make -s -C "$repo" --no-print-directory \
		--eval="lyona-root-print: ; @printf '%s\\n' $1" lyona-root-print
}

# Every Makefile expression the helper reads expands to something.
grep -o "tree_make_values \"\$[a-z_]*\" '[^']*'" "$helper_src" | sed "s/^[^']*'//; s/'\$//" |
	sort -u >"$work/exprs"
[ -s "$work/exprs" ] || fail 'the helper reads no Makefile values (the extraction found none)'
while IFS= read -r expr; do
	values=$(make_values "$expr" 2>"$work/make.err") ||
		fail "the tree's Makefile cannot expand $expr: $(cat "$work/make.err")"
	[ -n "$(printf '%s' "$values" | tr -d '[:space:]')" ] ||
		fail "the tree's Makefile expands $expr to nothing, which the installed helper relies on"
done <"$work/exprs"

# The targets the helper asks make for exist in the tree.
for target in all-root dwm clean install-system; do
	make -n -C "$repo" "$target" >/dev/null 2>"$work/make.err" ||
		fail "the tree has no $target target: $(head -3 "$work/make.err")"
done
# all-root never includes config.h: only dwm.c does, and dwm.o is not in it.
all_root=$(make_values '$(filter-out dwm.o,$(OBJ)) $(THUMB) $(TOML_TOOL) $(XWATCH)')
case " $(printf '%s' "$all_root" | tr '\n' ' ') " in
*" dwm.o "*) fail 'all-root would build dwm.o as root' ;;
esac
[ "$(grep -l '#include "config.h"' "$repo"/*.c)" = "$repo/dwm.c" ] ||
	fail 'a source other than dwm.c includes config.h, so all-root would compile it as root'

# The record fields the helper reads are the ones stamp-system writes.
for key in LYONA_PREFIX LYONA_MANPREFIX LYONA_DATADIR LYONA_XSESSIONSDIR; do
	grep -Fq "$key" "$helper_src" || continue
	grep -Fq "'$key=%s" "$repo/Makefile" || fail "stamp-system no longer writes $key, which the helper reads"
done

printf 'Update root helper contract: PASS\n'
