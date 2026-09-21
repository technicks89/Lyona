#!/usr/bin/env bash
# Run the "Full suite (manual)" workflow's job in a local Docker container, so a
# failure shows up here instead of after a push.
#
# It mirrors .github/workflows/full-suite.yml: the archlinux:base-devel image,
# the same package set, the same security options, an unprivileged `nobody`
# runner and `scripts/run-tests make TARGET`. The working tree is copied in as
# it is (tracked and untracked files, uncommitted edits included), so nothing
# has to be committed or pushed first.
#
# Usage: scripts/ci-local.sh [--each] [--clang] [--keep] [--refresh] [TARGET]
#
#   TARGET     make target to run (default: check, the whole suite)
#   --each     run every target of the `check` recipe on its own and list all
#              the failures at the end, instead of stopping at the first one
#              the way `make check` does
#   --clang    also build dwm with clang, like the workflow's second job
#   --keep     leave the container running afterwards for a look around
#              (docker exec -it NAME bash); it is named in the output
#   --refresh  rebuild the cached package image from a fresh base image
#
# The package layer is cached as the image lyona-ci:<hash of the package list>,
# so only the first run (or a run after the package list changed) installs
# packages. Use --refresh now and then: CI always starts from the newest image.
set -euo pipefail

usage() {
	sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
}

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
base_image=archlinux:base-devel
workspace=/__w/Lyona/Lyona
test_root=/var/tmp/lyona-ci
target=check
each=0
clang=0
keep=0
refresh=0

while (($#)); do
	case $1 in
	--each) each=1 ;;
	--clang) clang=1 ;;
	--keep) keep=1 ;;
	--refresh) refresh=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	-*)
		printf 'unknown option: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	*) target=$1 ;;
	esac
	shift
done

# The workflow keeps the input out of the shell grammar the same way.
[[ $target =~ ^[A-Za-z0-9_.-]+$ ]] || {
	printf 'invalid target: %s\n' "$target" >&2
	exit 2
}
command -v docker >/dev/null 2>&1 || {
	printf 'docker is not installed\n' >&2
	exit 1
}
docker info >/dev/null 2>&1 || {
	printf 'docker is not running, or this user cannot use it\n' >&2
	exit 1
}

# The package set the workflow installs (it drops names its repositories lack,
# which the image build does too).
# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"
mapfile -t packages < <(
	{
		dwm_packages arch full
		dwm_packages arch ci-smoke
		dwm_packages arch qml-validation
		printf '%s\n' shellcheck shfmt archiso python-dbus python-pillow \
			xorg-server-xvfb xorg-xauth xdotool dbus inotify-tools jq
	} | awk 'NF' | sort -u
)
image=lyona-ci:$(printf '%s\n' "${packages[@]}" | sha256sum | cut -c1-12)

logdir=${TMPDIR:-/tmp}/lyona-ci-local/$(date +%Y%m%d-%H%M%S)
mkdir -p "$logdir"
name=lyona-ci-$$

if ((refresh)) || ! docker image inspect "$image" >/dev/null 2>&1; then
	printf '==> Building %s (%d packages; this is the slow part, and it is cached)\n' \
		"$image" "${#packages[@]}"
	context=$(mktemp -d)
	printf '%s\n' "${packages[@]}" >"$context/packages.txt"
	cat >"$context/Dockerfile" <<EOF
