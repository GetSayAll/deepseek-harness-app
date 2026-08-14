# Agent Note: macOS 主窗口隐藏标题栏

Status: implemented

[中文](2026-08-14-macos-immersive-main-window.zh.md) | English

## Problem

主窗口默认标题栏与页面 toolbar 叠加成一条明显的白色横带，内容区域没有延伸到窗口顶部，偏离既有沉浸式页面设计。

## Decision

主窗口使用 SwiftUI 的 `hiddenTitleBar` window style，使页面内容占据标题栏区域。页面不再声明系统 toolbar；连接异常时继续使用主内容中的“重新连接”按钮，常规重连保留在菜单命令中。

## Alternatives considered

**仅隐藏 toolbar。** 被拒绝，因为默认 titlebar 仍会保留顶部白色区域。

**使用 AppKit 自定义 titlebar。** 被拒绝，因为 SwiftUI 原生窗口样式已能满足需求，不需要额外的窗口桥接代码。

## Consequences

主页面不再显示大面积系统白色 chrome，窗口控制按钮仍由系统提供。重连按钮不再占据整条顶部区域；异常状态下的页面内入口和菜单快捷键保持不变。

## Verification

`swift build --package-path apps/macos` 与 `swift test --package-path apps/macos` 均通过。
