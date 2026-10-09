#!/usr/bin/env bash
set -euo pipefail

# #260: lyona-appimage against fixture AppImages built here: a copy of
# /usr/bin/true as the ELF runtime with a squashfs image appended, as in a type-2
# AppImage. setsid, notify-send and gdbus are stubs that only log or answer, so
# nothing is run: TEST_CAPS is the notification server's capabilities, and
# TEST_ANSWER the button the user picks when asked (none: closed unanswered).

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
# The Exec= argument the shared writer produces for a path (#275).
# shellcheck source=scripts/dwm-desktop-entry.sh
. "$repo/scripts/dwm-desktop-entry.sh"
make_workspace
for tool in mksquashfs unsquashfs od python3; do
	command -v "$tool" >/dev/null 2>&1 || {
		printf 'SKIP: %s is unavailable\n' "$tool"
		exit 77
	}
done
helper=$repo/scripts/lyona-appimage

mkdir -p "$work/stubs" "$work/fixtures"
cat >"$work/stubs/setsid" <<'EOF'
#!/bin/sh
[ "$1" = -f ] && shift
[ "$1" = -- ] && shift
printf '%s\n' "$*" >>"$TEST_DIR/launch.log"
# The started AppImage must not inherit the open/remove lock (fd 9).
[ ! -e /proc/$$/fd/9 ] || echo inherited >>"$TEST_DIR/lock-inherited.log"
exit "${TEST_START_STATUS:-0}"
EOF
# A question (with buttons) goes to ask.log and is answered with TEST_ANSWER;
# anything else is a plain notification, in notify.log.
cat >"$work/stubs/notify-send" <<'EOF'
#!/bin/sh
case " $* " in
*" -A "*)
	printf '%s\n' "$*" >>"$TEST_DIR/ask.log"
	# Whether the open/remove lock was free while asking.
	# (exit 75 only for a conflict; no lock file yet is free too).
	status=0
	flock -n -E 75 "$TEST_LOCK" true 2>/dev/null || status=$?
	if [ "$status" = 75 ]; then echo held; else echo free; fi >>"$TEST_DIR/lock.log"
	# Something else happening while the question is open.
	[ -z "${TEST_DURING_ASK:-}" ] || sh -c "$TEST_DURING_ASK"
	[ -z "${TEST_ANSWER:-}" ] || printf '%s\n' "$TEST_ANSWER"
	;;
*) printf '%s\n' "$*" >>"$TEST_DIR/notify.log" ;;
esac
EOF
cat >"$work/stubs/gdbus" <<'EOF'
#!/bin/sh
printf "(['body', %s'persistence'],)\n" "$( [ -n "${TEST_CAPS:-}" ] && printf "'%s', " "$TEST_CAPS")"
EOF
chmod +x "$work/stubs/setsid" "$work/stubs/notify-send" "$work/stubs/gdbus"

# fixture NAME [setup]: builds $work/fixtures/NAME from the image directory
# $work/images/NAME, which the caller fills first.
fixture() { # NAME
	local image=$work/images/$1 out=$work/fixtures/$1
	mksquashfs "$image" "$out.sqfs" -noappend -quiet -all-root -no-xattrs >/dev/null
	cat /usr/bin/true "$out.sqfs" >"$out"
	rm -f -- "$out.sqfs"
}
png() { # PATH
	python3 -I -c 'import struct, sys, zlib
w = h = 4
raw = b"".join(b"\x00" + b"\xff\x00\x00" * w for _ in range(h))
def chunk(t, b): return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))' "$1"
}

# A well-formed one: its .desktop is a symlink into usr/share, as many are.
mkdir -p "$work/images/Good.AppImage/usr/share/applications"
cat >"$work/images/Good.AppImage/usr/share/applications/good.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Good App
Comment=A test application
Exec=good-app %U
Icon=good
Categories=Utility;
Terminal=false
MimeType=x-scheme-handler/good;
EOF
ln -s usr/share/applications/good.desktop "$work/images/Good.AppImage/good.desktop"
png "$work/images/Good.AppImage/good.png"
printf '#!/bin/sh\n' >"$work/images/Good.AppImage/AppRun"
fixture Good.AppImage

