# Agent Note: macOS Sparkle update channels

Status: implemented

English | [中文](2026-08-14-macos-sparkle-update-channels.zh.md)

## Problem

The native macOS application required users to discover a GitHub Release, download another DMG, and replace the application manually. A single stable feed would keep ordinary users current but would not let willing users receive preview candidates, while separate update code paths could diverge in signing, release notes, and installation behavior.

## Decision

DS Harness uses one long-lived Sparkle 2 updater controller. Packaged applications check the stable GitHub appcast once per day and ask before downloading or installing an update. Manual checks are available from the application menu, About window, and the Updates settings page.

The stable feed is `https://github.com/GetSayAll/deepseek-harness-app/releases/latest/download/appcast.xml`. The persisted **Receive preview updates** preference is off by default. When enabled, the application resolves the newest non-draft GitHub Release carrying `appcast.xml` through the Releases API and gives that URL to the same updater controller. A failed preview lookup falls back to the stable feed instead of disabling updates.

The notarized release lane emits one Apple silicon update ZIP and one signed appcast beside the DMG and checksum. Before Apple signing, a local no-Keychain helper derives the release public key according to the pinned Sparkle 2.9.5 rules for supported 32-byte and 96-byte key files and requires that value to match both the supplied key and the final application's `SUPublicEDKey`. Every appcast enclosure uses its immutable release-tag URL. The release command embeds the Markdown file named by `RELEASE_NOTES_FILE`, so Sparkle's update window displays the user-visible changes before installation. GitHub serves feeds and archives directly; this implementation adds no CDN or proxy route.

The Updates settings page shows the current version and selected channel, owns the preview preference, and links to the product site's version history. The website lists only releases whose download assets remain available.

## Alternatives considered

**Use separate stable and preview updater implementations.** This would duplicate check, presentation, download, and installation behavior. One updater with delegate-selected feeds keeps signature validation and the user journey identical across channels.

**Publish a mutable preview appcast URL.** A second fixed feed endpoint would require another hosting or synchronization mechanism. Resolving the latest eligible GitHub Release provides preview discovery without introducing the deferred CDN layer.

**Install updates silently.** This reduces interaction but changes the running application without an explicit user choice. Daily checks remain automatic while download and installation require confirmation.

**Build a custom update window.** A custom driver could match the application's card styling, but it would duplicate Sparkle's release-note, progress, permission, and restart behavior. The standard Sparkle user driver remains the update presentation.

## Consequences

Stable users receive only promoted releases, while preview users can opt into candidates without changing applications or reinstalling from a DMG. Both channels use the same signed archive format, embedded release notes, and installer behavior. Preview discovery depends on the GitHub Releases API and degrades to the stable feed when that request fails.

Every published update requires a `CFBundleVersion` greater than the maximum read from all public non-draft applications, a restricted private Ed25519 key, the verified matching public key in the application bundle, release-note Markdown, and the complete DMG/checksum/ZIP/appcast asset matrix. Intel, universal binaries, PKG distribution, CDN delivery, and automated release-policy enforcement remain outside the implemented lane.
