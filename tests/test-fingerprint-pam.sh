#!/usr/bin/env bash
set -euo pipefail

# lyona-fingerprint-pam (#483), against a fake root: fprintd is added to one use
# at a time as a "sufficient" line after the header, nothing else changes, and
# turning it off restores the file byte for byte; a file edited since loses only
# Lyona's lines; polkit's /etc copy is created and removed; lines Lyona did not
# add are reported and left alone unless remove-external is asked; bad input and
# symlinks are refused.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
tool=$repo/scripts/lyona-fingerprint-pam
r=$work/root
mkdir -p "$r/etc/pam.d" "$r/usr/lib/pam.d" "$r/usr/lib/security"
: >"$r/usr/lib/security/pam_fprintd.so"
cat >"$r/etc/pam.d/lightdm" <<'PAM'
#%PAM-1.0
auth        include     system-login
-auth       optional    pam_gnome_keyring.so
account     include     system-login
password    include     system-login
session     include     system-login
-session    optional    pam_gnome_keyring.so auto_start
PAM
printf '#%%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n' >"$r/etc/pam.d/sudo"
printf '#%%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\npassword   include      system-auth\nsession    include      system-auth\n' \
	>"$r/usr/lib/pam.d/polkit-1"
chmod 640 "$r/etc/pam.d/sudo"
for f in lightdm sudo; do cp -p "$r/etc/pam.d/$f" "$work/$f.orig"; done
cp -p "$r/usr/lib/pam.d/polkit-1" "$work/polkit-1.vendor"

run() { "$tool" --root "$r" "$@"; }
state_of() { run status | awk -F '\t' -v use="$1" '$1 == "use" && $2 == use { print $3 }'; }
expect_fail() { # MESSAGE ARGS...
	local message=$1
	shift
	if run "$@" >"$work/out" 2>"$work/err"; then fail "accepted: $*"; fi
	grep -Fq -- "$message" "$work/err" || fail "for $*: expected '$message', got: $(cat "$work/err")"
}

# All off to begin with.
for use in lightdm polkit sudo; do [[ $(state_of $use) == off ]] || fail "$use: $(run status)"; done
[[ $(run status) == *$'\nmodule\tavailable\t/usr/lib/security/pam_fprintd.so\n'* ]] || fail "module: $(run status)"

# On: two lines after the header, nothing else changed, mode kept.
[[ $(run enable lightdm) == $'fingerprint-pam-result\tenable\tlightdm\ton' ]] || fail 'enable lightdm'
[[ $(state_of lightdm) == on ]] || fail "after enable: $(run status)"
[[ $(sed -n 2p "$r/etc/pam.d/lightdm") == '# lyona-fingerprint: added by Lyona Settings > Fingerprint; turn it off there' ]] ||
	fail "line 2: $(sed -n 2p "$r/etc/pam.d/lightdm")"
[[ $(sed -n 3p "$r/etc/pam.d/lightdm") == '-auth      sufficient  pam_fprintd.so timeout=10 max-tries=3' ]] ||
	fail "line 3: $(sed -n 3p "$r/etc/pam.d/lightdm")"
diff <(sed '2,3d' "$r/etc/pam.d/lightdm") "$work/lightdm.orig" >/dev/null || fail 'enable changed other lines'
# Again: nothing more.
[[ $(run enable lightdm) == *already ]] || fail 'a second enable was not a no-op'
[[ $(grep -c pam_fprintd "$r/etc/pam.d/lightdm") == 1 ]] || fail 'a second enable added another line'
# Off: the original, byte for byte, and no state left.
[[ $(run disable lightdm) == *restored ]] || fail 'disable did not restore'
cmp "$r/etc/pam.d/lightdm" "$work/lightdm.orig" || fail 'lightdm is not the original'
# Only the use's lock stays.
[[ -z $(find "$r/var/lib/lyona/fingerprint" -name 'lightdm.*' ! -name lightdm.lock) ]] || fail 'state was left behind'
[[ $(run disable lightdm) == *already ]] || fail 'a second disable was not a no-op'

