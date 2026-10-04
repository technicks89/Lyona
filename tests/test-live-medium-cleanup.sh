#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 16 R16-01: the live medium's clean-up (archiso/airootfs/root/
# lyona-ui.sh). A file registered in LYONA_CLEANUP_FILES, such as the
# postinstall's passwordless sudoers rule, is gone however the run ends:
# - success;
# - a failure, then "Exit to shell" in the recovery menu;
# - a failure, then Retry (exec, which skips EXIT traps);
# - an interrupt.
# The recovery menu also says what state the machine is in.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

ui=$repo/archiso/airootfs/root/lyona-ui.sh
postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh

# gum: "choose" answers STUB_CHOICE, the rest print their last argument.
cat >"$work/bin/gum" <<'EOF'
#!/bin/sh
case $1 in
choose) printf '%s\n' "${STUB_CHOICE:-Exit to shell}" ;;
*) for last; do :; done; printf '%s\n' "$last" ;;
esac
EOF
chmod +x "$work/bin/gum"

# A run that registers SECRET, creates it, then ends as MODE says. A Retry run
# records whether SECRET was already gone when it started again.
cat >"$work/run.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
. "$UI"
LYONA_CLEANUP_FILES+=("$SECRET")
LYONA_RECOVER_HINT="The base system is installed; lyona is not."
install_error_trap "$@"
if [[ -e $WORK/retried ]]; then
	[[ -e $SECRET ]] && echo present >"$WORK/after-retry" || echo absent >"$WORK/after-retry"
	exit 0
fi
: >"$SECRET"
case $MODE in
ok) exit 0 ;;
fail) false ;;
retry)
	: >"$WORK/retried"
	false
	;;
interrupt)
	kill -INT $$
	sleep 5
	;;
esac
EOF
chmod +x "$work/run.sh"

secret=$work/90-lyona-install
run() { # MODE [CHOICE]
	rm -f "$secret" "$work/retried" "$work/after-retry"
	env PATH="$work/bin:$PATH" UI="$ui" SECRET="$secret" WORK="$work" MODE="$1" STUB_CHOICE="${2:-}" \
		LOG_FILE="$work/log" COLOR_DANGER=1 COLOR_DIM=2 COLOR_ACCENT=3 \
		"$work/run.sh" >"$work/out" 2>&1 || :
}

run ok
[[ ! -e $secret ]] || fail 'a successful run left the file'
run fail 'Exit to shell'
[[ ! -e $secret ]] || fail 'a failed run, then "Exit to shell", left the file'
grep -Fq 'The base system is installed; lyona is not.' "$work/out" || fail "the menu does not say what state the machine is in: $(cat "$work/out")"
run retry Retry
[[ $(cat "$work/after-retry" 2>/dev/null) == absent ]] || fail 'the file was still there when Retry ran the script again'
[[ ! -e $secret ]] || fail 'a retried run left the file'
run interrupt
[[ ! -e $secret ]] || fail 'an interrupted run left the file'

# The postinstall registers its sudoers rule, and removes any stale copy first.
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -Fq 'LYONA_CLEANUP_FILES+=("$install_sudoers")' "$postinstall" ||
	fail 'the postinstall does not register its sudoers rule for clean-up'
# shellcheck disable=SC2016 # the literal text in the postinstall
registered=$(grep -nF 'LYONA_CLEANUP_FILES+=("$install_sudoers")' "$postinstall" | cut -d: -f1)
written=$(grep -nF 'NOPASSWD: ALL' "$postinstall" | cut -d: -f1)
((registered < written)) || fail 'the sudoers rule is written before it is registered for clean-up'

printf 'Live medium clean-up: PASS\n'
