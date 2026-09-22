#!/usr/bin/env bash
# The environment of the full-suite CI job, defined once. scripts/ci-local.sh
# (the local Docker twin of .github/workflows/full-suite.yml) sources this file;
# the workflow, being YAML, repeats the same values and tests/test-ci-parity.sh
# fails if either drifts from here. Sourced, not run.

# shellcheck disable=SC2034 # read by the scripts that source this file

# The image the job runs in, and the two security options it needs: several
# acceptance tests create private namespaces, a private system bus and nested
# Xvfb displays.
CI_BASE_IMAGE=archlinux:base-devel
CI_SECURITY_OPTS=(--security-opt seccomp=unconfined --security-opt apparmor=unconfined)

# Where GitHub mounts the checkout inside the container.
CI_WORKSPACE=/__w/Lyona/Lyona

# The tests run as `nobody` with these directories.
CI_TEST_ROOT=/var/tmp/lyona-ci
CI_HOME=/home/dwm-ci
CI_RUNTIME_DIR=/run/dwm-ci