# The mode of a file that is not 0644 is kept, and restored.
run enable sudo >/dev/null
[[ $(stat -c %a "$r/etc/pam.d/sudo") == 640 ]] || fail "sudo is mode $(stat -c %a "$r/etc/pam.d/sudo")"
run disable sudo >/dev/null
cmp "$r/etc/pam.d/sudo" "$work/sudo.orig" || fail 'sudo is not the original'
[[ $(stat -c %a "$r/etc/pam.d/sudo") == 640 ]] || fail 'sudo lost its mode'

# Edited since it was turned on: only Lyona's two lines go, after a copy.
run enable sudo >/dev/null
printf 'session\t\toptional\tpam_echo.so\n' >>"$r/etc/pam.d/sudo"
[[ $(run disable sudo) == *removed ]] || fail 'disable of an edited file'
diff "$r/etc/pam.d/sudo" <(
	cat "$work/sudo.orig"
	printf 'session\t\toptional\tpam_echo.so\n'
) >/dev/null ||
	fail "an edited sudo: $(cat "$r/etc/pam.d/sudo")"
compgen -G "$r/var/lib/lyona/fingerprint/sudo.before-disable.*" >/dev/null || fail 'no copy before removing'
cp -p "$work/sudo.orig" "$r/etc/pam.d/sudo"

# polkit: an /etc copy over the system's, removed again.
[[ $(run enable polkit) == *on ]] || fail 'enable polkit'
[[ -f $r/etc/pam.d/polkit-1 && $(state_of polkit) == on ]] || fail 'no /etc/pam.d/polkit-1'
diff <(sed '2,3d' "$r/etc/pam.d/polkit-1") "$work/polkit-1.vendor" >/dev/null || fail 'polkit copy differs'
cmp "$r/usr/lib/pam.d/polkit-1" "$work/polkit-1.vendor" || fail "the system's polkit file was changed"
# #524: status says when polkit's own file changed since the copy was made.
detail_of() { run status | awk -F '\t' -v use="$1" '$1 == "use" && $2 == use { print $4 }'; }
[[ $(detail_of polkit) != *differs* ]] || fail "polkit reported a difference: $(detail_of polkit)"
printf 'session include system-session\n' >>"$r/usr/lib/pam.d/polkit-1"
[[ $(state_of polkit) == on && $(detail_of polkit) == *"differs from polkit's own /usr/lib/pam.d/polkit-1"* ]] ||
	fail "polkit drift not reported: $(run status)"
cp -p "$work/polkit-1.vendor" "$r/usr/lib/pam.d/polkit-1"
[[ $(run disable polkit) == *restored ]] || fail 'disable polkit'
[[ ! -e $r/etc/pam.d/polkit-1 && $(state_of polkit) == off ]] || fail 'the /etc copy was left'

# #535: the enrolment rule follows the uses: there while one is on, gone when
# none is, and made again by sync-enroll-rule.
rule=$r/etc/polkit-1/rules.d/50-lyona-fingerprint-enroll.rules
[[ ! -e $rule ]] || fail 'the enrolment rule exists with every use off'
run enable sudo >/dev/null
[[ -f $rule ]] || fail 'no enrolment rule with sudo on'
grep -Fq 'action.id == "net.reactivated.fprint.device.enroll"' "$rule" || fail "the enrolment rule: $(cat "$rule")"
grep -Fq 'polkit.Result.AUTH_ADMIN;' "$rule" || fail "the enrolment rule: $(cat "$rule")"
[[ $(stat -c %a "$rule") == 644 ]] || fail "the rule's mode: $(stat -c %a "$rule")"
run enable polkit >/dev/null
run disable sudo >/dev/null
[[ -f $rule ]] || fail 'the rule went while polkit was still on'
run disable polkit >/dev/null
[[ ! -e $rule ]] || fail 'the rule stayed with every use off'
run enable sudo >/dev/null
rm "$rule"
[[ $(run sync-enroll-rule) == $'fingerprint-pam-result\tsync-enroll-rule\tpresent' && -f $rule ]] ||
	fail 'sync-enroll-rule did not put the rule back'
run disable sudo >/dev/null
[[ $(run sync-enroll-rule) == $'fingerprint-pam-result\tsync-enroll-rule\tabsent' && ! -e $rule ]] ||
	fail 'sync-enroll-rule left the rule with every use off'

