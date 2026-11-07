# Cipherbook 架构

## 设计目标

Cipherbook 是本地优先的单机密码库。核心目标是：

1. 没有云端账号时也能完整使用；
2. 密码库文件离开设备前始终是加密文档；
3. 多设备同步不依赖中心服务器；
4. UI 不直接处理密钥、文件或网络协议；
5. 加密、存储和同步失败时优先保留可用副本，不静默覆盖最后一个有效密码库。

## 分层

```text
Flutter UI
  -> VaultController
     -> CryptoService
     -> VaultRepository
     -> ImportExportService / BitwardenInterchangeService
     -> LanSyncService / LanPairingStore
     -> DeviceKeyStore / QuickUnlockPreferenceStore
```

- `lib/models/`：密码库文档、条目、KDF、同步状态和 Bitwarden 交换模型。
- `lib/services/`：无 UI 的加密、文件、导入导出、TOTP、网络的平台适配逻辑。
- `lib/state/`：`VaultController` 编排解锁、锁定、写操作、同步和导入计划。
- `lib/ui/`：Android / Windows 自适应界面，只调用控制器公开接口。
- `android/`、`windows/`：平台桥接。系统认证和本地密钥包装不进入 Widget。

`main.dart` 创建 `CipherbookApp`，应用在启动时装配具体服务，并把同一个
`VaultController` 注入 `HomePage`。UI 通过 `ChangeNotifier` 观察状态。

## 会话模型

`VaultController` 只持有当前内存会话：

- 解密后的 `VaultData`；
- 256 位 DEK 和 KEK；
- 当前自动锁定计时器；
- 快速解锁状态；
- 单调递增的 session generation。

锁定会清空条目、DEK、KEK 和局域网分享状态。异步操作在返回后必须通过
session generation 校验；如果在下载、保存或导入期间发生了锁定，旧会话的结果会被丢弃，
不会把明文重新写回已锁定的控制器。

默认自动锁定时间为 2 分钟，设置页可选择 1、2、5 或 15 分钟。该设置只在当前应用会话中生效。
应用进入后台或窗口隐藏时，控制器还会根据生命周期主动锁定并停止局域网监听。

## 加密与文件格式

当前密码库文档版本为 `2`，同时保留旧版 `1` 的读取兼容逻辑。

### 密钥链

```text
主密码
  -> Argon2id(password, random salt)
  -> KEK（32 字节）

随机生成 DEK（32 字节）
  -> 使用 KEK + XChaCha20-Poly1305 包装

VaultData JSON
  -> 使用 DEK + XChaCha20-Poly1305 加密
```

默认 Argon2id 参数：

- 内存：64 MiB；
- 迭代：3；
- 并行度：1；
- 盐：16 字节随机值。

文档使用领域分离的 AAD 绑定密码库 ID、key generation 和 revision。修改主密码时会生成
新的盐、KEK 和 DEK，并递增 metadata 中的 key generation。

### 存储

`VaultRepository` 把当前密码库保存到应用支持目录的 `vault.pwv`。写入流程是：

1. 串行化所有写操作；
2. 写入临时文件并 flush；
3. 把现有有效主文件重命名为 `.bak`；
4. 把临时文件原子替换为主文件；
5. 启动或读取时验证主文件、备份和临时恢复候选。

只有通过完整解码和格式校验的候选才会被使用。损坏文件会被隔离为带后缀的副本；
可疑或未通过验证的候选不会直接替换主文件。文件大小和条目字段都有明确上限。

## 快速解锁

快速解锁缓存的是经过设备能力保护的 KEK，不是主密码，也不会把明文 DEK 写入普通文件。

- Windows：使用当前用户 DPAPI 保护缓存；读取缓存前必须通过 Windows Hello 验证。
- Android：使用 Android Keystore 中的 AES-GCM 密钥，密钥要求强生物识别认证；
  生物识别录入变化会使旧密钥失效。
