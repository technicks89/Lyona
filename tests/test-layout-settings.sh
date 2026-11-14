#!/usr/bin/env bash
set -euo pipefail

# scripts/dwm-layout-settings (#479), without X: what set writes to
# layout.toml, what it refuses, the backup it keeps, and how state and watch
# read dwm's properties (through a stub xprop).

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper=$repo/scripts/dwm-layout-settings
config=$work/config
layout=$config/lyona/layout.toml
run() {
	env HOME="$work/home" XDG_CONFIG_HOME="$config" PATH="$work/bin:$PATH" "$helper" "$@"
}
expect_fail() { # MESSAGE ARGS...
	local message=$1
	shift
	if run "$@" >"$work/out" 2>"$work/err"; then
		fail "accepted: $*"
	fi
	grep -Fq -- "$message" "$work/err" || fail "for $*: expected '$message', got: $(cat "$work/err")"
}
mkdir -p "$work/home" "$work/bin"

# Values merge into one entry per monitor and tag, sorted; "default" removes
# a value, and an entry left with none is dropped.
[[ $(run set 1 5 gap 12) == $'layout-settings-result\tok' ]]
run set 0 2 mfact 60 >/dev/null
run set 0 2 nmaster 2 >/dev/null
run set 0 1 gap 8 >/dev/null
run set 0 1 gap default >/dev/null
grep -v '^#' "$layout" | awk 'NF' >"$work/entries"
diff -u - "$work/entries" <<'EOF'
layouts = [
  { monitor=0, tag=2, mfact=60, nmaster=2 },
  { monitor=1, tag=5, gap=12 },
]
EOF
[[ $(stat -c %a "$layout") == 644 ]]
# The previous file is kept, and the result is what dwm's parser reads.
[[ -f $layout.bak ]]
"$repo/lyona-toml" dump "$layout" | grep -Fqx $'layouts\t0\tmfact\t60'
# Nothing left: an empty list on one line, which dwm's parser reads.
run set 0 2 mfact default >/dev/null
run set 0 2 nmaster default >/dev/null
run set 1 5 gap default >/dev/null
grep -Fqx 'layouts = []' "$layout"

# A hand-written file is read, its out-of-range values dropped, its comments
# not kept (the backup has them).
cat >"$layout" <<'EOF'
# mine
layouts = [
  { monitor=0, tag=3, mfact=99, gap=6 },
  { monitor=0, tag=10, gap=6 },
]
EOF
run set 0 4 nmaster 3 >/dev/null
grep -Fqx '  { monitor=0, tag=3, gap=6 },' "$layout"
grep -Fqx '  { monitor=0, tag=4, nmaster=3 },' "$layout"
if grep -Fq 'tag=10' "$layout"; then fail "an out-of-range tag was kept"; fi
grep -Fqx '# mine' "$layout.bak"

# Refused, with the file unchanged.
before=$(sha256sum "$layout")
expect_fail 'monitor must be 0-15' set 16 1 gap 1
expect_fail 'tag must be 1-9' set 0 0 gap 1
expect_fail 'tag must be 1-9' set 0 10 gap 1
expect_fail 'field must be mfact, nmaster or gap' set 0 1 size 1
expect_fail 'mfact must be 5-95 or default' set 0 1 mfact 4
expect_fail 'nmaster must be 0-20 or default' set 0 1 nmaster 21
expect_fail 'gap must be 0-64 or default' set 0 1 gap 65
expect_fail 'gap must be 0-64 or default' set 0 1 gap 08
expect_fail 'gap must be 0-64 or default' set 0 1 gap -1
expect_fail 'set takes MONITOR TAG FIELD VALUE' set 0 1 gap
[[ $(sha256sum "$layout") == "$before" ]]

# A symlink is never written through: the file, or a directory on the way.
mv "$layout" "$work/real.toml"
ln -s "$work/real.toml" "$layout"
expect_fail 'not a regular file' set 0 1 gap 2
rm "$layout"
mv "$config/lyona" "$work/real-lyona"
ln -s "$work/real-lyona" "$config/lyona"
expect_fail 'refusing a symlinked path' set 0 1 gap 2
rm "$config/lyona"
mv "$work/real-lyona" "$config/lyona"

# state and watch, from xprop's output.
cat >"$work/bin/xprop" <<'EOF'
#!/bin/sh
case " $* " in
*" -spy "*)
	printf '%s\n' '_DWM_LAYOUT_SETTINGS(CARDINAL) = 0, 1, 55, 1, 0' '_DWM_LAYOUT(CARDINAL) = 0' \
		'_DWM_LAYOUT_SETTINGS(CARDINAL) = 0, 1, 55, 1, 8' 'WM_NAME(STRING) = "x"' \
		'_DWM_LAYOUT(CARDINAL) = 2'
	;;
*) printf '%s\n' '_DWM_LAYOUT_SETTINGS(CARDINAL) = 1, 6, 40, 2, 12' '_DWM_LAYOUT(CARDINAL) = 1' ;;
esac
EOF
chmod +x "$work/bin/xprop"
[[ $(run state) == $'layout-settings\t1\t6\t40\t2\t12\t1' ]]
diff -u - <(run watch) <<'EOF'
layout-settings	0	1	55	1	0	-1
layout-settings	0	1	55	1	0	0
layout-settings	0	1	55	1	8	0
layout-settings	0	1	55	1	8	2
EOF
# No property (dwm before #479), or a malformed one: unavailable.
printf '#!/bin/sh\nprintf "%%s\\n" "_DWM_LAYOUT_SETTINGS:  not found."\n' >"$work/bin/xprop"
[[ $(run state) == $'layout-settings\tunavailable' ]]
printf '#!/bin/sh\nprintf "%%s\\n" "_DWM_LAYOUT_SETTINGS(CARDINAL) = 1, 2"\n' >"$work/bin/xprop"
[[ $(run state) == $'layout-settings\tunavailable' ]]

printf 'dwm-layout-settings: PASS\n'
