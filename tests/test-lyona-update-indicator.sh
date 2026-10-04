#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 15 S15-02: scripts/lyona-update-indicator against a stub
# checkupdates. A count is reported for pending updates, current for none, and
# a failure or a timeout as an error, never as current; the settings take only
# the allowed values, default otherwise, and are private. Sync Sprint 16
# R16-34: there is no network watcher any more (the shell's NetworkModel says
# when the connection comes up), so no resident python3.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper=$repo/scripts/lyona-update-indicator
export XDG_CONFIG_HOME=$work/config
conf=$XDG_CONFIG_HOME/lyona/update-indicator.conf

cat >"$work/bin/checkupdates" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/log"
case ${STUB_MODE:-updates} in
updates) printf 'linux 6.17.1-1 -> 6.17.2-1\nmesa 1:25.2.4-1 -> 1:25.2.5-1\nvim 9.1-1 -> 9.1-2\n' ;;
none) exit 2 ;;
fail) exit 1 ;;
hang) sleep 30 ;;
esac
EOF
chmod +x "$work/bin/checkupdates"
# Flatpak (S15-03): FLATPAK_SYSTEM and FLATPAK_USER are each a count of pending
# updates, or "fail".
cat >"$work/bin/flatpak" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/flatpak.log"
[ "$1 $2" = "remote-ls --updates" ] || exit 9
case $3 in
--system) want=${FLATPAK_SYSTEM:-0} ;;
--user) want=${FLATPAK_USER:-0} ;;
*) exit 9 ;;
esac
[ "$want" != fail ] || exit 1
i=0
while [ "$i" -lt "$want" ]; do
	printf 'org.example.App%s\tstable\n' "$i"
	i=$((i + 1))
done
EOF
chmod +x "$work/bin/flatpak"
export STUB_DIR=$work
: >"$work/log"

run() { PATH="$work/bin:$PATH" "$helper" "$@"; }
header=$'update-indicator-protocol\t1\t0'

out=$(run check)
[[ $out == "$header"$'\nprovider\tsystem\tavailable\t3\t3 package updates\nprovider\tflatpak\tcurrent\t0\tFlatpak apps are up to date\ncomplete\tcheck' ]] ||
	fail "three updates: $out"
# Flatpak: each installation is asked on its own, through the column interface.
grep -Fqx 'remote-ls --updates --system --columns=application,branch' "$work/flatpak.log" ||
	fail "the system installation was not asked: $(cat "$work/flatpak.log")"
grep -Fqx 'remote-ls --updates --user --columns=application,branch' "$work/flatpak.log" ||
	fail 'the user installation was not asked'
out=$(FLATPAK_SYSTEM=2 FLATPAK_USER=1 run check)
[[ $out == *$'provider\tflatpak\tavailable\t3\t3 Flatpak updates'* ]] || fail "both installations: $out"
out=$(FLATPAK_USER=2 run check)
[[ $out == *$'provider\tflatpak\tavailable\t2\t'* ]] || fail "the user installation alone: $out"
# One installation failing is an error naming it, never "up to date".
out=$(FLATPAK_SYSTEM=2 FLATPAK_USER=fail run check)
[[ $out == *$'provider\tflatpak\terror\t0\tThe Flatpak check failed for the user installation'* ]] ||
	fail "a failed user installation: $out"
grep -Fqx -- '--nocolor' "$work/log" || fail "checkupdates was not run with --nocolor"
out=$(STUB_MODE=none run check)
[[ $out == *$'provider\tsystem\tcurrent\t0\tPackages are up to date'* ]] || fail "no updates: $out"
out=$(STUB_MODE=fail run check)
[[ $out == *$'provider\tsystem\terror\t0\t'* ]] || fail "a failed check was not an error: $out"
# A stalled check is ended and reported, not left open (the bound is shortened here).
stage_helpers checkout "$work/short" lyona-update-indicator
sed -i 's/^readonly check_seconds=180$/readonly check_seconds=1/' "$work/short/lyona-update-indicator"
grep -q '^readonly check_seconds=1$' "$work/short/lyona-update-indicator" || fail 'could not shorten the check bound'
SECONDS=0
out=$(STUB_MODE=hang PATH="$work/bin:$PATH" "$work/short/lyona-update-indicator" check)
((SECONDS < 15)) || fail "a stalled check ran for ${SECONDS}s"
[[ $out == *$'provider\tsystem\terror\t0\tThe package check timed out'* ]] || fail "a stalled check: $out"
# Without checkupdates the provider is unavailable, with the package to install.
mkdir -p "$work/nobin"
for cmd in bash awk timeout mktemp mkdir mv chmod rm dirname cat; do
	ln -sf "$(command -v "$cmd")" "$work/nobin/$cmd"
