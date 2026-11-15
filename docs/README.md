# 文档索引

Cipherbook 的文档按“先理解边界，再开发和发布”的顺序组织。涉及真实凭据时，先阅读安全模型，
再执行构建、导入导出或同步操作。

## 推荐阅读顺序

| 文档 | 用途 | 适用读者 |
| --- | --- | --- |
| [`../README.md`](../README.md) | 功能、平台状态、快速开始和当前限制 | 所有用户 |
| [`architecture.md`](architecture.md) | 分层、密码库格式、局域网同步和 Bitwarden 桥接 | 开发者 |
| [`security.md`](security.md) | 资产、信任边界、快速解锁和已知风险 | 开发者、发布者 |
| [`development.md`](development.md) | Windows / Android 开发、构建、ADB 和排错 | 开发者 |
| [`frontend.md`](frontend.md) | 当前 Prism 前端结构、数据边界、回退入口和截图测试 | 前端开发者 |
| [`design/README.md`](design/README.md) | 当前视觉基线、响应式截图和更新方式 | 前端开发者、设计评审 |
| [`release.md`](release.md) | 版本规则、发布检查、产物校验和阻断项 | 发布者 |
| [`ios.md`](ios.md) | iOS 当前状态、缺失能力、未来编译和上架路径 | iOS 开发者 |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | 修改原则、测试、提交和 Pull Request 要求 | 贡献者 |
| [`../SECURITY.md`](../SECURITY.md) | 安全漏洞私密报告范围 | 所有报告者 |
| [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) | Prism、FlClash 和适配代码的上游归属与许可证 | 发布者、复用者 |

## 单一事实来源

- 应用版本和构建号只以 [`../pubspec.yaml`](../pubspec.yaml) 为准。
- 支持平台和用户可见能力以本目录及根目录 README 的最新说明为准。
- Android、Windows 的命令集中在 [`development.md`](development.md)；发布检查集中在
  [`release.md`](release.md)。
- 界面结构和设计说明以 [`frontend.md`](frontend.md)、[`design/README.md`](design/README.md)
  与源码中的视觉令牌为准，不保留子智能体过程报告作为长期文档。
- iOS 尚未支持。任何新增 iOS 宿主、签名或安装方式，都必须同步更新 [`ios.md`](ios.md)
  和根目录 README 的平台表。

## 敏感信息

文档、Issue、截图和日志不得包含主密码、DEK/KEK、TOTP 密钥、设备 token、真实密码库或
Bitwarden 明文导出。证书、Provisioning Profile、App Store Connect API Key 和私钥也不得提交到
Git。
