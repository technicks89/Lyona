# Sync Phase 1 — standalone fixes

Upstream: [`#197`](https://github.com/ChrisTitusTech/dwm-titus/pull/197)
`Prefer desktop ChatGPT for legacy web hotkeys` (`70e6e43`), and `f4f477c`
`fix(settings): stabilize appearance watcher lifecycle`.
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

No dependencies on any other phase. Three unrelated items, one commit each.

---

## 1a — Port `#197`: desktop ChatGPT for legacy web hotkeys

### Context

`7bd6a54 Prefer ChatGPT Desktop` ported the *launcher* half of upstream's ChatGPT
work (`1c16634`). The `webapp-launch` half never landed, so Lyona's
`scripts/webapp-launch` is still the original one-liner — and it is broken
independently of ChatGPT:

```bash
exec $(sed -n 's/^Exec=\([^ ]*\).*/\1/p' {~/.local,~/.nix-profile,/usr}/share/applications/$browser 2>/dev/null | head -1) --app="$1" "${@:2}" >/dev/null 2>&1
```

- Brace expansion runs **before** tilde expansion, so `{~/.local,…}` produces the
  literal string `~/.local/share/applications/...`. The two user-scoped candidates
  never match; only `/usr` is ever consulted.
- The unquoted `$(...)` word-splits, so a browser installed at a path containing a
  space is executed as two arguments.
- `sed 's/^Exec=\([^ ]*\).*/\1/'` mis-parses any desktop entry whose `Exec` is
  quoted or backslash-escaped, per the Desktop Entry Specification.
- No URL validation: whatever is passed reaches the browser as `--app=`.

The port fixes all four and adds the ChatGPT desktop preference on top.

### Files

| File | Change |
| --- | --- |
| `scripts/webapp-launch` | Full rewrite |
| `scripts/dwm-quickshell-launcher` | One line — close the recursion |
| `tests/test-webapp-launch.sh` | New, ported from upstream onto `tests/lib.sh` |
| `Makefile` | New `check-webapp-launch` target; `scripts/webapp-launch` into `check-shell` and `check-format` |

`scripts/webapp-launch` is already in `INSTALL_COMMANDS`.

### `scripts/webapp-launch`

Replace the file entirely:

```bash
#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf 'usage: %s URL [browser-argument ...]\n' "${0##*/}" >&2
}

# Extract argv[0] from a desktop-entry Exec= line, honouring the specification's
# quoting and backslash escapes. sed cannot do this correctly.
parse_exec_path() {
	local value=${1#Exec=} character escaped=0 quoted=0 result=

	value=${value#"${value%%[![:space:]]*}"}
	[[ -n $value ]] || return 1
	if [[ ${value:0:1} == '"' ]]; then
		quoted=1
		value=${value:1}
	fi

	while [[ -n $value ]]; do
		character=${value:0:1}
		value=${value:1}
		if [[ $escaped -eq 1 ]]; then
			result+=$character
			escaped=0
		elif [[ $character == \\ ]]; then
			escaped=1
		elif [[ $quoted -eq 1 && $character == '"' ]]; then
			printf '%s\n' "$result"
			return 0
		elif [[ $quoted -eq 0 && $character == [[:space:]] ]]; then
			printf '%s\n' "$result"
			return 0
		else
			result+=$character
		fi
	done

	[[ $escaped -eq 0 && $quoted -eq 0 && -n $result ]] || return 1
	printf '%s\n' "$result"
}

find_browser_exec() {
	local desktop_file candidate line exec_path

	for desktop_file in \
		"$HOME/.local/share/applications/$browser" \
		"$HOME/.nix-profile/share/applications/$browser" \
		"/usr/share/applications/$browser"; do
		[[ -f $desktop_file ]] || continue
		# Read in-process and stop at the first Exec=, rather than forking grep
		# once per candidate on every web-app launch.
		line=
		while IFS= read -r candidate || [[ -n $candidate ]]; do
			if [[ $candidate == Exec=* ]]; then
				line=$candidate
				break
			fi
		done <"$desktop_file"
		[[ -n $line ]] || continue
		if ! exec_path=$(parse_exec_path "$line"); then
			printf '%s: unsupported browser Exec line in %s\n' \
				"${0##*/}" "$desktop_file" >&2
			return 1
		fi
		# A wrapper takes its own arguments before the browser's, so --app=
		# would land on the wrapper instead of the browser.
		case ${exec_path##*/} in
		flatpak | flatpak-* | snap | env)
			printf '%s: unsupported browser wrapper in %s: %s\n' \
				"${0##*/}" "$desktop_file" "$exec_path" >&2
			return 1
			;;
		esac
		printf '%s\n' "$exec_path"
		return 0
	done

	return 1
}

if [[ $# -lt 1 ]]; then
	usage
	exit 2
fi

url=$1
case $url in
http://* | https://*)
	valid_url_pattern='^https?://[^/?#[:space:]]+([/?#][^[:space:]]*)?$'
	;;
*)
	valid_url_pattern='^[A-Za-z][A-Za-z0-9+.-]*:[^[:space:]]+$'
	;;
esac
if [[ ! $url =~ $valid_url_pattern ]]; then
	printf '%s: invalid web app URL: %s\n' "${0##*/}" "$url" >&2
	exit 2
fi

# A bare ChatGPT web launch prefers the installed desktop app. The env guard is
# how dwm-quickshell-launcher asks for the web fallback without recursing back
# into itself.
case $url in
https://chatgpt.com | https://chatgpt.com/)
	if [[ $# -eq 1 && ${DWM_CHATGPT_WEB_FALLBACK:-0} != 1 ]] &&
		command -v dwm-quickshell-launcher >/dev/null 2>&1; then
		exec dwm-quickshell-launcher launch-chatgpt
	fi
	;;
esac

browser=$(xdg-settings get default-web-browser 2>/dev/null || true)

case $browser in
google-chrome* | brave-* | microsoft-edge* | opera* | vivaldi* | helium-browser*) ;;
*) browser="helium.desktop" ;;
esac

if ! browser_exec=$(find_browser_exec); then
	printf '%s: browser desktop entry has no executable: %s\n' "${0##*/}" "$browser" >&2
	exit 1
fi

exec "$browser_exec" --app="$url" "${@:2}" >/dev/null 2>&1
```

> **Deviation from upstream (efficiency).** Upstream's `find_browser_exec` runs
> `grep -m 1 '^Exec='` per candidate path — up to three forks on every web-app
> launch, on a hot path bound to a keyboard shortcut. The `while IFS= read` loop
> above does the same work in-process and stops at the first match. Everything else,
> including the `flatpak`/`snap`/`env` wrapper rejection and the URL patterns, is
> upstream's.

### `scripts/dwm-quickshell-launcher`

Close the recursion — without the guard, `launch_chatgpt` calls `webapp-launch`,
which calls `dwm-quickshell-launcher launch-chatgpt`, forever:

```diff
 launch_chatgpt() {
 	…
-	launch_background webapp-launch https://chatgpt.com
+	launch_background env DWM_CHATGPT_WEB_FALLBACK=1 webapp-launch https://chatgpt.com
 }
```

### `Makefile`

```diff
+check-webapp-launch:
+	tests/test-webapp-launch.sh
```

Then:

- append `$(MAKE) check-webapp-launch` to the `check:` recipe;
- add `check-webapp-launch` to `.PHONY`;
- append `scripts/webapp-launch` to the `check-shell` and `check-format` file lists.

### `tests/test-webapp-launch.sh`

Port upstream's 133-line test from `70e6e43`, rewritten onto `tests/lib.sh` per the
global rules. Cases that must survive the rewrite:

| Case | Asserts |
| --- | --- |
| Bare `https://chatgpt.com` with `dwm-quickshell-launcher` on `PATH` | Execs the launcher, not a browser |
| Same, with `DWM_CHATGPT_WEB_FALLBACK=1` | Execs the browser — no recursion |
| Same, with extra arguments | Execs the browser (the desktop app takes no extra args) |
| Quoted `Exec="/opt/My Browser/bin/browser" %U` | Parses to the full path, unsplit |
| Backslash-escaped `Exec=/opt/odd\ path/browser` | Parses to `/opt/odd path/browser` |
| `Exec=flatpak run com.example.Browser` | Rejected, exit 1, message on stderr |
| `Exec=` absent from the entry | Falls through to the next candidate |
| A user-scoped entry under `$HOME/.local/share/applications` | **Found** — this is the tilde-expansion bug |
| `webapp-launch 'not a url'` | Exit 2 |
| `webapp-launch` with no arguments | Usage, exit 2 |

---

## 1b — Fold in the `#197` keybinds prose

Upstream edits `docs/src/content/keybinds.md` (their Astro layout). Lyona keeps
mdBook, so the same three lines go into `docs/src/keybinds.md`: that the ChatGPT
hotkey prefers an installed desktop app and falls back to the web app otherwise.

Nothing from `d03531a`'s site rebuild is ported. See
[`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md#already-in-lyona--excluded-from-every-phase).

---

## 1c — Verify `f4f477c`, do not port it

Upstream `f4f477c fix(settings): stabilize appearance watcher lifecycle` hardens the
inline watcher in their `AppearanceModel.qml`: a helper that dies while the surface
is still open must be restarted, and a burst of change lines must coalesce into one
refresh.

Lyona already extracted exactly that supervision into
`config/quickshell/core/WatchedProcess.qml` — `settleTimer` coalesces, `restartTimer`
revives, and both are gated on `active` so closing the surface stops the
supervision. `AppearanceModel.qml:1693` uses it.

**Expected outcome: no production code change.** Confirm the behaviour is covered in
`tests/test-quickshell-appearance-model.sh`; if it is not, add the assertion —
kill the watch helper with the Settings surface open and assert a refresh still
arrives after `restartInterval`.

If that test shows `WatchedProcess` does *not* recover, fix `WatchedProcess` rather
than porting upstream's inline version; four models depend on it.

---

## Verification

```bash
scripts/run-tests make check-shell
scripts/run-tests make check-format
scripts/run-tests make check-webapp-launch
scripts/run-tests make check-quickshell-launcher
scripts/run-tests make check-quickshell-appearance-model
```

Manual: bind the ChatGPT hotkey with the desktop app installed (launches natively),
then uninstall it and repeat (falls back to the browser web app). Then launch any
other web app created by `scripts/webapp-create` and confirm it still opens.

## Closes

No `TASKS.md` checkbox — this is upstream parity plus a latent bug fix in
`webapp-launch`. Record it in `CHANGELOG.md` under fixes.
