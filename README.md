# 密码本 Cipherbook

本项目是一个本地优先的多端加密密码本，当前 Android 端已经可以命令行构建、安装和运行。数据文件、导入文件、导出文件都按加密密码库格式保存。

## Android 当前状态

- 已生成 Flutter Android 宿主工程：`android/`
- 已支持 Android release APK 构建
- 已支持中文界面和 Flutter 中文本地化
- 已在 Android 原生层优先选择当前分辨率下的最高刷新率显示模式
- 已实现本地加密密码库、加密导入导出、导入预览、合并、主密码修改、搜索、密码生成、剪贴板自动清除、自动锁定、TOTP 验证码
- 当前 release APK 输出位置：`build/app/outputs/flutter-apk/app-release.apk`

## Android 使用方法

### 安装和打开

先安装 release APK：

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' install -r 'D:\Z_work\密码\build\app\outputs\flutter-apk\app-release.apk'
```

安装后可以从手机桌面打开 `密码本`，也可以用命令启动：

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' shell monkey -p com.example.cipherbook -c android.intent.category.LAUNCHER 1
```

### 第一次创建密码库

1. 打开应用。
2. 在 `主密码` 输入框中输入一个足够长的主密码。
3. 点击 `创建密码库`。
4. 主密码不会保存到本地，忘记后无法恢复密码库内容。

建议主密码至少 12 位以上，并使用短语、大小写、数字或符号组合。

### 解锁本地密码库

1. 打开应用。
2. 输入创建密码库时设置的主密码。
3. 点击 `解锁`。

如果密码错误，应用不会解密本地密码库。

### 新增或编辑密码条目

解锁后点击 `新增条目`。

可填写字段：

- `名称`：例如 GitHub、邮箱、银行卡。
- `账号`：登录用户名或邮箱。
- `密码`：该条目的密码。
- `生成长度`：点击 `生成` 可生成随机密码。
- `网址`：登录网站地址。
- `TOTP 密钥或 otpauth URI`：二次验证码密钥，可填 Base32 密钥或认证器导出的 `otpauth://` URI。
- `标签，用逗号分隔`：例如 `工作,重要`。
- `备注`：记录额外信息。

保存后条目会写入本地加密密码库文件。

### 搜索、查看和复制

- 在 `搜索条目` 输入关键字，可以按名称、账号、网址、备注、标签搜索。
- 点击条目右侧的查看图标可以查看详情。
- 点击复制图标可以复制密码或 TOTP 验证码。
- 复制到剪贴板后会自动清除，降低泄露风险。

### 使用 TOTP 验证码

在条目里填写 `TOTP 密钥或 otpauth URI` 后，查看详情时会显示动态验证码。

支持两种输入：

```text
JBSWY3DPEHPK3PXP
```

或：

```text
otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=6&period=30
```

验证码会按周期刷新，可以点击复制当前验证码。

### 导出加密备份

解锁后点击 `导出备份`。

导出时有两种方式：

- `导出密码` 留空：导出文件沿用当前密码库的加密配置。
- 填写 `导出密码`：导出文件会用新的导出密码重新加密。

导出文件扩展名为 `.pwv`。这个文件仍然是加密文件，可以复制到电脑、网盘或另一台手机保存。

### 导入备份

没有本地密码库时：

1. 在启动页输入 `导入文件密码`。
2. 点击 `导入为本地密码库`。
3. 选择 `.pwv` 加密备份文件。
4. 查看导入预览，确认后导入。

已有本地密码库时：

1. 先解锁本地密码库。
2. 点击 `导入并合并`。
3. 输入导入文件密码。
4. 选择 `.pwv` 文件。
5. 查看导入预览。
6. 点击 `导入` 合并到当前密码库。

合并规则基于条目 ID、更新时间和删除标记。导入前会显示新增、更新、删除、跳过的数量和变更条目列表。

### 修改主密码

1. 解锁密码库。
2. 点击 `修改主密码`。
3. 输入当前主密码。
4. 输入新主密码。
5. 点击 `保存`。

修改主密码会重新包装数据加密密钥，不需要重新加密每个条目的明文数据。

### 快速解锁

界面中有 `开启快速解锁` / `快速解锁` 按钮。

当前 Dart 侧流程已经存在，但 Android Keystore 原生桥还需要继续完善。因此这部分现在属于开发中功能，不应作为唯一解锁手段。继续保管好主密码。

### 锁定和自动锁定

- 点击右上角锁图标可手动锁定。
- 应用进入后台或长时间无操作会自动锁定。
- 锁定后需要主密码或可用的快速解锁流程重新打开。

### 备份和恢复建议

- 定期使用 `导出备份` 保存 `.pwv` 文件。
- 至少保留一份离线备份，例如电脑或 U 盘。
- 如果为导出文件设置了单独导出密码，请同时安全记录该密码。
- 丢失主密码或导出密码后，当前设计不提供后门恢复。

