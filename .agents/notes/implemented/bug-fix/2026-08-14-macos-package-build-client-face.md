# Agent Note: Build both TypeScript faces before packaging the macOS runtime

Status: implemented

English | [中文](2026-08-14-macos-package-build-client-face.zh.md)

## Problem

The macOS package script built only the Host TypeScript face before `pnpm deploy`. Client-bundle packages emit their Node loader entry during the Client face, so the deployed runtime contained package metadata and declarations but no `lib/index.js` for packages such as the Typert registry, API gateway, and session-log exporter.

## Decision

`apps/macos/scripts/package_app.sh` runs `build:lib:host` and then `build:lib:client` with the same isolated pnpm settings before building the native app and deploying its runtime. The existing cleanup removes browser-only `lib/client.js` artifacts after deployment; the Client pass supplies the Node entries that the sidecar loader needs.

## Alternatives considered

**Copy individual missing packages in the closure helper.** Rejected: that would copy incomplete packages when their Node entries were never built and would make packaging depend on a release-specific allowlist.

**Change every affected package to emit its Node entry during the Host pass.** Rejected: the shared client-bundle preset intentionally owns those packages in the Client pass; changing phase placement would alter the repository-wide build topology.

## Consequences

macOS packaging performs both lib build faces and takes longer before deployment. The runtime closure remains derived from package manifests, while the browser bundles are still excluded from the native app.
