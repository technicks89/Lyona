# GRUB themes

Vendored boot-menu themes, installed to `/usr/share/grub/themes/` by
`make install-grub-theme` and selected by `scripts/lyona-grub-theme`.

## CyberRe

Taken verbatim from
[ChrisTitusTech/bootloader-themes](https://github.com/ChrisTitusTech/bootloader-themes/tree/main/themes/CyberRe)
(MIT, see `LICENSE`), originally by L. Henrique Lopes - HENK.

`preview.png` is not vendored: it is a 638 KiB screenshot that nothing reads
at boot. Every other file in the upstream theme is carried unchanged, so the
directory can be re-synced from upstream by copying over it.

The theme is vendored rather than downloaded so that a GRUB theme is available
during an offline install, and so the bytes that reach the boot menu are the
reviewed ones.
