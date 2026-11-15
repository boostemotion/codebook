# 前端架构

## 当前状态

Cipherbook 默认使用 Prism 前端，入口为 `CipherbookPrismApp`。旧 Material 界面仍保留在
`lib/ui/`，仅作为临时回退：

```powershell
flutter run -d windows --dart-define=CIPHERBOOK_FRONTEND_V2=false
```

日常开发、截图基线和发布验证都以 Prism 前端为准。旧界面不继续扩展新功能。

## 目录

```text
lib/presentation/
  app/         应用入口、页面目的地、主题和本地化
  bridge/      Riverpod 与 VaultController 的连接
  dashboard/   仪表盘和统计
  vault/       全部密码、搜索、排序和编辑器
  categories/  分类工作台与拖动归类
  security/    重复密码和弱密码检查
  sync/        局域网设备同步
  tools/       工具入口
  unlock/      解锁、创建和恢复入口
  shared/      密码详情、列表行等共享组件
  theme/       可视化令牌、图标和主题

packages/prism_shell/  响应式应用壳、导航和页面保持
plugins/prism_ui/      Prism 组件、动效、形状和主题
```

`prism_shell` 只负责展示层壳结构，不包含产品数据、网络、文件或平台服务。
`prism_ui` 是需要随仓库一起构建的本地路径依赖，不能改成相邻工作区绝对路径。

## 数据与安全边界

```text
Prism Widget
  -> Riverpod provider / page controller
  -> VaultController
  -> services + platform bridges
```

- Widget 不直接读取 `vault.pwv`、密钥、设备 token 或网络端口。
- 所有解锁、保存、导入、同步和快速解锁操作继续调用 `VaultController` 的公开接口。
- 锁定、session generation、revision 和加密文件格式与前端框架无关。
- 前端迁移不修改密码库磁盘格式，也不会自动创建、覆盖或迁移用户数据目录。

## 页面结构

| 页面 | 主要职责 |
| --- | --- |
| 仪表盘 | 密码数量、安全统计、最近修改、分类分布和同步状态 |
| 全部密码 | 搜索、筛选、排序、列表/详情、复制、收藏和编辑 |
| 分类 | 分类筛选、密码详情、拖动密码归类和分类排序 |
| 密码检查 | 重复密码、基础弱密码和对应条目 |
| 设备同步 | 局域网发现、主密码验证、双向合并和同步结果 |
| 工具 | 导入导出、Bitwarden 桥接、快速解锁和设置入口 |

Windows 使用侧栏和分栏详情；Android 使用底部导航以及列表到详情的页面流。断点规则和视觉
令牌分别位于 `lib/presentation/shell/` 与 `lib/presentation/theme/`。

## 验证

```powershell
dart format lib test
flutter analyze --no-pub lib test
flutter test --no-pub
```

响应式截图和鼠标状态由以下测试维护：

- `test/frontend_visual_refresh_screenshot_test.dart`
- `test/category_workbench_screenshot_test.dart`
- `test/mobile_category_alignment_screenshot_test.dart`
- `test/password_inspector_screenshot_test.dart`

截图索引见 [`design/README.md`](design/README.md)。

## 上游与许可证

Prism 前端工作台，固定参考提交为
`fbe52d985c47e67c71f6f2feb703338bbaf10f75`。`packages/prism_shell/` 和
`plugins/prism_ui/` 均按 GPL-3.0 提供；`prism_ui` 还包含 Apache-2.0、MIT 和 BSD-3-Clause
适配代码。完整归属见 [`../THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)。

当前根项目尚未声明一个统一的整体许可证。发布二进制或把前端用于其他产品前，必须先确认
GPL-3.0 与项目的整体许可方案，不能仅凭仓库公开状态视为已完成许可审查。
