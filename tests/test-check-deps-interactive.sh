#!/usr/bin/env bash
set -euo pipefail

# check-deps.sh --interactive (#500): after its report, it offers to install
# what the shared dependency map would and is not installed, and installs it
# only on a yes, through `sudo pacman -S --needed` (never -y). A no installs
# nothing, a stale package database says to update first, a system that is not
# Arch offers nothing, and the exit status is the report's. sudo and pacman
# are stubs: the real ones are never reached.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

check=$repo/scripts/check-deps.sh
mkdir -p "$work/bin" "$work/home"
printf 'ID=arch\nNAME="Arch Linux"\n' >"$work/os-release"
printf 'ID=debian\nNAME="Debian"\n' >"$work/os-release-other"

# sudo runs its command (the pacman stub below); never the real sudo.
cat >"$work/bin/sudo" <<'EOF'
#!/bin/sh
printf 'sudo %s\n' "$*" >>"$STUB_LOG"
exec "$@"
EOF
# pacman -T prints the arguments listed in $STUB_ABSENT, as pacman does for
# the ones not installed; -S logs and installs them, or fails as asked.
cat >"$work/bin/pacman" <<'EOF'
#!/bin/sh
case $1 in
-T)
	shift
	found=0
	for package in "$@"; do
		if grep -qx -- "$package" "$STUB_ABSENT"; then
			printf '%s\n' "$package"
			found=1
		fi
	done
	[ "$found" = 0 ] || exit 127
	;;
-S*)
	printf 'pacman %s\n' "$*" >>"$STUB_LOG"
	case ${STUB_PACMAN_FAIL:-} in
	stale)
		printf "error: failed retrieving file 'jq-1.7-1-x86_64.pkg.tar.zst' from mirror : The requested URL returned error: 404\n" >&2
		exit 1
		;;
	other) exit 1 ;;
	esac
	shift
	for package in "$@"; do
		[ "$package" = --needed ] && continue
		grep -vx -- "$package" "$STUB_ABSENT" >"$STUB_ABSENT.new" || :
		mv "$STUB_ABSENT.new" "$STUB_ABSENT"
	done
	;;
*) exit 2 ;;
esac
EOF
chmod +x "$work/bin/sudo" "$work/bin/pacman"

# Runs check-deps.sh with ANSWERS on stdin; OUT gets its output, STATUS its exit.
deps() { # OUT ANSWERS [VAR=value...] [-- ARGS...]
	local out=$1 answers=$2
	shift 2
	local -a vars=() args=(--interactive)
	while (($#)); do
		if [[ $1 == -- ]]; then
			shift
			args=("$@")
			break
		fi
		vars+=("$1")
		shift
	done
	status=0
	printf '%b' "$answers" | env DWM_TEST_MODE=1 DWM_OS_RELEASE="$work/os-release" HOME="$work/home" \
		STUB_LOG="$work/stub.log" STUB_ABSENT="$work/absent" PATH="$work/bin:$PATH" "${vars[@]}" \
		"$check" "${args[@]}" >"$out" 2>&1 || status=$?
}

# The report alone, for its status (which the host's commands decide).
: >"$work/absent"
: >"$work/stub.log"
deps "$work/plain.out" '' --
plain_status=$status
[ -s "$work/plain.out" ] || fail 'the report printed nothing'

# Nothing absent: nothing offered, nothing installed, the report's status.
deps "$work/none.out" '\n'
[ "$status" = "$plain_status" ] || fail "status $status, the report's is $plain_status"
grep -Eq '^(Nothing to install\.|Every package the dependency map installs is installed)' "$work/none.out" ||
	fail "nothing absent: $(tail -5 "$work/none.out")"
if grep -q 'Install now' "$work/none.out"; then fail 'an install was offered with nothing absent'; fi
[ ! -s "$work/stub.log" ] || fail "something ran: $(cat "$work/stub.log")"

# Two absent, and a no: listed, asked, nothing installed.
printf 'jq\npicom\n' >"$work/absent"
deps "$work/no.out" 'n\n\n'
grep -Fqx 'Not installed: picom jq' "$work/no.out" || grep -Fqx 'Not installed: jq picom' "$work/no.out" ||
	fail "the absent packages were not listed: $(tail -5 "$work/no.out")"
grep -Fq 'Install now? [y/N]' "$work/no.out" || fail 'no question'
grep -Fq 'Nothing was installed.' "$work/no.out" || fail "a no: $(tail -3 "$work/no.out")"
[ ! -s "$work/stub.log" ] || fail "a no ran: $(cat "$work/stub.log")"
[ "$status" = "$plain_status" ] || fail "a no: status $status"
# An empty answer is a no too.
deps "$work/empty.out" '\n\n'
[ ! -s "$work/stub.log" ] || fail "an empty answer ran: $(cat "$work/stub.log")"

# A yes: exactly the absent ones, through sudo pacman -S --needed, then the
# report again.
deps "$work/yes.out" 'y\n\n'
grep -Eqx 'pacman -S --needed (picom jq|jq picom)' "$work/stub.log" || fail "the install: $(cat "$work/stub.log")"
grep -Eqx 'sudo pacman -S --needed (picom jq|jq picom)' "$work/stub.log" || fail 'pacman did not run through sudo'
grep -Fq 'Checking again:' "$work/yes.out" || fail 'the report did not run again'
[ ! -s "$work/absent" ] || fail 'the stub did not install'
[ "$status" = "$plain_status" ] || fail "after the install: status $status"

# A stale package database: says to update first, and never upgrades itself.
printf 'jq\n' >"$work/absent"
: >"$work/stub.log"
deps "$work/stale.out" 'y\n\n' STUB_PACMAN_FAIL=stale
[ "$status" = 1 ] || fail "a failed install: status $status"
grep -Fq 'Your package database is out of date: update the system first (sudo pacman -Syu), then run this check again.' \
	"$work/stale.out" || fail "no stale database advice: $(tail -5 "$work/stale.out")"
grep -Fq 'The install did not complete.' "$work/stale.out" || fail 'the failure was not reported'
# Another failure: reported, without the database advice.
deps "$work/other.out" 'y\n\n' STUB_PACMAN_FAIL=other
[ "$status" = 1 ] || fail "another failure: status $status"
if grep -q 'out of date' "$work/other.out"; then fail 'the database advice for another failure'; fi
if grep -Eq 'pacman -S[a-z]*y|-Syu' "$work/stub.log"; then fail "the database was refreshed: $(cat "$work/stub.log")"; fi

# Not Arch: nothing offered.
: >"$work/stub.log"
deps "$work/other-os.out" '\n' DWM_OS_RELEASE="$work/os-release-other"
grep -Fq 'Installing needs pacman on Arch Linux; nothing was installed.' "$work/other-os.out" ||
	fail "another system: $(tail -3 "$work/other-os.out")"
[ ! -s "$work/stub.log" ] || fail "another system ran: $(cat "$work/stub.log")"

# A wrong argument.
deps "$work/bad.out" '' -- --install
[ "$status" = 2 ] || fail "a wrong argument: status $status"
# The one pacman command it runs: no refresh (-y), no upgrade, and pacman's
# own confirmation kept (no --noconfirm).
[ "$(grep -E '^[[:space:]]*sudo pacman ' "$check")" = $'\tsudo pacman -S --needed "$@" 2>&1 | tee "$log"' ] ||
	fail "the pacman command changed: $(grep -n 'sudo pacman' "$check")"
if grep -q -- '--noconfirm' "$check"; then fail 'check-deps.sh skips confirmation'; fi

printf 'check-deps.sh --interactive: PASS\n'
