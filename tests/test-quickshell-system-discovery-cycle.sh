#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

# qmltestrunner ships with qt6-declarative, which quickshell itself already
# depends on, so it is always present alongside a working Quickshell install.
# The qt6-specific path is tried first and deliberately not overridden by a
# same-named `command -v qmltestrunner`: this repo's own Arch dev host has
# both qt5-declarative and qt6-declarative installed, and the plain `qmltestrunner`
# on PATH resolves to the Qt5 build first -- a *different* binary, not a
# symlink, that silently exits nonzero with no output at all on this file's
# Qt6-only `import QtQuick`/`import QtTest`. Prefer the qt6 tree explicitly;
# fall back to PATH only where that fixed path does not exist.
qmltestrunner=/usr/lib/qt6/bin/qmltestrunner
[ -x "$qmltestrunner" ] || qmltestrunner=$(command -v qmltestrunner 2>/dev/null || true)
if [ -z "$qmltestrunner" ]; then
	printf 'SKIP: qmltestrunner is unavailable\n'
	exit 77
fi

output=$(QT_QPA_PLATFORM=offscreen "$qmltestrunner" -input "$repo/tests/qml" 2>&1) || {
	printf '%s\n' "$output" >&2
	exit 1
}
printf '%s\n' "$output" | grep -Eq '^Totals: [0-9]+ passed, 0 failed' || {
	printf '%s\n' "$output" >&2
	printf 'qmltestrunner reported a failure or did not run to completion\n' >&2
	exit 1
}

printf 'System discovery cycle state machine: PASS\n'
