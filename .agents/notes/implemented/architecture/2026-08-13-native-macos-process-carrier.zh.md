# Agent Note: 原生 macOS 进程载体

Status: implemented

[English](2026-08-13-native-macos-process-carrier.md) | 中文

## Problem

原生 macOS 应用必须复用真实 Harness 插件树、持久化与 API 行为，同时不嵌入浏览器 UI，也不暴露 localhost 服务器。它还会与 Host 包独立发布，因此需要一项与绑定发布的 Web 客户端不同的显式兼容性检查。

## Decision

`apps/macos` 是 SwiftPM 应用，主界面使用 SwiftUI。AppKit 仅作为窄范围桥接，用于前台激活及 SwiftUI 无法精确表达的桌面控件。

应用从同一分发包启动 Node sidecar。sidecar 通过 `runProfile` 启动 `web` profile，再应用 `Host/native.overlay.yml`：Host 侧存储、工作区、会话、预设和 `ApiProxy` 保持挂载，Web 服务器、浏览器载体、浏览器运行时和浏览器 UI 条目则被禁用。原生目录选择器提供方替换 Web 自适应选择器。整个过程不开放 TCP 端口。

`@deepseek-ai/dsh/profile-boot` 是原生载体使用的稳定包入口。macOS 构建会编译 sidecar、部署其生产依赖树，再只复制各 workspace 包声明的发布文件，从而补齐缺失的内部 `dependencies` 与必要对等依赖（peer dependency）。应用把该依赖树和经过校验和验证的官方 Node 分发包内置于 `Contents/Resources/runtime`；已打包应用启动时不会回退到仓库路径、`tsx` 或系统 Node 安装。

发布应用为 `DS Harness.app`，标识为 `app.sayall.ds-app`。其 release 流水线面向 arm64，使用仓库内的 1024×1024 图标母版，并使用 Developer ID 与 Hardened Runtime，由内向外签名原生 addon、Node 和外层应用。Node 保留 V8 与原生 addon 所需的最小 entitlement，但不包含 `get-task-allow`。Apple 公证与 staple 同时应用于应用和最终 DMG。

物理载体是在子进程 stdin 与 stdout 上传输的逐行 JSON。stdout 只承载协议帧，诊断信息使用 stderr。每个请求都携带客户端生成的 id，Swift actor 据此关联并发 continuation。Swift 先把管道数据缓冲为完整的逐行 JSON 帧，再执行解码。优雅关闭使用一条有确认响应的协议帧，随后释放 Cordis 插件树；应用会等待子进程退出，再释放管道状态。

原生载体从 `protocolVersion` 0 开始。其清单生成 Swift 版本和第一项强类型 Host 响应。启动时必须先协商到相同版本，才能发送业务请求。一元调用通过 `toFetchHandler` 保留标准 `ClientRequest` 与 `ServerResponse` 形式；mux 和 Host 流保留标准 `ServerRequest` 形式；审批和用户问答使用稳定的服务端请求 `rpcId`，并保留 `ClientResponse`。进程载体不会定义第二套业务 API。

插件通过 Host 计算的 `ToolEventView` 提供工具展示语义。贡献内容选择带版本的语义卡片及其数据，每一种渲染器都由 Swift 拥有。缺失和未知 view 会回退到通用卡片。插件不能加载 Swift View、在界面中执行 JavaScript，也不能扩展原生 RPC 集合。

## Alternatives considered

**在 WKWebView 中嵌入现有 Web UI。** 这种方式上线更快，但会保留浏览器布局和交互限制，无法建立所需的原生插件表面，并会让原生控件逐渐变成围绕 Web 应用增长的例外集合。

**用 Swift 重写 Harness 后端。** 这会重复插件运行时、持久化、会话语义和工具执行路径。两套实现会持续漂移，却不能为第一版带来对应的用户价值。

**运行现有 localhost Web 服务器。** loopback 端口会引入 origin、端口分配和信任问题，却无法帮助进程内桌面客户端。stdio 让应用直接拥有子进程，并缩小攻击面。

**允许插件提供任意原生视图。** 从插件装载 Swift 代码或通用 UI 描述会让兼容性与审查范围失去边界。原生插件协议改为通过带版本的语义贡献逐步扩展，由应用拥有渲染器并提供通用回退。

## Consequences

首个原生应用复用生产 Host 行为，并可通过显式载体版本独立演进。SwiftUI 保持状态事实来源，未来的 AppKit 使用仍局限在明确位置。

客户端通过一元调用、客户端响应以及 mux 或 Host 事件列出工作区与会话、创建会话、读取可见历史、发送提示、流式显示助手文本、取消生成、渲染工具事件，并处理审批和用户问答。它只把直接用户消息和助手文本 block 渲染为聊天消息；插件上下文与 reasoning 保留在规范日志中，不作为普通聊天内容显示。

开发环境可以通过显式环境覆盖选择源码 sidecar 和 Node。打包过程会在仓库外运行已编译 sidecar、拒绝内嵌仓库路径与符号链接，并在应用包元数据中固定版本、标识与图标。发布流程会验证签名、entitlement、校验和、Gatekeeper 接受状态和已打包 sidecar 的退出。语义卡片集合可以增量扩展，通用回退使旧客户端仍可使用；载体帧或必要能力发生变化时，需要决定是否提升协议版本。
