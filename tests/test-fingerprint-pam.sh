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
[[ -z $(find "$r/var/lib/lyona/fingerprint" -name 'lightdm.*') ]] || fail 'state was left behind'
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
[[ $(run disable polkit) == *restored ]] || fail 'disable polkit'
[[ ! -e $r/etc/pam.d/polkit-1 && $(state_of polkit) == off ]] || fail 'the /etc copy was left'

# A line Lyona did not add (as on a machine set up by hand): external, left
# alone by enable and disable, removed only by remove-external, with a copy.
sed -i '1a auth        sufficient  pam_fprintd.so' "$r/etc/pam.d/lightdm"
cp -p "$r/etc/pam.d/lightdm" "$work/lightdm.hand"
[[ $(state_of lightdm) == external ]] || fail "a hand-added line: $(run status)"
expect_fail 'outside Lyona' enable lightdm
expect_fail 'outside Lyona' disable lightdm
cmp "$r/etc/pam.d/lightdm" "$work/lightdm.hand" || fail 'refused requests changed the file'
[[ $(run remove-external lightdm) == *removed ]] || fail 'remove-external'
cmp "$r/etc/pam.d/lightdm" "$work/lightdm.orig" || fail "after remove-external: $(cat "$r/etc/pam.d/lightdm")"
compgen -G "$r/var/lib/lyona/fingerprint/lightdm.external.*" >/dev/null || fail 'no copy before remove-external'
# A commented-out line is not one.
sed -i '1a #auth sufficient pam_fprintd.so' "$r/etc/pam.d/lightdm"
[[ $(state_of lightdm) == off ]] || fail 'a comment counted as fprintd'
cp -p "$work/lightdm.orig" "$r/etc/pam.d/lightdm"

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
