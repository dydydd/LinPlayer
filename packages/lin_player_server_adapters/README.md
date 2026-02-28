# lin_player_server_adapters

`lin_player_server_adapters` 是 LinPlayer 的**服务端适配层（Adapter Layer）**：用统一接口屏蔽不同服务端/不同产品差异，让 UI 只依赖抽象接口而不是具体 API 实现。

## 解决什么问题
- UI 不需要知道“这个请求到底是 EmbyApi 还是别的实现”。
- 当后期新增/替换服务端实现时，只需要新增 adapter 并在 factory 收口，避免在 UI 里散落 `if/else`。
- 便于做 Feature Flags：决定“哪些服务器类型可用/哪些入口可见”，但不污染 UI 业务逻辑。

## 主要内容
- `server_adapters/server_adapter.dart`
  - `MediaServerAdapter`：统一的服务端能力接口（认证、拉媒体库/列表、播放信息、上报等）。
  - `ServerAuthSession`：认证会话（token/baseUrl/userId/apiPrefix 等）。
- `server_adapters/server_adapter_factory.dart`
  - `ServerAdapterFactory`：按 `AppConfig.current.product` 选择具体 adapter，实现“差异收口点”。
- `server_adapters/lin/lin_emby_adapter.dart`
  - 当前主实现：基于 `EmbyApi` 的 adapter（同时覆盖 Emby/Jellyfin）。
- `server_adapters/uhd/*`
  - 目前为占位/复用实现（后续可按需要替换为真正实现）。

## 不放什么（边界）
- 不放 UI（Widget/页面）。
- 不放持久化/状态管理（`AppState`、`ServerProfile` 等在主工程或其它模块）。
- 不直接处理“平台专属能力”（例如 Android TV 内置代理），这些应在平台模块收口。

## 使用方式（在主工程里）
```dart
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_core/state/media_server_type.dart';

final adapter = ServerAdapterFactory.forLogin(
  serverType: MediaServerType.emby,
  deviceId: 'device-1',
);
```

## 新增服务端/能力的建议流程
1. 先在 `MediaServerAdapter` 里补齐“UI 真正需要”的最小接口（不要为了未来一次性加太多）。
2. 为新服务端实现一个 adapter（可内部复用 `lin_player_server_api` 的某个 API 客户端）。
3. 在 `ServerAdapterFactory` 统一选择与注入（保持 UI 侧无感）。

