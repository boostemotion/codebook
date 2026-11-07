# 开发与构建

## 环境要求

项目声明的最低 Dart 版本见 `pubspec.yaml`。当前验证环境为：

- Flutter `3.47.5` stable；
- Dart `3.13.4`；
- Java 17；
- Android SDK；
- Windows 10/11 SDK；
- Visual Studio 2022 Build Tools（安装“使用 C++ 的桌面开发”工作负载）。

在 Windows 开发机上，Flutter、JDK、Android SDK 和 Visual Studio Build Tools
可统一放在 `D:\DevTools`。具体目录不影响源码，但命令中需要替换为实际路径。

## 获取依赖

```powershell
$env:PUB_CACHE = 'D:\DevTools\pub-cache'
flutter pub get
```

## 静态分析与测试

```powershell
flutter analyze --no-pub lib test
flutter test --no-pub
```

建议优先运行与修改相关的测试文件，例如：

```powershell
flutter test --no-pub test\vault_controller_test.dart
flutter test --no-pub test\bitwarden_interchange_service_test.dart
```

涉及加密、存储、导入、同步、锁定或快速解锁的修改，不允许只做手工界面验证。

## Windows

### 开发运行

```powershell
$env:PUB_CACHE = 'D:\DevTools\pub-cache'
flutter run -d windows
```

### Release 构建

Windows 原生插件需要 MSVC 环境。使用当前机器的 Build Tools 时：

```powershell
cmd.exe /d /s /c ""D:\DevTools\VisualStudio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul && set "PUB_CACHE=D:\DevTools\pub-cache" && flutter build windows --release --no-pub"
```

输出目录：

```text
build\windows\x64\runner\Release\
```

如果 `cl.exe` 不在 `PATH`，先确认 Build Tools 路径，再加载 `vcvars64.bat`。

### 安装包

先完成 Windows Release 构建，再执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File packaging\windows\build_installer.ps1
```

打包脚本会读取 `pubspec.yaml` 的版本，并检查 `cipherbook.exe` 的文件版本是否一致。
IExpress 输出位于 `dist\`，该目录不提交到 Git。

## Android

### 构建 APK

```powershell
$env:ANDROID_HOME = 'D:\DevTools\android-sdk'
$env:JAVA_HOME = 'D:\DevTools\jdk-17'
$env:PUB_CACHE = 'D:\DevTools\pub-cache'
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"
flutter build apk --release --no-pub
```

原始输出：

```text
build\app\outputs\flutter-apk\app-release.apk
```

### ADB 覆盖安装

`adb install -r` 会保留现有应用数据：

```powershell
$adb = 'D:\DevTools\android-sdk\platform-tools\adb.exe'
& $adb devices -l
& $adb install -r dist\Cipherbook-1.3.0+5-android.apk
& $adb shell monkey -p com.example.cipherbook -c android.intent.category.LAUNCHER 1
```

若版本已经变化，请按 `pubspec.yaml` 替换 APK 文件名。

### 已验证限制

- Android 快速解锁只接受强生物识别，不提供设备 PIN/图案回退。
- `MainActivity` 设置了 `FLAG_SECURE`，因此 ADB 截图通常是黑的；这是预期安全行为。
- 局域网同步依赖前台 Multicast Lock，锁屏、锁定或进入后台后会停止分享。

## 调试密码库

Debug 模式可以通过编译参数创建固定测试密码库：

```powershell
flutter run -d windows --dart-define=CIPHERBOOK_SEED_DEBUG_VAULT=true
```

该逻辑只会在 `kDebugMode` 且本地不存在密码库时执行。不要在 Release 构建中依赖它，
也不要把真实凭据放进调试种子。

## 代码约定

- Dart 文件使用 `snake_case.dart`，类名使用 `PascalCase`，方法和变量使用 `lowerCamelCase`。
- 业务逻辑放在 `lib/services/` 或 `lib/state/`，Widget 只负责交互和显示。
- 平台密钥、网络协议、文件路径和剪贴板操作不得直接写进 Widget。
- 不打印主密码、DEK/KEK、TOTP 密钥、Bitwarden 明文导出内容或设备 token。
- 新测试文件必须以 `_test.dart` 结尾。

## 常见问题

### Windows 构建提示找不到 C++ 编译器

确认 Visual Studio Build Tools 的 C++ 组件已安装，并在构建前加载 `vcvars64.bat`。
不要通过覆盖系统级 Flutter/Windows SDK 配置解决路径问题。

### Android 构建提示 Gradle / AGP / Kotlin 即将停止支持

当前 Flutter 工具链会提示升级 Gradle、Android Gradle Plugin 和 Kotlin 版本。
这些预警在 `1.3.0+5` 构建中仍可通过，但发布前应单独完成工具链升级并重新验证
Keystore、Biometric 和局域网插件。

### 局域网只看到一台设备

确认两端：

- 处于同一网段；
- 应用在前台且密码库已解锁；
- 系统未启用限制广播的访客 Wi-Fi / AP 隔离；
- Android 允许应用使用本地网络和 Multicast Lock。