# Its .desktop points outside the image, at a host file: refused.
mkdir -p "$work/images/Escape.AppImage"
printf '[Desktop Entry]\nName=SECRET FROM HOST\n' >"$work/host-secret.desktop"
ln -s "$work/host-secret.desktop" "$work/images/Escape.AppImage/escape.desktop"
fixture Escape.AppImage

# No .desktop and no icon at all.
mkdir -p "$work/images/Bare.AppImage"
printf '#!/bin/sh\n' >"$work/images/Bare.AppImage/AppRun"
fixture Bare.AppImage

# Not in a terminal (stdin is /dev/null), so it asks with a notification. By
# default the server has buttons and the user picks Add and run.
run_helper() { # ARGS...
	env -i HOME="$work/home" PATH="$work/stubs:/usr/bin:/bin" TEST_DIR="$work" \
		TEST_CAPS="${TEST_CAPS-actions}" TEST_ANSWER="${TEST_ANSWER-run}" \
		TEST_START_STATUS="${TEST_START_STATUS:-0}" TEST_DURING_ASK="${TEST_DURING_ASK:-}" \
		TEST_LOCK="$work/home/.local/state/lyona/appimage.lock" XDG_DATA_HOME="$work/home/.local/share" XDG_STATE_HOME="$work/home/.local/state" \
		XDG_CACHE_HOME="$work/home/.cache" "$helper" "$@" </dev/null
}
count() { # FILE
	[[ -f $1 ]] && wc -l <"$1" || printf '0\n'
}
apps=$work/home/Applications
entries=$work/home/.local/share/applications
mkdir -p "$work/home/Downloads"

# --- The ELF runtime's end is where the image starts. ---------------------------
size=$(stat -c %s /usr/bin/true)
[[ $(od -An -c -j "$size" -N4 "$work/fixtures/Good.AppImage" | tr -d ' \n') == hsqs ]] ||
	fail 'the fixture is not a runtime followed by a squashfs image'

# --- Opening from Downloads: moved, executable, an entry and an icon, started. ---
cp "$work/fixtures/Good.AppImage" "$work/home/Downloads/Good.AppImage"
run_helper open "$work/home/Downloads/Good.AppImage" || fail 'opening a good AppImage failed'
[[ ! -e $work/home/Downloads/Good.AppImage ]] || fail 'the AppImage was not moved out of Downloads'
[[ -x $apps/Good.AppImage ]] || fail 'the AppImage is not executable in ~/Applications'
entry=$entries/lyona-appimage-good-appimage.desktop
[[ -f $entry ]] || fail 'no launcher entry was written'
grep -Fxq 'Name=Good App' "$entry" || fail 'the entry does not carry the name from inside the image'
grep -Fxq "Exec=$(desktop_exec_arg "$apps/Good.AppImage") %U" "$entry" || fail "the entry does not start the moved file: $(grep ^Exec= "$entry")"
grep -Fxq "X-Lyona-AppImage=$apps/Good.AppImage" "$entry" || fail 'the entry does not record its file'
grep -Fxq 'Categories=Utility;' "$entry" || fail 'the categories were not kept'
if grep -q '^MimeType=' "$entry"; then
	fail 'an AppImage must not register MIME types through lyona-appimage'
fi
icon=$(sed -n 's/^Icon=//p' "$entry")
if [[ $icon != "$work/home/.local/share/lyona/appimage-icons/lyona-appimage-good-appimage.png" || ! -f $icon ]]; then
	fail "the icon was not installed: $icon"
fi
if [[ $(count "$work/notify.log") != 1 ]] || ! grep -Fq 'Added Good App to the launcher' "$work/notify.log"; then
	fail 'adding it was not said exactly once'
fi
if [[ $(count "$work/launch.log") != 1 ]] || ! grep -Fxq "$apps/Good.AppImage" "$work/launch.log"; then
	fail 'the AppImage was not started once'
fi
if [[ $(count "$work/ask.log") != 1 ]] || ! grep -Fq 'Run Good.AppImage?' "$work/ask.log"; then
	fail 'the first open did not ask once'
fi
grep -Fq -- '-u critical' "$work/ask.log" || fail 'the question is not critical, so Do Not Disturb would hide it'
grep -Fq 'Moved to' "$work/notify.log" || fail 'the added notification does not say the file moved'

