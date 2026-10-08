# Step 1: lyona's lean Picom default, ahead of the package's

Commit: "Ship a lean default Picom configuration (#244)".

## Why

lyona ships no `picom.conf`, so Picom and `dwm-settings-picom` use the
package's `/etc/xdg/picom.conf`. On Arch (Picom 13) that file turns on
`shadow`, `fading` and `frame-opacity = 0.9`, and sets `backend = "xrender"`,
which keeps the helper's automatic backend choice from ever applying. The issue
asks for a lean default: no blur, shadows or animations, and the cheapest
working backend for weak or unknown GPUs.

## How

Picom searches `$XDG_CONFIG_HOME` first, then each directory in
`$XDG_CONFIG_DIRS` (default `/etc/xdg`), for `picom.conf` and then
`picom/picom.conf`. Checked on Xvfb with Picom 13: with a directory put first in
`XDG_CONFIG_DIRS`, `picom --diagnostics` reports `Config file used:` from it;
without, `/etc/xdg/picom.conf`.

So `dwm-settings-picom` puts lyona's directory first in `XDG_CONFIG_DIRS`,
once, in `main()`. Everything it does inherits it: its own lookup
(`candidates()`, `resolve_include()`), the `picom --diagnostics` probe, and
every Picom it starts. A user's own `~/.config/picom.conf` or
`~/.config/picom/picom.conf` still wins, because `XDG_CONFIG_HOME` is searched
first. Settings' import-on-first-edit treats lyona's file like any vendor file,
so editing still copies it into the user's configuration. No `--config` is
passed, so the helper's rule against editing an explicit `--config` is not
triggered. (Passing `--config` was rejected for that reason: Settings would
refuse to edit, and a stale path would survive the user's first copy.)

Checked on Xvfb with the helper from this checkout and a prepended directory:
`start` launched `picom --backend xrender` (the automatic choice on an
unaccelerated display), `status` reported the prepended file as its path, and
`stop` stopped only that display's Picom.

Where the file is:

- In an install: `PREFIX/share/lyona/xdg/picom/picom.conf`, so the directory is
  `PREFIX/share/lyona/xdg`, found from the helper's own path
  (`PREFIX/bin/dwm-settings-picom`), like the other shipped defaults (Sync
  Sprint 12 S12-13).
- In a checkout: `config/picom/picom.conf`, so the directory is `config/`.
  Picom only looks for `picom.conf` and `picom/picom.conf` in it.

## New file: `config/picom/picom.conf`

Checked: Picom 13 parses it (with a backend given, as the helper does), and the
helper's own parser reads `shadow` and `fading` as false and the backend as
`auto`.

```
# lyona's default Picom configuration (#244).
#
# Lean on purpose, so old hardware can run it: no shadows, no fading, no blur
# and no animations. The backend is not set here: dwm-settings-picom chooses it,
# GLX on an accelerated Intel or AMD renderer and XRender for NVIDIA, software
# rendering or unknown hardware. Start Picom with `dwm-settings-picom start`,
# which passes it; Picom 13 started by hand needs `--backend`.
#
# This file is used only when you have no ~/.config/picom.conf or
# ~/.config/picom/picom.conf of your own. To change it, use Settings >
# Appearance > Compositor (Create user configuration copies it there first), or
# copy it there yourself. Updates replace this file; your copy is never touched.

shadow = false;
fading = false;
blur-background = false;
corner-radius = 0;

# Every window opaque. Settings writes active and inactive opacity into your
# copy.
frame-opacity = 1.0;
detect-client-opacity = true;

vsync = true;
use-damage = true;
detect-rounded-corners = true;
detect-transient = true;
mark-wmwin-focused = true;
mark-ovredir-focused = true;
```

If step 4 finds GLX costs more than XRender on the old machine, add one line
under the header and say why:

```
backend = "xrender";
```

## `scripts/dwm-settings-picom`

After `config_home()`:

```diff
 def config_home():
     value = os.environ.get("XDG_CONFIG_HOME", "")
     return Path(value) if value.startswith("/") else Path.home() / ".config"
 
 
+def lyona_config_dir(script=None):
+    """lyona's default configuration directory (#244): PREFIX/share/lyona/xdg in
+    an install, config/ in a checkout. None when neither holds picom/picom.conf."""
+    base = Path(script or __file__).resolve().parent.parent
+    for directory in (base / "share/lyona/xdg", base / "config"):
+        if (directory / "picom/picom.conf").is_file():
+            return directory
+    return None
+
+
+def use_lyona_defaults(script=None):
+    """Put lyona's lean default ahead of the package's /etc/xdg/picom.conf, for
+    this helper and every Picom it starts (#244). A user's own configuration
+    still wins: Picom searches XDG_CONFIG_HOME before XDG_CONFIG_DIRS."""
+    directory = lyona_config_dir(script)
+    if directory is None:
+        return
+    dirs = [d for d in os.environ.get("XDG_CONFIG_DIRS", "/etc/xdg").split(":") if d]
+    if str(directory) not in dirs:
+        os.environ["XDG_CONFIG_DIRS"] = ":".join([str(directory), *dirs])
+
+
 def run(argv, timeout=8):
```

At the start of `main()`. Not at import: `tests/test-picom.py` loads the helper
as a module and sets its own `XDG_CONFIG_DIRS`.

```diff
 def main():
+    use_lyona_defaults()
     parser = argparse.ArgumentParser(description=__doc__)
     subs = parser.add_subparsers(dest="action", required=True)
```

## `Makefile`

`install-system`, after the shipped default TOMLs:

```diff
 	@echo "==> Installing shipped default config..."
 	for f in ${INSTALL_DEFAULTS}; do \
 		install -Dm644 "$$f" ${DESTDIR}${SHARE_DIR}/config/$$(basename "$$f"); \
 	done
+	@# lyona's lean Picom default, which dwm-settings-picom puts ahead of
+	@# /etc/xdg (#244).
+	install -Dm644 config/picom/picom.conf ${DESTDIR}${SHARE_DIR}/xdg/picom/picom.conf
```

`uninstall`:

```diff
 	for name in ${INSTALL_DEFAULT_NAMES}; do \
 		rm -f ${DESTDIR}${SHARE_DIR}/config/$$name; \
 	done
-	-rmdir ${DESTDIR}${SHARE_DIR}/config ${DESTDIR}${SHARE_DIR} 2>/dev/null
+	rm -f ${DESTDIR}${SHARE_DIR}/xdg/picom/picom.conf
+	-rmdir ${DESTDIR}${SHARE_DIR}/config ${DESTDIR}${SHARE_DIR}/xdg/picom \
+		${DESTDIR}${SHARE_DIR}/xdg ${DESTDIR}${SHARE_DIR} 2>/dev/null
```

To check at implementation: whether the release archive target and
`tests/test-installed-helper-paths.sh` list installed files explicitly; if so,
add `share/lyona/xdg/picom/picom.conf` there too.

## `tests/test-picom.py`

A new test case, before `if __name__ == "__main__":`. It uses the imports the
file already has.

```python
class LyonaDefaultTests(unittest.TestCase):
    """#244: lyona's lean default, ahead of the package's /etc/xdg file."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR"))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.script = self.root / "bin/dwm-settings-picom"
        self.env = patch.dict(
            os.environ,
            {"XDG_CONFIG_DIRS": "/etc/xdg", "XDG_CONFIG_HOME": str(self.root / "home"),
             "DWM_PICOM_CONFIG": ""},
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    def layout(self, directory):
        (self.root / directory / "picom").mkdir(parents=True)
        (self.root / directory / "picom/picom.conf").write_text("shadow = false;\n")
        return self.root / directory

    def test_installed_directory(self):
        expected = self.layout("share/lyona/xdg")
        self.assertEqual(picom.lyona_config_dir(self.script), expected)

    def test_checkout_directory(self):
        expected = self.layout("config")
        self.assertEqual(picom.lyona_config_dir(self.script), expected)

    def test_no_default_changes_nothing(self):
        self.assertIsNone(picom.lyona_config_dir(self.script))
        picom.use_lyona_defaults(self.script)
        self.assertEqual(os.environ["XDG_CONFIG_DIRS"], "/etc/xdg")

    def test_prepended_once_ahead_of_etc_xdg(self):
        directory = self.layout("share/lyona/xdg")
        picom.use_lyona_defaults(self.script)
        picom.use_lyona_defaults(self.script)
        self.assertEqual(os.environ["XDG_CONFIG_DIRS"], "%s:/etc/xdg" % directory)

    def test_user_configuration_still_wins(self):
        directory = self.layout("share/lyona/xdg")
        user = self.root / "home/picom/picom.conf"
        user.parent.mkdir(parents=True)
        user.write_text("shadow = true;\n")
        picom.use_lyona_defaults(self.script)
        with patch.object(picom, "processes", return_value=[]):
            self.assertEqual(picom.source_path(), user)
            user.unlink()
            self.assertEqual(picom.source_path(), directory / "picom/picom.conf")

    def test_shipped_default_is_lean(self):
        shipped = Path(__file__).resolve().parents[1] / "config/picom/picom.conf"
        config = picom.Configuration(shipped)
        self.assertIs(config.scalar("shadow", None), False)
        self.assertIs(config.scalar("fading", None), False)
        self.assertEqual(config.scalar("backend", "auto"), "auto")
```

## Found while implementing

**The helper edited lyona's default in place.** In a checkout the file is
writable, and `tests/test-picom-xvfb.py`'s first edit wrote its opacity into
`config/picom/picom.conf`. (An install's file is root-owned, so it would have
been copied, but the helper must not rely on that.) `safe_target()`, the gate
for every path the helper writes, now refuses anything under lyona's default
directory:

```diff
 def safe_target(path):
-    """Resolve owned dotfile symlinks; reject writable-by-others paths."""
+    """Resolve owned dotfile symlinks; reject writable-by-others paths, and
+    lyona's shipped default, which is only ever copied, never edited (#244)."""
+    default = lyona_config_dir()
+    if default is not None and default.resolve() in path.resolve().parents:
+        raise Error("lyona's default configuration is read-only; create a user configuration to edit it")
     current = path
```

So Settings treats it like `/etc/xdg/picom.conf`: not editable, and
**Create user configuration** (`copy-config`) copies it. `LyonaDefaultTests`
gains `test_shipped_default_is_never_edited`.

**`tests/test-picom-xvfb.py`**, which runs the checkout's helper, sees the
checkout's default:

- Its first case tested a first edit with no configuration at all. That no
  longer happens with lyona installed, so it now tests the real first run: the
  default is the source, not editable but copyable; `copy-config` creates the
  user's file, which is then edited; the shipped file is unchanged.
- Its vendor-shader case lists its vendor directory ahead of `config/` in
  `XDG_CONFIG_DIRS`. The helper keeps an order it is given (it prepends only
  when lyona's directory is not listed), so an administrator's order wins too.

**`check-install-manifest`** lists every installed file: it gains
`usr/share/lyona/xdg/picom/picom.conf`. The release archive is git's file list,
so it needs nothing.

## Validation

- `make check-picom` (the new case included) and `make check-picom-xvfb`.
- `make install-system DESTDIR=...` places `share/lyona/xdg/picom/picom.conf`,
  and `make uninstall DESTDIR=...` removes it and the empty directories.
- On Xvfb, from a staged install: `dwm-settings-picom start` uses the shipped
  file (`status` reports its path) and starts Picom with a `--backend`.
- In the VM, after an image install: `dwm-settings-picom status` reports the
  shipped file, `picom --diagnostics` shows no shadow or fading, and Settings >
  Appearance > Compositor still edits after "Create user configuration".