done
out=$(PATH="$work/nobin" "$helper" check)
[[ $out == *$'provider\tsystem\tunavailable\t0\tInstall pacman-contrib'* ]] || fail "no checkupdates: $out"
# Without Flatpak there is nothing to count, and that is not an error.
[[ $out == *$'provider\tflatpak\tunavailable\t0\tFlatpak is not installed'* ]] || fail "no flatpak: $out"

# Settings: defaults, the allowed values, and nothing else.
out=$(run status)
[[ $out == "$header"$'\nsetting\tinterval-hours\t6\nsetting\tshow-when-current\tno\nsetting\tfloat-terminal\tno\nsetting\tfloat-rule\tmissing\ncomplete\tstatus' ]] ||
	fail "default settings: $out"
[[ ! -e $conf ]] || fail 'status wrote the settings file'
run set-interval 12 >/dev/null
run set-show-when-current yes >/dev/null
out=$(run status)
[[ $out == *$'interval-hours\t12'* && $out == *$'show-when-current\tyes'* ]] || fail "saved settings: $out"
[[ $(stat -c %a "$conf") == 600 ]] || fail "the settings file is $(stat -c %a "$conf"), not 600"
for bad in 0 2 25 -1 6h ''; do
	if run set-interval "$bad" >/dev/null 2>&1; then fail "set-interval accepted '$bad'"; fi
done
if run set-show-when-current maybe >/dev/null 2>&1; then fail 'set-show-when-current accepted maybe'; fi
# The float setting (S15-04) is kept beside the others, and changes neither.
run set-float-terminal yes >/dev/null
out=$(run status)
[[ $out == *$'float-terminal\tyes'* && $out == *$'interval-hours\t12'* && $out == *$'show-when-current\tyes'* ]] ||
	fail "float-terminal: $out"
if run set-float-terminal 1 >/dev/null 2>&1; then fail 'set-float-terminal accepted 1'; fi
# The rule that floats it is read from window-rules.toml, never written.
rules=$XDG_CONFIG_HOME/lyona/window-rules.toml
float_rule() { run status | awk -F '\t' '$2 == "float-rule" { print $3 }'; }
# Read as dwm reads it, through lyona-toml (Sync Sprint 16 R16-44).
rules_file() { printf 'rules = [\n%s\n]\n' "$1" >"$rules"; }
rules_file '  { class="Alacritty", isterminal=1 },'
[[ $(float_rule) == missing ]] || fail 'a rules file without the rule read as present'
rules_file '  # { class="lyona-update-float", isfloating=1 },'
[[ $(float_rule) == missing ]] || fail 'a commented-out rule read as present'
rules_file '  { class="lyona-update-float", isfloating=0 },'
[[ $(float_rule) == missing ]] || fail 'a rule that does not float read as present'
rules_file '  { class="lyona-update-float" },
  { class="Other", isfloating=1 },'
[[ $(float_rule) == missing ]] || fail 'the class and isfloating from different rules read as present'
printf 'other = [\n  { class="lyona-update-float", isfloating=1 },\n]\n' >"$rules"
[[ $(float_rule) == missing ]] || fail 'a rule outside the rules array read as present'
rules_file '  { isfloating = 1, class = "lyona-update-float" },'
[[ $(float_rule) == present ]] || fail 'a floating rule written another way read as missing'
cp "$repo/config/window-rules.toml" "$rules"
[[ $(float_rule) == present ]] || fail 'the shipped rules file lacks the float rule'
cmp -s "$repo/config/window-rules.toml" "$rules" || fail 'status changed window-rules.toml'
rm -f "$rules"
[[ $(run status) == *$'interval-hours\t12'* ]] || fail 'a rejected value changed the settings'
# A hand-edited bad value reads as the default.
printf 'interval-hours=7\nshow-when-current=sure\n' >"$conf"
out=$(run status)
[[ $out == *$'interval-hours\t6'* && $out == *$'show-when-current\tno'* ]] || fail "bad stored values: $out"
# A symlinked settings file is never written through.
rm -f "$conf"
ln -s "$work/elsewhere" "$conf"
if run set-interval 3 >/dev/null 2>&1; then fail 'wrote through a symlinked settings file'; fi
[[ ! -e $work/elsewhere ]] || fail 'the symlink target was created'
rm -f "$conf"
if run frobnicate >/dev/null 2>&1; then fail 'an unknown action succeeded'; fi

# No network watcher: the command is gone, and no python3 is left in the helper.
status=0
run watch-network >/dev/null 2>&1 || status=$?
[[ $status == 2 ]] || fail "watch-network is still accepted (status $status)"
if grep -n 'python' "$helper" | grep -q .; then
	fail "the helper still runs python: $(grep -n python "$helper")"
fi

printf 'lyona-update-indicator: PASS\n'