# --- Opening it again: started, nothing added twice. ----------------------------
run_helper open "$apps/Good.AppImage" || fail 'opening it again failed'
[[ $(find "$entries" -name 'lyona-appimage-*.desktop' | wc -l) == 1 ]] || fail 'opening it again added a second entry'
[[ $(count "$work/notify.log") == 1 ]] || fail 'opening it again said it was added again'
[[ $(count "$work/launch.log") == 2 ]] || fail 'opening it again did not start it'
[[ $(count "$work/ask.log") == 1 ]] || fail 'opening an added AppImage asked again'
# The same file downloaded again: no second copy in ~/Applications, no second entry.
cp "$work/fixtures/Good.AppImage" "$work/home/Downloads/Good.AppImage"
run_helper open "$work/home/Downloads/Good.AppImage" || fail 'opening an identical copy failed'
[[ $(find "$apps" -type f | wc -l) == 1 ]] || fail 'an identical copy was added to ~/Applications again'
[[ $(find "$entries" -name 'lyona-appimage-*.desktop' | wc -l) == 1 ]] || fail 'an identical copy added a second entry'
rm -f "$work/home/Downloads/Good.AppImage"

# --- A symlink out of the image is not followed: the host file is never read. ----
cp "$work/fixtures/Escape.AppImage" "$work/home/Downloads/Escape.AppImage"
run_helper open "$work/home/Downloads/Escape.AppImage" || fail 'an escaping .desktop stopped the open'
escape_entry=$entries/lyona-appimage-escape-appimage.desktop
if grep -q 'SECRET FROM HOST' "$escape_entry"; then
	fail 'a symlink inside the image read a file from the host'
fi
grep -Fxq 'Name=Escape' "$escape_entry" || fail 'an AppImage without a usable entry is not named after its file'

# --- No .desktop, no icon: named after the file, a generic icon. ---------------
cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/Bare.AppImage"
run_helper open "$work/home/Downloads/Bare.AppImage" || fail 'an AppImage without an entry failed'
bare_entry=$entries/lyona-appimage-bare-appimage.desktop
grep -Fxq 'Name=Bare' "$bare_entry" || fail 'a bare AppImage is not named after its file'
grep -Fxq 'Icon=application-x-executable' "$bare_entry" || fail 'a bare AppImage has no generic icon'
grep -Fxq "Exec=$(desktop_exec_arg "$apps/Bare.AppImage")" "$bare_entry" || fail 'a bare AppImage has the wrong Exec'

# --- A path that needs quoting. -------------------------------------------------
cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/My \$Tool.AppImage"
run_helper open "$work/home/Downloads/My \$Tool.AppImage" || fail 'a name with a space and a dollar failed'
# Quoted for Exec ($ escaped), then the key file's escaping doubles the backslash.
grep -Fxq "Exec=\"$apps/My \\\\\$Tool.AppImage\"" "$entries/lyona-appimage-my-tool-appimage.desktop" ||
	fail "the Exec line is not quoted: $(grep ^Exec= "$entries/lyona-appimage-my-tool-appimage.desktop")"

# --- A % in the name is written %%, not read as a field code. -------------------
cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/Tool%20X.AppImage"
run_helper open "$work/home/Downloads/Tool%20X.AppImage" || fail 'a name with a percent sign failed'
percent_entry=$entries/lyona-appimage-tool-20x-appimage.desktop
if ! grep -Fxq "Exec=$(desktop_exec_arg "$apps/Tool%20X.AppImage")" "$percent_entry" ||
	! grep -Fq 'Tool%%20X.AppImage' "$percent_entry"; then
	fail "a % in the Exec line is not doubled: $(grep ^Exec= "$percent_entry")"
fi

# --- A failure after the move puts the file back. -------------------------------
cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/Stuck.AppImage"
chmod a-w "$entries"
if run_helper open "$work/home/Downloads/Stuck.AppImage" 2>/dev/null; then
	chmod u+w "$entries"
	fail 'opening succeeded although its entry could not be written'
fi
chmod u+w "$entries"
[[ -f $work/home/Downloads/Stuck.AppImage ]] || fail 'a failed open did not put the file back'
[[ ! -e $apps/Stuck.AppImage ]] || fail 'a failed open left the file in ~/Applications'
[[ ! -e $entries/lyona-appimage-stuck-appimage.desktop ]] || fail 'a failed open left an entry'
rm -f "$work/home/Downloads/Stuck.AppImage"

