# Agent Note: macOS 打包前构建两个 TypeScript face

Status: implemented

[English](2026-08-14-macos-package-build-client-face.md) | 中文

## 问题

macOS 打包脚本在 `pnpm deploy` 前只构建了 Host TypeScript face。使用 client bundle 的包会在 Client face 生成 Node loader 入口，因此部署后的运行时虽然有包元数据和声明，却缺少 Typert registry、API gateway、session-log exporter 等包的 `lib/index.js`。

## 决策

`apps/macos/scripts/package_app.sh` 在构建原生应用和部署运行时前，使用相同的隔离 pnpm 参数依次运行 `build:lib:host` 与 `build:lib:client`。现有清理步骤会在部署后移除浏览器专用的 `lib/client.js`；Client face 负责提供 sidecar loader 所需的 Node 入口。

## 考虑过的替代方案

**在闭包 helper 中逐个复制缺失的包。** 否决：如果 Node 入口从未构建，这会复制不完整的包，并让打包流程依赖发布版本专用的 allowlist。

**把所有受影响的包改为在 Host face 生成 Node 入口。** 否决：共享 client-bundle preset 有意把这些包归入 Client face；改变阶段归属会修改整个仓库的构建拓扑。

## 后果

macOS 打包在部署前会执行两个 lib build face，耗时增加。运行时闭包仍由包 manifest 推导，同时浏览器 bundle 继续被排除在原生应用之外。
