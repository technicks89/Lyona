# ARM5-01: the release workflow for ARM images

ARM Sprint 5 item ARM5-01 (Lyona-ARM issue #18, then Lyona #489). Written
2026-11-12; the release run in Lyona, 2026-11-13, is under "The release run"
below. Per the amendment of
2026-10-27 (`docs/sprints/ARM64.md`, End state), this is the part that belongs
in Lyona-ARM: the workflow and `scripts/lyona-release`, checked with stubs. The
release run itself, and the acceptance (a pre-release with the x86_64, generic
aarch64 and Pi images, each checksummed and signed), happens in Lyona after the
merge.

## What changed

- `.github/workflows/build-iso.yml` is still one workflow with one run per
  release, so the x86_64 and aarch64 images come from the same commit, and the
  release is made only when every image built:
  - `build-iso` is unchanged (the x86_64 ISO, the version and tag check, the
    release archive check).
  - `build-aarch64-iso` and `build-rpi-image` run on `ubuntu-24.04-arm`, after
    `build-iso` (so a bad version fails before an hour of building), with a
    read-only token, no environment and no secret. Each builds the Arch Linux
    ARM container image (`scripts/ci-archlinuxarm-image.sh`, signature and
    checksum checked) and runs `scripts/ci-release-aarch64.sh iso|rpi` in it,
    privileged, with the checkout mounted.
  - `sign` attests the source archive and all three images, still the only job
    with the OIDC token and still running no repository code.
  - `release` needs all three builds and `sign`, and passes the aarch64 ISO and
    the Pi image to `scripts/lyona-release` with `--asset`, and
    `--architecture x86_64 --architecture aarch64`.
- `scripts/ci-release-aarch64.sh`: builds one image in the container. The ISO
  needs archiso 91, which Arch Linux ARM does not package, so it clones
  archiso and checks out the commit `v91` points at
  (`723da192226e1c9d5def9168f13332793c82a85e`), and refuses any other. It
  leaves one file in the output directory.
- `scripts/lyona-release`: `--asset PATH` (repeatable) uploads another image,
  checksummed in `SHA256SUMS` and, with `--bundle`, required to be signed;
  `--architecture ARCH` (repeatable, `x86_64` or `aarch64`) adds the empty
  asset `lyona-VERSION-architecture-ARCH`, unsigned and not in `SHA256SUMS`.
  `lyona-update` reads those markers (#53, `docs/src/updating.md`).
- Names, as `scripts/build-lyona-arch-iso.sh` and `scripts/build-lyona-rpi-image.sh`
  already make them: `lyona-VERSION-x86_64.iso`, `lyona-VERSION-aarch64.iso`,
  `lyona-VERSION-rpi-aarch64.img.xz`.

## Checks

- `tests/test-release-helper.sh`: the extra images are published, checksummed
  and checked against the bundle (a bundle that leaves out the Pi image is
  refused with nothing uploaded); the markers are empty, published, and not in
  `SHA256SUMS`; a missing image and an unknown architecture are refused; no
  `--architecture` makes no marker.
- `tests/test-release-workflows.sh` (needs PyYAML): the six jobs; the aarch64
  jobs run on the arm64 runner after `build-iso` with a read-only token, no
  environment and no secret; `sign` and `release` need every build; no job or
  step can be skipped or fail silently; the sign step's subjects include each
  image; the release step's `lyona-release` arguments; the release step refuses
  to run when either aarch64 image is missing. ShellCheck on every step script.
- ShellCheck on `scripts/ci-release-aarch64.sh` and `scripts/lyona-release`:
  clean. `shfmt` was not available on this machine; the Full suite's format
  check covers it.

## The release run (in Lyona, 2026-11-13)

`v2026.11.0-beta.1` was published as a pre-release on 2026-11-13 at 23:21 UTC:
https://github.com/technicks89/Lyona/releases/tag/v2026.11.0-beta.1. The third
run made it; the first two found two faults, both fixed before it.

| Run | Commit | Result |
| --- | --- | --- |
| [43505662704](https://github.com/technicks89/Lyona/actions/runs/43505662704) | 3104f16 (#492) | x86_64 ISO built; both aarch64 jobs failed in seconds: `scripts/ci-release-aarch64.sh` ran `git config` before its `pacman` installed git (`git: command not found`). Nothing published. Fixed in #493, with `tests/test-ci-release-aarch64.sh` |
| [43518050560](https://github.com/technicks89/Lyona/actions/runs/43518050560) | 0b044a4 (#493) | All three images built and were signed; `release` made the tag, then GitHub refused the first architecture marker, an empty file (`HTTP 400: Bad Content-Length`). `gh` removed its draft release; the tag, with no release, was deleted by hand. Fixed in #494: each marker holds its architecture's name |
| [43523332090](https://github.com/technicks89/Lyona/actions/runs/43523332090) | db24732 (#494) | Published |

The published run, all on GitHub's hosted runners (runner image 20261103.629):

| Job | Runner and container | Time |
| --- | --- | --- |
| `build-iso` | `ubuntu-latest` (x86_64), `archlinux:base-devel@sha256:996c3a1d...` | 22:56 to 23:07 (11 min) |
| `build-aarch64-iso` | `ubuntu-24.04-arm`, Arch Linux ARM container from `ArchLinuxARM-aarch64-latest.tar.gz` (signed by `68B3537F39A313B3E574D06777193F152BDBE6A6` on 2026-08-05, SHA-256 `42a4eeaa...`), archiso at `v91` (`723da192`) | 23:08 to 23:17 (9 min) |
| `build-rpi-image` | `ubuntu-24.04-arm`, the same container | 23:08 to 23:18 (10 min) |
| `sign` | `ubuntu-latest` | 23:18 to 23:19 |
| `release` | `ubuntu-latest` | 23:19 to 23:21 |

The Pi image took 10 minutes here against 1 h 29 min on the Pi 4, and neither
aarch64 job ran short of disk; the questions this file left open are
answered.

The release's assets:

| Asset | Bytes | SHA-256 |
| --- | --- | --- |
| `lyona-2026.11.0-beta.1.tar.gz` | 6,595,883 | `20efa2ef96036a8047237078b8a24042dc3df5b338b15690821ee4899a84d088` |
| `lyona-2026.11.0-beta.1-x86_64.iso` | 1,339,965,440 | `9d939847deaa6a5fd7ad394789b70b6f2c5cf67a4163f5f3cb4566f90ae139c3` |
| `lyona-2026.11.0-beta.1-aarch64.iso` | 973,287,424 | `82baf4a2b9b8053526bf0f37abe791aac1a193576efd41554d85baa329cfde91` |
| `lyona-2026.11.0-beta.1-rpi-aarch64.img.xz` | 857,759,340 | `1d051caf5fb586787a7306c8c89c101eb5e72d72d6ad900cba0e4b0718c1cf00` |
| `lyona-2026.11.0-beta.1-SHA256SUMS` | 405 | the four lines above |
| `lyona-2026.11.0-beta.1.sigstore.json` | 11,238 | the signature |
| `lyona-2026.11.0-beta.1-architecture-x86_64` | 7 | holds `x86_64` |
| `lyona-2026.11.0-beta.1-architecture-aarch64` | 8 | holds `aarch64` |

Checked after publication, from the downloaded assets:

- `SHA256SUMS` lists the source archive and the three images; the source
  archive matches it.
- The signature bundle's subjects are the same four files with the same
  digests, and `cosign verify-blob-attestation` with the identity
  `lyona-update` uses (`build-iso.yml` on `main`, GitHub's OIDC issuer)
  prints "Verified OK" for the source archive.
- The tag points at db24732, and the archive's `.lyona-commit` names the same
  commit.
- Both markers are published, hold their architecture's name, and are not in
  `SHA256SUMS`.
- The release is a pre-release, not a draft.

## Not tested

- None of the three published images has been installed or booted. Each
  supported target's validation run used an image built from the ARM branch
  (`docs/evidence/arm2-05-generic-image.md`, `arm6-06-xps13-9345.md`,
  `arm3-06-raspberry-pi.md`); a run of this release's images on the VM, the
  XPS 13 9345 and the Pi 4 is still to do.
- The signature was verified for the source archive only, as `lyona-update`
  checks it; the images' digests were compared with the bundle's subjects, not
  verified with `cosign` one by one.
- `lyona-update` against this release, on either architecture: ARM5-02
  (#490).
