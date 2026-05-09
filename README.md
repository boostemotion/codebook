# Cipherbook（密码本）

本项目是一个本地优先的多端密码库，当前重点支持 Android 与 Windows。  
核心特性：本地加密存储、导入导出（`.pwv`）、合并预览、TOTP、自动锁定、快速解锁（生物/DPAPI）。

## 功能概览

- 本地加密密码库（主密码解锁）
- 条目管理：新增、编辑、删除、搜索、复制
- TOTP（支持 Base32 密钥和 `otpauth://` URI）
- 导入/导出加密备份（`.pwv`）
- 导入预览与合并摘要
- 主密码修改（重包裹 DEK）
- 快速解锁
  - Android：Biometric + Android Keystore
  - Windows：DPAPI

## 项目结构

- `lib/`：Flutter 业务代码
- `lib/ui/`：界面与交互
- `lib/state/`：状态与控制器
- `lib/services/`：加密、存储、导入导出等服务
- `test/`：单元与流程测试
- `android/`：Android 宿主工程
- `windows/`：Windows 宿主工程

## 开发与验证

在项目根目录执行：

```powershell
flutter pub get
flutter analyze lib test
flutter test
```

## Android 使用

### 构建

```powershell
flutter build apk --debug
flutter build apk --release
```

输出：

- `build/app/outputs/flutter-apk/app-debug.apk`
- `build/app/outputs/flutter-apk/app-release.apk`

### ADB 安装与启动

```powershell
adb devices
adb install -r build\app\outputs\flutter-apk\app-release.apk
adb shell monkey -p com.example.cipherbook -c android.intent.category.LAUNCHER 1
```

### 首次使用建议

1. 创建主密码（建议高强度随机密码）
2. 立即导出一份 `.pwv` 备份
3. 再开启快速解锁（可选）

## Windows 使用

### 运行与构建

```powershell
flutter run -d windows
flutter build windows --release
```

输出目录：

- `build\windows\x64\runner\Release\`

## 加密设计（简述）

- KDF：Argon2id（当前参数：`memory=64MB, iterations=3, parallelism=1`）
- 对称加密：XChaCha20-Poly1305（AEAD）
- 分层密钥：
  - 主密码 -> 派生 KEK
  - 随机 DEK 加密实际数据
  - DEK 使用 KEK 包裹存储

说明：本设计能有效抵抗离线穷举，但安全性仍依赖主密码强度与设备安全。

## 已知事项

### 1) 中文路径下的 Release 构建问题

若工程路径包含中文，Flutter AOT 在少数环境会出现 `app.dill` 读取失败。  
建议将构建副本放到纯英文路径（如 `C:\temp\cipherbook_release_build`）后再构建 release。

### 2) Debug 模式数据保护

调试模式下的“测试数据 seed”已增加保护：若检测到本地已有密码库，不会覆盖现有数据。

## 安全建议

- 不要把主密码保存到聊天工具、截图或明文笔记
- 导出备份建议至少保留 1 份离线副本
- 主密码丢失后无法恢复数据（无后门）
- 复制到剪贴板的数据应尽快清理（应用已做自动清理）

## 常见问题

### 1) 解锁失败但确认密码正确

- 先确认安装的是同一套数据对应的应用包
- 如之前经历过 debug 覆盖，可重建新库并恢复备份
- 无备份且库已被覆盖时，旧数据无法恢复

### 2) `adb` 不可用

将 Android SDK `platform-tools` 加入 PATH，或使用完整路径执行 `adb.exe`。

### 3) Release 比 Debug 更流畅吗？

是。Debug 有额外调试开销，性能评估应以 Release 为准。
