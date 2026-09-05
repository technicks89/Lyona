# Sync Phase 7 — XKB input accessibility

Upstream: [`#203`](https://github.com/ChrisTitusTech/dwm-titus/pull/203)
`Phase 5: add XKB accessibility controls` (`8b846fb`, +608 / -82).
Depends on [Phase 4](SYNC-P4-A11Y-CAPABILITIES.md).
Index: [`UPSTREAM-SYNC.md`](UPSTREAM-SYNC.md).

Sticky keys, slow keys, bounce keys and mouse keys, over `xkbset`. Independent of
Phases 5 and 6 — it extends `dwm-settings-input`, not `Theme.qml`.

## Files

| File | Upstream | Note |
| --- | --- | --- |
| `scripts/dwm-settings-input` | +107 | Extends the existing `setxkbmap` path |
| `scripts/dwm-settings-provider` | +46 | Keyboard-accessibility capability detail |
| `config/quickshell/settings/InputSettingsPane.qml` | +14 | Four toggles |
| `config/quickshell/settings/SettingsModel.qml` | +2 | Model wiring |
| `config/quickshell/shell.qml` | +26 | IPC probes for the xvfb test |
| `scripts/check-deps.sh` | +1 | `xkbset` |
| `scripts/dwm-packages.sh` | **adapted** | `arch:desktop`, not `fedora:desktop` |
| `archiso/packages.x86_64` | **adapted** | Replaces upstream's two `.ks` files |
| `tests/test-settings-input.sh` | +103 | Rewrite onto `tests/lib.sh` |
| `tests/test-settings.sh` | +55 | Rewrite onto `tests/lib.sh` |
| `tests/test-arch-packages.sh` | **adapted** | Replaces `tests/test-fedora-packages.sh` |
| `docs/P5-INPUT-ACCESSIBILITY.md` | 46 new | Rewrite for Lyona |
| `docs/src/configuration.md`, `docs/src/install.md`, `docs/src/settings.md` | +14 | mdBook paths, not `docs/src/content/` |

## Context

Lyona's `scripts/dwm-settings-input` already owns the XKB surface — `need_setxkbmap()`
at `:43`, and a per-device `setxkbmap -device "$id" -query` at `:218-236` that
already emits `emit_unsupported` records when a keyboard cannot be queried. This
phase extends that path; it does not add a second one.

The new dependency is `xkbset`, which is what actually toggles AccessX. `setxkbmap`
cannot.

## `scripts/dwm-settings-input`

```diff
 self="$script_dir/${BASH_SOURCE[0]##*/}"
+accessibility_key=accessx
```

Then the five new functions. `run_xkbset` is the choke point — every `xkbset` call
goes through it, bounded, so a wedged X server cannot hang a Settings open:

```bash
need_xkbset() {
	command -v xkbset >/dev/null 2>&1 || die "xkbset is unavailable"
	command -v timeout >/dev/null 2>&1 || die "timeout is unavailable"
	[[ -n ${DISPLAY:-} ]] || die "DISPLAY is not set"
}

run_xkbset() {
	local timeout_path
	timeout_path=$(command -v timeout) || return 127
	"$timeout_path" --signal=TERM --kill-after=1 2 xkbset "$@"
}

accessibility_label() {
	case $1 in
	accessx-shortcuts) printf '%s\n' 'Accessibility Features (AccessX)' ;;
	sticky-keys) printf '%s\n' 'Sticky-Keys' ;;
	slow-keys) printf '%s\n' 'Slow-Keys' ;;
	bounce-keys) printf '%s\n' 'Bounce-Keys' ;;
	mouse-keys) printf '%s\n' 'Mouse-Keys' ;;
	*) return 1 ;;
	esac
}

accessibility_value() {
	local setting=$1 snapshot=${2-} label value
	label=$(accessibility_label "$setting") || return 1
	if (($# < 2)); then
		need_xkbset
		snapshot=$(LC_ALL=C run_xkbset q) || die "unable to query XKB accessibility controls"
	fi
	value=$(awk -F ' = ' -v label="$label" '$1 == label { print $2; found = 1; exit }
		END { exit !found }' <<<"$snapshot") || return 1
	case $value in
	On) printf '1\n' ;;
	Off) printf '0\n' ;;
	*) return 1 ;;
	esac
}

apply_accessibility_value() {
	local setting=$1 value=$2 option
	need_xkbset
	case $setting in
	accessx-shortcuts) option=a ;;
	sticky-keys) option=st ;;
	slow-keys) option=sl ;;
	bounce-keys) option=bo ;;
	mouse-keys) option=m ;;
	*) die "unsupported accessibility setting: $setting" ;;
	esac
	if [[ $value == 1 ]]; then
		LC_ALL=C run_xkbset "$option"
	else
		LC_ALL=C run_xkbset "-$option"
	fi
}
```

Two details worth keeping exactly as written:

- **`accessibility_value` takes an optional snapshot argument.** `discover` needs all
  five settings; passing one `xkbset q` result in means five reads cost one
  subprocess instead of five. Callers that read a single setting omit it and pay for
  their own query.
- **`LC_ALL=C`** on every `xkbset` call. The `awk -F ' = '` parse matches literal
  English labels (`Sticky-Keys = On`); under another locale the labels shift and the
  parse silently returns nothing.

The remaining upstream hunks extend `discover` to emit the five settings, and
`apply`/`reset` to route through `apply_accessibility_value`. They follow the file's
existing `emit_unsupported` conventions.

## Platform adaptation

Upstream adds `xkbset` to `fedora:desktop` and touches `dwm-fedora.ks`,
`dwm-fedora-nvidia.ks`, `tests/test-fedora-packages.sh` and
`tests/test-kickstart-variants.sh`. None of those exist in Lyona. The equivalent:

```diff
 	arch:desktop)
 		printf '%s\n' \
 			… \
-			bluez blueman playerctl upower power-profiles-daemon flatpak xdg-desktop-portal-gtk
+			bluez blueman playerctl upower power-profiles-daemon flatpak xdg-desktop-portal-gtk \
+			xkbset
 		;;
```

in `scripts/dwm-packages.sh`, plus `xkbset` in `archiso/packages.x86_64`,
`scripts/check-deps.sh`, and an assertion in `tests/test-arch-packages.sh`.

`xkbset` is in the Arch `extra` repository, so no AUR handling is needed.

## Degradation

`xkbset` absent, or `DISPLAY` unset, must produce `emit_unsupported` records — not
a `die` that takes the whole `discover` down. Lyona's existing pattern at
`scripts/dwm-settings-input:226-236` is the template:

```bash
	emit_unsupported "$key" accessibility "xkbset is unavailable"
```

The capability record from [Phase 4](SYNC-P4-A11Y-CAPABILITIES.md) reports
`restricted` for a present-but-unreachable X display and `unavailable` for a missing
`xkbset`, so the two failures stay distinguishable in Settings.

## Verification

```bash
scripts/run-tests make check-shell
scripts/run-tests make check-format
scripts/run-tests make check-settings
scripts/run-tests make check-arch-packages
scripts/run-tests make check-quickshell-settings-xvfb
```

Manual, in a live X session:

1. `dwm-settings-input discover` reports all five accessibility settings with their
   current state.
2. Toggle sticky keys from Settings → Input; confirm with `xkbset q` and by pressing
   `Shift` then a letter.
3. Toggle slow keys and bounce keys; confirm the timing behaviour changes and that
   both survive a `dwm-settings-input reset` back to off.
4. Mouse keys: confirm the numeric keypad moves the pointer.
5. `DISPLAY= dwm-settings-input discover` — must emit `unsupported` rows and exit 0,
   not `die`.
6. Uninstall `xkbset` and repeat step 5.

## Closes

Part of `TASKS.md:88` (the keyboard-accessibility capability, whose record
[Phase 4](SYNC-P4-A11Y-CAPABILITIES.md) defined) and the input half of
`TASKS.md:91`.
