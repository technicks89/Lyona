# Security Policy

## Supported Versions

Security fixes are developed on `main` and included in the next release. The
latest published release is the supported stable line. Older releases may be
asked to upgrade before receiving a fix.

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability. Email
`namato@technicks89.com` with the subject `lyona security report`.

Include affected versions or commits, reproduction steps, impact, relevant
logs, and any proposed mitigation. Do not include credentials, private keys,
tokens, or unrelated personal data.

The maintainer will assess severity and scope, then coordinate a fix and
disclosure when the report is confirmed. Please allow a reasonable remediation
window before public disclosure.

## Security Boundaries

The installer and helpers must preserve the privilege and configuration rules
in `SPEC.md`: package and system installation are explicit, user configuration
is preserved, downloaded artifacts are verified where checksums are available,
and privileged repair actions remain allowlisted and bounded.

## Hardening Notes

- **2026-09-06** — closed a read-only security audit of `scripts/`, `config/`,
  `install.sh`, and `config.mk` (see `CHANGELOG.md`'s "Security" section;
  its planning document, `docs/SYNC-P11-SECURITY-HARDENING.md`, was removed
  once implemented): removed the last
  unverified `curl | sudo sh` and unpinned-clone-then-root-install paths in
  the installer (`install-mybash`'s Starship/fzf/zoxide fallbacks,
  `install.sh`'s `yay-bin` bootstrap), pinned the CachyOS signing key's
  fingerprint before it is locally signed, wired `xscreensaver-setup.sh`
  into `dwm-lock`'s real locker chain so it actually locks, added standard
  compiler hardening flags to the `dwm` build, closed a `.desktop`-key
  injection path in `webapp-create`, and added a dedicated polkit action for
  `dwm-settings-display`'s `pkexec` call.