# --- Cancel, or closing the question: nothing moved, added or started. ---------
for answer in cancel ''; do
	cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/Maybe.AppImage"
	launched_before=$(count "$work/launch.log")
	TEST_ANSWER=$answer run_helper open "$work/home/Downloads/Maybe.AppImage" 2>/dev/null ||
		fail "answering '$answer' failed"
	[[ -f $work/home/Downloads/Maybe.AppImage && ! -x $work/home/Downloads/Maybe.AppImage ]] ||
		fail "answering '$answer' moved the file or made it executable"
	[[ ! -e $apps/Maybe.AppImage && ! -e $entries/lyona-appimage-maybe-appimage.desktop ]] ||
		fail "answering '$answer' added it"
	[[ $(count "$work/launch.log") == "$launched_before" ]] || fail "answering '$answer' started it"
done

# --- The question does not hold the lock; a second open while it is up. --------
grep -qx held "$work/lock.log" && fail 'the open/remove lock was held while asking'
cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/Twice.AppImage"
launched_before=$(count "$work/launch.log")
# While the first open asks, a second open of the same file adds it (answer: add).
TEST_DURING_ASK="TEST_DURING_ASK= TEST_ANSWER=add $(printf '%q open %q' "$helper" "$work/home/Downloads/Twice.AppImage")" \
	run_helper open "$work/home/Downloads/Twice.AppImage" 2>"$work/err" || fail "the first of two opens failed: $(cat "$work/err")"
[[ -x $apps/Twice.AppImage && ! -e $work/home/Downloads/Twice.AppImage ]] || fail 'two opens did not add the file once'
[[ $(find "$entries" -name 'lyona-appimage-twice-appimage*.desktop' | wc -l) == 1 ]] || fail 'two opens wrote two entries'
[[ $(count "$work/launch.log") == $((launched_before + 1)) ]] || fail 'the first open (Add and run) did not start it'

# --- Add only: added, not started. ----------------------------------------------
launched_before=$(count "$work/launch.log")
TEST_ANSWER=add run_helper open "$work/home/Downloads/Maybe.AppImage" || fail 'Add only failed'
[[ -x $apps/Maybe.AppImage && -f $entries/lyona-appimage-maybe-appimage.desktop ]] || fail 'Add only did not add it'
[[ $(count "$work/launch.log") == "$launched_before" ]] || fail 'Add only started it'

# --- No server that can ask: added, never started unasked. ----------------------
cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/Quiet.AppImage"
asked_before=$(count "$work/ask.log")
TEST_CAPS='' run_helper open "$work/home/Downloads/Quiet.AppImage" || fail 'opening without buttons failed'
[[ -f $entries/lyona-appimage-quiet-appimage.desktop ]] || fail 'without buttons it was not added'
[[ $(count "$work/launch.log") == "$launched_before" ]] || fail 'without buttons it was started unasked'
[[ $(count "$work/ask.log") == "$asked_before" ]] || fail 'it asked a server without buttons'

# --- In a terminal, it asks there. ----------------------------------------------
if command -v script >/dev/null 2>&1; then
	cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/Term.AppImage"
	printf 'a\n' | env -i HOME="$work/home" PATH="$work/stubs:/usr/bin:/bin" TEST_DIR="$work" \
		XDG_DATA_HOME="$work/home/.local/share" XDG_STATE_HOME="$work/home/.local/state" \
		XDG_CACHE_HOME="$work/home/.cache" TERM=dumb \
		script -qec "$(printf '%q open %q' "$helper" "$work/home/Downloads/Term.AppImage")" /dev/null \
		>"$work/term.out" 2>&1 || fail "the terminal question failed: $(cat "$work/term.out")"
	grep -Fq '[r] Add and run' "$work/term.out" || fail "it did not ask in the terminal: $(cat "$work/term.out")"
	[[ -f $entries/lyona-appimage-term-appimage.desktop ]] || fail 'answering a in the terminal did not add it'
	[[ $(count "$work/launch.log") == "$launched_before" ]] || fail 'answering a in the terminal started it'
fi

