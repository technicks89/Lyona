#!/bin/sh

set -eu

# #533: builds and runs tests/test-fullscreen-state.c, which checks every move
# of fullscreen.h against the logic dwm.c had before it.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

work=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/fullscreen-state.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# shellcheck disable=SC2086 # CFLAGS is a list of flags
${CC:-cc} ${CFLAGS:--O2 -std=c99 -pedantic -Wall -Wextra} -Werror \
	-o "$work/test-fullscreen-state" "$tests_dir/test-fullscreen-state.c"
"$work/test-fullscreen-state"
