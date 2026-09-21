#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
helper=$repo/scripts/install-gearlever
setup=$repo/scripts/dwm-flatpak-setup
make_workspace

mock_bin=$work/bin
state=$work/state
log=$work/flatpak.log
mime_log=$work/xdg-mime.log
mkdir -p "$mock_bin" "$state"

cat >"$mock_bin/flatpak" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$MOCK_FLATPAK_LOG"

case $1 in
info)
	case $2 in
	--user) test -f "$MOCK_FLATPAK_STATE/user-app" ;;
	--system) test -f "$MOCK_FLATPAK_STATE/system-app" ;;
	*) exit 2 ;;
	esac
	;;
remotes)
	[[ ${MOCK_FLATPAK_REMOTES_FAIL:-false} != true ]] || exit 1
	# A state file per scope holds the remote's options column.
	if [[ -f $MOCK_FLATPAK_STATE/${2#--}-remote ]]; then
		printf 'flathub\t%s\t%s\n' "${MOCK_FLATPAK_REMOTE_URL:-https://dl.flathub.org/repo/}" \
			"$(cat "$MOCK_FLATPAK_STATE/${2#--}-remote")"
	fi
	;;
remote-add)
	printf '%s\n' "${MOCK_FLATPAK_ADDED_OPTIONS:-}" >"$MOCK_FLATPAK_STATE/${2#--}-remote"
	;;
install)
	if [[ ${MOCK_FLATPAK_INSTALL_FAIL:-false} == true ]]; then
		exit 1
	fi
	touch "$MOCK_FLATPAK_STATE/user-app"
	;;
*) exit 2 ;;
esac
MOCK
chmod +x "$mock_bin/flatpak"

cat >"$mock_bin/xdg-mime" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$MOCK_XDG_MIME_LOG"
case $1 in
query)
	if [[ -f $MOCK_FLATPAK_STATE/mime-default ]]; then
		printf '%s\n' it.mijorus.gearlever.desktop
	fi
	;;
default)
	[[ $2 == it.mijorus.gearlever.desktop ]]
	[[ $3 == application/vnd.appimage ]]
	touch "$MOCK_FLATPAK_STATE/mime-default"
	;;
*) exit 2 ;;
esac
MOCK
chmod +x "$mock_bin/xdg-mime"

run_helper() {
	PATH="$mock_bin:$PATH" \
		MOCK_FLATPAK_LOG="$log" \
		MOCK_FLATPAK_STATE="$state" \
		MOCK_XDG_MIME_LOG="$mime_log" \
		bash "$helper"
}

run_helper >"$work/install.out"
grep -Fqx 'remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$log"
grep -Fqx 'install --user --noninteractive flathub it.mijorus.gearlever' "$log"
# The remote is verified (disabled remotes included) before anything installs,
# and again after it was added.
verify_query='remotes --user --show-disabled --columns=name,url,options'
grep -Fqx "$verify_query" "$log"
verify_line=$(grep -nFx "$verify_query" "$log" | head -n 1 | cut -d: -f1)
add_line=$(grep -n '^remote-add ' "$log" | head -n 1 | cut -d: -f1)
install_line=$(grep -n '^install ' "$log" | head -n 1 | cut -d: -f1)
last_verify_line=$(grep -nFx "$verify_query" "$log" | tail -n 1 | cut -d: -f1)
if ! ((verify_line < add_line && add_line < last_verify_line && last_verify_line < install_line)); then
	printf 'Gear Lever did not verify the Flathub remote around adding it and before installing.\n' >&2
	cat "$log" >&2
	exit 1
fi
grep -Fq 'Adding the official user Flathub remote' "$work/install.out"
grep -Fqx 'default it.mijorus.gearlever.desktop application/vnd.appimage' "$mime_log"
grep -Fq 'Gear Lever is ready.' "$work/install.out"

before=$(wc -l <"$log")
run_helper >"$work/idempotent.out"
after=$(wc -l <"$log")
if ((after != before + 1)); then
	printf 'Idempotent Gear Lever setup unexpectedly changed Flatpak state.\n' >&2
	exit 1
fi
# An app that is already installed never depends on the remote being healthy.
if tail -n +"$((before + 1))" "$log" | grep -Eq '^(remotes|remote-add) '; then
	printf 'An installed Gear Lever still consulted the Flathub remote.\n' >&2
	exit 1
