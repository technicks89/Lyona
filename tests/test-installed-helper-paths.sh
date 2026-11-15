#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 16 R16-03: installed helpers use installed paths, never their
# checkout's. Staged as an install (PREFIX/bin, PREFIX/lib/lyona), with a stub
# terminal that records what it was asked to run:
# - the Control Center's dependency check runs the check-deps.sh installed
#   beside it, interactively, which offers the install itself (#500);
# - "install missing dependencies", the action that replaced, and System
#   Health's install-dependencies repair run the same.
# From a checkout, its own check-deps.sh; never install.sh. And no installed
# command computes a checkout path ($0/.. or BASH_SOURCE/..) outside the few
# guarded cases.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

prefix=$work/prefix
stage_helpers prefix "$prefix" dwm-quickshell-controlcenter dwm-system-health check-deps.sh
# The package library the installed fallback sources.
command cp "$repo/scripts/dwm-utils.sh" "$repo/scripts/dwm-packages.sh" "$prefix/lib/lyona/"

# dwm-terminal -e sh -c COMMAND: records COMMAND.
cat >"$work/bin/dwm-terminal" <<'EOF'
#!/bin/sh
shift 3
printf '%s\n' "$1" >>"$STUB_DIR/terminal.log"
EOF
chmod +x "$work/bin/dwm-terminal"
export STUB_DIR=$work DWM_TEST_SYNC=1
run() {
	rm -f "$work/terminal.log"
	env PATH="$work/bin:$PATH" HOME="$work/home" "$@" >/dev/null 2>&1 || :
}
mkdir -p "$work/home"

# Installed: the check-deps.sh beside the helper, and the package library.
for action in dependency-check install-missing-deps; do
	run "$prefix/bin/dwm-quickshell-controlcenter" action "$action"
	[ "$(cat "$work/terminal.log" 2>/dev/null)" = "'$prefix/bin/check-deps.sh' --interactive" ] ||
		fail "the installed $action ran: $(cat "$work/terminal.log" 2>/dev/null)"
done
# System Health's repair is the same action.
run "$prefix/bin/dwm-system-health" repair-user install-dependencies
grep -Fq "check-deps.sh' --interactive" "$work/terminal.log" ||
	fail "System Health's install-dependencies repair ran: $(cat "$work/terminal.log" 2>/dev/null)"

# A checkout: its own check-deps.sh, and never the full installer.
run "$repo/scripts/dwm-quickshell-controlcenter" action install-missing-deps
[ "$(cat "$work/terminal.log" 2>/dev/null)" = "'$repo/scripts/check-deps.sh' --interactive" ] ||
	fail "the checkout's dependency check ran: $(cat "$work/terminal.log" 2>/dev/null)"

# No installed command computes a checkout path, except the guarded few:
# - the Settings provider, whose themes.toml read checks the file exists;
# - lyona-release, a release tool that only runs in a checkout.
mapfile -t installed < <(make -s -C "$repo" -pn 2>/dev/null |
	awk '/^INSTALL_COMMANDS = / { sub(/^INSTALL_COMMANDS = /, ""); print; exit }' | tr ' ' '\n' | grep '^scripts/')
((${#installed[@]} > 20)) || fail 'could not read INSTALL_COMMANDS from the Makefile'
allowed=' scripts/dwm-settings-provider scripts/lyona-release '
for helper in "${installed[@]}"; do
	[[ $allowed == *" $helper "* ]] && continue
	# shellcheck disable=SC2016 # literal $0 and BASH_SOURCE patterns
	if grep -nE '(\$0|BASH_SOURCE\[0\]\}?|script_dir|SCRIPT_DIR)[^ ]*/\.\.' "$repo/$helper" |
		grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
		# shellcheck disable=SC2016 # literal $0 and BASH_SOURCE patterns
		fail "$helper computes a checkout path: $(grep -nE '(\$0|BASH_SOURCE|script_dir|SCRIPT_DIR)[^ ]*/\.\.' "$repo/$helper" | head -1)"
	fi
done

# Sync Sprint 16 R16-48: the shell starts lyona's helpers only through
# Commands.helperCommand, which honours LYONA_DEV_SCRIPTS; a bare helper name in
# a command array would always run the installed one.
bare=$(grep -rnE '\[[[:space:]]*"(dwm|lyona)-[a-z-]+"' "$repo/config/quickshell" --include='*.qml' |
	grep -v 'Commands\.' || true)
[[ -z $bare ]] || fail "QML runs a helper without Commands: $bare"

printf 'Installed helper paths: PASS\n'
