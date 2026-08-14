# DS Harness macOS 应用

[English](README.md) | 中文

`apps/macos` 构建 DeepSeek Harness 的原生 macOS 客户端 DS Harness。SwiftUI 负责场景、导航和应用状态；窄范围 AppKit 钩子负责前台激活及仅桌面端需要的控件。应用以 Node sidecar 启动真实 Harness profile，并通过 stdio 上带版本的 NDJSON 通信，不开放 localhost 端口。用户在原生设置窗口配置 DeepSeek API Key；值只写通过既有 credentials API 进入仅所有者可访问的 Harness 凭据存储，界面只能读回状态。原生“关于”窗口使用带 `from=mac` 归因参数的链接进入 DS Harness 官网。

首个客户端切片可以列出工作区与会话、创建会话、读取可见对话历史、渲染基础 Markdown、发送提示、流式显示助手文本并取消正在进行的生成。它还会显示工具活动、响应审批请求，并在输入区呈现结构化用户问答。插件注入的上下文和模型 reasoning 仍保留在 Harness 日志中，但不会作为用户可见聊天消息渲染。

## 开发

环境要求为 macOS 14 或更高版本、Swift 6.2 或更高版本、符合仓库 engine 要求的 Node，以及已安装的 pnpm 依赖。

```sh
pnpm --filter @deepseek-ai/dsh-macos run generate
pnpm --filter @deepseek-ai/dsh-macos run test:host
cd apps/macos && swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh --package
```

普通运行模式会组装 `dist/DS Harness.app`，并以前台开发应用方式启动。只有设置仓库覆盖路径后，`DSH_MACOS_REPOSITORY_ROOT` 与 `DSH_NODE_PATH` 才会选择源码 sidecar 和开发用 Node 可执行文件。

打包模式会构建 release Swift 可执行文件和已编译 sidecar、以复制方式部署生产依赖、依据每个包的发布文件清单补齐缺失的内部 workspace 依赖、移除原生 overlay 已禁用的浏览器入口、验证官方 Node 压缩包校验和，并在 `Contents/Resources/runtime` 下写入自包含运行时。复制部署保证应用不受后续 workspace 构建影响。其冒烟测试从临时目录启动已打包 sidecar，打包过程也会拒绝应用中的仓库路径、浏览器入口或符号链接。已打包应用不会查找开发仓库或系统 Node 安装。

## 分发

arm64 release 应用包为 `DS Harness.app`，bundle identifier 是 `app.sayall.ds-app`。`Resources/AppIcon.png` 是 1024×1024 图标母版。`scripts/sign_and_package.sh` 使用 Developer ID 与 Hardened Runtime，由内向外签名原生 addon、Node 运行时和外层应用。Node 只获得 V8 与原生 addon 所需的 JIT、未签名可执行内存和停用库验证权限；release 会拒绝调试 entitlement。公证流水线会对应用与 `DS-Harness-<version>-arm64.dmg` 分别执行 staple 和验证，再写入其 SHA-256 文件。

## 原生客户端协议

`Protocol/native-client-protocol.json` 负责进程载体版本和生成的 Swift 事实。版本 0 提供协议协商、一元 Host RPC、对可响应服务端请求的客户端响应，以及标准 mux 与 Host 事件流。一元帧保留 `ClientRequest` 与 `ServerResponse`，流帧保留 `ServerRequest`，响应帧保留 `ClientResponse`；原生载体只把 HTTP 替换为带关联 id 的 NDJSON 帧。

原生插件协议传递语义，不允许注入可执行 UI。Harness presenter 可以为工具调用和结果事件附加可选的 `ToolEventView`；Swift 拥有受支持卡片的渲染器，缺失或未知 presentation 时回退到通用工具卡片。插件不能向应用注入 Swift View、JavaScript 或额外 RPC 方法。
