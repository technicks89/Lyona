#!/usr/bin/env bash
set -euo pipefail

# #273: scripts/lyona-reconcile-user, the per-user changes install.sh and
# lyona-update (through make install-user) share.
# - The profile is recorded with --profile, read back without it, and inferred
#   for an account installed before it was recorded.
# - hotkeys.toml lines that are still an earlier release's default move to this
#   release's, after a backup; a line the user changed is kept; the added "Quit
#   dwm now" line only goes in when its chord is free; a second run changes
#   nothing; a symlinked file is left alone.
# - install.sh and make install-user both run it.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

reconcile=$repo/scripts/lyona-reconcile-user
table=$repo/scripts/hotkeys-migrations
mkdir -p "$work/bin"
# xdg-mime: answers nothing, logs defaults. No quickshell unless STUB_QUICKSHELL.
cat >"$work/bin/xdg-mime" <<'EOF'
#!/bin/sh
[ "$1" = default ] && printf '%s\n' "$2" >>"$TEST_DIR/xdg-mime.log"
exit 0
EOF
chmod +x "$work/bin/xdg-mime"
# The system's commands without quickshell, so the profile inference sees only
# the stub below when it is there.
mkdir -p "$work/sysbin"
for command_path in /usr/bin/*; do
	[[ ${command_path##*/} == quickshell ]] || ln -s "$command_path" "$work/sysbin/${command_path##*/}"
done

home=$work/home
run() { # ARGS...: the reconcile step for the scratch account
	env -i HOME="$home" PATH="$work/bin:$work/sysbin" TEST_DIR="$work" \
		XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" XDG_STATE_HOME="$home/.local/state" \
		"$reconcile" "$@"
}
record=$home/.local/state/lyona/install-profile

# ── the profile ─────────────────────────────────────────────────────────
mkdir -p "$home"
run --profile core >"$work/out" 2>&1 || fail "--profile core failed: $(cat "$work/out")"
[[ $(cat "$record") == core ]] || fail 'the profile was not recorded'
run >"$work/out" 2>&1 || fail "reading the profile back failed: $(cat "$work/out")"
grep -q 'No install profile' "$work/out" && fail 'a recorded profile was inferred instead'
status=0
run --profile bogus >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail "an unknown profile was not refused with exit 2 ($status)"

rm -f "$record"
run >"$work/out" 2>&1
grep -Fq 'treating it as core' "$work/out" || fail "an unrecorded account without Quickshell is not core: $(cat "$work/out")"
printf '#!/bin/sh\n' >"$work/bin/quickshell"
chmod +x "$work/bin/quickshell"
run >"$work/out" 2>&1
grep -Fq 'treating it as recommended' "$work/out" || fail "an unrecorded account with Quickshell is not recommended: $(cat "$work/out")"
grep -Fq 'AppImages open with lyona-appimage' "$work/out" || fail "a recommended account did not get the AppImage handler: $(cat "$work/out")"
[[ ! -e $record ]] || fail 'an inferred profile was recorded as if it had been chosen'
rm -f "$work/bin/quickshell"

