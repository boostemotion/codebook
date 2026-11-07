# 参与开发

感谢参与 Cipherbook。这个项目处理真实凭据，提交代码、日志和测试数据时请优先保护用户数据。

## 开始之前

1. 阅读 [`docs/architecture.md`](docs/architecture.md) 和 [`docs/security.md`](docs/security.md)。
2. 安装 Flutter、Android SDK、JDK 17 和 Windows C++ Build Tools。
3. 执行 `flutter pub get`。
4. 从 `main` 创建范围明确的分支。

当前开发环境和完整命令见 [`docs/development.md`](docs/development.md)。

## 修改原则

- 业务和加密逻辑放在 `lib/services/` 与 `lib/state/`，Widget 不直接访问平台密钥、文件或网络。
- 条目、密码库文档、KDF、同步和 Bitwarden 交换格式的变更必须先补测试。
- 新增平台桥接时，同时提供无平台环境的测试实现或明确的不可用分支。
- 不提交 `build/`、`dist/`、`*.jks`、`*.keystore`、`key.properties`、私钥或真实密码库。
- 不在日志、测试快照、Issue 或截图中暴露主密码、DEK/KEK、TOTP 密钥和设备 token。
- 涉及 UI 的改动应验证 Windows 和 Android 的窄窗口/小屏布局。

## 本地验证

```powershell
dart format lib test
flutter analyze --no-pub lib test
flutter test --no-pub
```

安全相关改动还应说明：

- 改变了哪个信任边界；
- 失败时是否保留最后一个有效密码库；
- 是否影响旧版 `.pwv`、局域网配对或快速解锁缓存；
- 是否需要增加恢复或迁移测试。

## 提交与 Pull Request

提交信息应简短、动作明确，例如：

```text
Add Bitwarden duplicate review
Polish Android settings sheet
Fix quick unlock cold-start preference
```

Pull Request 建议包含：

- 改动目的和用户可见行为；
- 加密、存储、导入、同步或平台桥接的风险；
- 执行过的精确测试命令；
- UI 改动的截图或录屏（不要包含真实凭据）；
- 关联 Issue（如有）。

## 安全问题

不要在公开 Issue 中发布漏洞细节或真实凭据。请按 [`SECURITY.md`](SECURITY.md) 私密报告。
