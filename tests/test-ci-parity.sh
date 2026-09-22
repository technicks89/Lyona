#!/usr/bin/env bash
set -euo pipefail

# The full-suite workflow and scripts/ci-local.sh (its local twin) must not drift:
# they take the package set from one profile and the environment from one file.
# Nothing here runs Docker or the network.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

workflow=$repo/.github/workflows/full-suite.yml
local_runner=$repo/scripts/ci-local.sh
env_file=$repo/scripts/ci-env.sh
assert_file "$workflow"
assert_file "$local_runner"
assert_file "$env_file"

# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"
# shellcheck source=scripts/ci-env.sh
source "$env_file"

# ── the package set ───────────────────────────────────────────────────────

ci_full=$(dwm_packages arch ci-full | awk 'NF' | LC_ALL=C sort -u)
[[ -n $ci_full ]] || fail 'the ci-full profile is empty'
for profile in full ci-smoke qml-validation ci-tools; do
	missing=$(LC_ALL=C comm -13 <(printf '%s\n' "$ci_full") \
		<(dwm_packages arch "$profile" | awk 'NF' | LC_ALL=C sort -u))
	[[ -z $missing ]] || fail "ci-full lacks packages of the $profile profile: $missing"
done
# What the suite needs beyond the desktop: named here on purpose, so removing one
# from the profile cannot go unnoticed.
for tool in shellcheck shfmt archiso python-dbus python-pillow xorg-server-xvfb \
	xorg-xauth xdotool inotify-tools jq dbus; do
	printf '%s\n' "$ci_full" | grep -Fxq "$tool" || fail "ci-full does not install $tool"
done

# Both installers ask for the profile, and neither keeps a package list of its own.
for file in "$workflow" "$local_runner"; do
	[[ $(grep -Fc 'dwm_packages arch ci-full' "$file") -eq 1 ]] ||
		fail "$(basename "$file") must take its packages from 'dwm_packages arch ci-full' exactly once"
	for stale in 'dwm_packages arch ci-smoke' 'dwm_packages arch qml-validation' \
		'dwm_packages arch full' 'shellcheck shfmt'; do
		if grep -Fq "$stale" "$file"; then
			fail "$(basename "$file") still assembles the package set itself ($stale)"
		fi
	done
done

# ── the environment ───────────────────────────────────────────────────────

# The workflow's literals are the same values scripts/ci-env.sh defines.
grep -Fq "DWM_TEST_TMP_ROOT: $CI_TEST_ROOT" "$workflow" || fail 'workflow DWM_TEST_TMP_ROOT differs from ci-env.sh'
grep -Fq "image: $CI_BASE_IMAGE" "$workflow" || fail 'workflow container image differs from ci-env.sh'
grep -Fq "$CI_HOME $CI_RUNTIME_DIR" "$workflow" || fail 'workflow runner directories differ from ci-env.sh'
grep -Fq "HOME=$CI_HOME XDG_RUNTIME_DIR=$CI_RUNTIME_DIR" "$workflow" ||
	fail 'workflow runner environment differs from ci-env.sh'
for option in "${CI_SECURITY_OPTS[@]}"; do
	[[ $option == --security-opt ]] && continue
	grep -Fq -- "--security-opt $option" "$workflow" || fail "workflow lacks --security-opt $option (ci-env.sh has it)"
done
# ci-local.sh reads them from there instead of repeating them.
grep -Fq 'ci-env.sh' "$local_runner" || fail 'ci-local.sh does not source ci-env.sh'
for literal in "$CI_TEST_ROOT" "$CI_HOME" "$CI_RUNTIME_DIR" 'seccomp=unconfined' 'apparmor=unconfined'; do
	if grep -Fq -- "$literal" "$local_runner"; then
		fail "ci-local.sh repeats $literal instead of using ci-env.sh"
	fi
done
[[ $CI_WORKSPACE == /__w/Lyona/Lyona ]] || fail 'the workspace path is the one GitHub mounts for this repository'

printf 'CI parity: PASS\n'
