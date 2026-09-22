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
# Usage: scripts/ci-local.sh [--each [--jobs N] [--targets "A B"]] [--clang] [--keep]
#                            [--refresh] [TARGET]
# Usage: scripts/ci-local.sh [--each] [--clang | --clang-only] [--keep] [--refresh] [TARGET]
#
#   TARGET     make target to run (default: check, the whole suite)
#   --each     run every target of the `check` recipe on its own and list all
#              the failures at the end, instead of stopping at the first one
#              the way `make check` does
#   --jobs N   with --each, run the targets on N containers at once (default 1).
#              Faster, but a weaker signal: timing-sensitive tests can fail only
#              under the extra load, so rerun a failure serially before believing
#              it. N is capped by the cores and by the number of targets.
#   --targets "A B"
#              with --each, run just these targets instead of the whole check
#              recipe (to rerun what failed)
#   --clang    also build dwm with clang, like the workflow's second job
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
# (the clang build's as lyona-ci-clang:<hash>). The clang image keeps its stable
# build profile and compiler in separate layers, so compiler-list changes reuse
# the build dependencies. Use --refresh now and then: CI always starts from the
# newest image.
set -euo pipefail

usage() {
	sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
}

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=scripts/ci-env.sh
source "$repo/scripts/ci-env.sh"
base_image=$CI_BASE_IMAGE
workspace=$CI_WORKSPACE
test_root=$CI_TEST_ROOT
target=check
each=0
jobs=1
only_targets=
clang=0
clang_only=0
keep=0
refresh=0

while (($#)); do
	case $1 in
	--each) each=1 ;;
	--jobs)
		jobs=${2:?--jobs needs a number}
		shift
		;;
	--targets)
		only_targets=${2:?--targets needs a list of targets}
		shift
		;;
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

[[ $jobs =~ ^[1-9][0-9]*$ ]] || {
	printf 'invalid --jobs: %s (a positive number)\n' "$jobs" >&2
	exit 2
}
if ((! each)) && { ((jobs > 1)) || [[ -n $only_targets ]]; }; then
	printf -- '--jobs and --targets need --each\n' >&2
	exit 2
