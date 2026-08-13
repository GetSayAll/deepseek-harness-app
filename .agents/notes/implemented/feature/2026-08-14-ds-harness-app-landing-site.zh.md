# Agent Note: DS Harness App 官网

Status: implemented

[English](2026-08-14-ds-harness-app-landing-site.md) | 中文

## 问题

桌面 App 在产品可下载之前就需要一个公开主页。既有 `website/` 应用发布 canonical 项目文档，其生成路由树始终包含上游产品名称；若让 App 域名复用该构建，就会混合两个品牌，并让营销页面依赖文档投影规则。

## 决策

`website/landing/` 是 `dsapp.sayall.app` 的独立静态入口。它只展示 DS Harness App 产品名称，明确 App 仍在开发中，介绍 App 优势，并按要求把访客带到上游项目页面与公开源码仓库。它不会替换或修改 VitePress 文档构建。

Cloudflare Workers Static Assets 通过 `website/landing.wrangler.jsonc` 提供该目录。官网没有应用运行时、分析、持久化或构建依赖；HTML、CSS 与用于导航和渐入效果的少量脚本构成全部生产输入。

## 曾考虑的替代方案

**替换 VitePress 首页。** 不采用：文档 projector 持有该路由树，并以既有产品身份发布 canonical 项目材料。仅用于营销的替换要么隐藏文档，要么要求在文档配置中到处增加品牌分支。

**创建另一个 JavaScript 应用与打包流水线。** 不采用：第一版只有一个信息页面，没有客户端数据或应用状态。框架与依赖图会增加部署和维护工作，却不会增加用户可见能力。

**等桌面 App 可以下载后再发布。** 不采用：在 binary 就绪之前，稳定域名、产品定位与公开进度链接已经有用。

## 后果

App 拥有小型、可独立部署的公开入口，canonical 文档保持不变。静态目录不会复制文档内容，并且不得把上游注册商标作为 App 品牌展示。未来的交互式产品能力需要明确决定该静态入口是否仍然足够，或是否应升级为单独的应用包。
