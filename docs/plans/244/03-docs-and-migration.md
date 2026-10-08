# Step 3: docs, SPEC and migration notes

Commit: "Document Picom as part of the lyona desktop (#244)".

AGENTS.md says to update SPEC.md only when requirements intentionally change.
This is one: Picom goes from optional to required with the desktop.

## `AGENTS.md`

```diff
-- Keep optional desktop components optional. The absence of Picom, a wallpaper,
-  or a preferred terminal must not crash dwm.
+- Keep optional desktop components optional. The absence of a wallpaper or a
+  preferred terminal must not crash dwm.
+- Picom is part of the lyona desktop (recommended and full profiles): the
+  overview's window previews need it (#244). That is a packaging and session
+  rule only. dwm's C code never depends on it, and a missing, failing or
+  stopped Picom must not crash or hang dwm or the shell: the overview falls
+  back to icon-and-title cards and the user is told once.
```

## `SPEC.md`

Section 3 (session support):

```diff
-- Startup without Picom, a wallpaper, or a polkit agent.
+- Startup without a wallpaper or a polkit agent, and without Picom: Picom is
+  required with the lyona desktop (5.10.1), but a session without it still
+  starts, with icon-and-title overview cards and one notification.
```

Section 5.10.1, first paragraph of the protocol text:

```diff
 and `copy-config REVISION`. Mutations require the displayed source revision,
 validate before publication, preserve unrelated libconfig source and include
-files, back up changed files, and roll back failed activation. Missing Picom
-remains optional. Missing configuration shows 100 percent defaults and is
-created only on edit. Read-only system configurations require an explicit user
-copy, including referenced configuration files.
+files, back up changed files, and roll back failed activation. Missing
+configuration shows 100 percent defaults and is created only on edit. Read-only
+system configurations require an explicit user copy, including referenced
+configuration files.
+
+Picom is part of the lyona desktop (#244): the recommended and full profiles
+install it, autostart starts it through `dwm-settings-picom`, and the dependency
+checks report it missing as a required failure when Quickshell is installed
+(optional in the core profile). When it is missing or cannot start, the session
+continues, the overview keeps icon-and-title cards, and one notification says
+so; it is never retried in a loop. Stopping it (`stop`, `toggle`, the Control
+Center's `toggle-compositor`) remains a troubleshooting action that turns
+window previews off until it starts again.
+
+lyona ships a lean default configuration, `PREFIX/share/lyona/xdg/picom/picom.conf`
+(no shadows, fading, blur or animations; every window opaque; no backend, so the
+Automatic policy below applies). `dwm-settings-picom` puts its directory first in
+`XDG_CONFIG_DIRS` for itself and every Picom it starts, so it precedes the
+package's `/etc/xdg/picom.conf`, while a user's own configuration still wins.
```

Same section, discovery sentence:

```diff
 Explicit `DWM_PICOM_CONFIG` and existing session `--config`
-paths precede standard Picom XDG discovery. `PICOM_BACKEND` overrides an
+paths precede standard Picom XDG discovery, which searches the user's
+configuration, then lyona's default, then the system's. `PICOM_BACKEND` overrides an
```

## `README.md`

```diff
-| **A focused desktop** | Automatic window tiling, nine workspaces, fast keyboard navigation, multi-monitor support, and flexible fullscreen modes. |
+| **A focused desktop** | Automatic window tiling, nine workspaces, fast keyboard navigation, a window overview with live previews of every window, multi-monitor support, and flexible fullscreen modes. |
```

## `docs/src/getting-started.md`

```diff
 `Super` + `O` shows every open window, on every tag and monitor, as a card with
-a preview. Type to narrow the cards by title or class; `Up`, `Down`, `Home` and
+a preview. The previews come from Picom, the compositor lyona starts at login;
+without it the cards show each window's icon and title instead. Type to narrow
+the cards by title or class; `Up`, `Down`, `Home` and
```

## `docs/src/theming.md`

In "Picom opacity and backend":