# A line Lyona did not add (as on a machine set up by hand): external, left
# alone by enable and disable, removed only by remove-external, with a copy.
sed -i '1a auth        sufficient  pam_fprintd.so' "$r/etc/pam.d/lightdm"
cp -p "$r/etc/pam.d/lightdm" "$work/lightdm.hand"
[[ $(state_of lightdm) == external ]] || fail "a hand-added line: $(run status)"
# A line added by hand turns fingerprint on too: the enrolment rule follows it.
[[ $(run sync-enroll-rule) == *present && -f $rule ]] || fail 'no enrolment rule with a hand-added line'
expect_fail 'outside Lyona' enable lightdm
expect_fail 'outside Lyona' disable lightdm
cmp "$r/etc/pam.d/lightdm" "$work/lightdm.hand" || fail 'refused requests changed the file'
[[ $(run remove-external lightdm) == *removed ]] || fail 'remove-external'
cmp "$r/etc/pam.d/lightdm" "$work/lightdm.orig" || fail "after remove-external: $(cat "$r/etc/pam.d/lightdm")"
compgen -G "$r/var/lib/lyona/fingerprint/lightdm.external.*" >/dev/null || fail 'no copy before remove-external'
[[ ! -e $rule ]] || fail 'the enrolment rule stayed after the hand-added line went'
# Lyona's own line with no marker before it, first in a file without a header,
# is one Lyona did not add.
cp -p "$r/etc/pam.d/lightdm" "$work/lightdm.keep"
printf '%s\n' '-auth      sufficient  pam_fprintd.so timeout=10 max-tries=3' 'auth include system-login' >"$r/etc/pam.d/lightdm"
[[ $(state_of lightdm) == external ]] || fail "an unmarked first line: $(run status)"
expect_fail 'outside Lyona' enable lightdm
cp -p "$work/lightdm.keep" "$r/etc/pam.d/lightdm"
# A commented-out line is not one.
sed -i '1a #auth sufficient pam_fprintd.so' "$r/etc/pam.d/lightdm"
[[ $(state_of lightdm) == off ]] || fail 'a comment counted as fprintd'
cp -p "$work/lightdm.orig" "$r/etc/pam.d/lightdm"

# A stack the file pulls in counts too: fprintd in system-auth, two includes
# below sudo, is external, keeps the enrolment rule and refuses enable.
printf 'auth include system-auth\n' >"$r/etc/pam.d/system-login"
printf 'auth substack system-fp\n' >"$r/etc/pam.d/system-auth"
printf 'auth sufficient pam_fprintd.so\n' >"$r/usr/lib/pam.d/system-fp"
[[ $(state_of sudo) == external && $(state_of lightdm) == external ]] || fail "fprintd in an included stack: $(run status)"
run status | grep -Fq '/usr/lib/pam.d/system-fp, which /etc/pam.d/sudo pulls in' || fail "the detail: $(run status)"
[[ $(run sync-enroll-rule) == *present && -f $rule ]] || fail 'no enrolment rule with fprintd in an included stack'
expect_fail 'pulls in' enable sudo
cmp "$r/etc/pam.d/sudo" "$work/sudo.orig" || fail 'a refused enable changed sudo'
# Debian's @include, and an included stack that cannot be read.
printf '@include common-fp\n' >"$r/etc/pam.d/system-auth"
printf 'auth [success=1 default=ignore] pam_fprintd.so\n' >"$r/etc/pam.d/common-fp"
[[ $(state_of sudo) == external ]] || fail "fprintd through @include: $(run status)"
if ((EUID != 0)); then
	printf 'auth required pam_unix.so\n' >"$r/etc/pam.d/common-fp"
	chmod 000 "$r/etc/pam.d/common-fp"
	[[ $(state_of sudo) == external ]] || fail "an unreadable included stack: $(run status)"
	chmod 644 "$r/etc/pam.d/common-fp"