- 开关默认关闭。只有用户主动开启后，冷启动才能直接请求系统认证。
- `QuickUnlockPreferenceStore` 只保存布尔开关。若系统认证不可用、被取消或密钥失效，
  仍必须输入主密码。

快速解锁可以在设置中关闭；关闭时会删除设备包装密钥，并清除冷启动直接解锁偏好。

## 局域网同步

局域网同步由两部分组成：

- UDP 广播发现：固定发现端口 `45821`；
- 随机本地 HTTP 端口：传输已经加密的 `.pwv` 文档。

设备在未锁定时启动一个临时 HTTP 分享端，并广播设备名、密码库 ID、版本、
KDF 参数和一次性 challenge。发现端不会广播主密码。

同步步骤：

1. 使用共同主密码在本机派生 KEK；
2. 对 challenge 计算 HMAC-SHA256，作为不泄露主密码的验证证明；
3. 下载对端加密文档，在本机验证密码库格式和主密码；
4. 对每台已验证设备执行 `VaultData.merge`；
5. 将合并后的加密文档写回对端；
6. 保存设备 token，供同一密码库的已配对设备在前台执行低频自动同步。

合并以条目 ID、更新时间和删除标记为基础，逐端收集再广播，因此 A 有而 B 没有、
B 有而 A 没有的条目都可以进入最终合集。网络请求不在全局写锁内等待对端，
避免两台设备同时发起同步时互相死锁。

局域网同步的限制：

- Android 只保证应用前台且解锁时可用；
- 端口用于局域网，不应暴露到公网；
- 当前没有中心服务器、远端冲突仲裁或跨网段穿透；
- 同步上限为 16 MiB 加密文档。

## Bitwarden 桥接

`BitwardenInterchangeService` 只处理未加密 JSON/CSV 交换文件，不把 Bitwarden 云端 API
或加密 JSON 当作依赖。单次导入最多 10,000 条。

导入时支持：

- 登录项和安全笔记；
- 文件夹、收藏、TOTP；
- `cipherbook_id` 自定义字段，用于回写来源 ID；
- 账号文本中的邮箱和手机号别名。

重复判断是启发式的，不是自动合并策略。应用可能依据来源 ID、同网站、账号别名、
标题、密码和 TOTP 生成候选；当多个本机条目得分相同时，会禁止自动替换并要求人工核验。
默认动作是“两边都保留”。

导出为 Bitwarden JSON/CSV 是明文操作，需要二次确认。当前不支持额外网址、任意自定义字段、
Passkey、附件、银行卡、身份资料、Collections、密码历史和重新输入主密码保护。

## 导入和错误处理

- 所有导入先形成带 session generation 和 revision 的计划；
- 预览后如果密码库变化，计划失效并要求重新预览；
- 写入失败时保留旧内存状态，不把 UI 更新成未落盘的数据；
- 局域网部分失败会报告成功设备数和失败数，可再次重试；
- 文件恢复、加密和同步错误不得输出主密码、TOTP 密钥或明文凭据。

## 测试边界

`test/` 覆盖加密文档、KDF 参数、仓库恢复、导入导出、Bitwarden 解析与匹配、局域网合并、
锁定竞态、快速解锁和主要 UI 流程。涉及以下区域的修改必须补充针对性测试：

- 密钥生成、包装或主密码变更；
- 文件恢复和删除；
- 条目合并、导入计划或 revision 校验；
- session generation、生命周期锁定和异步竞态；
- 局域网认证和写入；
- Bitwarden 文件格式或重复匹配规则。

## 修改规则

1. 业务逻辑放在 `services` 或 `state`，Widget 不直接读写密钥、文件或网络。
2. 新平台能力通过 `lib/services/` 的抽象和宿主桥接实现，并保留无平台环境的测试实现。
3. 不提交生成的 `build/`、`dist/`、签名密钥或本地设备身份。
4. 安全相关改动必须说明威胁变化，不能只验证“界面可以打开”。
5. 文档、`CHANGELOG.md`、版本号和发布产物必须在同一个发布流程中对齐。
