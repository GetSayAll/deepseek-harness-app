# Agent Note: macOS V1 Deep Ocean Workbench

Status: implemented

English | [中文](2026-08-14-macos-v1-deep-ocean-workbench.zh.md)

## Problem

The native macOS client exposes the Harness session and interaction protocol, but independent SwiftUI screens would let column behavior, composer takeovers, status colors, and controls diverge as native protocol coverage grows.

## Decision

DS Harness macOS `0.1.1` uses the V1 “Deep Ocean Workbench” design in [the macOS design reference](../../../../apps/macos/DESIGN.md). SwiftUI owns the main and settings scenes, three-column layout, navigation, conversation timeline, composer, interaction takeovers, tool details, and responsive behavior. AppKit remains limited to foreground activation, application lifecycle, the application icon, and the existing native directory picker.

The main window uses a light sidebar, a centered conversation column, and an optional tool-details column. Stored sidebar and details widths survive relaunch. Width pressure closes the details column first and changes the sidebar to a `56 pt` icon rail below `1024 pt`. Tool selection opens the details column at widths that retain the required center content width.

Ordinary input, approvals, and structured questions share one stable composer seat. The ordinary composer remains mounted while an interaction owns the seat, so its draft survives the takeover. Approval and question cards use the same maximum width and status language as the composer.

Settings use a separate native window with a fixed navigation column. The model page writes the DeepSeek API key through `credentials.set`, reads status through `credentials.describe`, and never receives the stored value. The packaged application includes its Node runtime and Host sidecar and does not open a localhost server.

The current native protocol supplies conversation messages, tool presentation data, approvals, and structured questions. The client does not invent trajectory, plan review, goal, background-task, preset, plugin, or subagent data before corresponding protocol methods exist.

## Alternatives considered

**Embed the Web client in a WebView.** This would reproduce the browser UI faster, but it would give up native window, menu, focus, accessibility, and desktop-control behavior and would mix executable Web UI with the semantic native protocol.

**Keep the minimal SwiftUI screens and style each feature locally.** This avoids shared layout components, but navigation, status, cards, and interaction patterns would diverge as protocol coverage grows.

**Use the high-contrast V2 dark sidebar.** The stronger color split reduces the calm reading surface and does not match the approved visual direction. V1's light sidebar and restrained blue-cyan emphasis remain the baseline.

## Consequences

The native client gains a stable desktop information architecture without adding WebView or presentation RPC methods. New protocol-backed features can reuse the existing sidebar, header, composer seat, details column, settings navigation, and design tokens.

The first release intentionally trails the Web client where the native protocol does not expose structured data. The light theme is the `0.1.1` acceptance target; dark appearance remains basic system-derived behavior.

Swift and Host tests cover credential status, write-only credential transport, protocol handshake, interaction decoding, and tool folding. The self-contained package smoke runs the bundled sidecar with the bundled Node runtime. Rendered visual comparison remains required before release and is recorded in [the design QA report](../../../../apps/macos/design-qa.md).
