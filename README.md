# Cipherbook

Cipherbook 是一个本地优先的 Android / Windows 密码库。密码库默认只以加密文件保存在当前设备，
不需要账号、云端服务或自建后端；需要多设备协作时，可在同一局域网内验证共同主密码后双向合并。

当前应用版本：`1.4.0+6`（以 [`pubspec.yaml`](pubspec.yaml) 为唯一来源）。

> 当前构建用于本地测试和自用验证。Android 仍使用 debug 签名，Windows 安装包尚无正式代码签名；
> iOS 尚未提供官方构建或安装包。正式分发前请先阅读
> [`docs/release.md`](docs/release.md) 中的阻断项。

## 功能概览

- 本地加密密码库：Argon2id + XChaCha20-Poly1305，主密码不会上传。
- 登录项与安全笔记：新增、编辑、搜索、复制、收藏、文件夹和回收站。
- TOTP：兼容已有验证器密钥和 `otpauth://totp` URI。
- 加密备份：`.pwv` 导入、导出、导入预览和异常文件恢复。
- 局域网同步：UDP 发现，验证共同主密码后收集并双向合并多台设备的数据。
  接收端完成合并后会显示同步成功提醒。
- Bitwarden 数据桥接：未加密 JSON / CSV 导入导出、重复候选人工核验、来源 ID 回写，
  并可按 Bitwarden 基线只导出缺失条目。
- 快速解锁：Android 强生物识别、Windows Hello；默认冷启动先验证一次主密码，也可逐设备开启
  “冷启动直接快速解锁”。
- 自动锁定、锁定时清理会话密钥，并尝试清理本应用复制到剪贴板的内容。

## 平台支持

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Windows 10/11 | 支持 | Flutter 桌面应用；Windows Hello + DPAPI 快速解锁 |
| Android 7.0+ / API 24+ | 支持 | Flutter 应用；快速解锁要求设备支持强生物识别 |
| iOS / iPadOS | 规划中 | 尚无宿主工程、Keychain / Face ID、文件保存、局域网权限和签名配置 |

iOS 的当前边界和未来接入条件见 [`docs/ios.md`](docs/ios.md)。不要把 Android 或 Windows
产物描述为 iOS 支持，也不要使用未经确认的第三方签名包处理真实密码库。

## 快速开始

从源码运行：

```powershell
git clone https://github.com/boostemotion/codebook.git
cd codebook
flutter pub get
flutter run -d windows
```

Android 设备可通过 `flutter devices` 查看设备 ID，再执行：

```powershell
flutter run -d <device-id>
```

完整的工具链、Release 构建、ADB 安装和测试命令见
[`docs/development.md`](docs/development.md)。安装包命名和发布检查见
[`docs/release.md`](docs/release.md)。

## 文档导航

- [`docs/README.md`](docs/README.md)：文档索引和阅读顺序；
- [`docs/architecture.md`](docs/architecture.md)：分层、加密文件、同步和 Bitwarden 桥接；
- [`docs/security.md`](docs/security.md)：资产、信任边界、快速解锁和部署风险；
- [`docs/development.md`](docs/development.md)：Windows、Android、测试和常见构建问题；
- [`docs/release.md`](docs/release.md)：版本、构建、产物校验和正式发布阻断项；
- [`docs/ios.md`](docs/ios.md)：iOS 未支持状态、所需工作和未来真机/上架路径；
- [`CONTRIBUTING.md`](CONTRIBUTING.md)：代码、测试、提交和 Pull Request 要求；
- [`SECURITY.md`](SECURITY.md)：安全漏洞的私密报告方式。

## 数据与安全

- 主密码通过 Argon2id 派生 256 位密钥加密密钥（KEK），默认参数为 64 MiB、3 次迭代、并行度 1。
- 每个密码库使用独立 DEK；DEK 由 KEK 包装，实际数据使用 XChaCha20-Poly1305 加密。
- 修改主密码会生成新的盐、KEK 和 DEK，并使用新参数重新加密密码库。
- 快速解锁只缓存经过设备保护包装的 DEK。Windows 在读取前会验证 Windows Hello；
  Android 使用 Android Keystore 中要求强生物识别的密钥。
- “冷启动直接快速解锁”只保存设备本地开关，不保存主密码或明文 DEK。
- 密码库写入采用临时文件、校验和 `.bak` 备份流程，避免直接覆盖最后一个可用文件。
- Android 禁用系统自动备份并设置 `FLAG_SECURE`，减少截图和最近任务泄露。

完整的威胁边界和已知取舍见 [`docs/security.md`](docs/security.md)。

## 局域网同步

