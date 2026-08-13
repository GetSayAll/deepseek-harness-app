# Agent Note: macOS V1 Deep Ocean Workbench

Status: proposed

English | [中文](2026-08-14-macos-v1-deep-ocean-workbench.zh.md)

## Problem

The native macOS client exposes the Harness session and interaction protocol, but its current SwiftUI views do not yet provide the Web client's workspace, conversation, trajectory, details, settings, goal, and subagent information architecture at desktop density. Implementing each screen independently would create inconsistent column behavior, composer takeovers, status colors, and controls.

## Proposal

DS Harness macOS `0.1.1` uses the V1 “Deep Ocean Workbench” design in [the macOS design reference](../../../../apps/macos/DESIGN.md). The client retains the Web client's three-column hierarchy and control locations while implementing native windows, menus, popovers, sheets, keyboard behavior, and accessibility with SwiftUI and narrow AppKit bridges.

The implementation treats the composer as one stable seat shared by ordinary input, approval, structured questions, plan review, and subagent read-only states. Tool and trajectory inspection use the persistent right column. Settings use a separate native window, and workspace selection uses an attached sheet.

The light theme is the `0.1.1` visual baseline. A dark-theme implementation may remain system-derived, but it does not change the component hierarchy or delay the light-theme acceptance path.

## Alternatives considered

**Embed the Web client in a WebView.** This would reproduce the current browser UI faster, but it would give up native window, menu, focus, accessibility, and desktop-control behavior and would mix the Web executable UI with the semantic native protocol.

**Keep the current minimal SwiftUI screens and style each feature locally.** This avoids a shared design pass, but it would let navigation, status, card, and interaction patterns diverge as protocol coverage grows.

**Use the high-contrast V2 dark sidebar.** The stronger color split reduced the calm reading surface and did not match the approved visual direction. V1's light material sidebar and restrained blue-cyan emphasis remain the baseline.

## Acceptance criteria

- The main window preserves sidebar, center, and details widths and follows the concession order documented in the design reference.
- Empty, active conversation, tool details, trajectory, approval, questions, plan review, goal/background task, subagent, settings, and workspace-selection states use the shared V1 component language.
- Composer takeovers preserve the ordinary draft and occupy the same layout seat.
- The `0.1.1` light theme meets the documented color, typography, keyboard, reduced-motion, and accessibility requirements.
- The native carrier continues to transport semantics only; plugins do not inject Swift views, JavaScript, or new presentation RPC methods.

## Risks

Generated mockups contain illustrative copy and geometry that cannot be treated as pixel-exact source. The written design reference owns dimensions, behavior, and precedence when a mockup conflicts with runtime data or native control behavior.

Matching the Web client's information density may require targeted AppKit interop for split widths, focus, or text editing. Broad AppKit ownership would increase lifecycle complexity, so SwiftUI remains the default implementation surface.
