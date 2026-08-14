# Agent Note: macOS candidate promotion release

Status: implemented

English | [中文](2026-08-14-macos-candidate-promotion-release.zh.md)

## Problem

The macOS application has local scripts that assemble, sign, notarize, and checksum a DMG, but the repository did not define who may mutate release state or how a tested candidate becomes stable. An ambiguous release request could therefore trigger a stable publication, feature work could enter a release branch, a dirty worktree could contaminate provenance, or stable publication could rebuild bytes that users never tested.

The available scripts also do not implement every distribution mechanism associated with a production Mac application. Without an explicit limit, release notes or agent reports could claim Intel support, PKG distribution, CDN delivery, or automated release-policy enforcement that the repository does not provide.

## Decision

The [macOS release reference](../../../../apps/macos/RELEASING.md) governs only `apps/macos`. Product development reaches `master` through ordinary pull requests. Release preparation starts from the latest fetched `origin/master` in an isolated `release/pre-vX.Y.Z` worktree and contains exactly one non-merge release commit whose sole parent is that `master` commit. The pushed candidate branch is never rebased or force-pushed, and its commit is the authority for every capability claimed in the release.

The coordinating agent alone creates or pushes release branches and tags, signs and notarizes artifacts, uploads GitHub Release assets, and changes a release from pre-release to stable. Subagents research, plan, implement, test, and report evidence without mutating release state. An unqualified release request selects a pre-release candidate, while stable promotion requires an explicit exact `vX.Y.Z` target.

Before candidate creation, the coordinating agent downloads every non-draft arm64 DMG, including pre-releases and failed candidates, from its fixed-tag GitHub URL, mounts the application, and computes the greatest public `CFBundleVersion`. The new positive build must be greater than that value, so a failed public candidate's build cannot be reused. The public `v0.1.1` artifact establishes build `1`, so the planned `v0.1.2` build is `2`, but later releases repeat the artifact-derived check instead of relying on that recorded value.

The candidate pull request passes review and required checks but remains unmerged while artifacts are built. Its one release commit changes exactly the package version, a tracked Markdown release-note file, and the version-history page. Sparkle product changes and their `Package.resolved` update must already have reached `master` through an ordinary product pull request; candidate preparation only verifies that the lockfile is tracked and unchanged. The history article names the Markdown source, repeats its user-visible bullets, and uses a fixed-tag DMG URL, with an executable comparison rejecting drift.

The coordinating agent uses that one non-empty notes file and the committed version, build, tag, and Sparkle keys to build once with [`package_app.sh`](../../../../apps/macos/scripts/package_app.sh) and [`sign_and_package.sh`](../../../../apps/macos/scripts/sign_and_package.sh). Before any Apple signing, the local [`derive_sparkle_public_key.mjs`](../../../../apps/macos/scripts/derive_sparkle_public_key.mjs) helper derives the release public key according to the pinned Sparkle 2.9.5 rules for canonical base64 32-byte and 96-byte key files: it derives from a 32-byte seed or reads the public component from a 96-byte legacy key without accessing Keychain or logging key material. The release script then requires equality with both the supplied public key and the final application's `SUPublicEDKey`. It also requires the final `CFBundleVersion` to equal the selected build. Immediately before pre-release creation, `HEAD`, the remote branch, and the annotated `vX.Y.Z` tag identify the same commit, and that commit is not yet an ancestor of `master`.

The GitHub pre-release carries exactly five assets: the DMG, its SHA-256 file, the signed Sparkle ZIP, the fixed-tag signed appcast, and `candidate-provenance.json`. The provenance record stores the branch, `master` parent, tag commit, version, build, and size and SHA-256 for the four payloads; the annotated tag stores the provenance file's SHA-256. After public verification, the existing pull request merges only by merge commit or true fast-forward so the tagged candidate remains an ancestor of `master`. Stable promotion edits only the same GitHub Release state.

A failed public candidate remains a pre-release with its original tag and assets. Its version is never reused or repaired by replacing bytes or moving the tag. A later attempt fixes the product through `master` and uses a new exact version.

The supported lane is a Developer ID-signed, notarized Apple silicon app with a DMG, SHA-256 file, Sparkle ZIP, signed appcast, and direct GitHub delivery. Intel or universal binaries, PKG distribution, App Store delivery, CDN delivery, and automated branch, tag, artifact, or promotion guards are outside the implemented lane.

## Verification

The packaging scripts build the host and Swift release executable, embed and sign Sparkle, exercise the packaged sidecar, reject known bundle contamination, verify build and Sparkle key consistency before signing, verify signatures and Node entitlements, submit and staple the app and DMG, run Gatekeeper checks, write the checksum, and sign the update ZIP and appcast. Focused helper tests cover the 32-byte seed, 96-byte legacy key, invalid base64, and invalid decoded length without Keychain access. The release operator also derives the build floor from every public non-draft application, mechanically compares Markdown notes with the version-history article, runs the focused host and Swift tests, uses failing `lipo` and `file` assertions for both arm64 entry points, and requires a clean tracked `Package.resolved` before tagging.

After candidate upload and immediately before and after stable promotion, the operator repeats the same documented shell procedure. It requires the exact five asset names and count, pins the provenance file to the annotated tag, recomputes every payload size and SHA-256, checks the DMG checksum, requires the appcast's fixed-tag enclosure and release-page URLs, and repeats the Sparkle ZIP and appcast signature checks. Promotion does not invoke a build, signing, notarization, or upload command. Repository documentation checks verify the standing-order link, Agent Note format, Markdown links, and bilingual pairing; no automated release-policy guard is claimed.

## Alternatives considered

**Develop on the candidate branch.** This makes a release branch a second integration line and lets unreviewed product changes bypass the ordinary pull-request flow. Keeping candidate mutations release-only preserves `master` as the product integration branch.

**Rebuild for stable publication.** A second build can produce bytes different from the tested and publicly downloaded candidate. Promoting the existing GitHub Release state makes stable publication a metadata change over the exact candidate bytes.

**Replace a failed candidate under the same tag.** Reusing the version conceals which bytes earlier testers received and breaks the tag and checksum as immutable provenance. Consuming the failed version keeps every public candidate auditable.

**Document planned distribution lanes as release options.** Intel or universal builds, PKG distribution, CDN delivery, and automated guards require code or CI that is absent. Naming only the implemented direct-download and Sparkle arm64 lane prevents procedural prose from becoming a false product claim.

## Consequences

Stable users receive the complete five-file set that passed candidate validation, and the preserved commit, tag, provenance record, release notes, version-history entry, and checksums identify its source and bytes. An ambiguous request cannot silently produce a stable release, stale build numbers and mismatched Sparkle keys fail before signing, and dirty capability outside the candidate commit cannot be represented as shipped.

The process is intentionally manual. The coordinating agent is a release bottleneck, every failed public candidate consumes a version, and policy violations are caught by operator review rather than CI. The available product remains Apple silicon-only and uses GitHub Releases directly without a CDN.
