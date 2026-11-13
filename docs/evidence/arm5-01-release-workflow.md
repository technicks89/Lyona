# ARM5-01: the release workflow for ARM images (the part before the merge)

ARM Sprint 5 item ARM5-01 (issue #18). Written 2026-11-12. Per the amendment of
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

## Not tested

- The aarch64 jobs have not run on a GitHub arm64 runner, and
  `scripts/ci-release-aarch64.sh` has not run at all. Open questions for the
  first run in Lyona: whether the runner's free disk space is enough for the Pi
  image (the Pi 4 needed about 15 GB free, and took 1 h 29 min; the job's
  timeout is 3 hours), and whether the privileged container can build the ISO
  and the Pi image on that runner (the earlier builds ran in a privileged
  container on the GB10 and natively on the Pi 4).
- No release has been made: the workflow's `release` job, the signing of the
  new files and `lyona-update` against a release with markers all wait for the
  run in Lyona (ARM5-01's second part, then ARM5-02).
- The release evidence of each target's validation run (item 3 of the plan)
  waits for the release.
