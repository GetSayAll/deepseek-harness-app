# Agent Note: macOS 候选晋升发布流程

Status: implemented

[English](2026-08-14-macos-candidate-promotion-release.md) | 中文

## 问题

macOS 应用已有在本机构建、签名、公证 DMG 并生成校验和的脚本，但仓库没有规定谁可以改变发布状态，也没有规定通过测试的候选版本如何成为稳定版。因此，含糊的发布请求可能触发稳定发布，功能开发可能进入发布分支，脏 worktree 可能污染来源记录，稳定发布也可能重新构建用户从未测试过的字节。

现有脚本也没有实现生产级 Mac 应用可能采用的全部分发机制。如果不明确限制，发布说明或 agent 报告可能声称仓库提供了实际不存在的 Intel 支持、PKG 分发、CDN 交付或自动发布策略门禁。

## 决策

[macOS 发布参考](../../../../apps/macos/RELEASING.md)只约束 `apps/macos`。产品开发通过普通 PR（Pull Request）进入 `master`。发布准备从最新 fetch 的 `origin/master` 创建隔离的 `release/pre-vX.Y.Z` worktree，只包含一个非 merge 发布 commit，且该 commit 的唯一父 commit 就是这个 `master` commit。已推送的候选分支不得 rebase 或 force-push，其 commit 是发布中所有能力声明的权威来源。

只有总管可以创建或推送发布分支与 tag、签名和公证产物、上传 GitHub Release 资产，以及把 pre-release 改为 stable。subagent 只研究、规划、实现、测试并回报证据，不改变发布状态。未限定的发布请求选择 pre-release 候选版本；stable 晋升必须明确给出精确的 `vX.Y.Z` 目标。

创建候选版本前，总管会从每个非草稿公开版本的固定 tag GitHub URL 下载 arm64 DMG，其中包括 pre-release 和失败候选版本，然后挂载应用并计算公开 `CFBundleVersion` 的最大值。新的正整数 build 必须大于该值，因此失败候选版本的公开 build 也不能复用。公开的 `v0.1.1` 产物确定其 build 为 `1`，所以计划中的 `v0.1.2` 使用 build `2`；后续版本仍重复从产物动态读取的检查，不依赖这个记录值。

候选 PR 通过 review 和必需检查，但构建产物时保持未 merge。其唯一发布 commit 恰好只修改 package 版本、已跟踪的 Markdown 发布说明和版本历史页面。Sparkle 产品改动及其 `Package.resolved` 更新必须先通过普通产品 PR 进入 `master`；候选准备只验证锁文件已跟踪且未改变。版本历史 article 会标明 Markdown 来源、重复其中面向用户的 bullet，并使用固定 tag 的 DMG URL；可执行比较会拒绝两处内容漂移。

总管使用同一个非空发布说明文件，以及已提交的版本、build、tag 和 Sparkle 密钥，通过 [`package_app.sh`](../../../../apps/macos/scripts/package_app.sh) 与 [`sign_and_package.sh`](../../../../apps/macos/scripts/sign_and_package.sh) 只构建一次。在任何 Apple 签名前，本地 [`derive_sparkle_public_key.mjs`](../../../../apps/macos/scripts/derive_sparkle_public_key.mjs) helper 会按照锁定 Sparkle 2.9.5 的规范 base64 32-byte／96-byte 密钥规则取得发布公钥：从 32-byte seed 派生，或者读取 96-byte 旧格式中的公钥部分，且不访问 Keychain、不记录密钥材料。发布脚本随后要求该值同时等于传入公钥和最终应用的 `SUPublicEDKey`。脚本还要求最终 `CFBundleVersion` 等于选定 build。创建 pre-release 前，`HEAD`、远端分支与附注 `vX.Y.Z` tag 标识同一个 commit，且该 commit 尚不是 `master` 的祖先。

