# 发布流程

## 版本规则

`pubspec.yaml` 的 `version: 主版本.次版本.补丁版本+构建号` 是 Android、Windows 和安装包的唯一版本来源。

- 修复问题：递增补丁版本；
- 新增兼容功能：递增次版本；
- 不兼容变更：递增主版本，并补充迁移说明；
- 每次重新打包都必须递增构建号。

当前版本为 `1.3.0+5`。仅修改文档也应先确认是否需要发版；若二进制没有变化，不必只为文档递增构建号。

## 发布前检查

1. 确认 `README.md`、`CHANGELOG.md`、`docs/` 与实际功能一致。
2. 确认 `pubspec.yaml` 版本和构建号已更新。
3. 确认没有提交密钥、真实密码库、Bitwarden 明文导出、`build/` 或 `dist/`。
4. 执行静态分析和完整测试。
5. 构建 Android 与 Windows Release。
6. 生成安装包，记录大小和 SHA-256。
7. 在至少一台 Android 设备和一台 Windows 机器上验证启动、解锁、保存和升级。
8. 检查 Git 差异，再提交并推送。

### 自动检查

```powershell
$env:PUB_CACHE = 'D:\DevTools\pub-cache'
flutter analyze --no-pub lib test
flutter test --no-pub
```

## Android Release

```powershell
$env:ANDROID_HOME = 'D:\DevTools\android-sdk'
$env:JAVA_HOME = 'D:\DevTools\jdk-17'
$env:PUB_CACHE = 'D:\DevTools\pub-cache'
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"
flutter build apk --release --no-pub
```

构建成功后复制为版本化名称：

```powershell
Copy-Item `
  -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' `
  -Destination 'dist\Cipherbook-1.3.0+5-android.apk' `
  -Force
```

覆盖安装验证：

```powershell
$adb = 'D:\DevTools\android-sdk\platform-tools\adb.exe'
& $adb install -r 'dist\Cipherbook-1.3.0+5-android.apk'
& $adb shell dumpsys package com.example.cipherbook |
  Select-String -Pattern 'versionName=|versionCode='
```

## Windows Release

```powershell
cmd.exe /d /s /c ""D:\DevTools\VisualStudio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul && set "PUB_CACHE=D:\DevTools\pub-cache" && flutter build windows --release --no-pub"
```

生成 IExpress 安装包：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File packaging\windows\build_installer.ps1
```

打包脚本会验证 EXE 的 `FileVersion` 与 `pubspec.yaml` 一致。当前产物：

```text
dist\Cipherbook-1.3.0+5-windows-setup.exe
```

安装器行为：

- 首次安装由用户选择目录；
- 后续升级读取注册表、开始菜单和桌面快捷方式定位原安装目录；
- 检测 `cipherbook.exe` 是否正在运行；
- 等待 IExpress 输出大小稳定后才返回成功。

## 产物校验

```powershell
Get-Item `
  'dist\Cipherbook-1.3.0+5-android.apk', `
  'dist\Cipherbook-1.3.0+5-windows-setup.exe' |
  Select-Object FullName, Length, LastWriteTime

Get-FileHash -Algorithm SHA256 `
  'dist\Cipherbook-1.3.0+5-android.apk', `
  'dist\Cipherbook-1.3.0+5-windows-setup.exe'
```

## Git 提交与推送

```powershell
git status --short
git diff --check
git diff
git add README.md CHANGELOG.md docs lib test pubspec.yaml
git commit -m "Document current password vault release"
git push origin main
```

`dist/` 和 `build/` 已被 `.gitignore` 排除。需要公开下载时，应把版本化安装包附到对应 GitHub Release，
不要强制加入 Git 历史。

## 正式发布前的阻断项

当前构建仍属于本地测试发布：

- Android `applicationId` 是 `com.example.cipherbook`；
- Android Release 使用 debug 签名；
- Windows 安装包没有正式代码签名；
- 没有公开 CI 产物校验和自动发布流水线；
- Flutter 已提示未来需要升级 Gradle、AGP 和 Kotlin 版本。

在解决签名、唯一应用 ID、依赖升级和发布自动化之前，不应把当前 APK 描述为可公开发布的正式商店版本。