1. 确保设备连接同一局域网，打开应用并解锁密码库。
2. 从任意一台设备进入“设备配对与同步”，输入所有设备共同使用的主密码。
3. 应用通过 UDP 发现设备，验证主密码证明，下载并合并已经加密的 `.pwv` 文档，再把合并结果写回各端。
4. 每台设备继续保留自己的密码库编号、KDF 参数和加密文件；主密码不在网络中直接传输。

同步按条目 ID 和更新时间合并，并保留删除标记；它不是云同步，也不提供中心服务器冲突仲裁。
Android 端依赖应用在前台且已解锁，锁定或进入后台后会停止监听。

## Bitwarden 数据交换

### 向 Bitwarden 补充缺失项

Bitwarden 的文件导入只会新增条目，不会按账号、网址或来源 ID 更新已有条目。
因此 Bitwarden 中已有数据时，不要直接再次导入 Cipherbook 的全量导出文件。推荐流程：

1. 在 Bitwarden 中导出当前密码库，得到未加密 JSON 或 CSV，作为基线。
2. 在 Cipherbook 的“导出”页面点击“核对 Bitwarden 并导出缺失项”。
3. 选择第 1 步的 Bitwarden 文件，Cipherbook 会核对账号、网址、邮箱/手机号、标题、
   密码和安全笔记内容。
4. 查看“已匹配”和“缺失”数量，再导出缺失 JSON 或缺失 CSV。
5. 只把这份缺失文件导入 Bitwarden。Bitwarden 已有条目不会被改动或删除。

Bitwarden 基线与 Cipherbook 中密码不同但账号相同时，会视为已经存在而不重复导出；
这类密码更新目前仍需在 Bitwarden 条目中单独修改。完全相同的 Cipherbook 记录只会导出一次。

### 从 Bitwarden 导入 Cipherbook

在 Bitwarden 中导出未加密 JSON，或使用 CSV 兼容格式，再从 Cipherbook 的“导入”页面导入。
应用会：

- 导入登录项、安全笔记、文件夹、收藏、TOTP 和可用的来源 ID；
- 从混合账号文本中提取手机号和邮箱别名；
- 按来源 ID、网站、账号别名、标题、密码和 TOTP 给出重复候选；
- 对每条候选要求人工选择“两边都保留”“用导入项替换本机”或“不导入这一条”；
- 对额外网址、自定义字段、Passkey、附件、密码历史和不支持的项目给出提示。

Bitwarden JSON/CSV 是明文凭据文件。导出前应用会二次确认；导入目标密码管理器后应立即删除交换文件。
Bitwarden 加密 JSON 不能直接导入，需要先在 Bitwarden 中导出未加密 JSON 或 CSV。

## 项目结构

```text
lib/models/       密码库、KDF、同步与 Bitwarden 交换模型
lib/services/     加密、存储、导入导出、TOTP、快速解锁和局域网同步
lib/state/        VaultController、会话锁定、导入计划和合并编排
lib/ui/           Android / Windows 共享与平台自适应界面
android/          Android 宿主、Keystore、Biometric 和网络桥接
windows/          Windows 宿主、Windows Hello 和 DPAPI 桥接
packaging/        Windows IExpress 安装器
docs/             架构、开发、安全与发布文档
test/             单元测试和 Flutter 流程测试
```

更多设计说明见 [`docs/architecture.md`](docs/architecture.md)。

## 开发与验证

```powershell
flutter analyze --no-pub lib test
flutter test --no-pub
```

发布前还需构建两个平台：

```powershell
flutter build apk --release --no-pub
flutter build windows --release --no-pub
```

贡献代码前请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。安全问题请按
[`SECURITY.md`](SECURITY.md) 的方式报告。

## 当前限制

- 当前没有云端同步、账号体系和后台常驻同步。
- iOS 版本尚未工程化；Windows 不能直接完成 iOS 构建和签名，详见 [`docs/ios.md`](docs/ios.md)。
- Bitwarden 桥接只覆盖登录项、安全笔记及已列出的字段，不支持加密 JSON、Passkey、附件、
  银行卡、身份资料、Collections、额外网址和任意自定义字段。
- Android Release 目前使用 debug 签名，`applicationId` 仍是 `com.example.cipherbook`；
  正式发布前必须替换唯一 ID 并配置独立签名密钥。
- Windows 安装包尚未配置正式代码签名证书。
- 当前没有 GitHub Actions 或其他自动发布流水线；公开仓库可以后续增加 macOS 编译任务，
  但签名、TestFlight 和 App Store 上传仍需 Apple 开发者凭据。
- 构建产物位于本地 `build/` 和 `dist/`，不提交到 Git；如需公开提供，应作为 GitHub Release
  附件单独发布。