```diff
-The controls read the active Picom configuration, normally `~/.config/picom.conf`
-or `~/.config/picom/picom.conf`, and observe external edits. With no configuration,
-they show 100% and create a minimal file on the first edit. A system configuration
-can be copied with **Create user configuration**.
+The controls read the active Picom configuration: your own `~/.config/picom.conf`
+or `~/.config/picom/picom.conf` when you have one, otherwise lyona's default
+(`/usr/share/lyona/xdg/picom/picom.conf` in a standard install). lyona's default
+is lean so that old hardware can run it: no shadows, fading, blur or animations,
+and every window opaque. It is read-only; **Create user configuration** copies it
+to `~/.config/picom.conf`, after which your copy is used and lyona's updates never
+touch it. The controls observe external edits.
```

## `docs/src/troubleshooting.md`

The section becomes:

````diff
-## Picom / Compositor Artifacts
+## Picom / Compositor
+
+Picom is part of the lyona desktop: the window overview's previews need it.
+dwm and the panel work without it; the overview then shows icon-and-title cards.
+
+### Picom does not start
+
+At login, a notification says "Picom could not start" (with the path of its
+log) or "Picom is not installed". It is shown once. To see why:
+
+```bash
+dwm-settings-picom status
+dwm-settings-picom start
+```
+
+`start` prints the reason and the log path. Common causes: an old or broken GPU
+driver, or a virtual machine without 3D acceleration. Choose **XRender** in
+**Settings > Appearance > Compositor**: it needs no GPU acceleration. If it is not
+installed: `sudo pacman -S picom`. Start Picom with `dwm-settings-picom start`, not
+`picom` alone: lyona's default configuration leaves the backend for the helper to
+choose, and Picom 13 does not start without one.
+
+### Stopping Picom
+
+**Control Center > Restart Picom** restarts it. To stop it while troubleshooting,
+run `dwm-settings-picom stop`: window previews are off until it starts again, and
+it starts again at the next login.
+
+### Artifacts
 
 Restart picom via the Control Center (**Quick Actions → Restart Picom**) or:
````

## `CHANGELOG.md`

Under `## [Unreleased]`, `### Changed`:

```markdown
- **Picom is part of the lyona desktop.** The overview's window previews need it, so the recommended and full profiles
  treat it as required: `check-deps.sh` and `dwm-diagnostics` report it missing as a required failure when Quickshell
  is installed (the core profile is unchanged), and System Health calls a stopped Picom a warning that turns previews
  off. When it is missing or cannot start at login, the session still starts, the overview shows icon-and-title cards,
  and one notification says why; nothing retries in a loop. dwm itself never depends on it (#244).
- **A lean default Picom configuration.** lyona now ships its own `picom.conf`, used when you have none of your own:
  no shadows, fading, blur or animations, and every window opaque. It leaves the backend to `dwm-settings-picom`'s
  Automatic choice (GLX on accelerated Intel and AMD graphics, XRender otherwise), which the package's configuration
  used to override with XRender everywhere (#244).
  - **Migration:** a session that used the package's `/etc/xdg/picom.conf` (no `~/.config/picom.conf` of your own)
    loses its shadows and fading at the next login. To keep them, copy that file to `~/.config/picom/picom.conf`.
    Your own configuration is never changed.
  - **Migration:** if you stopped or uninstalled Picom on purpose, for example because of an old GPU, you now get one
    notification at each login that it is not running, and System Health reports it. Try **XRender** in
    **Settings > Appearance > Compositor** first; see Troubleshooting > Picom.
```

## Validation

- Docs only, plus the plan's own files: no tests read these sections. Check
  ASCII-only additions (except where the file already uses non-ASCII, such as
  the `→` in troubleshooting) and that `mdbook build docs` still builds, if the
  repo's docs check covers it.

## Found while implementing

Step 1 made lyona's default read-only to the helper, and the helper keeps a
`XDG_CONFIG_DIRS` order that already lists lyona's directory. SPEC 5.10.1 and the
CHANGELOG entry say both: "unless it is already listed" and "It is never edited
in place: like any system configuration, editing it requires a user copy."

Settings > Appearance also said "Picom is optional and not installed"
(`scripts/dwm-settings-appearance`, and `dwm-settings-picom status`). Both now say
"Picom is not installed, so window previews are off", and the three tests that
pinned the old text follow.
