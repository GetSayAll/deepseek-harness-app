# Agent Note: Native macOS process carrier

Status: implemented

English | [中文](2026-08-13-native-macos-process-carrier.zh.md)

## Problem

The native macOS application must reuse the real Harness plugin tree, persistence, and API behavior without embedding the browser UI or exposing a localhost server. It also releases independently from the Host packages, so it needs an explicit compatibility check that the co-released Web client does not require.

## Decision

`apps/macos` is a SwiftPM application whose main interface is SwiftUI. AppKit remains a narrow bridge for foreground activation and desktop controls SwiftUI cannot express precisely.

The application launches a Node sidecar from the same distribution. The sidecar boots the `web` profile through `runProfile`, then applies `Host/native.overlay.yml`: Host-plane storage, workspaces, sessions, presets, and `ApiProxy` remain mounted, while the web server, browser carrier, browser runtime, and browser UI rows are disabled. A native directory picker provider replaces the adaptive Web picker. No TCP port is opened.

`@deepseek-ai/dsh/profile-boot` is the stable package entry for native carriers. The macOS build compiles the sidecar, deploys its production dependency tree, then closes missing internal `dependencies` and required peer dependencies by copying only each workspace package's declared publish files. The application embeds that tree and a checksum-verified official Node distribution under `Contents/Resources/runtime`; packaged startup does not fall back to a repository path, `tsx`, or a system Node installation.

The shipped application is `DS Harness.app`, identified as `app.sayall.ds-app`. Its release lane targets arm64, uses the checked-in 1024×1024 icon master, and signs native addons, Node, and the containing application from the inside out with Developer ID and Hardened Runtime. Node keeps the minimum V8 and native-addon entitlements but not `get-task-allow`. Apple notarization and stapling apply to both the application and final DMG.

The physical carrier is newline-delimited JSON over the child process's stdin and stdout. Stdout carries protocol frames only; diagnostics use stderr. Each request carries a client-generated id so the Swift actor can correlate concurrent continuations. Swift buffers pipe data into complete newline-delimited frames before decoding. Graceful shutdown is an acknowledged protocol frame followed by disposal of the Cordis tree, and the application waits for the child process to exit before releasing its pipe state.

The native carrier starts at `protocolVersion` 0. Its manifest generates the Swift version and first typed Host response. Startup must negotiate the same version before any business request. Unary calls retain the standard `ClientRequest` and `ServerResponse` forms by passing through `toFetchHandler`; mux and Host streams retain the standard `ServerRequest` form; approval and user-question answers retain `ClientResponse` and the stable server-request `rpcId`. The process carrier does not define a second business API.

Plugins contribute tool presentation through the Host-computed `ToolEventView`. The contribution selects a versioned semantic card and its data; Swift owns every renderer. Missing and unknown views fall back to a generic card. Plugins cannot load Swift views, execute JavaScript in the interface, or extend the native RPC set.

## Alternatives considered

**Embed the existing Web UI in WKWebView.** This would ship sooner but preserves browser layout and interaction constraints, does not establish the requested native plugin surface, and makes native controls a growing set of exceptions around a web application.

**Rewrite the Harness backend in Swift.** This duplicates the plugin runtime, persistence, session semantics, and tool execution path. The duplicated implementations would drift while delivering no first-version user value.

**Run the existing localhost Web server.** A loopback port adds origin, port allocation, and trust concerns without helping an in-process desktop client. Stdio gives the application direct process ownership and a smaller attack surface.

**Expose arbitrary plugin-authored native views.** Loading Swift code or a general UI description from plugins would make compatibility and review unbounded. The native plugin protocol instead grows through versioned semantic contributions with application-owned renderers and generic fallbacks.

## Consequences

The first native application reuses production Host behavior and can evolve independently through an explicit carrier version. SwiftUI stays the source of truth, and future AppKit use remains localized.

The client lists workspaces and sessions, creates sessions, reads visible history, sends prompts, streams assistant text, cancels generation, renders tool events, and resolves approvals and user questions through unary calls, client responses, and mux or Host events. It renders only direct user messages and assistant text blocks as chat messages; plugin context and reasoning remain in the canonical log without appearing as ordinary chat content.

Development can select the source sidecar and Node through explicit environment overrides. Packaging runs the compiled sidecar outside the repository, rejects embedded repository paths and symbolic links, and pins the application version, identity, and icon in bundle metadata. The release process verifies signatures, entitlements, checksums, Gatekeeper acceptance, and packaged sidecar shutdown. The semantic card set can grow additively while generic fallback keeps older clients usable; a change to carrier framing or required capabilities needs a protocol-version decision.