fi
grep -Fq 'Gear Lever is already installed for' "$work/idempotent.out"

rm -f "$state/user-app" "$state/user-remote"
touch "$state/system-app"
: >"$log"
run_helper >"$work/system.out"
grep -Fqx 'info --user it.mijorus.gearlever' "$log"
grep -Fqx 'info --system it.mijorus.gearlever' "$log"
if grep -Eq '^(remote-add|install) ' "$log"; then
	printf 'Gear Lever setup duplicated an existing system installation.\n' >&2
	exit 1
fi
grep -Fq 'Gear Lever is already installed system-wide.' "$work/system.out"

rm -f "$state/system-app" "$state/mime-default"
touch "$state/user-remote"
if PATH="$mock_bin:$PATH" \
	MOCK_FLATPAK_LOG="$log" \
	MOCK_FLATPAK_STATE="$state" \
	MOCK_FLATPAK_REMOTE_URL=https://example.invalid/repo/ \
	MOCK_XDG_MIME_LOG="$mime_log" \
	bash "$helper" >"$work/untrusted.out" 2>"$work/untrusted.err"; then
	printf 'Gear Lever setup trusted a non-official Flathub remote.\n' >&2
	exit 1
fi
grep -Fq 'Refusing non-official user Flathub remote URL' "$work/untrusted.err"

touch "$state/user-remote"
if PATH="$mock_bin:$PATH" \
	MOCK_FLATPAK_LOG="$log" \
	MOCK_FLATPAK_STATE="$state" \
	MOCK_XDG_MIME_LOG="$mime_log" \
	MOCK_FLATPAK_INSTALL_FAIL=true \
	bash "$helper" >"$work/failure.out" 2>"$work/failure.err"; then
	printf 'Gear Lever setup ignored a failed Flatpak install.\n' >&2
	exit 1
fi

# Every refusal stops before anything is added or installed, and says why.
# expect_refused MESSAGE: run the installer against the current state.
expect_refused() {
	: >"$log"
	if run_helper >"$work/refused.out" 2>"$work/refused.err"; then
		printf 'Gear Lever setup went ahead: expected "%s".\n' "$1" >&2
		cat "$work/refused.err" >&2
		exit 1
	fi
	# A failed remotes query has no message of its own, only the refusal.
	[[ -z $1 ]] || grep -Fq "$1" "$work/refused.err" || {
		printf 'Expected "%s"; got:\n' "$1" >&2
		cat "$work/refused.err" >&2
		exit 1
	}
	if grep -Eq '^(install|remote-add) ' "$log"; then
		printf 'Gear Lever setup changed Flatpak state despite refusing: %s\n' "$1" >&2
		cat "$log" >&2
		exit 1
	fi
	[[ ! -e $state/user-app ]] || fail "an app was installed despite: $1"
}
reset_flatpak() { rm -f "$state"/user-app "$state"/system-app "$state"/user-remote "$state"/system-remote; }

reset_flatpak
printf 'no-gpg-verify\n' >"$state/user-remote"
expect_refused 'signature verification disabled'

reset_flatpak
printf 'user,no-gpg-verify\n' >"$state/user-remote"
expect_refused 'signature verification disabled'

reset_flatpak
printf 'disabled\n' >"$state/user-remote"
expect_refused 'Flathub remote is disabled'

reset_flatpak
printf 'user,no-enumerate,disabled\n' >"$state/user-remote"
expect_refused 'Flathub remote is disabled'

reset_flatpak
printf '\n' >"$state/user-remote"
MOCK_FLATPAK_REMOTE_URL=https://example.invalid/repo/ expect_refused 'Refusing non-official user Flathub remote URL'

reset_flatpak
printf '\n' >"$state/user-remote"
MOCK_FLATPAK_REMOTES_FAIL=true expect_refused ''

# A remote that was just added must verify too: an unsigned one is refused,
# after the add but before the install.
reset_flatpak
: >"$log"
if MOCK_FLATPAK_ADDED_OPTIONS=no-gpg-verify run_helper >"$work/unverified.out" 2>"$work/unverified.err"; then
	printf 'Gear Lever installed from a remote that failed verification after being added.\n' >&2
	exit 1