GitHub pre-release 恰好携带五项资产：DMG、其 SHA-256 文件、已签名 Sparkle ZIP、使用固定 tag URL 的已签名 appcast，以及 `candidate-provenance.json`。provenance 记录保存分支、`master` 父 commit、tag commit、版本、build，以及四项 payload 的大小与 SHA-256；附注 tag 保存 provenance 文件的 SHA-256。公开验证通过后，既有 PR 只能通过 merge commit 或真正的 fast-forward 合入，使带 tag 的候选 commit 保持为 `master` 的祖先。stable 晋升只编辑同一个 GitHub Release 状态。

公开后失败的候选版本保留为 pre-release，并保留原始 tag 与资产。不得复用其版本，也不得通过替换字节或移动 tag 修复它。后续尝试通过 `master` 修复产品，并使用新的精确版本。

受支持的 lane 是经过 Developer ID 签名和公证的 Apple silicon 应用，以及 DMG、SHA-256 文件、Sparkle ZIP、签名 appcast 和 GitHub 直接交付。Intel 或通用二进制、PKG 分发、App Store 交付、CDN 交付，以及自动分支、tag、产物或晋升门禁都不在已实现 lane 内。

## 验证

打包脚本会构建 host 与 Swift release 可执行文件，嵌入并签名 Sparkle，运行已打包 sidecar，拒绝已知 bundle 污染，在签名前验证 build 与 Sparkle 密钥一致性，验证签名与 Node entitlement，提交并 staple 应用和 DMG，执行 Gatekeeper 检查，写出校验和，并签名更新 ZIP 与 appcast。聚焦 helper 测试覆盖 32-byte seed、96-byte 旧格式密钥、非法 base64 和非法解码长度，且不访问 Keychain。发布操作者还会从所有公开非草稿应用动态取得 build 下限，机械比较 Markdown 发布说明与版本历史 article，运行聚焦的 host 与 Swift 测试，通过会失败的 `lipo` 与 `file` 断言验证两个 arm64 入口，并在打 tag 前要求已跟踪的 `Package.resolved` 保持 clean。

候选上传后以及 stable 晋升前后，操作者都会重复同一套已记录的 shell 流程。该流程要求精确的五项资产名称与数量，把 provenance 文件固定到附注 tag，重新计算每项 payload 的大小与 SHA-256，核对 DMG 校验和，要求 appcast 使用固定 tag 的 enclosure 与发布页 URL，并重复 Sparkle ZIP 与 appcast 签名检查。晋升过程不调用构建、签名、公证或上传命令。仓库文档检查会验证常驻指令链接、Agent Note 格式、Markdown 链接和双语配对；流程不声称存在自动发布策略门禁。

## 考虑过的替代方案

**在候选分支上开发。** 这会让发布分支成为第二条集成线，并使未审查的产品改动绕过普通 PR 流程。候选改动仅限发布内容，可保持 `master` 为产品集成分支。

**为 stable 发布重新构建。** 第二次构建可能产生不同于已测试且已公开下载候选版本的字节。晋升现有 GitHub Release 状态，可让 stable 发布成为基于精确候选字节的元数据变更。

**在同一个 tag 下替换失败候选版本。** 复用版本会掩盖早期测试者收到的字节，并破坏 tag 与校验和作为不可变来源记录的作用。消耗失败版本可让每个公开候选版本保持可审计。

**把计划中的分发 lane 写成发布选项。** Intel 或通用构建、PKG 分发、CDN 交付和自动门禁需要目前不存在的代码或 CI。只列出已经实现的 arm64 直接下载和 Sparkle lane，可防止流程文档成为错误的产品声明。

## 后果

stable 用户会收到通过候选验证的完整五文件集合，保留的 commit、tag、provenance 记录、发布说明、版本历史条目与校验和共同标识其来源与字节。含糊请求不会静默产生 stable 发布，过期 build 号与不匹配的 Sparkle 密钥会在签名前失败，候选 commit 之外的 dirty 能力也不能被描述为已经交付。

该流程有意保持手工执行。总管会成为发布瓶颈，每个失败的公开候选版本都会消耗一个版本号，策略违规由操作者审查而非 CI 捕获。可用产品仍仅支持 Apple silicon，并直接使用 GitHub Releases，不经过 CDN。
