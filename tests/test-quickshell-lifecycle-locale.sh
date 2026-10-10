#!/bin/sh
# #280 VM: the managed Quickshell is found under a C locale too. Qt prints its
# "not UTF-8" warning to stdout, which broke `quickshell list --json`, so from a
# TTY, ssh or a service restart-quickshell found no instance and did nothing.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

command -v jq >/dev/null 2>&1 || {
	printf 'SKIP: jq is unavailable\n'
	exit 77
}

bin=$work/bin
mkdir -p "$bin"
# As Qt does: the warning on stdout unless the locale is UTF-8.
cat >"$bin/quickshell" <<'STUB'
#!/bin/sh
[ "$1" = list ] || exit 2
case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
*UTF-8* | *utf8*) ;;
*) printf '  WARN: Detected locale "C" with character encoding "ANSI_X3.4-1968", which is not UTF-8.\n' ;;
esac
printf '[{"config_path": "/x/shell.qml", "pid": 4242}]\n'
STUB
chmod +x "$bin/quickshell"

# shellcheck disable=SC2016 # expanded by the inner shell
pids=$(env -u LANG -u LC_ALL -u LC_CTYPE PATH="$bin:$PATH" lyona_lib="$repo/scripts" sh -c '
	. "$lyona_lib/dwm-quickshell-lifecycle.sh"
	quickshell_instance_pids /x/shell.qml
') || fail 'quickshell_instance_pids failed under a C locale'
[ "$pids" = 4242 ] || fail "under a C locale the managed instance was not found: '$pids'"

printf 'Quickshell lifecycle under a C locale: PASS\n'
