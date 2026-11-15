# 界面设计与截图

本目录只保留当前有效的视觉说明和回归截图。开发过程里的 builder task、review round、
QA 临时报告不作为长期文档；视觉事实以代码令牌、测试和这里的最终截图为准。

## 视觉基线

- 主题和尺寸常量：`lib/presentation/theme/cipherbook_visual_tokens.dart`
- Shell 与导航：`lib/presentation/shell/`
- 共享密码详情：`lib/presentation/shared/password_inspector.dart`
- 仪表盘：`lib/presentation/dashboard/dashboard_page.dart`
- 分类工作台：`lib/presentation/categories/category_workbench.dart`

## 截图集

### 分类工作台

[`frontend-v2/category-workbench-v2/screenshots/`](frontend-v2/category-workbench-v2/screenshots/)

覆盖 1440、768 和 375 宽度，以及空分类、详情、Windows 484×953 窄窗口和列表滚动到底状态。
对应测试：`test/category_workbench_screenshot_test.dart`。

### 手机分类对齐

[`frontend-v2/mobile-category-alignment/screenshots/`](frontend-v2/mobile-category-alignment/screenshots/)

记录“全部密码”和“分类”页在手机上的左基线、搜索框、筛选条和密码列表对齐。
对应测试：`test/mobile_category_alignment_screenshot_test.dart`。

### 密码详情

[`frontend-v2/password-detail-2026-11-14/screenshots/`](frontend-v2/password-detail-2026-11-14/screenshots/)

覆盖桌面与手机详情、稀疏/完整数据、同分类列表以及复制账号和密码后的原位成功状态。
对应测试：`test/password_inspector_screenshot_test.dart`。

### 响应式视觉刷新

[`frontend-v2/visual-refresh-2026-11-14/screenshots/`](frontend-v2/visual-refresh-2026-11-14/screenshots/)

覆盖 1440、1024、768 和 375 宽度下的主要页面。仪表盘可点击条目统一使用 48px 行高，
顶部概览背景完整跨越相邻分隔线。
对应测试：`test/frontend_visual_refresh_screenshot_test.dart`。

## 更新截图

只有确认界面变化符合设计要求后才更新基线：

```powershell
flutter test --no-pub --update-goldens test\frontend_visual_refresh_screenshot_test.dart
flutter test --no-pub --update-goldens test\category_workbench_screenshot_test.dart
flutter test --no-pub --update-goldens test\mobile_category_alignment_screenshot_test.dart
flutter test --no-pub --update-goldens test\password_inspector_screenshot_test.dart
```

截图不得包含真实密码、TOTP 密钥、设备 token、主密码或 Bitwarden 明文导出。
