# AGENTS.md — macOS application

These instructions apply only under `apps/macos/`.

## Development and release ownership

- Product development, Sparkle changes, and `Package.resolved` updates use ordinary pull requests into `master`. A `release/pre-vX.Y.Z` candidate changes only the package version, tracked Markdown release notes, and version-history page; never develop features or fixes there.
- The coordinating agent alone performs release mutations: creating or pushing candidate branches and tags, signing, notarizing, uploading assets, and changing GitHub Release state. Subagents research, plan, implement, test, and report results without performing those mutations.
- Use an isolated worktree based on current `origin/master`. The candidate's single release commit is the authority for shipped capability; dirty or uncommitted work outside that commit must never be described as released.
- Never rebase or force-push a candidate branch. Follow [RELEASING.md](RELEASING.md) for its exact provenance, pull-request, artifact, and promotion rules.

## Release intent and available lane

- An unqualified request to “release” means a pre-release candidate. A stable release requires an explicit exact version such as `v0.1.2`.
- The available lane is the Apple silicon direct-download and Sparkle lane. It signs and notarizes the app, emits a DMG, DMG checksum, Sparkle ZIP, signed appcast, and candidate provenance record, and serves stable and preview update feeds from GitHub Releases.
- Intel or universal binaries, PKG distribution, CDN delivery, and automated branch, tag, or promotion guards are not implemented and must not be represented as available.
