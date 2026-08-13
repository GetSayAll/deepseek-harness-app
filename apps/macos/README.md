# DS Harness for macOS

English | [中文](README.zh.md)

`apps/macos` builds DS Harness, the native macOS client for DeepSeek Harness. SwiftUI owns scenes, navigation, and application state; narrow AppKit hooks provide foreground activation and desktop-only controls. The app starts the real Harness profile as a Node sidecar and communicates over versioned NDJSON on stdio. It does not open a localhost port. The native About window links to the DS Harness website with the `from=mac` attribution parameter.

The first client slice lists workspaces and sessions, creates sessions, reads visible conversation history, renders basic Markdown, sends prompts, streams assistant text, and cancels active generation. It also renders tool activity, answers approval requests, and presents structured user questions in the composer. Plugin-injected context and model reasoning remain in the Harness log but are not rendered as user-visible chat messages.

## Development

Requirements are macOS 14 or later, Swift 6.2 or later, Node matching the repository engine, and installed pnpm dependencies.

```sh
pnpm --filter @deepseek-ai/dsh-macos run generate
pnpm --filter @deepseek-ai/dsh-macos run test:host
cd apps/macos && swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --package
```

The normal run modes stage `dist/DS Harness.app` and launch it as a foreground development application. `DSH_MACOS_REPOSITORY_ROOT` and `DSH_NODE_PATH` select the source sidecar and development Node executable only when the repository override is set.

The package mode builds a release Swift executable and compiled sidecar, deploys production dependencies, completes missing internal workspace dependencies from each package's publish-file list, verifies the official Node archive checksum, and writes a self-contained runtime under `Contents/Resources/runtime`. Its smoke test runs the packaged sidecar from a temporary directory, and packaging rejects repository paths or symbolic links in the application. A packaged app does not search for a repository or system Node installation.

## Distribution

The arm64 release bundle is `DS Harness.app`, with bundle identifier `app.sayall.ds-app`. `Resources/AppIcon.png` is the 1024×1024 icon master. `scripts/sign_and_package.sh` signs native addons, the Node runtime, and the containing application from the inside out with Developer ID and Hardened Runtime. Node receives only the JIT, unsigned executable memory, and library-validation exceptions required by V8 and native addons; the release rejects the debug entitlement. The notarized lane staples and validates both the application and `DS-Harness-<version>-arm64.dmg`, then writes its SHA-256 file.

## Native client protocol

`Protocol/native-client-protocol.json` owns the process-carrier version and generated Swift facts. Version 0 provides protocol negotiation, unary Host RPC, client responses to answerable server requests, and the standard mux and Host event streams. Unary frames retain `ClientRequest` and `ServerResponse`; stream frames retain `ServerRequest`; response frames retain `ClientResponse`. The native carrier only replaces HTTP with correlated NDJSON frames.

The native plugin protocol is semantic rather than executable UI injection. Harness presenters attach an optional `ToolEventView` to tool call and result events. Swift owns the renderers for supported cards, while missing or unknown presentations use a generic tool card. Plugins cannot inject Swift views, JavaScript, or additional RPC methods into the application.
