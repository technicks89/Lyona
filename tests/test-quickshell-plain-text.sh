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
# Every QML file on disk, tracked or not, so a new file cannot slip past.
qml_files=$(find config/quickshell -name '*.qml' | sort)

# check_text_blocks FILE...: print FILE:LINE for every block opened by "Text {"
# (also "delegate: Text {" and "component X: Text {") that does not itself set
# textFormat: Text.PlainText. Comments are removed first, so a commented-out line
# does not count, and each Text block is checked on its own: a textFormat line only
# counts for the innermost Text it sits directly in, so a nested Text needs its own.
check_text_blocks() {
	awk '
	FNR == 1 { depth = 0; top = 0; in_block = 0 }
	{
		line = $0
		# Remove /* ... */ (also across lines) and // comments outside strings.
		out = ""; in_str = 0
		for (k = 1; k <= length(line); k++) {
			ch = substr(line, k, 1); nx = substr(line, k + 1, 1)
			if (in_block) {
				if (ch == "*" && nx == "/") { in_block = 0; k++ }
				continue
			}
			if (!in_str && ch == "/" && nx == "*") { in_block = 1; k++; continue }
			if (!in_str && ch == "/" && nx == "/") break
			if (ch == "\\" && in_str) { out = out ch nx; k++; continue }
			if (ch == "\"") in_str = !in_str
			out = out ch
		}
		line = out
		opens = (line ~ /(^|[^A-Za-z0-9_.])Text[[:space:]]*\{/)
		if (opens) {
			top++; level[top] = depth + 1; start[top] = FNR; has[top] = 0
			# "Text { textFormat: Text.PlainText; ... }" on one line
			rest = line; sub(/.*(^|[^A-Za-z0-9_.])Text[[:space:]]*\{/, "", rest)
			if (rest ~ /textFormat:[[:space:]]*Text\.PlainText/) has[top] = 1
		} else if (top > 0 && level[top] == depth && line ~ /textFormat:[[:space:]]*Text\.PlainText/) {
			has[top] = 1
		}
		o = gsub(/\{/, "{", line); c = gsub(/\}/, "}", line)
		depth += o - c
		while (top > 0 && level[top] > depth) {
			if (!has[top]) print FILENAME ":" start[top]
			top--
		}
	}' "$@"
}

# The checker itself: fixtures it must flag, and one it must pass.
fixtures=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/plain-text-fixtures.XXXXXX")
trap 'rm -rf "$fixtures"' EXIT HUP INT TERM
printf 'Text {\n    // textFormat: Text.PlainText\n    text: "x"\n}\n' >"$fixtures/commented.qml"
printf 'Text {\n    /* textFormat: Text.PlainText */\n    text: "x"\n}\n' >"$fixtures/block-comment.qml"
printf 'Text {\n    textFormat: Text.PlainText\n    Text {\n        text: "inner"\n    }\n}\n' >"$fixtures/nested.qml"
printf 'Item {\n    textFormat: Text.PlainText\n    Text { text: "x" }\n}\n' >"$fixtures/sibling.qml"
printf 'Text {\n    textFormat: Text.PlainText\n    Text { textFormat: Text.PlainText; text: "y" }\n    text: "http://a//b"\n}\n' >"$fixtures/good.qml"
for bad in commented block-comment nested sibling; do
	[ -n "$(check_text_blocks "$fixtures/$bad.qml")" ] || {
		printf 'the plain-text checker missed the %s fixture\n' "$bad" >&2
		exit 1
	}
done
[ -z "$(check_text_blocks "$fixtures/good.qml")" ] || {
	printf 'the plain-text checker flagged a correct fixture: %s\n' "$(check_text_blocks "$fixtures/good.qml")" >&2
	exit 1
}

# shellcheck disable=SC2086 # the file list is newline-separated paths
missing=$(check_text_blocks $qml_files)
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