# ── the hotkeys migration ───────────────────────────────────────────────
hotkeys=$home/.config/lyona/hotkeys.toml
mkdir -p "${hotkeys%/*}"
# The first two old defaults from the table, the old Super+Shift+Q, one of them
# changed by the user, and a binding of the user's own.
mapfile -t olds < <(sed -n 's/^- //p' "$table")
old_quit=$(sed -n 's/^- \(.*desc="Quit dwm".*\)$/\1/p' "$table" | head -n 1)
[[ -n $old_quit ]] || fail 'the table has no old Super+Shift+Q line'
edited=${olds[1]/desc=\"/desc=\"My }
own='  { mod="SUPER",            key="z",       desc="Mine",                    func="spawn",       cmd="true" },'
printf '%s\n' '# my hotkeys' "${olds[0]}" "$edited" "$old_quit" "$own" >"$hotkeys"
chmod 640 "$hotkeys"
before=$(cat "$hotkeys")
run --profile core >"$work/out" 2>&1 || fail "the migration failed: $(cat "$work/out")"
new0=$(grep -A1 -Fx -- "- ${olds[0]}" "$table" | sed -n '2s/^+ //p')
grep -Fxq -- "$new0" "$hotkeys" || fail "an old default was not moved to this release's: $(cat "$hotkeys")"
grep -Fxq -- "${olds[0]}" "$hotkeys" && fail 'the old default line is still there'
grep -Fxq -- "$edited" "$hotkeys" || fail 'a line the user changed was not kept'
grep -Fxq -- "$own" "$hotkeys" || fail "the user's own binding was not kept"
grep -Fxq '# my hotkeys' "$hotkeys" || fail "the user's comment was not kept"
grep -Fq 'desc="Log out (asks first)"' "$hotkeys" || fail 'the old Super+Shift+Q was not migrated'
grep -Fq 'desc="Quit dwm now"' "$hotkeys" || fail 'the direct quit was not added on its free chord'
[[ $(stat -c %a "$hotkeys") == 640 ]] || fail "the file's mode changed to $(stat -c %a "$hotkeys")"
set -- "$hotkeys".bak.*
[[ -f $1 && $(cat "$1") == "$before" ]] || fail 'the previous hotkeys.toml was not backed up as it was'
grep -Fq 'Moved 2 key binding(s)' "$work/out" || fail "the migration was not reported: $(cat "$work/out")"

# A second run: nothing changes, no new backup.
after=$(cat "$hotkeys")
run --profile core >"$work/out" 2>&1
[[ $(cat "$hotkeys") == "$after" ]] || fail 'a second run changed hotkeys.toml'
set -- "$hotkeys".bak.*
[[ $# == 1 ]] || fail "a second run made another backup: $*"
grep -Fq 'Moved' "$work/out" && fail 'a second run reported a migration'

# The direct quit's chord already bound to something else: not added.
rm -f "$hotkeys".bak.*
taken='  { mod="SUPER CTRL SHIFT", key="q",       desc="Mine too",                func="spawn",       cmd="true" },'
printf '%s\n' "$old_quit" "$taken" >"$hotkeys"
run --profile core >/dev/null 2>&1
grep -Fq 'desc="Quit dwm now"' "$hotkeys" && fail 'the direct quit was added over a chord the user had bound'
grep -Fxq -- "$taken" "$hotkeys" || fail "the user's binding on that chord was not kept"

# A symlinked hotkeys.toml is the user's arrangement: left alone.
rm -f "$hotkeys" "$hotkeys".bak.*
printf '%s\n' "${olds[0]}" >"$work/linked.toml"
ln -s "$work/linked.toml" "$hotkeys"
run --profile core >/dev/null 2>&1
[[ -L $hotkeys && $(cat "$work/linked.toml") == "${olds[0]}" ]] || fail 'a symlinked hotkeys.toml was changed'

# Every line the table replaces with is a binding in today's default.
while IFS= read -r line; do
	grep -Fxq -- "$line" "$repo/config/hotkeys.toml" || fail "the table installs a line that is not in config/hotkeys.toml: $line"
done < <(sed -n 's/^+?\{0,1\} //p' "$table")

# ── wiring ───────────────────────────────────────────────────────────────
grep -Fq 'scripts/lyona-reconcile-user' "$repo/Makefile" || fail 'make install-user does not run lyona-reconcile-user'
# A failure is a warning there too, so the rest of install-user (stamp-user) runs.
grep -A1 -F 'scripts/lyona-reconcile-user ||' "$repo/Makefile" | grep -Fq 'Warning:' ||
	fail 'make install-user stops when lyona-reconcile-user fails'
# shellcheck disable=SC2016 # the literal text in install.sh
[[ $(grep -cF '"$REPO_DIR/scripts/lyona-reconcile-user" --profile "$INSTALL_PROFILE"' "$repo/install.sh") == 2 ]] ||
	fail 'install.sh does not record the profile in both the recommended and the core path'

printf 'Reconcile user state (profile, defaults, hotkeys migration): PASS\n'
