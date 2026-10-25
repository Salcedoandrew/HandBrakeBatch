# Security Policy

## Supported versions

Only the latest release is supported with security fixes (currently `v1.3.0`).
Older releases, and the original
[taglia/handbrakebatch](https://github.com/taglia/handbrakebatch) project,
are covered by their own maintainers, not by this edition.

## Reporting a vulnerability

**Please do not open a public issue for a security vulnerability.**

Use GitHub's private vulnerability reporting for this repository:
**Security tab → Report a vulnerability**. That opens a private advisory
visible only to the maintainer.

If private reporting is unavailable, open a regular issue with no technical
details and ask the maintainer for a private channel.

Please include, where you can:

- What you found and where (file or feature, with steps to reproduce)
- The impact — for example, whether a file could be overwritten, a
  command injected, or a download subverted
- The version you tested (release tag or commit)

## What happens next

This is a single-maintainer project, so response is best-effort. The
maintainer will confirm the report, work on a fix, and publish it in a
release. Please hold off on public disclosure until a fix is released so
users have a chance to update.

## Notes on the bundled encoder

The app ships HandBrake's official, unmodified HandBrakeCLI build
(1.11.2). `build.sh` downloads it from HandBrake's GitHub release and
checks its SHA-256 before bundling it. A checksum mismatch, a download
from anywhere other than HandBrake's release, or anything that runs
commands built from untrusted input should be reported as a security
issue. The app itself never runs shell strings: HandBrakeCLI is always
invoked with an argument array.

## Please don't

- Test against anyone else's files or machines.
- Include a working exploit in a public issue or discussion.
