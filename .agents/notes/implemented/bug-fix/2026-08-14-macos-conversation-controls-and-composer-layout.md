# Agent Note: macOS conversation controls expose real state

Status: implemented

English | [中文](2026-08-14-macos-conversation-controls-and-composer-layout.zh.md)

## Problem

The macOS conversation header and composer presented a chevron, a trace tab, and an agent-preset chip as interactive affordances without actions. User messages combined a leading avatar with a trailing body, separating one message across the full conversation width. The composer accepted a flexible line count inside a frame that expanded to its maximum proposed height, so an empty draft consumed excessive space and users had no direct way to resize it.

## Decision

The title is plain text without a disclosure affordance. The conversation header owns a real dialogue/trace selection: dialogue renders the complete conversation, while trace renders the existing tool cards and an empty state before any tool runs. Both labels are plain-style buttons with the selected underline.

The macOS client reads `agentPreset.list`, displays the selected session preset in a menu, and applies `agentPreset.select` only while the session is blank. A started session still opens the menu, but its choices are disabled and the menu states that the preset is locked. The client uses the Host's existing roster and selection methods; it adds no macOS-specific preset source or protocol method.

User messages render the name, bubble, and avatar as one trailing group. Assistant messages retain the leading avatar and full-width body.

The composer has a persisted height with a 116-point default and a 104-to-300-point range. A top drag handle changes that height while the composer remains anchored at the bottom. The send action remains disabled for an empty trimmed draft and continues to use the existing send/cancel path.

## Alternatives considered

**Keep the placeholder controls and add help text.** Rejected: a visible tab, disclosure chevron, or picker chip communicates an available action; explanatory help does not repair a dead hit target.

**Add a separate trace protocol and model.** Rejected: the client already folds tool calls and results into `ToolCard` values, which are the complete data needed for this trace view.

**Replace the SwiftUI text field with an AppKit text view.** Rejected: the defect is the surrounding frame proposal, not missing text-system behavior. An explicit SwiftUI height and drag gesture preserve the existing draft and submit path.

## Consequences

The macOS connection sequence now requires the bundled Host's existing `agentPreset.list` method alongside workspace, session, and credential discovery. Preset changes update the selected session summary immediately after the Host accepts them.

The trace tab is a tool-focused projection of the same conversation, not a second event store. Selecting a tool there continues to open the existing details panel. Composer height persists across launches under the app's preferences and remains bounded so it cannot cover the conversation or collapse the controls.

`swift test --package-path apps/macos` covers the complete macOS package and real sidecar handshake. A foreground app pass verifies the compact default composer and both drag directions; the development bundle requires an ad-hoc signature after its existing run script mutates the binary.
