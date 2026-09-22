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
# Usage: scripts/ci-local.sh [--each] [--clang | --clang-only] [--keep] [--refresh] [TARGET]
#
#   TARGET     make target to run (default: check, the whole suite)
#   --each     run every target of the `check` recipe on its own and list all
#              the failures at the end, instead of stopping at the first one
#              the way `make check` does
#   --clang    also build dwm with clang, like the workflow's second job: in a
#              fresh container that has only the `build` packages and clang
#              (cached as its own small image), so a build dependency missing
#              from the `build` profile fails here as it does in CI
#   --clang-only
#              run just that clang build, without the test suite
#   --keep     leave the container running afterwards for a look around
#              (docker exec -it NAME bash); it is named in the output and
#              removes itself after four hours
#   --refresh  rebuild the cached package image(s) from a fresh base image
#
# It runs this tree's own scripts and tests, on the host (it sources
# scripts/dwm-packages.sh) and in a container whose seccomp and AppArmor
# profiles are off, as the workflow's are: use it on code you trust, not on an
# unreviewed branch.
#
# The package layer is cached as the image lyona-ci:<hash of the package list>
# (the clang build's as lyona-ci-clang:<hash>), so only the first run (or a run
# after a package list changed) installs packages. Use --refresh now and then:
# CI always starts from the newest image.
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
clang_only=0
keep=0
refresh=0

while (($#)); do
	case $1 in
	--each) each=1 ;;
	--clang) clang=1 ;;
	--clang-only) clang=1 clang_only=1 ;;
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
# The workflow's clang job installs the build profile and clang in a clean
# container, and nothing more.
mapfile -t clang_packages < <({
	dwm_packages arch build
	printf '%s\n' clang
} | awk 'NF' | sort -u)
clang_image=lyona-ci-clang:$(printf '%s\n' "${clang_packages[@]}" | sha256sum | cut -c1-12)

logdir=$(mktemp -d "${TMPDIR:-/tmp}/lyona-ci-local.XXXXXX")
name=lyona-ci-$(basename "$logdir")
max_life=14400

# What this run created, so the EXIT trap removes those and nothing else: the
# build context, the file list, and the containers once they have been started.
context=
filelist=
containers=()
# shellcheck disable=SC2329 # runs from the EXIT trap
cleanup() {
	local one
	[[ -z $context ]] || rm -rf "$context"
	[[ -z $filelist ]] || rm -f "$filelist"
	for one in ${containers[@]+"${containers[@]}"}; do
		if ((keep)); then
			printf '==> Container kept: docker exec -it %s bash   (remove with: docker rm -f %s)\n' "$one" "$one"
		else
			docker rm -f "$one" >/dev/null 2>&1 || true
		fi
	done
}
trap cleanup EXIT

