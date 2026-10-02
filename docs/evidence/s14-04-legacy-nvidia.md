# S14-04: the legacy NVIDIA driver on real hardware

Sync Sprint 14 S14-04, issue `#204`. **Status: not yet run.** Nothing here is
verified on hardware. The legacy driver path (S14-02, S14-03) has been tested
only against a stub chroot (`tests/test-legacy-nvidia.sh`). A VM cannot stand in,
because no emulated GPU is an NVIDIA one.

Run each check on an install from the live medium, choosing the proprietary
driver at the prompt.

| Check | Pascal card (580xx) | Kepler card (470xx) |
| --- | --- | --- |
| The prompt offered the legacy driver, and the summary named it | not run | not run |
| With the CachyOS repository: the driver came from `cachyos/` (save the successful installation transaction output showing `cachyos/nvidia-580xx-dkms` or `cachyos/nvidia-470xx-dkms` and completion) | not run | not run |
| Without it (repository setup failed or blocked): the AUR build finished, and the closing message said to update with `yay` | not run | not run |
| The driver is in use: `nvidia-smi` runs, and `lsmod` lists `nvidia`, not `nouveau` | not run | not run |
| The session reaches the desktop, with Picom on | not run | not run |
| After a kernel update, DKMS rebuilt the module and the desktop still starts | not run | not run |

Record, for each machine:
- the card and its device ID (`lspci -nn -d 10de:`);
- the medium's build;
- whether the CachyOS repository was in use;
- anything that went wrong.

Until this is filled in, the docs describe the legacy path as untested on
hardware (SPEC.md section 9.4).
