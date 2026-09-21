# Cipherbook

Cipherbook 是一个本地优先的跨设备密码库，当前支持 Windows 和 Android。
密码库始终保存在本机加密文件中，不依赖云端账号或后端服务。

## 功能

- 主密码解锁的本地加密密码库
- 新增、编辑、搜索、复制和回收站
- TOTP：支持 Base32 密钥和 `otpauth://` URI
- 加密备份导入、导出与导入预览
- Windows 与 Android 局域网配对和加密同步
- 主密码修改与自动锁定
- 快速解锁：Android 生物识别、Windows Hello + DPAPI
- Windows 和 Android 使用统一的 Cipherbook 锁图标

## 技术栈

- Flutter / Dart：跨平台 UI、状态编排和业务逻辑
- Argon2id：从主密码派生密钥加密密钥（KEK）
- XChaCha20-Poly1305：加密实际密码库数据
- Android Keystore + Biometric：Android 快速解锁
- Windows Hello + DPAPI：Windows 快速解锁
- UDP 发现 + HTTP 加密文档传输：局域网配对

项目没有传统后端。`lib/services/` 负责加密、文件存储、导入导出和网络同步，
`lib/state/` 负责会话与业务编排，`lib/ui/` 只负责界面交互。

## 项目结构

```text
lib/models/       数据模型与校验
lib/services/     加密、存储、导入导出、TOTP、局域网同步
lib/state/        VaultController 和导入计划
lib/ui/           Android / Windows 界面
android/          Android 宿主、Keystore 和生物识别
windows/          Windows 宿主、Windows Hello 和 DPAPI
packaging/        Windows 安装器脚本
tools/            图标和开发辅助脚本
docs/             架构与维护说明
test/             单元测试和界面流程测试
```

## 开发环境

建议使用以下工具链，并将工具安装在 `D:\DevTools` 等独立目录：

- Flutter 3.47+
- Dart 3.13+
- Android SDK、JDK 17
- Windows 10/11 SDK

安装依赖：

```powershell
$env:PUB_CACHE = 'D:\DevTools\pub-cache'
flutter pub get
```

检查和测试：

```powershell
flutter analyze lib test
flutter test
```

## Android

构建 Release APK：

```powershell
$env:JAVA_HOME = 'D:\DevTools\jdk-17'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
$env:PUB_CACHE = 'D:\DevTools\pub-cache'
flutter build apk --release --no-pub
```

输出：`build\app\outputs\flutter-apk\app-release.apk`

通过 ADB 安装并启动：

```powershell
$adb = 'D:\DevTools\android-sdk\platform-tools\adb.exe'
& $adb devices
& $adb install -r build\app\outputs\flutter-apk\app-release.apk
& $adb shell monkey -p com.example.cipherbook -c android.intent.category.LAUNCHER 1
```

当前 Release 构建使用 debug 签名，只适合本地安装和测试，不应直接作为公开发布版本。

## Windows

运行：

```powershell
flutter run -d windows
```

构建：

```powershell
$env:PUB_CACHE = 'D:\DevTools\pub-cache'
flutter clean
flutter pub get
flutter build windows --release --no-pub
```

输出目录：`build\windows\x64\runner\Release\`

生成安装包：

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\build_installer.ps1
```

安装包：`dist\Cipherbook-Setup.exe`

安装器首次安装时选择目录，后续会读取 `HKCU\Software\Cipherbook` 和已有快捷方式定位安装目录。
安装前会检查 `cipherbook.exe` 是否正在运行，并等待 IExpress 输出完整后再返回。

## 局域网配对与同步

配对只在局域网内进行：

1. 来源设备在“设备配对与同步”中开启分享。
2. 目标设备发现来源设备并输入一次性配对码。
3. 目标设备先预览变更，再确认导入。
4. 后续只在应用处于前台、密码库已解锁时低频发现和同步。

传输内容是加密的 `.pwv` 文档，不传输明文密码、主密码或 KEK。已有密码库按条目更新时间合并，
本地较新的条目不会被来源设备覆盖。锁定或进入后台后会停止网络监听。

## 安全说明

- 主密码丢失后无法恢复数据，不存在后门。
- 密码库写入使用临时文件、备份文件和校验恢复流程。
- 不要把主密码、TOTP 密钥或导出密码写入日志、截图或提交记录。
- Android 已禁用系统自动备份，并使用安全窗口标记减少最近任务和截图泄露。
- 正式发布前必须配置唯一的 Android application ID 和正式签名密钥，签名文件不得提交到 Git。

## 当前限制

- iOS 尚未加入工程。Flutter 业务代码可以复用，但需要 macOS/Xcode、iOS Keychain/Face ID 原生桥接、
  本地网络权限和 Apple 签名配置；Windows 上不能直接完成 iOS 签名发布。
- Android 局域网同步依赖前台运行，不能承诺像桌面端一样长期后台监听。
- 当前没有云端同步和服务端冲突解决；同步以本地加密文档和条目更新时间合并为边界。
- Android Release 目前是 debug 签名，仅用于本地测试。

## 维护约定

业务逻辑放在 `lib/services/` 和 `lib/state/`，不要在 Widget 中直接写文件或调用平台 API。
涉及加密、存储、导入、同步或会话锁定的修改必须补充针对性测试。

更详细的边界说明见 [`docs/architecture.md`](docs/architecture.md)。