fi
for each_target in $only_targets; do
	[[ $each_target =~ ^[A-Za-z0-9_.-]+$ ]] || {
		printf 'invalid target in --targets: %s\n' "$each_target" >&2
		exit 2
	}
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
# shellcheck source=scripts/ci-schedule.sh
source "$repo/scripts/ci-schedule.sh"
mapfile -t packages < <(
	{
		dwm_packages arch full
		dwm_packages arch ci-smoke
		dwm_packages arch qml-validation
		printf '%s\n' shellcheck shfmt archiso python-dbus python-pillow \
			xorg-server-xvfb xorg-xauth xdotool dbus inotify-tools jq
	} | awk 'NF' | sort -u
)
mapfile -t packages < <(dwm_packages arch ci-full | awk 'NF' | sort -u)
image=lyona-ci:$(printf '%s\n' "${packages[@]}" | sha256sum | cut -c1-12)
# The workflow's clang job installs the build profile and clang in a clean
# container, and nothing more. Keep the profiles separate for Docker layer
# caching, then retain the complete list for the image tag and status output.
mapfile -t clang_build_packages < <(dwm_packages arch build | awk 'NF' | sort -u)
clang_tool_packages=(clang)
mapfile -t clang_packages < <({
	printf '%s\n' "${clang_build_packages[@]}"
	printf '%s\n' "${clang_tool_packages[@]}"
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
	local cname
	[[ -z $context ]] || rm -rf "$context"
	[[ -z $filelist ]] || rm -f "$filelist"
	for cname in "${containers[@]}"; do
		if ((keep)); then
			printf '==> Container kept: docker exec -it %s bash   (remove with: docker rm -f %s)\n' "$cname" "$cname"
		else
			docker rm -f "$cname" >/dev/null 2>&1 || true
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
# the full suite's install step does. STRICT=1 installs the clang build and tool
# profiles as independent layers without filtering unavailable package names,
# so a name pacman does not know still fails as it does in the clang job.
ensure_image() {
	local tag=$1 strict=$2
	shift 2
	if ! ((refresh)) && docker image inspect "$tag" >/dev/null 2>&1; then
		return 0
	fi
	printf '==> Building %s (%d packages; this is the slow part, and it is cached)\n' "$tag" "$#"
	context=$(mktemp -d "${TMPDIR:-/tmp}/lyona-ci-context.XXXXXX")
	if ((strict)); then
		printf '%s\n' "${clang_build_packages[@]}" >"$context/build-packages.txt"
		printf '%s\n' "${clang_tool_packages[@]}" >"$context/tool-packages.txt"
		cat >"$context/Dockerfile" <<EOF
FROM $base_image
RUN pacman -Syu --noconfirm
COPY build-packages.txt /build-packages.txt
RUN pacman -S --noconfirm --needed \$(cat /build-packages.txt) \\
 && rm -rf /var/cache/pacman/pkg/*
COPY tool-packages.txt /tool-packages.txt
RUN pacman -S --noconfirm --needed \$(cat /tool-packages.txt) \\
 && rm -rf /var/cache/pacman/pkg/*
EOF
	else
		printf '%s\n' "$@" >"$context/packages.txt"
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
fi

# The files to copy: those git knows about or would add, and .git itself (some
# tests read the history). Files deleted since the last commit are simply
# absent. The list goes to a file so a failing git is seen (a process
# substitution would hide it and tar would quietly copy only .git).
printf '==> Starting %s from %s\n' "$name" "$image"
# --rm and a finite sleep: if this script is killed before its trap runs, the
# container still goes away by itself.
docker run -d --rm --init --label lyona-ci=1 --name "$name" \
	"${CI_SECURITY_OPTS[@]}" \
	-e DWM_TEST_TMP_ROOT="$test_root" \
	"$image" sleep "$max_life" >/dev/null
container=$name

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
tar_errors=$logdir/tar.err
# In a linked worktree .git is a one-line pointer file, not a repository, so
# ship the shared repository as .git and this worktree's own HEAD and index.
gitdir=$(git -C "$repo" rev-parse --absolute-git-dir)
commondir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)

# start_container NAME: --rm and a finite sleep, so that if this script is
# killed before its trap runs the container still goes away by itself.
start_container() {
	local cname=$1
	docker run -d --rm --init --label lyona-ci=1 --name "$cname" \
		--security-opt seccomp=unconfined --security-opt apparmor=unconfined \
		-e DWM_TEST_TMP_ROOT="$test_root" \
		"$image" sleep "$max_life" >/dev/null
	containers+=("$cname")
}

# copy_tree_into NAME: the working tree as it is now (--ignore-failed-read: a
# file deleted since the last commit is still listed).
copy_tree_into() {
	local cname=$1 state_file
	docker exec "$cname" mkdir -p "$workspace"
	if [[ $gitdir == "$commondir" ]]; then
		tar -C "$repo" --ignore-failed-read --null -T "$filelist" -cf - .git 2>>"$tar_errors" |
			docker exec -i "$cname" tar --no-same-owner -xf - -C "$workspace"
	else
		tar -C "$repo" --ignore-failed-read --null -T "$filelist" -cf - 2>>"$tar_errors" |
			docker exec -i "$cname" tar --no-same-owner -xf - -C "$workspace"
		tar -C "$commondir" -cf - --transform 's,^\.,.git,' . |
			docker exec -i "$cname" tar --no-same-owner -xf - -C "$workspace"
		for state_file in HEAD index; do
			[[ ! -f $gitdir/$state_file ]] ||
				docker exec -i "$cname" tee "$workspace/.git/$state_file" <"$gitdir/$state_file" >/dev/null
		done
	fi
}

prepare_container() {
	docker exec "$1" bash -c "
		git config --global --add safe.directory '$workspace'
		install -d -m 0700 -o nobody -g nobody /home/dwm-ci /run/dwm-ci '$test_root'
		chown -R nobody:nobody '$workspace'"
}

# as_nobody_in NAME COMMAND...: run a command the way the workflow does, as
# nobody, in the workspace.
as_nobody_in() {
	local cname=$1
	shift
	docker exec -w "$workspace" "$cname" \
		runuser -u nobody -- env HOME=/home/dwm-ci XDG_RUNTIME_DIR=/run/dwm-ci \
		DWM_TEST_TMP_ROOT="$test_root" "$@"
}
as_nobody() { as_nobody_in "$name" "$@"; }

# The targets --each runs: the ones named, or the Makefile's own check recipe.
targets=()
if ((each)); then
	if [[ -n $only_targets ]]; then
		read -r -a targets <<<"$only_targets"
	else
		mapfile -t targets < <(awk '/^check:/{f=1;next} f&&/^\t\$\(MAKE\) /{print $2} f&&!/^\t/{f=0}' "$repo/Makefile")
	fi
	((${#targets[@]} > 0)) || {
		printf 'no targets to run (the check recipe is empty)\n' >&2
		exit 2
	}
fi
workers=1
if ((each && jobs > 1)); then
	workers=$(ci_clamp_jobs "$jobs" "$(nproc 2>/dev/null || echo 1)" "${#targets[@]}")
	((workers == jobs)) || printf '==> --jobs %d becomes %d (the cores and the number of targets cap it)\n' "$jobs" "$workers"
fi

worker_names=()
if ((workers > 1)); then
	for ((i = 1; i <= workers; i++)); do worker_names+=("$name-w$i"); done
	printf '==> Starting %d containers from %s\n' "$workers" "$image"
	for cname in "${worker_names[@]}"; do
		start_container "$cname"
		copy_tree_into "$cname"
		prepare_container "$cname"
	done
	name=${worker_names[0]} # the clang leg, if asked for, runs in the first
else
	printf '==> Starting %s from %s\n' "$name" "$image"
	start_container "$name"
	copy_tree_into "$name"
	prepare_container "$name"
fi
if [[ -s $tar_errors ]]; then

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
docker exec "$name" bash -c "
	git config --global --add safe.directory '$workspace'
	install -d -m 0700 -o nobody -g nobody '$CI_HOME' '$CI_RUNTIME_DIR' '$test_root'
	chown -R nobody:nobody '$workspace'"

# Run a command the way the workflow does: as nobody, in the workspace.
# shellcheck disable=SC2329 # runs through run_logged
as_nobody() {
	docker exec -w "$workspace" "$name" \
		runuser -u nobody -- env HOME="$CI_HOME" XDG_RUNTIME_DIR="$CI_RUNTIME_DIR" \
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
	# Each worker runs its targets one after another as nobody, keeping one log
	# per target inside its container; the host reads the PASS/FAIL lines.
if ((clang_only)); then
	:
elif ((each)); then
	printf '==> Running every target of make check on its own\n'
	# The list comes from the Makefile's own check recipe.
	# shellcheck disable=SC2016 # this script is for the shell in the container
	each_script='
		mkdir -p "$DWM_TEST_TMP_ROOT/each"
		for t in "$@"; do
			start=$SECONDS
			if scripts/run-tests make "$t" >"$DWM_TEST_TMP_ROOT/each/$t.log" 2>&1; then
				printf "PASS %-52s %4ds\n" "$t" "$((SECONDS - start))"
			else
				printf "FAIL %-52s %4ds\n" "$t" "$((SECONDS - start))"
			fi
		done'
	durations_file=${XDG_STATE_HOME:-$HOME/.local/state}/lyona/ci-local-durations
	mkdir -p "$logdir/each"
	if ((workers > 1)); then
		printf '==> Running %d targets on %d containers (a weaker signal than one; rerun any failure serially)\n' \
			"${#targets[@]}" "$workers"
		schedule=$(ci_schedule "$workers" "$durations_file" "${targets[@]}")
		pids=()
		for ((i = 1; i <= workers; i++)); do
			mapfile -t mine < <(printf '%s\n' "$schedule" | awk -v w="$i" '$1 == w { print $2 }')
			(as_nobody_in "${worker_names[i - 1]}" bash -c "$each_script" bash "${mine[@]}" 2>&1 |
				tee "$logdir/worker-$i.out" | sed -u "s/^/[w$i] /") &
			pids+=($!)
		done
		for pid in "${pids[@]}"; do wait "$pid" || true; done
		cat "$logdir"/worker-*.out >"$logdir/each.log"
		for cname in "${worker_names[@]}"; do
			docker cp "$cname:$test_root/each/." "$logdir/each/" >/dev/null 2>&1 || true
		done
	else
		printf '==> Running %d target(s) of make check, each on its own\n' "${#targets[@]}"
		run_logged "$logdir/each.log" as_nobody bash -c "$each_script" bash "${targets[@]}" || true
		docker cp "$name:$test_root/each/." "$logdir/each/" >/dev/null 2>&1 || true
	fi
	# The summary comes from the PASS/FAIL lines; a target with none did not run
	# (its worker died), which counts as a failure.
	failed=()
	missing=()
	for each_target in "${targets[@]}"; do
		result=$(awk -v t="$each_target" '$2 == t { print $1 }' "$logdir/each.log" | head -n 1)
		case $result in
		PASS) ;;
		FAIL) failed+=("$each_target") ;;
		*) missing+=("$each_target") ;;
		esac
	done
	printf '\n%d target(s), %d failed' "${#targets[@]}" "$((${#failed[@]} + ${#missing[@]}))"
	((${#missing[@]} == 0)) || printf ' (%d did not run: %s)' "${#missing[@]}" "${missing[*]}"
	printf '\n'
	((${#failed[@]} == 0)) || printf 'failed: %s\n' "${failed[*]}"
	if ((${#failed[@]} + ${#missing[@]} > 0)); then
		status=1
		rerun=("${failed[@]}" "${missing[@]}")
		printf 'rerun just these: scripts/ci-local.sh --each --targets "%s"\n' "${rerun[*]}"
	fi
	# The repeated serial/parallel qualification helper sets both variables.
	# Keep this machine-readable evidence separate from the human console log.
	if [[ -n ${CI_LOCAL_VALIDATION_RESULTS:-} || -n ${CI_LOCAL_VALIDATION_RUN:-} ]]; then
		if [[ -z ${CI_LOCAL_VALIDATION_RESULTS:-} || -z ${CI_LOCAL_VALIDATION_RUN:-} ]]; then
			printf 'CI_LOCAL_VALIDATION_RESULTS and CI_LOCAL_VALIDATION_RUN must be set together\n' >&2
			status=1
		else
			validation_mode=serial
			((workers == 1)) || validation_mode=parallel
			if ! ci_record_run "$CI_LOCAL_VALIDATION_RUN" "$validation_mode" "$workers" \
				"$logdir/each.log" >>"$CI_LOCAL_VALIDATION_RESULTS"; then
				printf 'could not record validation run %s\n' "$CI_LOCAL_VALIDATION_RUN" >&2
				status=1
			fi
		fi
	fi
	# Remember how long each took, to balance the next parallel run.
	if mkdir -p "$(dirname "$durations_file")" 2>/dev/null; then
		{
			[[ ! -f $durations_file ]] || cat "$durations_file"
			awk '$1 == "PASS" || $1 == "FAIL" { t = $3; sub(/s$/, "", t); print $2, t }' "$logdir/each.log"
		} | awk '{ last[$1] = $2 } END { for (k in last) print k, last[k] }' | LC_ALL=C sort >"$durations_file.tmp" &&
			mv -f "$durations_file.tmp" "$durations_file" || true
	fi
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