# ensure_image IMAGE STRICT PACKAGE...: build the cached image unless it exists
# (--refresh rebuilds it). STRICT=0 drops the names the repositories lack, as
# the full suite's install step does; STRICT=1 installs the list as it is, so a
# name pacman does not know fails the build, as it does in the clang job.
ensure_image() {
	local tag=$1 strict=$2
	shift 2
	if ! ((refresh)) && docker image inspect "$tag" >/dev/null 2>&1; then
		return 0
	fi
	printf '==> Building %s (%d packages; this is the slow part, and it is cached)\n' "$tag" "$#"
	context=$(mktemp -d "${TMPDIR:-/tmp}/lyona-ci-context.XXXXXX")
	printf '%s\n' "$@" >"$context/packages.txt"
	if ((strict)); then
		cat >"$context/Dockerfile" <<EOF
FROM $base_image
COPY packages.txt /packages.txt
RUN pacman -Syu --noconfirm --needed git \\
 && pacman -S --noconfirm --needed \$(cat /packages.txt) \\
 && rm -rf /var/cache/pacman/pkg/*
EOF
	else
		cat >"$context/Dockerfile" <<EOF
FROM $base_image
COPY packages.txt /packages.txt
RUN pacman -Syu --noconfirm --needed git \\
 && pacman -Slq | LC_ALL=C sort -u >/tmp/repo-packages.txt \\
 && LC_ALL=C sort -u /packages.txt >/tmp/wanted-packages.txt \\
 && available=\$(LC_ALL=C comm -12 /tmp/repo-packages.txt /tmp/wanted-packages.txt) \\
 && pacman -S --noconfirm --needed \$available \\
 && rm -rf /var/cache/pacman/pkg/*
EOF
	fi
	build_flags=()
	((refresh)) && build_flags+=(--pull --no-cache)
	# An explicit return: the clang leg calls this in an `if`, where `set -e` is off.
	docker build "${build_flags[@]}" -t "$tag" "$context" || return 1
	rm -rf "$context"
	context=
}

# The files git knows about or would add: the working tree as it is now. Files
# deleted since the last commit are simply absent. The list goes to a file so a
# failing git is seen (a process substitution would hide it and tar would
# quietly copy only .git).
filelist=$(mktemp "${TMPDIR:-/tmp}/lyona-ci-files.XXXXXX")
git -C "$repo" ls-files -z --cached --others --exclude-standard >"$filelist" || {
	printf 'git ls-files failed; not testing an incomplete tree\n' >&2
	exit 1
}
[[ -s $filelist ]] || {
	printf 'git ls-files listed no files; not testing an empty tree\n' >&2
	exit 1
}

# warn_tar_errors FILE: say so if tar could not copy some files.
warn_tar_errors() {
	[[ -s $1 ]] || return 0
	printf '==> warning: some files were not copied into the container (%s):\n' \
		"$(wc -l <"$1") message(s)" >&2
	head -n 5 "$1" >&2
}

# The container the suite runs in: the full image, the tree, and .git itself
# (some tests read the history).
start_suite_container() {
	local state_file
	ensure_image "$image" 0 "${packages[@]}"
	printf '==> Starting %s from %s\n' "$name" "$image"
	# --rm and a finite sleep: if this script is killed before its trap runs, the
	# container still goes away by itself.
	docker run -d --rm --init --label lyona-ci=1 --name "$name" \
		--security-opt seccomp=unconfined --security-opt apparmor=unconfined \
		-e DWM_TEST_TMP_ROOT="$test_root" \
		"$image" sleep "$max_life" >/dev/null
	containers+=("$name")
	docker exec "$name" mkdir -p "$workspace"
	tar_errors=$logdir/tar.err
	# --ignore-failed-read: a file deleted since the last commit is still listed.
	# In a linked worktree .git is a one-line pointer file, not a repository, so
	# ship the shared repository as .git and this worktree's own HEAD and index.
	gitdir=$(git -C "$repo" rev-parse --absolute-git-dir)
	commondir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
	if [[ $gitdir == "$commondir" ]]; then
		tar -C "$repo" --ignore-failed-read --null -T "$filelist" -cf - .git 2>"$tar_errors" |
			docker exec -i "$name" tar --no-same-owner -xf - -C "$workspace"
	else
		tar -C "$repo" --ignore-failed-read --null -T "$filelist" -cf - 2>"$tar_errors" |
			docker exec -i "$name" tar --no-same-owner -xf - -C "$workspace"
		tar -C "$commondir" -cf - --transform 's,^\.,.git,' . |
			docker exec -i "$name" tar --no-same-owner -xf - -C "$workspace"
		for state_file in HEAD index; do
			[[ ! -f $gitdir/$state_file ]] ||
				docker exec -i "$name" tee "$workspace/.git/$state_file" <"$gitdir/$state_file" >/dev/null
		done
	fi
	warn_tar_errors "$tar_errors"

	docker exec "$name" bash -c "
		git config --global --add safe.directory '$workspace'
		install -d -m 0700 -o nobody -g nobody /home/dwm-ci /run/dwm-ci '$test_root'
		chown -R nobody:nobody '$workspace'"
}
((clang_only)) || start_suite_container

# Run a command the way the workflow does: as nobody, in the workspace.
# shellcheck disable=SC2329 # runs through run_logged
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
if ((clang_only)); then
	:
elif ((each)); then
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
		[[ -d $logdir/each && ! -L $logdir/each ]] || exit "$status"
		for log in "$logdir"/each/*.log; do
			[[ -f $log && ! -L $log ]] || continue
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

# The workflow's second job: the build profile and clang in a clean container,
# as root, `make clean all CC=clang`. A build dependency missing from the
# profile fails here, which a container that already has every package would hide.
if ((clang)); then
	printf '==> clang build (a clean container: the build packages and clang)\n'
	if ensure_image "$clang_image" 1 "${clang_packages[@]}"; then
		clang_name=$name-clang
		docker run -d --rm --init --label lyona-ci=1 --name "$clang_name" \
			"$clang_image" sleep "$max_life" >/dev/null
		containers+=("$clang_name")
		docker exec "$clang_name" mkdir -p "$workspace"
		tar -C "$repo" --ignore-failed-read --null -T "$filelist" -cf - 2>"$logdir/tar-clang.err" |
			docker exec -i "$clang_name" tar --no-same-owner -xf - -C "$workspace"
		warn_tar_errors "$logdir/tar-clang.err"
		docker exec -w "$workspace" "$clang_name" make clean all CC=clang || status=1
	else
		status=1
	fi
fi

if ((status == 0)); then
	printf '\n==> PASSED (logs: %s)\n' "$logdir"
else
	printf '\n==> FAILED, exit %d (logs: %s)\n' "$status" "$logdir"
fi
exit "$status"
