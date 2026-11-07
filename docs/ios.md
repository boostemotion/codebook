# iOS 支持状态

## 当前结论

截至 `1.4.0+6`，Cipherbook **不支持 iOS 或 iPadOS**：

- 仓库没有 `ios/` 宿主工程；
- 没有 Xcode、Bundle ID、Provisioning Profile 或 App Store 配置；
- 没有 Keychain + Face ID / Touch ID 快速解锁桥接；
- 没有 iOS 本地网络权限、安全区布局和系统分享导出；
- 没有可验证的 IPA、TestFlight 或 App Store 安装包。

Windows 可以继续开发和运行 Flutter 共享代码，但不能编译、签名或直接安装 iOS 应用。
官方 iOS 构建仍需要 macOS、Xcode、Apple 签名环境和真实 iPhone 测试。

## 可复用部分

以下共享 Dart 代码以平台无关逻辑为主，可作为未来 iOS 实现的基础：

- 密码库模型、KDF、加密文档和文件恢复；
- `VaultController` 的会话、锁定和异步 revision 校验；
- TOTP、密码生成和剪贴板服务；
- 局域网发现、认证和加密文档合并协议；
- Windows 与 Android 共用的主要 Flutter 界面。

部分第三方依赖已提供 iOS 实现，例如 `path_provider` 和 `file_selector`。插件“能够编译”不代表
现有业务流程在 iOS 上可用，必须按下面的平台差距逐项验证。

## 尚未实现

### 宿主工程和签名

- 生成并提交 `ios/Runner`、Xcode workspace 和必要的 scheme；
- 选择唯一的 Bundle ID，正式项目不得继续使用 `com.example.*`；
- 配置开发团队、证书、Provisioning Profile 和 App Store Connect 记录；
- 配置应用图标、启动页、显示名称和版本同步。

### 快速解锁

现有 `DeviceKeyStore` 通过 MethodChannel 调用平台原生能力。iOS 需要新增 Swift 实现：

- 使用 Keychain 保存经过设备保护的 KEK；
- 使用 LocalAuthentication 调用 Face ID 或 Touch ID；
- 生物识别集合变化或认证失败时使旧缓存不可用；
- 不保存主密码、明文 KEK/DEK 或可绕过的布尔开关；
- 在 `Info.plist` 提供准确的 `NSFaceIDUsageDescription`。

原生桥接完成前，现有 MethodChannel 会返回“不支持”，不得把 iOS 描述为支持快速解锁。

### 文件和导入导出

`file_selector` 的 iOS 实现支持打开文件，但不支持当前使用的目录选择和 `getSaveLocation`。
因此不能直接复用 Android 的导出分支。需要选择以下一种方式：

1. 生成临时文件，通过系统分享面板交给“文件”、AirDrop 或其他应用；
2. 实现 `UIDocumentPickerViewController`，让用户选择保存位置；
3. 使用经过审查、支持 iOS 文档导出的 Flutter 插件。

必须覆盖 `.pwv`、Bitwarden JSON/CSV 和异常取消流程，并确保临时明文交换文件在完成后可删除。

### 局域网同步

- 增加 `NSLocalNetworkUsageDescription`；
- 如系统策略阻止局域网 HTTP，评估 `NSAllowsLocalNetworking` 的最小范围配置；
- 验证 UDP 广播发现、HTTP 传输、前后台切换和锁定后的监听停止；
- 保持仅在前台、已解锁且用户主动同步时运行；
- 不在公共 Wi-Fi 或公网端口上使用。

iOS 仍沿用“无中心服务器、传输加密 `.pwv`、主密码不直接发送”的协议边界，但必须重新验证
真实设备上的权限提示、地址选择和超时行为。

### 界面与隐私

- 把只判断 Android 的手机布局扩展为 Android 与 iOS 共用的移动端分支；
- 适配安全区、键盘、窄屏、横屏和系统深浅色；
- 在进入后台或应用切换器时遮住密码条目；
- 评估截图和录屏风险。iOS 没有与 Android `FLAG_SECURE` 完全等价的公开通用开关；
- 不把桌面端的鼠标、窗口尺寸和右键交互假设带到 iPhone。

## 未来构建路径

### Mac 真机开发

1. 安装 Xcode 和 Flutter iOS 工具链；
2. 执行 `flutter doctor -v`，确认 CocoaPods、签名设备和 Xcode 均通过；
3. 在仓库中生成并审查 iOS 宿主工程；
4. 用 Xcode 自动签名连接真实 iPhone；
5. 在设备上验证创建密码库、重启解锁、Face ID、导入导出和局域网同步。

免费 Apple ID 的个人签名通常需要定期重新部署，适合短期测试，不适合作为长期密码库安装方案。

### 付费开发者分发

- TestFlight：适合受控测试，每个构建有有效期；
- Ad Hoc：适合登记过 UDID 的少量设备；
- App Store 或不公开分发：适合长期安装和正式更新；
- App Store Connect API Key、证书和 Provisioning Profile 只能放在本地安全存储或受保护的
  CI Secrets 中，不得提交到仓库。

### GitHub Actions

公开仓库可以使用 macOS Runner 做未签名编译，或者在具备付费开发者凭据时生成签名产物并上传
TestFlight。当前仓库尚未配置 iOS 工作流；添加时必须遵守：

- 未签名构建可以处理普通提交；
- 签名 Secrets 不得暴露给不可信 Pull Request；
- 签名任务限制为手动触发或受保护分支；
- macOS Runner 不能替代真实 iPhone 上的 Face ID、文件和局域网测试；
- 工作流、签名方式和产物说明必须与本文同步更新。

## App Store 准备

在真正提交审核前至少需要：

- 唯一 Bundle ID 和稳定的应用图标；
- 隐私政策、支持网址、App Store 截图、分类和年龄分级；
- App 隐私标签，并与实际数据收集行为一致；
- 对标准加密使用情况完成出口合规问答；
- Face ID、本地网络和文件访问的用途说明；
- 不含真实凭据的审核步骤，确保审核员可以创建本地密码库；
- 如在中国大陆区提供下载，确认适用的 App 备案和其他本地合规要求。

## 验收条件

只有同时满足以下条件，才能把平台表改为“支持 iOS”：

1. `ios/` 工程可稳定构建；
2. 至少一台真实 iPhone 完成安装和升级；
3. 创建、解锁、自动锁定、重启和快速解锁通过；
4. `.pwv` 与 Bitwarden JSON/CSV 导入导出通过；
5. Android、Windows 与 iOS 之间的局域网双向同步通过；
6. 锁屏、后台、取消权限和网络中断有明确失败行为；
7. 文档说明可用的安装渠道、签名有效期和已知限制。