## 加密设计简述

- 主密码不直接加密所有数据，而是通过 Argon2id 派生 KEK，也就是 key encryption key。
- 每个密码库有随机 DEK，也就是 data encryption key，用于加密实际密码库内容。
- DEK 会被 KEK 包装加密后存储。
- 密码库内容使用 AEAD 加密，并带 AAD 校验，防止密文被静默篡改。
- 导出文件仍是加密格式，可以选择继续使用当前密码库加密，也可以为导出文件单独设置导出密码。

## Windows 电脑继续开发 Android 端需要的环境

推荐全部走命令行，不依赖 Android Studio 图形界面。

### 必需工具

1. Flutter SDK

当前本机使用的 Flutter SDK 路径：

```powershell
C:\Users\opena\.codex\memories\flutter-sdk
```

常用命令：

```powershell
& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' --version
& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' doctor
```

2. Android SDK

当前本机 Android SDK 路径：

```powershell
C:\Users\opena\AppData\Local\Android\Sdk
```

ADB 路径：

```powershell
C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe
```

如果 `adb` 不能直接识别，用完整路径执行：

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' devices
```

3. JDK

当前项目使用 Android Studio 自带 JBR：

```powershell
C:\Program Files\Android\Android Studio\jbr
```

项目已在 `android/gradle.properties` 中固定：

```properties
org.gradle.java.home=C:/Program Files/Android/Android Studio/jbr
```

如果换电脑开发，需要安装 Android Studio 或单独安装 JDK 17，并把这里改成实际 JDK 路径。

4. Git

Flutter 工具链会调用 Git。换电脑后确认：

```powershell
git --version
```

## 项目关键路径

- Flutter 业务代码：`lib/`
- Flutter 测试：`test/`
- Android 宿主工程：`android/`
- Android 主 Activity：`android/app/src/main/kotlin/com/example/cipherbook/MainActivity.kt`
- Android 应用清单：`android/app/src/main/AndroidManifest.xml`
- Debug APK：`build/app/outputs/flutter-apk/app-debug.apk`
- Release APK：`build/app/outputs/flutter-apk/app-release.apk`

## 首次检查环境

在项目根目录执行：

```powershell
$env:GIT_CONFIG_GLOBAL='D:\Z_work\密码\.gitconfig.flutter'
$env:PUB_CACHE='D:\Z_work\密码\.pub-cache'
$env:APPDATA='D:\Z_work\密码\.appdata'
$env:LOCALAPPDATA='D:\Z_work\密码\.localappdata'
$env:USERPROFILE='D:\Z_work\密码\.userprofile'
$env:HOME='D:\Z_work\密码\.home'

& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' doctor
& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' pub get
```

这些环境变量的作用是把 Flutter/Dart 的缓存和配置尽量限制在项目附近，减少污染用户全局目录。

## 运行测试和静态检查

```powershell
$env:GIT_CONFIG_GLOBAL='D:\Z_work\密码\.gitconfig.flutter'
$env:PUB_CACHE='D:\Z_work\密码\.pub-cache'
$env:APPDATA='D:\Z_work\密码\.appdata'
$env:LOCALAPPDATA='D:\Z_work\密码\.localappdata'
$env:USERPROFILE='D:\Z_work\密码\.userprofile'
$env:HOME='D:\Z_work\密码\.home'

& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\dart.bat' format lib test
& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' analyze lib test
& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' test
```

当前已验证：

- `flutter analyze lib test` 通过
- `flutter test` 通过，22 个测试

## 构建 Android APK

### Debug 包

Debug 包用于开发调试，不适合判断手机流畅度。Flutter debug 模式会明显更卡。

```powershell
$env:GIT_CONFIG_GLOBAL='D:\Z_work\密码\.gitconfig.flutter'
$env:PUB_CACHE='D:\Z_work\密码\.pub-cache'
$env:APPDATA='D:\Z_work\密码\.appdata'
$env:LOCALAPPDATA='D:\Z_work\密码\.localappdata'
$env:USERPROFILE='D:\Z_work\密码\.userprofile'
$env:HOME='D:\Z_work\密码\.home'

& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' build apk --debug
```

输出：

```powershell
build\app\outputs\flutter-apk\app-debug.apk
```

### Release 包

Release 包用于真实手机体验和流畅度判断。

```powershell
$env:GIT_CONFIG_GLOBAL='D:\Z_work\密码\.gitconfig.flutter'
$env:PUB_CACHE='D:\Z_work\密码\.pub-cache'
$env:APPDATA='D:\Z_work\密码\.appdata'
$env:LOCALAPPDATA='D:\Z_work\密码\.localappdata'
$env:USERPROFILE='D:\Z_work\密码\.userprofile'
$env:HOME='D:\Z_work\密码\.home'

& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' build apk --release
```

输出：

```powershell
build\app\outputs\flutter-apk\app-release.apk
```

## 中文路径注意事项

当前项目路径包含中文：

```powershell
D:\Z_work\密码
```

Flutter debug 构建通常可用，但 Windows 上 release AOT 构建可能因为中文路径解析问题失败。当前解决方式是在 ASCII 路径维护一个构建副本：

```powershell
C:\Users\opena\.codex\memories\cipherbook-release-src
```

如果在原项目路径构建 release 报类似 `D:\Z_work\����` 或 `.dart_tool\flutter_build` 路径错误，可以复制源码到 ASCII 路径后构建：

```powershell
$root='C:\Users\opena\.codex\memories\cipherbook-release-src'
New-Item -ItemType Directory -Force -Path $root | Out-Null
Copy-Item -Recurse -Force -LiteralPath 'D:\Z_work\密码\android' -Destination $root
Copy-Item -Recurse -Force -LiteralPath 'D:\Z_work\密码\lib' -Destination $root
Copy-Item -Recurse -Force -LiteralPath 'D:\Z_work\密码\test' -Destination $root
Copy-Item -Force -LiteralPath 'D:\Z_work\密码\pubspec.yaml' -Destination $root
Copy-Item -Force -LiteralPath 'D:\Z_work\密码\pubspec.lock' -Destination $root
Copy-Item -Force -LiteralPath 'D:\Z_work\密码\analysis_options.yaml' -Destination $root
```

然后在副本目录构建：

```powershell
$env:GIT_CONFIG_GLOBAL='D:\Z_work\密码\.gitconfig.flutter'
$env:PUB_CACHE='D:\Z_work\密码\.pub-cache'
$env:APPDATA='D:\Z_work\密码\.appdata'
$env:LOCALAPPDATA='D:\Z_work\密码\.localappdata'
$env:USERPROFILE='D:\Z_work\密码\.userprofile'
$env:HOME='D:\Z_work\密码\.home'

& 'C:\Users\opena\.codex\memories\flutter-sdk\bin\flutter.bat' build apk --release
```

构建成功后复制回原项目：

```powershell
Copy-Item -Force `
  -LiteralPath 'C:\Users\opena\.codex\memories\cipherbook-release-src\build\app\outputs\flutter-apk\app-release.apk' `
  -Destination 'D:\Z_work\密码\build\app\outputs\flutter-apk\app-release.apk'
```

## 安装到 Android 手机

### 手机准备

1. 打开开发者选项。
2. 打开 USB 调试。
3. 用数据线连接电脑。
4. 手机弹出授权时选择允许 USB 调试。

检查设备：

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' devices
```

正常会看到类似：

```text
List of devices attached
3a5aca7b    device
```

如果状态是 `unauthorized`，看手机屏幕确认授权。

### 安装 release 包

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' install -r 'D:\Z_work\密码\build\app\outputs\flutter-apk\app-release.apk'
```

### 启动应用

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' shell monkey -p com.example.cipherbook -c android.intent.category.LAUNCHER 1
```

## 流畅度和 120Hz 测试

不要用 debug 包判断流畅度。请安装 release 包后再测。

本项目 Android 原生层会优先选择当前分辨率下设备支持的最高刷新率，代码在：

```text
android/app/src/main/kotlin/com/example/cipherbook/MainActivity.kt
```

如果 release 包仍然卡，可以抓 Android 帧耗时：

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' shell dumpsys gfxinfo com.example.cipherbook framestats
```

也可以查看设备连接和进程状态：

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' shell pidof com.example.cipherbook
```

## Android 端后续开发重点

- 接入 Android Keystore，实现真正设备绑定的快速解锁原生桥。
- 为 release 包配置正式签名，不再使用 debug key 签 release。
- 增加 Android 仪器测试或集成测试，覆盖导入、导出、锁定、解锁等关键流程。
- 做一次真机 profile，定位大列表、TOTP 刷新、弹窗等场景是否还有掉帧。
- 完善应用图标、启动页和正式包名。

## 常见问题

### `JAVA_HOME is not set`

说明当前 shell 找不到 Java。当前项目优先使用 `android/gradle.properties` 中的：

```properties
org.gradle.java.home=C:/Program Files/Android/Android Studio/jbr
```

如果这条路径不存在，需要安装 Android Studio 或 JDK 17，并修改该路径。

### `adb` 不是可识别命令

说明 Android SDK platform-tools 没有进 PATH。直接使用完整路径：

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' devices
```

### release 构建卡住或中文路径乱码

优先使用上面的 ASCII 构建副本流程。不要在卡住时反复开多个 Gradle 构建，必要时先结束旧的 Java/Dart 构建进程。

### 界面还是英文

确认安装的是最新 release 包，不是旧 debug 包：

```powershell
& 'C:\Users\opena\AppData\Local\Android\Sdk\platform-tools\adb.exe' install -r 'D:\Z_work\密码\build\app\outputs\flutter-apk\app-release.apk'
```