# --- Not an AppImage: refused, said, nothing moved. ------------------------------
printf 'not an appimage\n' >"$work/home/Downloads/fake.AppImage"
cp /usr/bin/true "$work/home/Downloads/elf-only.AppImage"
for fake in fake elf-only; do
	notified_before=$(count "$work/notify.log")
	if run_helper open "$work/home/Downloads/$fake.AppImage" 2>"$work/err"; then
		fail "$fake.AppImage was accepted as an AppImage"
	fi
	[[ -e $work/home/Downloads/$fake.AppImage ]] || fail "$fake.AppImage was moved although it was refused"
	if [[ $(count "$work/notify.log") != $((notified_before + 1)) ]] ||
		! tail -n 1 "$work/notify.log" | grep -Fq 'AppImage not added'; then
		fail "refusing $fake.AppImage was not said"
	fi
done

# --- list and remove. -----------------------------------------------------------
listed=$(run_helper list)
grep -Fq "Good App	$apps/Good.AppImage" <<<"$listed" || fail "list does not show Good App: $listed"
printf 'keep me\n' >"$apps/unrelated.txt"
run_helper remove 'good app' >/dev/null || fail 'removing by name (any case) failed'
[[ ! -e $apps/Good.AppImage && ! -e $entry && ! -e $icon ]] || fail 'remove left the file, the entry or the icon'
[[ -f $apps/unrelated.txt && -f $apps/Bare.AppImage && -f $bare_entry ]] || fail 'remove took something it had not added'
run_helper remove Bare.AppImage >/dev/null || fail 'removing by file name failed'
[[ ! -e $apps/Bare.AppImage && ! -e $bare_entry ]] || fail 'remove by file name left something'
if run_helper remove 'Nothing Like This' 2>/dev/null; then
	fail 'removing an unknown name succeeded'
fi

# --- A name two AppImages share: refused, with their file names. -----------------
mkdir -p "$work/images/Twin.AppImage"
printf '[Desktop Entry]\nName=Twin\n' >"$work/images/Twin.AppImage/twin.desktop"
fixture Twin.AppImage
cp "$work/fixtures/Twin.AppImage" "$work/home/Downloads/TwinOne.AppImage"
cat "$work/fixtures/Twin.AppImage" >"$work/home/Downloads/TwinTwo.AppImage"
printf 'x' >>"$work/home/Downloads/TwinTwo.AppImage" # a different file, same entry name
run_helper open "$work/home/Downloads/TwinOne.AppImage" || fail 'opening TwinOne failed'
run_helper open "$work/home/Downloads/TwinTwo.AppImage" || fail 'opening TwinTwo failed'
if run_helper remove Twin 2>"$work/err"; then
	fail 'a name two AppImages share removed something'
fi
if ! grep -Fq '2 AppImages are named Twin' "$work/err" || ! grep -Fq 'TwinOne.AppImage' "$work/err"; then
	fail "an ambiguous name was not explained: $(cat "$work/err")"
fi
[[ -f $apps/TwinOne.AppImage && -f $apps/TwinTwo.AppImage ]] || fail 'an ambiguous remove deleted a file'
run_helper remove TwinTwo.AppImage >/dev/null || fail 'removing one twin by file name failed'
[[ -f $apps/TwinOne.AppImage && ! -e $apps/TwinTwo.AppImage ]] || fail 'removing by file name took the wrong twin'

# --- Names whose slugs collide get their own entries. ---------------------------
cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/My_App.AppImage"
cat "$work/fixtures/Bare.AppImage" >"$work/home/Downloads/My-App.AppImage"
printf 'y' >>"$work/home/Downloads/My-App.AppImage"
run_helper open "$work/home/Downloads/My_App.AppImage" || fail 'opening My_App failed'
run_helper open "$work/home/Downloads/My-App.AppImage" || fail 'opening My-App failed'
grep -Fxq "X-Lyona-AppImage=$apps/My_App.AppImage" "$entries/lyona-appimage-my-app-appimage.desktop" ||
	fail 'the second AppImage took the first one'"'"'s entry'
grep -Fxq "X-Lyona-AppImage=$apps/My-App.AppImage" "$entries/lyona-appimage-my-app-appimage-2.desktop" ||
	fail 'the second AppImage did not get an entry of its own'
asked_before=$(count "$work/ask.log")
run_helper open "$apps/My_App.AppImage" || fail 'opening My_App again failed'
[[ $(count "$work/ask.log") == "$asked_before" ]] || fail 'My_App was added again after My-App'

