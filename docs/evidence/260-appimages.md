# #260: AppImages, checked with real files

Issue `#260`. Design: `docs/plans/260/README.md`.

## The AppImages (2026-10-08)

Two builds of `appimagetool` from the AppImage project's GitHub releases, one
per runtime:

| File | Source | Runtime | SHA-256 |
| --- | --- | --- | --- |
| `classic-appimagetool.AppImage` | AppImageKit release 12 | Classic type 2, dynamically linked, needs `libfuse.so.2` | `d918b4df547b388ef253f3c9e7f6529ca81a885395c31f619d9aaf7030499a13` |
| `static-appimagetool.AppImage` | appimagetool `continuous` (build 313, 2026-10-04) | Static type-2 runtime | `95cbe7cce9717fce90c484e34052ee7c7f1d7635b33c12525b4776826a7d29b6` |

## On the development machine: integration only, nothing run

`lyona-appimage open` for each, with a scratch `HOME` and `setsid` and
`notify-send` replaced by stubs that only log, so neither file ran:

- Both were moved to `~/Applications`, made executable, and got an entry:
  `Name=appimagetool`, `Comment=Tool to generate AppImages from AppDirs`,
  `Categories=Development;`, `Terminal=true` (the tool's own setting).
- Icons: the classic one's is an SVG, the static one's a PNG.
- Each was announced once and started once (the stub's log).
- Both are named "appimagetool", which showed that `remove appimagetool` would
  have taken both. It now refuses a shared name and lists the file names; the
  test covers it.

## In the VM: a real lyona install

The QEMU/KVM VM from the install-speed runs (image install, before this change),
with this branch's `lyona-appimage` and its desktop entry copied in
(`/usr/local`).

Before (no `fuse2`, as every lyona install so far), each run from a scratch copy:

```
== classic without fuse2:
dlopen(): error loading libfuse.so.2
AppImages require FUSE to run.
exit 1
== static without fuse2:
appimagetool, continuous build (git version 854e19e), build 313 built on 2026-10-04 14:58:08 UTC
exit 0
```

After `pacman -S fuse2 squashfs-tools` (`fuse2 2.9.9-6`, `squashfs-tools
4.7.5-1.1`), with `lyona-appimage.desktop` the default for
`application/vnd.appimage` (it already was, as the only registered handler),
both opened the way Thunar opens a file, `gio open ~/Downloads/NAME.AppImage`, in
the user's session:

- Both were moved from `~/Downloads` to `~/Applications` and made executable,
  and `lyona-appimage list` showed both.
- Both started from `~/Applications`, the classic one too:
  `appimagetool, continuous build (commit effcebc), build 2084` and
  `appimagetool, continuous build (git version 854e19e), build 313`.
- The lyona launcher, searched for "appimagetool", listed both with the icon,
  description and "Dev" category from inside the files.

## Not tested

- The image installer's own run of the new `install.sh` step (the VM's install
  predates it); the step is covered by the installer tests.
- `--with-gearlever` against Flathub for real, and an existing install with Gear
  Lever installed (both covered by stub tests).
- A type-1 AppImage (refused by design) and a non-x86 one.
- Opening from Thunar by double-click; `gio open` takes the same MIME route.
