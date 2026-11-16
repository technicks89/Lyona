# Clipboard history privacy

Clipboard history (#469, ported from upstream dwm-titus #389 and #411) keeps
text you copy, so you can get an earlier copy back with **Super+V**. It is off
until you turn it on, and what it may keep is decided before any text is read.

## Opt-ins and storage

- **Capture** is off by default. Turned on in the clipboard window, it starts
  `dwm-clipboard-observer` (installed in `PREFIX/lib/lyona`, run through
  `dwm-clipboard-history observe`, bound to the shell's lifetime). Turned off,
  the observer stops, the list empties and saving turns off too.
- **Saving** to disk is a second, separate opt-in, available only with capture
  on. Saved history is `${XDG_STATE_HOME:-$HOME/.local/state}/lyona/clipboard-history.json`,
  mode 0600 in a 0700 directory, written whole and renamed into place under
  umask 077, so it is never readable by others, even for a moment. It is
  plain text, not encrypted: home backups and file sync tools copy it like any
  other file under your home. Turning saving off deletes the file (with `rm`,
  not overwritten). **Clear all** deletes it too.
- The two settings are `${XDG_CONFIG_HOME:-$HOME/.config}/lyona/clipboard-history.conf`
  (`capture=on`, `persist=on`; anything else reads as off). A symlinked file or
  directory on the way is refused, never written through.
- At most 50 entries are kept, each at most 64 KiB of text. Copying an entry
  back moves it to the top.

The shell never reads the clipboard itself for history: it takes only what
the observer admits, and never falls back to Quickshell's own clipboard, which
would see every copy.

## What is kept

Ordinary copies from browsers and terminals are kept. **A password copied by a
browser password-manager extension, or selected in a terminal, looks like any
other copy and can be kept.** The clipboard window says so before capture is
turned on. No marker or source check can guarantee that every password is
excluded.

Copies are not kept when:

- the application advertises a sensitivity marker among its clipboard targets:
  `x-kde-passwordManagerHint` (KeePassXC sets it),
  `application/x-keepassxc`, `application/x-nspasteboard-concealed-type`,
  `ExcludeClipboardContentFromMonitorProcessing` or
  `application/x-dwm-clipboard-private`, whatever its value;
- the copying process is an identifiable password manager: an executable
  named for Bitwarden, KeePass (KeePassXC, KeePassX), 1Password, Proton Pass,
  NordPass, Enpass, Dashlane, LastPass or Keeper Desktop, or the clients `bw`,
  `bws`, `rbw`, `pass`, `gopass` or `kpcli`. An interpreter running one
  (`mono KeePass.exe`, `node /usr/bin/bw`, `perl /usr/bin/kpcli`) counts too;
  an interpreter option the observer does not know refuses rather than guess
  which argument is the program;
- a parent of the copying process, up to 16 levels of this user's, is one;
- the copying process cannot be identified: not this user's, unreadable, or
  too deep.

Names are best-effort: a renamed executable, a detached helper or an
application this list does not name can get past the source check. **The
command-line managers `pass -c` and `gopass` are the usual case** (#526): they
hand the password to `xclip` or `xsel`, which fork into the background, so the
clipboard's owner is a lone `xclip` whose parent is no longer `pass`, and the
copy is probably kept. With those tools, leave capture off, or clear the entry
after use. Text
copied, pasted into another application and copied again carries that
application's identity, not the first one's. The policy does not defend
against a hostile client in the same X11 session, and it does not guess at
passwords from the text or a window title. `dwm-clipboard-observer --policy`
prints the limit in one line.

Only CLIPBOARD is followed; selecting text (PRIMARY) is never kept. The
observer never owns, clears or replaces the clipboard: copying and pasting
work as before.

## Before any text is read

1. Ownership changes come from XFixes events; nothing polls. The clipboard as
   it was when the observer started is never imported.
2. The owner's process ID comes from the X server (XRes 1.2, local client
   PID), never from `_NET_WM_PID`, `WM_CLASS`, a title or the focused window.
3. The process is checked: this user's `/proc` entry, executable and its
   inode, start time, bounded launch arguments (for interpreters) and parents.
4. Only the list of targets (at most 128) is requested; any sensitivity marker
   there ends it.
5. Only then is `UTF8_STRING` requested: at most 65,536 bytes of valid UTF-8,
   in one reply. INCR, partial, malformed, oversized and late replies are
   refused. Each request has a one-second deadline.
6. The owner, its process and the change count are checked again before the
   text is passed on; a new copy meanwhile drops it. Each request uses a fresh
   requestor window, so a late reply is never taken for a current one.

The observer prints one ASCII JSON object per line: `{"event":"ready","protocol":1}`
once, then `{"event":"text","text":"..."}` for each admitted copy, every
non-ASCII character escaped. It prints no clipboard text or arguments to
stderr, and core dumps are off. The shell stops capture on a malformed or
oversized record, on the observer ending, or when it is not ready within 3
seconds; turning capture on again retries. Without XFixes, XRes 1.2 or a local
display, the observer exits with a generic message.

## Validation

- `make check-clipboard-observer`: native clipboard owners on private Xvfb
  servers. Browser and terminal copies are admitted; managers by name, by
  interpreter entry point, behind an option operand and as a parent are
  refused before any request; a marker stops it before the text; forged
  `WM_CLASS` and `_NET_WM_PID`, a re-copy racing a read, an owner that never
  answers, INCR, oversized and invalid replies, and a server without XRes are
  handled; nothing is imported at startup and nothing is polled. No real vault
  or password manager is used.
- `make check-clipboard-history`: the settings and storage helper.
- `make check-quickshell-clipboard-history-xvfb`: the shell's model and window
  against a stub helper.
