# DS Harness for macOS

English | [中文](README.zh.md)

`apps/macos` builds DS Harness, the native macOS client for DeepSeek Harness. SwiftUI owns scenes, navigation, and application state; narrow AppKit hooks provide foreground activation and desktop-only controls. The app starts the real Harness profile as a Node sidecar and communicates over versioned NDJSON on stdio. It does not open a localhost port. Users configure the DeepSeek API key in the native Settings window; the value travels write-only through the existing credentials API into the owner-only Harness credential store, and the UI reads back status only. The native About window links to the DS Harness website with the `from=mac` attribution parameter.

The first client slice lists workspaces and sessions, creates sessions, reads visible conversation history, renders basic Markdown, sends prompts, streams assistant text, and cancels active generation. It also renders tool activity, answers approval requests, and presents structured user questions in the composer. Plugin-injected context and model reasoning remain in the Harness log but are not rendered as user-visible chat messages.

## Development

Requirements are macOS 14 or later, Swift 6.2 or later, Node matching the repository engine, and installed pnpm dependencies.

```sh
pnpm --filter @deepseek-ai/dsh-macos run generate
pnpm --filter @deepseek-ai/dsh-macos run test:host
cd apps/macos && swift test
./script/build_and_run.sh --verify
SPARKLE_PUBLIC_ED_KEY='<public-key>' ./script/build_and_run.sh --package
```

The normal run modes stage `dist/DS Harness.app` and launch it as a foreground development application. `DSH_MACOS_REPOSITORY_ROOT` and `DSH_NODE_PATH` select the source sidecar and development Node executable only when the repository override is set. Development bundles omit Sparkle feed metadata, so update controls remain disabled while source-side debugging continues to work without release credentials.

The package mode builds a release Swift executable and compiled sidecar, embeds Sparkle, deploys copied production dependencies, completes missing internal workspace dependencies from each package's publish-file list, removes browser entries disabled by the native overlay, verifies the official Node archive checksum, and writes a self-contained runtime under `Contents/Resources/runtime`. Copy deployment keeps the application independent from later workspace builds. Its smoke test runs the packaged sidecar from a temporary directory, and packaging rejects repository paths, browser entries, or symbolic links outside Sparkle.framework. A packaged app does not search for a repository or system Node installation.

## Distribution

The arm64 release bundle is `DS Harness.app`, with bundle identifier `app.sayall.ds-app`. `Resources/AppIcon.png` is the 1024×1024 icon master. `scripts/sign_and_package.sh` signs Sparkle, native addons, the Node runtime, and the containing application from the inside out with Developer ID and Hardened Runtime. Node receives only the JIT, unsigned executable memory, and library-validation exceptions required by V8 and native addons; the release rejects the debug entitlement. The notarized lane staples and validates the application and `DS-Harness-<version>-arm64.dmg`, writes its SHA-256 file, and generates a signed Sparkle ZIP and appcast with embedded Markdown release notes.

The application checks the stable GitHub appcast once per day and asks before downloading or installing an update. **Check for Updates…** is available from the application menu, About window, and **Settings → Updates**. **Receive preview updates** is off by default; when enabled, automatic and manual checks resolve the newest non-draft GitHub Release that carries `appcast.xml`. Failure to resolve that feed falls back to the stable appcast. Release delivery uses GitHub directly; CDN handling is not part of this lane.

The current notarized release is [DS Harness 0.1.1](https://github.com/GetSayAll/deepseek-harness-app/releases/tag/v0.1.1) for Apple Silicon on macOS 14 or later. The [latest DMG link](https://github.com/GetSayAll/deepseek-harness-app/releases/latest/download/DS-Harness-0.1.1-arm64.dmg) resolves through the latest GitHub Release.

## Native and Web clients

Both clients use the same Harness workspace, session, conversation, tool, approval, and structured-question semantics. The native client packages Node and Host inside the application, carries RPC and events over stdio, stores the DeepSeek credential through the write-only credentials API, and provides macOS windows, menus, shortcuts, directory selection, accessibility behavior, Dock badges, and system notifications without a browser or localhost server. Notifications cover completed turns, approval requests, and structured questions, contain no conversation content, and open the corresponding session when selected. The application requests notification authorization only when the first eligible reminder is ready; it does not add camera, microphone, screen-recording, Accessibility, or Automation entitlements.

The Web client remains the complete product surface. Native `0.1.1` does not yet render trajectory inspection, plan review, goals and background tasks, preset and plugin management, model catalogs, or subagent navigation because the native protocol does not expose their structured data. It also targets Apple Silicon and the approved light appearance, while the Web client covers browser platforms and its existing appearance modes. Unknown tool presentations remain usable through the native generic tool card, but Web-specific executable UI cannot cross the native plugin protocol.

## ROI-ordered roadmap

1. **Protocol-backed workbench parity.** Add structured native methods and events for trajectory, plan review, goals and background tasks, and read-only subagent status; render them in the existing composer seat and details column. This unlocks the largest share of long-running agent work without changing the V1 information architecture.
2. **In-app composition.** Expose presets, plugins, default model, and model catalog through the native protocol and settings. This removes configuration-file work for the common setup path.
3. **Release diagnostics.** Add privacy-preserving crash diagnostics and release-health signals without expanding the application's sensitive permissions.
4. **Tool and artifact depth.** Add dedicated diff, location, artifact, search, and long-terminal renderers while retaining the generic fallback for third-party plugins.
5. **Platform reach and appearance.** Evaluate a universal binary and complete dark/high-contrast visual QA after core workflow parity, because these expand reach but unlock less day-one task value than missing workbench operations.

## Native client protocol

`Protocol/native-client-protocol.json` owns the process-carrier version and generated Swift facts. Version 0 provides protocol negotiation, unary Host RPC, client responses to answerable server requests, and the standard mux and Host event streams. Unary frames retain `ClientRequest` and `ServerResponse`; stream frames retain `ServerRequest`; response frames retain `ClientResponse`. The native carrier only replaces HTTP with correlated NDJSON frames.

The native plugin protocol is semantic rather than executable UI injection. Harness presenters attach an optional `ToolEventView` to tool call and result events. Swift owns the renderers for supported cards, while missing or unknown presentations use a generic tool card. Plugins cannot inject Swift views, JavaScript, or additional RPC methods into the application.