fi
grep -Fq 'signature verification disabled' "$work/unverified.err"
grep -Fq 'could not be verified after setup' "$work/unverified.err"
grep -Eq '^remote-add ' "$log"
if grep -Eq '^install ' "$log"; then
	printf 'Gear Lever installed after its remote failed verification.\n' >&2
	exit 1
fi

# Other options do not block a healthy official remote, and nothing is re-added.
reset_flatpak
printf 'user,no-enumerate\n' >"$state/user-remote"
: >"$log"
run_helper >"$work/options.out"
grep -Eq '^install ' "$log"
if grep -Eq '^remote-add ' "$log"; then
	printf 'A verified official remote was added again.\n' >&2
	exit 1
fi

# The setup helper on its own: usage, missing Flatpak, and the system scope.
run_setup() {
	PATH="$mock_bin:$PATH" \
		MOCK_FLATPAK_LOG="$log" \
		MOCK_FLATPAK_STATE="$state" \
		bash "$setup" "$@"
}
setup_status=0
run_setup >"$work/usage.out" 2>"$work/usage.err" || setup_status=$?
[[ $setup_status == 2 ]] || fail "dwm-flatpak-setup without a scope exited $setup_status, not 2"
grep -Fq 'Usage: dwm-flatpak-setup --user|--system' "$work/usage.err"
setup_status=0
run_setup --nope >"$work/usage.out" 2>"$work/usage.err" || setup_status=$?
[[ $setup_status == 2 ]] || fail "dwm-flatpak-setup accepted an unknown scope (exit $setup_status)"
grep -Fq 'Usage: dwm-flatpak-setup --user|--system' "$work/usage.err"
setup_status=0
run_setup --user --system >"$work/usage.out" 2>"$work/usage.err" || setup_status=$?
[[ $setup_status == 2 ]] || fail "dwm-flatpak-setup accepted two scopes (exit $setup_status)"

mkdir -p "$work/empty-bin"
if PATH="$work/empty-bin" "$BASH" "$setup" --user >"$work/noflatpak.out" 2>"$work/noflatpak.err"; then
	fail 'dwm-flatpak-setup succeeded without flatpak'
fi
grep -Fq 'requires the flatpak package' "$work/noflatpak.err"

reset_flatpak
: >"$log"
run_setup --system >"$work/system-setup.out"
grep -Fqx 'remotes --system --show-disabled --columns=name,url,options' "$log"
grep -Fqx 'remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' "$log"
grep -Fq 'Flatpak and system Flathub are ready.' "$work/system-setup.out"
printf 'no-gpg-verify\n' >"$state/system-remote"
if run_setup --system >"$work/system-refused.out" 2>"$work/system-refused.err"; then
	fail 'the system-scope setup accepted an unsigned remote'
fi
grep -Fq 'The system Flathub remote has signature verification disabled' "$work/system-refused.err"
# Scopes are independent: a healthy user remote is untouched by the system one.
reset_flatpak
printf '\n' >"$state/user-remote"
run_setup --user >"$work/user-setup.out"
grep -Fq 'Flatpak and user Flathub are ready.' "$work/user-setup.out"

# The helper is found by its own path even when CDPATH makes `cd` print one:
# with a scripts directory earlier on CDPATH, an unguarded lookup lands in the
# wrong directory and yields two lines.
reset_flatpak
printf '\n' >"$state/user-remote"
mkdir -p "$work/cdpath/scripts"
: >"$log"
(cd "$repo" && CDPATH="$work/cdpath" PATH="$mock_bin:$PATH" \
	MOCK_FLATPAK_LOG="$log" MOCK_FLATPAK_STATE="$state" MOCK_XDG_MIME_LOG="$mime_log" \
	bash scripts/install-gearlever) >"$work/cdpath.out" 2>"$work/cdpath.err" ||
	fail "install-gearlever failed with CDPATH set: $(cat "$work/cdpath.err")"
grep -Eq '^install ' "$log" || fail 'install-gearlever did not install with CDPATH set'

"$repo/install.sh" --dry-run --non-interactive --profile recommended \
	>"$work/install-plan.out"
grep -Fq 'Gear Lever: user-scoped Flathub install (it.mijorus.gearlever)' \
	"$work/install-plan.out"

printf '%s\n' 'Gear Lever setup: PASS'
