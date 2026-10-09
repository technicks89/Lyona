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
#   desktop_entries_read GROUP FILE...  Every key of GROUP in every FILE, in one
#                                       pass (#308): "FILE<TAB>KEY<TAB>VALUE"
#                                       lines, then "FILE<TAB><TAB>ok" for each
#                                       file read, or only
#                                       "FILE<TAB><TAB>invalid" for a file
#                                       refused whole. A file without GROUP is
#                                       ok with no keys; a missing or
#                                       unreadable one, or one whose name holds
#                                       a tab or line break, gives nothing.
#   desktop_entry_set SOURCE DEST GROUP KEY VALUE [KEY VALUE]...
#                                       SOURCE written to DEST with each KEY of
#                                       GROUP set to VALUE: its line replaced
#                                       where it is, else added at the end of
#                                       GROUP. Line ends become plain LF; with
#                                       no KEY, that is the only change.
#   desktop_exec_arg VALUE              VALUE as one argument of an Exec line.
#   desktop_list_without LIST TOKEN...  A semicolon list (OnlyShowIn and the
#                                       like) without TOKENs or empty items.
#   desktop_list_with LIST TOKEN        LIST with TOKEN, added at the end when
#                                       missing.

# Larger than any real desktop entry; a bound on what is read.
DESKTOP_ENTRY_MAX_BYTES=65536

# The one parser. gawk (Arch's awk) reads NUL bytes as data, so a NUL is
# caught here with the other control characters, in the same pass.
# shellcheck disable=SC2016 # awk source
DESKTOP_ENTRY_PARSER='
	function flush() {
		if (file == "") return
		if (!bad) {
			for (i = 1; i <= count; i++) printf "%s\t%s\t%s\n", file, names[i], values[i]
			printf "%s\t\tok\n", file
		} else {
			printf "%s\t\tinvalid\n", file
		}
	}
	function start() {
		flush()
		file = FILENAME
		if (file ~ /[\t\n]/) file = ""
		bad = 0; bytes = 0; count = 0; group = ""
		delete groups; delete keys
	}
	FNR == 1 { start() }
	file == "" { nextfile }
	{
		bytes += length($0) + 1
		if (bytes > max) { bad = 1; nextfile }
		# A CRLF line end is only a line end.
		sub(/\r$/, "")
		# Other control characters: the specification allows none in a value,
		# and a tab or escape here is a forged or broken file.
		if (index($0, "\0") > 0 || $0 ~ /[\001-\010\011\013-\037\177]/) { bad = 1; nextfile }
	}
	/^[ ]*(#|$)/ { next }
	/^\[/ {
		if ($0 in groups) { bad = 1; nextfile }
		groups[$0] = 1
		group = $0
		next
	}
	group == target {
		eq = index($0, "=")
		if (eq == 0) next
		name = substr($0, 1, eq - 1)
		sub(/ +$/, "", name)
		if (name in keys) { bad = 1; nextfile }
		keys[name] = 1
		value = substr($0, eq + 1)
		sub(/^ +/, "", value)
		names[++count] = name
		values[count] = value
	}
	END { flush() }
'

desktop_entries_read() {
	local group=$1 file
	local -a files=()
	shift
	for file in "$@"; do
		[[ -f $file && -r $file ]] && files+=("$file")
	done
	((${#files[@]} > 0)) || return 0
	LC_ALL=C gawk -v target="[$group]" -v max="$DESKTOP_ENTRY_MAX_BYTES" \
		"$DESKTOP_ENTRY_PARSER" "${files[@]}" 2>/dev/null || :
}

desktop_entry_get() {
	local file=$1 key=$2 group=${3:-Desktop Entry} size
	[[ -f $file && -r $file ]] || return 1
	size=$(stat -c %s -- "$file" 2>/dev/null) || return 2
	((size <= DESKTOP_ENTRY_MAX_BYTES)) || return 2
	[[ $file != *[$'\t\n']* ]] || return 2
	desktop_entries_read "$group" "$file" | LC_ALL=C awk -F '\t' -v want="$key" '
		$2 == want && !found { value = substr($0, length($1) + length($2) + 3); found = 1 }
		$2 == "" { status = $3 }
		END {
			if (status != "ok") exit 2
			if (!found) exit 1
			printf "%s\n", value
		}'
}

desktop_entry_set() {
	local source=$1 destination=$2 group=$3
	shift 3
	(($# % 2 == 0)) || return 2
	local -a pairs=()
	while (($# > 0)); do
		# A key or value holding a line break or a tab would forge a line.
		[[ $1 =~ ^[A-Za-z0-9-]+(\[[^][]+\])?$ && $2 != *[$'\t\n\r']* ]] || return 2
		pairs+=("$1=$2")
		shift 2
	done
	LC_ALL=C awk -v target="[$group]" '
		BEGIN {
			for (i = 1; i < ARGC - 1; i++) {
				eq = index(ARGV[i], "=")
				key = substr(ARGV[i], 1, eq - 1)
				order[++count] = key
				wanted[key] = ARGV[i]
				ARGV[i] = ""
			}
		}
		function add_missing(i) {
			for (i = 1; i <= count; i++) if (!(order[i] in done)) print wanted[order[i]]
		}
		{ sub(/\r$/, "") }
		/^\[/ {
			if (in_group) add_missing()
			in_group = ($0 == target)
			if (in_group) seen_group = 1
			print
			next
		}
		in_group && (eq = index($0, "=")) > 0 {
			key = substr($0, 1, eq - 1)
			sub(/ +$/, "", key)
			if (key in wanted && !(key in done)) {
				print wanted[key]
				done[key] = 1
				next
			}
		}
		{ print }
		END {
			if (in_group) add_missing()
			else if (!seen_group) { print target; add_missing() }
		}
	' "${pairs[@]}" "$source" >"$destination"
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

desktop_list_without() {
	local item token result=
	local -a items=()
	IFS=';' read -r -a items <<<"$1"
	shift
	for item in "${items[@]}"; do
		[[ -n $item ]] || continue
		for token in "$@"; do
			[[ $item != "$token" ]] || continue 2
		done
		result+="$item;"
	done
	printf '%s' "$result"
}

desktop_list_with() {
	local value=$1 item
	local -a items=()
	IFS=';' read -r -a items <<<"$value"
	for item in "${items[@]}"; do
		if [[ $item == "$2" ]]; then
			printf '%s' "$value"
			return
		fi
	done
	[[ -z $value || ${value: -1} == ';' ]] || value+=';'
	printf '%s' "$value$2;"
}
