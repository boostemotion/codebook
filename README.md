# Cipherbook

Cipherbook 是一个本地优先的跨设备密码库，当前支持 Windows 和 Android。
密码库始终保存在本机加密文件中，不依赖云端账号或后端服务。

## 功能

- 主密码解锁的本地加密密码库
- 新增、编辑、搜索、复制和回收站
- 密码表单仅保留名称、账号、密码、网址、备注，支持选择长度生成密码
- 兼容已有 TOTP 与标签数据，编辑普通信息不会清除这些数据
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

安装包按当前版本命名，例如：`dist\Cipherbook-1.2.1+4-windows-setup.exe`。
打包脚本会检查 EXE 的版本与 `pubspec.yaml` 是否一致，避免把旧构建打成新版本。

安装器首次安装时选择目录，后续会读取 `HKCU\Software\Cipherbook` 和已有快捷方式定位安装目录。
安装前会检查 `cipherbook.exe` 是否正在运行，并等待 IExpress 输出完整后再返回。

## 局域网配对与同步

配对只在局域网内进行：

1. 所有设备升级至 1.2.0 或更高版本，连接同一局域网，并打开、解锁密码本。
2. 在任意一端进入“设备配对与同步”，输入各端共同使用的主密码。
3. 点击“验证并同步所有设备”。应用自动过滤本机，验证其他设备，收集合并各端条目，再将合并结果写回各端。
4. 界面显示对端已确认写入的设备数量；部分失败会单独提示，可以直接重试。

这一操作也支持分别创建、使用相同主密码的密码库，不要求其密码库编号相同。
各端继续保留自己的加密参数与密码库编号，主密码仅在本机用于派生密钥和生成验证证明，不直接广播或传输。
“单台设备导入（高级）”保留原有逐台预览、确认合并的入口。
从同一密码库导入的已配对设备，后续仍可在应用前台且已解锁时低频自动同步。

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

### 版本与发布

版本唯一来源是 `pubspec.yaml` 的 `version: 主版本.次版本.补丁版本+构建号`，
例如当前的 `1.2.1+4`。Android 的版本名称/版本代码和 Windows EXE 的产品/文件版本均由 Flutter 自动生成。

- 修复问题：`1.1.0` → `1.1.1`。
- 新增兼容功能：`1.1.0` → `1.2.0`。
- 不兼容的大改动：`1.x.x` → `2.0.0`，同时提供迁移说明。
- 每次发布构建号必须递增（`+2` → `+3`），包括同一功能版本重新打包。
- 先修改版本并运行 `flutter pub get`，再构建两端；同一批发布共用版本号与构建号。
- Windows 安装包使用 `Cipherbook-版本+构建号-windows-setup.exe`，Android 分发文件使用
  `Cipherbook-版本+构建号-android.apk`；Flutter 原始 APK 输出名仍为 `app-release.apk`。
- 每次发布在 [CHANGELOG.md](CHANGELOG.md) 记录用户可见的改动。

应用版本与 `.pwv` 密码库格式版本分别维护；仅升级应用版本不会改变密码库格式。

业务逻辑放在 `lib/services/` 和 `lib/state/`，不要在 Widget 中直接写文件或调用平台 API。
涉及加密、存储、导入、同步或会话锁定的修改必须补充针对性测试。

更详细的边界说明见 [`docs/architecture.md`](docs/architecture.md)。
