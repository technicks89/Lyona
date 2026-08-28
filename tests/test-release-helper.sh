#!/bin/sh

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
helper=$repo/scripts/lyona-release
make_workspace

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$work/bin/gh"
: >"$work/lyona.iso"

output=$(
	PATH="$work/bin:$PATH" "$helper" \
		--dry-run \
		--skip-checks \
		--iso "$work/lyona.iso"
)

printf '%s\n' "$output" | grep -Fq '+ make release'
printf '%s\n' "$output" | grep -Fq '+ gh api -X POST repos/:owner/:repo/git/refs'
build_line=$(printf '%s\n' "$output" | grep -nF '+ make release' | cut -d: -f1)
tag_line=$(printf '%s\n' "$output" |
	grep -nF '+ gh api -X POST repos/:owner/:repo/git/refs' | cut -d: -f1)
if [ "$build_line" -ge "$tag_line" ]; then
	printf '%s\n' 'release validation must run before remote tag creation' >&2
	exit 1
fi

if PATH="$work/bin:$PATH" "$helper" \
	--dry-run --skip-checks --iso "$work/lyona.iso" \
	--version 2099.01.0 >"$work/mismatch.out" 2>"$work/mismatch.err"; then
	printf '%s\n' 'release helper accepted a version not committed in config.mk' >&2
	exit 1
fi
grep -Fq 'does not match committed config.mk VERSION' "$work/mismatch.err"

printf '%s\n' 'Release helper preflight and remote-write ordering: PASS'
