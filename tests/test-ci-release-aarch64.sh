#!/bin/sh
# scripts/ci-release-aarch64.sh, run as the release workflow runs it, against
# stubs: a fresh Arch Linux ARM container has no git until the script's own
# pacman installs it (the first release run failed with "git: command not
# found", 2026-11-13). The script is copied into a stub checkout whose
# builders write a dummy image, and run as root in a user namespace with a
# PATH that has no git until the stub pacman puts one there. Each kind must
# install its tools before running git and leave exactly its one image in OUT.
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

if ! command -v unshare >/dev/null 2>&1 || ! unshare -r true 2>/dev/null; then
	printf 'SKIP: no user namespace (unshare -r) to run the script as root\n'
	exit 77
fi

unshare=$(command -v unshare)
make_workspace
fake=$work/checkout
stubs=$work/stubs
mkdir -p "$fake/scripts" "$stubs"
cp "$repo/scripts/ci-release-aarch64.sh" "$fake/scripts/"

# The tools the script uses besides git, uname and pacman, from the host.
for tool in bash env mktemp rm find install dirname mkdir; do
	path=$(command -v "$tool") || fail "no $tool on the host"
	ln -s "$path" "$work/bin/$tool"
done

cat >"$work/bin/uname" <<'EOF'
#!/bin/sh
[ "${1:-}" = -m ] && { echo aarch64; exit 0; }
echo Linux
EOF

cp=$(command -v cp) || fail 'no cp on the host'
# pacman logs its arguments, and "installs" git when asked for it.
cat >"$work/bin/pacman" <<EOF
#!/bin/sh
printf 'pacman %s\n' "\$*" >>"$work/calls.log"
case " \$* " in *" git "*) "$cp" "$stubs/git" "$work/bin/git" ;; esac
EOF

cat >"$stubs/git" <<EOF
#!/bin/sh
printf 'git %s\n' "\$*" >>"$work/calls.log"
case "\$1" in
clone) mkdir -p "\$4" ;;
-C) [ "\$3" = rev-parse ] && echo 723da192226e1c9d5def9168f13332793c82a85e ;;
esac
exit 0
EOF

# The builders: one image each, plus a working file the script must not copy.
for kind in arch-iso:aarch64.iso rpi-image:rpi-aarch64.img.xz; do
	cat >"$fake/scripts/build-lyona-${kind%%:*}.sh" <<EOF
#!/bin/sh
printf 'build %s\n' "\$*" >>"$work/calls.log"
while [ "\$#" -gt 0 ]; do
	[ "\$1" = --output ] && out=\$2
	shift
done
mkdir -p "\$out"
: >"\$out/lyona-0.0.0-${kind#*:}"
: >"\$out/working-file"
EOF
done
chmod +x "$work/bin/uname" "$work/bin/pacman" "$stubs/git" "$fake/scripts/"*

for kind in iso rpi; do
	out=$work/out-$kind
	mkdir -p "$out"
	: >"$work/calls.log"
	if ! "$unshare" -r env -i PATH="$work/bin" \
		"$work/bin/bash" "$fake/scripts/ci-release-aarch64.sh" "$kind" "$out" \
		>"$work/$kind.out" 2>&1; then
		cat "$work/$kind.out" >&2
		fail "ci-release-aarch64.sh $kind failed against the stubs"
	fi
	first=$(sed -n '1s/ .*//p' "$work/calls.log")
	[ "$first" = pacman ] ||
		fail "$kind: the first call was '$first', not pacman installing the tools: $(cat "$work/calls.log")"
	grep -q '^pacman .* git ' "$work/calls.log" || fail "$kind: pacman did not install git"
	grep -q '^git config --global --add safe.directory ' "$work/calls.log" ||
		fail "$kind: the checkout was not marked as a safe directory"
	grep -q '^build .*--output ' "$work/calls.log" || fail "$kind: the builder did not run"
	case $kind in
	iso) want=lyona-0.0.0-aarch64.iso ;;
	rpi) want=lyona-0.0.0-rpi-aarch64.img.xz ;;
	esac
	[ "$(ls "$out")" = "$want" ] || fail "$kind: OUT holds '$(ls "$out")', not just $want"
done

printf 'aarch64 release image build script: PASS\n'
