# shellcheck shell=bash
# Desktop entries, read and written in one place (#275), the way lyona-toml is
# the only TOML reader (D-20). The scripts read entries they did not write, some
# from inside an AppImage, so the reader is strict: a file with control
# characters, a repeated group or a duplicate key is refused whole, rather than
# each script deciding differently which of two values counts.
#
#   desktop_entry_get FILE KEY [GROUP]  KEY's value as written, from GROUP
#                                       ("Desktop Entry" unless given).
#                                       0 found, 1 missing, 2 invalid file.
#   desktop_exec_arg VALUE              VALUE as one argument of an Exec line.

# Larger than any real desktop entry; a bound on what is read.
DESKTOP_ENTRY_MAX_BYTES=65536

desktop_entry_get() {
	local file=$1 key=$2 group=${3:-Desktop Entry} size
	[[ -f $file && -r $file ]] || return 1
	size=$(stat -c %s -- "$file" 2>/dev/null) || return 2
	((size <= DESKTOP_ENTRY_MAX_BYTES)) || return 2
	# A NUL byte, which awk would not see.
	[[ $(LC_ALL=C tr -d '\000' <"$file" | wc -c) == "$size" ]] || return 2
	LC_ALL=C awk -v want="$key" -v target="[$group]" '
		# A CRLF line end is only a line end.
		{ sub(/\r$/, "") }
		# Other control characters: the specification allows none in a value,
		# and a tab or escape here is a forged or broken file.
		/[\001-\010\011\013-\037\177]/ { bad = 1; exit }
		/^[ ]*(#|$)/ { next }
		/^\[/ {
			if ($0 in groups) { bad = 1; exit }
			groups[$0] = 1
			group = $0
			next
		}
		group == target {
			eq = index($0, "=")
			if (eq == 0) next
			name = substr($0, 1, eq - 1)
			sub(/ +$/, "", name)
			if (name in keys) { bad = 1; exit }
			keys[name] = 1
			if (name == want) {
				value = substr($0, eq + 1)
				sub(/^ +/, "", value)
				found = 1
			}
		}
		END {
			if (bad) exit 2
			if (!found) exit 1
			printf "%s\n", value
		}' "$file"
}

# One argument of an Exec line (desktop entry specification): quoted when it
# holds a space or a reserved character, with ", `, $ and \ escaped inside the
# quotes and a literal % written %%; then every backslash doubled again by the
# key file's own string escaping.
desktop_exec_arg() {
	local arg=${1//%/%%}
	if [[ $arg =~ [[:space:]\"\'\\\>\<\~\|\&\;\$\*\?\#\(\)\`] ]]; then
		arg=${arg//\\/\\\\}
		arg=${arg//\"/\\\"}
		arg=${arg//\`/\\\`}
		arg=${arg//\$/\\\$}
		arg="\"$arg\""
	fi
	printf '%s' "${arg//\\/\\\\}"
}
