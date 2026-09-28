#!/bin/sh

set -eu

# Sync Sprint 12 S12-06: nothing in the managed shell renders markup. Window
# titles, notifications, network and device names come from other programs, and
# Qt's default Text.AutoText renders them as rich text (fetching remote <img>
# sources, and letting a title restyle the panel). The shell uses no markup, so
# every Text sets Text.PlainText, UiText (and everything built on it) included,
# and no file asks for another format.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

cd "$repo"
qml_files=$(git ls-files 'config/quickshell/*.qml' 2>/dev/null || find config/quickshell -name '*.qml')

# Every block opened by "Text {" (also "delegate: Text {" and "component X: Text {")
# must set textFormat: Text.PlainText inside it.
# shellcheck disable=SC2086 # the file list is newline-separated paths
missing=$(awk '
	FNR == 1 { depth = 0; open = 0 }
	{
		line = $0
		if (!open && line ~ /(^|[^A-Za-z0-9_.])Text[[:space:]]*\{/) {
			open = 1; start = FNR; has = 0; depth = 0
		}
		if (open) {
			if (line ~ /textFormat:[[:space:]]*Text\.PlainText/) has = 1
			o = gsub(/\{/, "{", line); c = gsub(/\}/, "}", line)
			depth += o - c
			if (depth <= 0) {
				if (!has) print FILENAME ":" start
				open = 0
			}
		}
	}' $qml_files)
if [ -n "$missing" ]; then
	printf 'Text without textFormat: Text.PlainText (it would render markup from other programs):\n%s\n' "$missing" >&2
	exit 1
fi

# shellcheck disable=SC2086
if grep -nE 'Text\.(RichText|StyledText|AutoText|MarkdownText)|TextEdit\.(RichText|AutoText|MarkdownText)' $qml_files; then
	printf 'The shell must not render markup.\n' >&2
	exit 1
fi

grep -Fq 'textFormat: Text.PlainText' config/quickshell/core/UiText.qml
grep -Fq 'textFormat: Text.PlainText' config/quickshell/core/SectionLabel.qml

printf 'Quickshell plain text policy: PASS\n'