FROM $base_image
COPY packages.txt /packages.txt
RUN pacman -Syu --noconfirm --needed git \\
 && available=\$(for p in \$(cat /packages.txt); do pacman -Si -- "\$p" >/dev/null 2>&1 && printf '%s\\n' "\$p"; done) \\
 && pacman -S --noconfirm --needed \$available \\
 && rm -rf /var/cache/pacman/pkg/*
EOF
	build_flags=()
	((refresh)) && build_flags+=(--pull --no-cache)
	docker build "${build_flags[@]}" -t "$image" "$context"
	rm -rf "$context"
fi

# shellcheck disable=SC2329 # runs from the EXIT trap
cleanup() {
	if ((keep)); then
		printf '==> Container kept: docker exec -it %s bash   (remove with: docker rm -f %s)\n' "$name" "$name"
	else
		docker rm -f "$name" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

printf '==> Starting %s from %s\n' "$name" "$image"
docker run -d --name "$name" \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined \
	-e DWM_TEST_TMP_ROOT="$test_root" \
	"$image" sleep infinity >/dev/null

# Copy the working tree as it is now: files git knows about or would add, and
# .git itself (some tests read the history). Files deleted since the last
# commit are simply absent.
docker exec "$name" mkdir -p "$workspace"
tar -C "$repo" --ignore-failed-read --null -T <(git -C "$repo" ls-files -z --cached --others --exclude-standard) \
	-cf - .git 2>/dev/null |
	docker exec -i "$name" tar --no-same-owner -xf - -C "$workspace"

docker exec "$name" bash -c "
	git config --global --add safe.directory '$workspace'
	install -d -m 0700 -o nobody -g nobody /home/dwm-ci /run/dwm-ci '$test_root'
	chown -R nobody:nobody '$workspace'"

# Run a command the way the workflow does: as nobody, in the workspace.
as_nobody() {
	docker exec -w "$workspace" "$name" \
		runuser -u nobody -- env HOME=/home/dwm-ci XDG_RUNTIME_DIR=/run/dwm-ci \
		DWM_TEST_TMP_ROOT="$test_root" "$@"
}

# run_logged LOG COMMAND...: show the output and keep it in LOG, and return
# the command's own status (a plain `| tee` would report tee's).
run_logged() {
	local log=$1 result
	shift
	set +e
	"$@" 2>&1 | tee "$log"
	result=${PIPESTATUS[0]}
	set -e
	return "$result"
}

status=0
if ((each)); then
	printf '==> Running every target of make check on its own\n'
	# The list comes from the Makefile's own check recipe.
	# shellcheck disable=SC2016 # this script is for the shell in the container
	run_logged "$logdir/each.log" as_nobody bash -c '
		targets=$(awk "/^check:/{f=1;next} f&&/^\t\\\$\(MAKE\) /{print \$2} f&&!/^\t/{f=0}" Makefile)
		[[ -n $targets ]] || { echo "no targets found in the check recipe" >&2; exit 2; }
		mkdir -p "$DWM_TEST_TMP_ROOT/each"
		failed=()
		for t in $targets; do
			start=$SECONDS
			if scripts/run-tests make "$t" >"$DWM_TEST_TMP_ROOT/each/$t.log" 2>&1; then
				printf "PASS %-52s %4ds\n" "$t" "$((SECONDS - start))"
			else
				printf "FAIL %-52s %4ds\n" "$t" "$((SECONDS - start))"
				failed+=("$t")
			fi
		done
		printf "\n%d target(s), %d failed\n" "$(wc -w <<<"$targets")" "${#failed[@]}"
		((${#failed[@]} == 0)) || printf "failed: %s\n" "${failed[*]}"
		exit "$((${#failed[@]} > 0))"
	' || status=$?
	docker cp "$name:$test_root/each" "$logdir/each" >/dev/null 2>&1 || true
	if ((status != 0)); then
		for log in "$logdir"/each/*.log; do
			grep -q . "$log" 2>/dev/null || continue
			target_name=$(basename "$log" .log)
			grep -q "^FAIL $target_name " "$logdir/each.log" || continue
			printf '\n==> %s (last 25 lines; full log: %s)\n' "$target_name" "$log"
			tail -n 25 "$log"
		done
	fi
else
	printf '==> make %s\n' "$target"
	run_logged "$logdir/full-suite.log" as_nobody scripts/run-tests make "$target" || status=$?
fi

if ((clang)); then
	printf '==> clang build\n'
	docker exec "$name" pacman -S --noconfirm --needed clang >/dev/null
	# shellcheck disable=SC2016 # this script is for the shell in the container
	as_nobody bash -c 'rm -rf "$DWM_TEST_TMP_ROOT/clang" && cp -a . "$DWM_TEST_TMP_ROOT/clang" &&
		make -C "$DWM_TEST_TMP_ROOT/clang" clean all CC=clang' || status=1
fi

if ((status == 0)); then
	printf '\n==> PASSED (logs: %s)\n' "$logdir"
else
	printf '\n==> FAILED, exit %d (logs: %s)\n' "$status" "$logdir"
fi
exit "$status"