# --- A path longer than a cleaned value is still recognised as added. ------------
long=$(printf 'L%.0s' {1..230}) # with the directory, a path over 256 characters
cp "$work/fixtures/Bare.AppImage" "$apps/$long.AppImage"
run_helper open "$apps/$long.AppImage" || fail 'opening a long name failed'
asked_before=$(count "$work/ask.log")
run_helper open "$apps/$long.AppImage" || fail 'opening a long name again failed'
[[ $(count "$work/ask.log") == "$asked_before" ]] || fail 'a long path was added again on every open'
run_helper remove "$apps/$long.AppImage" >/dev/null || fail 'removing a long path by path failed'

# --- A name a launcher entry cannot hold: refused, nothing moved. ----------------
for bad in $'Two\nLines' 'Back\\slash'; do
	cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/$bad.AppImage"
	if run_helper open "$work/home/Downloads/$bad.AppImage" 2>"$work/err"; then
		fail "a name with a control character or backslash was accepted"
	fi
	grep -Fq 'rename it' "$work/err" || fail "refusing a bad name did not say why: $(cat "$work/err")"
	[[ -f $work/home/Downloads/$bad.AppImage ]] || fail 'a refused name was moved'
	rm -f -- "$work/home/Downloads/$bad.AppImage"
done

# --- A directory named like an entry is not extracted. ---------------------------
mkdir -p "$work/images/Dir.AppImage/huge.desktop/sub"
printf '[Desktop Entry]\nName=From a directory\n' >"$work/images/Dir.AppImage/huge.desktop/sub/x.desktop"
printf '[Desktop Entry]\nName=Dir App\n' >"$work/images/Dir.AppImage/real.desktop"
fixture Dir.AppImage
cp "$work/fixtures/Dir.AppImage" "$work/home/Downloads/Dir.AppImage"
run_helper open "$work/home/Downloads/Dir.AppImage" || fail 'opening an image with a .desktop directory failed'
grep -Fxq 'Name=Dir App' "$entries/lyona-appimage-dir-appimage.desktop" ||
	fail 'the real entry was not read past a .desktop directory'
[[ -z $(find "$work/home/.cache/lyona" -mindepth 1 2>/dev/null) ]] || fail 'the scratch directory was left behind'

# --- One that fails to start is reported. ----------------------------------------
cp "$work/fixtures/Bare.AppImage" "$work/home/Downloads/Broken.AppImage"
if TEST_START_STATUS=3 run_helper open "$work/home/Downloads/Broken.AppImage" 2>"$work/err"; then
	fail 'an AppImage that failed to start was reported as started'
fi
grep -Fq 'Broken.AppImage did not start (exit 3)' "$work/err" || fail "a failed start was not said: $(cat "$work/err")"
grep -Fq 'Broken.AppImage did not start' "$work/notify.log" || fail 'a failed start was not notified'
[[ -f $entries/lyona-appimage-broken-appimage.desktop ]] || fail 'a failed start took the entry away'

# --- remove: to the trash, said, and only its own icon. --------------------------
outside=$work/home/keep.png
printf 'keep\n' >"$outside"
sed -i "s|^Icon=.*|Icon=$work/home/.local/share/lyona/appimage-icons/../../../../keep.png|" \
	"$entries/lyona-appimage-broken-appimage.desktop"
run_helper remove Broken.AppImage >"$work/remove.out" || fail 'removing Broken failed'
grep -Fq "Removed Broken from the launcher; $apps/Broken.AppImage" "$work/remove.out" ||
	fail "remove did not say what it did: $(cat "$work/remove.out")"
[[ ! -e $apps/Broken.AppImage ]] || fail 'remove left the file'
if command -v gio >/dev/null 2>&1 && grep -Fq 'moved to the trash' "$work/remove.out"; then
	[[ -f $work/home/.local/share/Trash/files/Broken.AppImage ]] || fail 'remove said trash but the file is not there'
fi
[[ -f $outside ]] || fail 'remove deleted an icon outside its own directory'

[[ ! -e $work/lock-inherited.log ]] || fail 'a started AppImage inherited the open/remove lock'

# --- Usage. ----------------------------------------------------------------------
status=0
run_helper frobnicate 2>/dev/null || status=$?
[[ $status == 2 ]] || fail "a bad action did not exit 2 ($status)"

printf 'lyona-appimage (open, re-open, symlink escape, bare, quoting, percent, rollback, ask, refusal, list, remove, collisions, bounds): PASS\n'
