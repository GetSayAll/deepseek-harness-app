# Agent Note: macOS Sparkle 更新通道

Status: implemented

[English](2026-08-14-macos-sparkle-update-channels.md) | 中文

## Problem

原生 macOS 应用要求用户自行发现 GitHub Release、下载新的 DMG 并手工替换应用。单一正式版 feed 可以让普通用户保持更新，但无法让愿意尝鲜的用户接收预览候选版本；独立的更新代码路径还会让签名、发布说明和安装行为逐渐分化。

## Decision

DS Harness 使用一个长生命周期的 Sparkle 2 更新控制器。已打包应用每天检查一次 GitHub 正式版 appcast，发现更新后由用户确认下载和安装。“检查更新…”可从应用菜单、关于窗口和更新设置页打开。

正式版 feed 是 `https://github.com/GetSayAll/deepseek-harness-app/releases/latest/download/appcast.xml`。“接收预览版更新”偏好会持久化且默认关闭。开启后，应用通过 Releases API 解析带有 `appcast.xml` 的最新非草稿 GitHub Release，并把该 URL 交给同一个更新控制器。预览版查询失败时会回退正式版 feed，不会停用更新。

公证发布 lane 会在 DMG 与校验文件之外生成一个 Apple Silicon 更新 ZIP 和一个签名 appcast。在 Apple 签名前，本地无 Keychain helper 会按照锁定 Sparkle 2.9.5 的受支持 32-byte／96-byte 密钥规则取得发布公钥，并要求该值同时匹配传入密钥和最终应用的 `SUPublicEDKey`。每个 appcast enclosure 都使用不可变的 release tag URL。发布命令会嵌入 `RELEASE_NOTES_FILE` 指定的 Markdown，因此 Sparkle 更新窗口会在安装前显示用户可见改动。feed 和压缩包由 GitHub 直接提供；本实现不增加 CDN 或代理路由。

更新设置页显示当前版本与所选通道，负责预览版偏好，并链接产品官网的版本历史。官网只列出下载资产仍可获取的版本。

## Alternatives considered

**分别实现正式版与预览版更新器。** 这种方式会重复检查、展示、下载和安装行为。通过 delegate 为同一个更新器选择 feed，可以让两个通道使用完全相同的签名验证和用户流程。

**发布可变的预览版 appcast URL。** 第二个固定 feed 端点需要额外托管或同步机制。解析最新符合条件的 GitHub Release，可以在不引入暂缓 CDN 层的情况下发现预览版。

**静默安装更新。** 这种方式减少交互，但会在没有明确选择时改变正在运行的应用。每日检查保持自动，下载和安装仍需用户确认。

**自定义更新窗口。** 自定义 driver 可以匹配应用卡片样式，但会重复 Sparkle 的发布说明、进度、权限和重启行为。更新展示继续使用 Sparkle 标准 user driver。

## Consequences

正式版用户只会接收已晋升版本，预览版用户则可以选择接收候选版本，无需更换应用或重新安装 DMG。两个通道使用相同的签名压缩包格式、嵌入式发布说明和安装行为。预览版发现依赖 GitHub Releases API；请求失败时会降级到正式版 feed。

每个已发布更新都需要大于所有公开非草稿应用中最大值的 `CFBundleVersion`、受限存储的 Ed25519 私钥、应用 bundle 中经过验证的匹配公钥、发布说明 Markdown，以及完整的 DMG／校验文件／ZIP／appcast 资产矩阵。Intel、通用二进制、PKG 分发、CDN 交付和自动发布策略执行仍不属于已实现 lane。