fi
# The control word in any case, as PAM reads it, and an include continued
# onto the next line with a backslash.
printf 'auth Include system-fp\n' >"$r/etc/pam.d/system-auth"
[[ $(state_of sudo) == external ]] || fail "fprintd through 'Include': $(run status)"
printf 'auth include \\\n\tsystem-fp\n' >"$r/etc/pam.d/system-auth"
[[ $(state_of sudo) == external ]] || fail "fprintd through a continued include: $(run status)"
[[ $(run status) == *'/usr/lib/pam.d/system-fp, which /etc/pam.d/sudo pulls in'* ]] || fail "the continued include's detail: $(run status)"
# More stacks than the scan follows: not known to be off.
printf 'auth include deep1\n' >"$r/etc/pam.d/system-auth"
for i in $(seq 40); do printf 'auth include deep%s\n' "$((i + 1))" >"$r/etc/pam.d/deep$i"; done
[[ $(state_of sudo) == external ]] || fail "a chain past the limit: $(run status)"
[[ $(run status) == *'more than 32 PAM files'* ]] || fail "the chain's detail: $(run status)"
expect_fail 'pulls in more than 32 PAM files' enable sudo
cmp "$r/etc/pam.d/sudo" "$work/sudo.orig" || fail 'a refused enable changed sudo'
rm "$r"/etc/pam.d/deep*
# Include loops end; a stack without fprintd leaves the use off.
printf 'auth include system-login\n' >"$r/etc/pam.d/system-auth"
[[ $(state_of sudo) == off ]] || fail "an include loop: $(run status)"
rm "$r/etc/pam.d/system-login" "$r/etc/pam.d/system-auth" "$r/etc/pam.d/common-fp" "$r/usr/lib/pam.d/system-fp"
run sync-enroll-rule >/dev/null

# The enrolment rule is written before the PAM file: refused, fingerprint
# stays off.
mkdir -p "$work/elsewhere"
mv "$r/etc/polkit-1/rules.d" "$work/rules.d.real"
ln -s "$work/elsewhere" "$r/etc/polkit-1/rules.d"
expect_fail 'refusing a symlinked path' enable sudo
cmp "$r/etc/pam.d/sudo" "$work/sudo.orig" || fail 'enable turned sudo on without the enrolment rule'
[[ $(state_of sudo) == off ]] || fail "sudo after a refused rule: $(run status)"
rm "$r/etc/polkit-1/rules.d"
mv "$work/rules.d.real" "$r/etc/polkit-1/rules.d"

# One change at a time, across every use and the enrolment rule: while
# another holds the lock, a change, and sync-enroll-rule, wait for it.
mkdir -p "$r/var/lib/lyona/fingerprint"
for request in 'enable sudo' sync-enroll-rule; do
	flock "$r/var/lib/lyona/fingerprint/pam.lock" sleep 1 &
	holder=$!
	for _ in $(seq 100); do
		if ! flock -n "$r/var/lib/lyona/fingerprint/pam.lock" true; then break; fi
		sleep 0.02
	done
	started=$(date +%s%N)
	# shellcheck disable=SC2086 # the request splits into its words
	run $request >/dev/null
	waited=$((($(date +%s%N) - started) / 1000000))
	wait "$holder"
	((waited >= 500)) || fail "$request did not wait for the lock (${waited} ms)"
done
run disable sudo >/dev/null
cmp "$r/etc/pam.d/sudo" "$work/sudo.orig" || fail 'sudo is not the original after the locked change'

# Without pam_fprintd, nothing is added.
mv "$r/usr/lib/security/pam_fprintd.so" "$work/module"
expect_fail 'install fprintd first' enable sudo
[[ $(run status) == *$'\nmodule\tmissing\t'* ]] || fail 'a missing module was not reported'
mv "$work/module" "$r/usr/lib/security/pam_fprintd.so"

# Symlinks and bad input are refused; nothing is written through a link.
mv "$r/etc/pam.d/sudo" "$work/sudo.real"
ln -s "$work/sudo.real" "$r/etc/pam.d/sudo"
expect_fail 'refusing' enable sudo
cmp "$work/sudo.real" "$work/sudo.orig" || fail 'enable wrote through a symlink'
[[ $(state_of sudo) == unavailable ]] || fail "a symlinked sudo: $(run status)"
rm "$r/etc/pam.d/sudo"
mv "$work/sudo.real" "$r/etc/pam.d/sudo"
expect_fail 'unknown use' enable login
expect_fail 'unknown use' enable ../shadow
expect_fail 'takes one use' enable
if "$tool" --root relative status 2>/dev/null; then fail 'a relative --root was accepted'; fi

printf 'Fingerprint PAM (#483): PASS\n'
