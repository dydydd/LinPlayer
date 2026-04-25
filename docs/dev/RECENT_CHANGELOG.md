# 最近更新日志（2026-03）

> 根据 `2026-03-01` 到 `2026-03-21` 的近期提交按日期整理。合并提交与重复的下载页版本同步已做归并，重点保留每天实际改了什么。

## 2026-03-21

涉及 commit：`3fba7b8`、`041ca44`、`eb7d0a5`、`c95fe91`、`3ccb3dc`、`b86e1ae`、`0611c99`、`7263ec1`、`b856c8e`、`a4427d6`、`0ed1b40`、`83041af`、`890c5c2`

- 插件宿主 `V1` 明显推进，补齐了插件页宿主、`slot` 区域、运行时策略、远程 URL 解析、注册表管理等链路，并补上 `plugin_runtime_v1`、`plugin_remote_url_v1` 相关测试。
- 首页、详情页、桌面首页与插件页开始更紧密联动，新增宿主动作与治理流程，插件入口从独立页面逐步接入主界面。
- 播放器字幕链路继续增强，`MPV` / `Exo` 播放页、`subtitle_support` 与 Android patched `video_player` 一起调整，重点在字幕轨枚举、渲染和兼容性补强。
- Android / TV 代理相关逻辑继续整理，涉及 `MainActivity`、`built_in_proxy_service`、设备识别与依赖配置，同时清理了一段旧代理逻辑。
- 开发文档同步扩充，新增播放内核优化文档、补写插件宿主文档与开发索引；下载页版本信息也做了同步更新。

## 2026-03-08

涉及 commit：`4247e41`、`8369155`、`713df58`

- 流地址解析链路继续重构，集中修改了 `stream_resolver`、`stream_models`、`stream_redirect_resolver`、`stream_body_link_resolver` 和 `strm_resolver`，重点放在正文提链与重定向识别。
- 本地 HTTP 流代理与服务端代理协作方式增强，`local_http_stream_proxy`、`http_stream_proxy` 以及相关测试一并更新。
- 播放页和设置页开始接入更完整的诊断能力，新增 `app_diagnostics_log`、`app_diagnostics_report`，提升播放失败和代理场景下的可观测性。

## 2026-03-07

涉及 commit：`69840f4`、`b730142`

- `strm` 解析继续深化，新增 `strm_target_parser`、`strm_text_reader`，并继续完善 `strm_resolver` 与统一的流解析模型。
- `MPV` / `Exo` 播放页同步适配新的解析结果，围绕跳转链接、目标地址和播放入口的处理做了后续收口。
- 补充了 `stream_redirect_resolver`、`stream_resolver`、`strm_resolver` 测试，并调整了 `windows/CMakeLists.txt` 以配合桌面端构建。

## 2026-03-06

涉及 commit：`9e7b43b`、`8b2c847`、`98dd68a`、`10d10a9`、`93f1d19`、`005a2ca`、`95fc94e`、`14ec62f`、`c111437`

- 插件系统进入大规模接入阶段，新增或重构了插件页面宿主、`schema` 渲染、插件页、运行时管理与设置页入口，`plugin_manager` 在这一天连续多次调整。
- 桌面首页、播放页、详情页开始接入插件 `slot` 与内容注入能力，插件扩展点从单点实验转向主界面集成。
- 为插件运行补齐依赖与桌面端注册，更新了 `pubspec.yaml` / `pubspec.lock` 以及 Windows、macOS、Linux 的 generated registrant 文件。
- 下载页版本信息做了同步更新。

## 2026-03-05

涉及 commit：`5e95dee`、`2cd4af8`

- `legacy/tv-legacy` 播放器内核继续重构，重点修改 `PlayerActivity`、`IjkPlayerCore`、`PlayerCoreType`、`PlayerCores`、`AppPrefs`，明显围绕多内核切换与播放行为整理。
- `WebDAV`、预加载和当前 Flutter 播放页之间开始联动，`WebDavMediaBackend`、`webdav_browser_page`、`strm_resolver`、`stream_preload_service` 一起更新。
- 旧 TV 工程的 `build.gradle.kts`、`AndroidManifest.xml`、播放器布局也做了同步清理。

## 2026-03-04

涉及 commit：`f130f22`、`a4effbe`、`6ec8227`、`d3a125c`、`041b21f`、`45067fd`、`c0c8687`、`a2403e4`、`c5079ee`

- TV 端内容浏览页继续推进，`Bangumi` / `TMDB` 页面与对应 API 适配层持续调整，首页也跟着更新。
- 播放前预加载与详情页跳转链路增强，`play_network_page`、`play_network_page_native`、`show_detail_page`、`stream_preload_service` 都有联动修改。
- CI / 发布流程有一轮整理，更新了 `build-all.yml`、`release-latest.yml`、`retry.sh` 和相关构建配置。
- 下载页版本信息在这一天有多次同步。

## 2026-03-03

涉及 commit：`17cf16c`、`4e6db36`、`67e8fb4`、`a6f62ff`、`d5a282c`、`4a813cc`、`cb4acad`、`9cf91ce`、`08a5554`、`77d5a6b`、`c803dd4`

- 首页聚合能力大幅扩展，接入了 `Bangumi`、`TMDB`、`IMDb` 相关页面与 API，TV 场景下的首页内容源明显增强。
- `play_network_page` / `play_network_page_native` 在这一天多次迭代，播放入口、参数传递和页面结构都有较大调整。
- 设置页与全局状态继续扩展，补充了代理、TV 遥控、服务页相关状态与入口。
- CI 构建配置也有同步修改。

## 2026-03-02

涉及 commit：`ef1bf40`、`23c1f82`、`a4c2d4b`、`b8d8fb1`、`22aea2b`

- `legacy/tv-legacy` 的图片加载与页面体验继续调整，涉及 `BitmapBlur`、`BitmapFetcher`、`ImageLoader` 以及 Library / Search / Settings / Servers 页面。
- 远程控制和代理链路继续完善，更新了 `RemoteHttpServer`、`ProxyService`、`MihomoConfig`、`EmbyApi` 与远程控制前端页面。
- App 图标、字符串资源和 `AndroidManifest` 同步更新，`IjkPlayerCore` 也有单独迭代。

## 2026-03-01

涉及 commit：`6329a2f`、`cee5f18`、`6389f78`、`5db0b14`、`2023d9e`、`99654e0`、`fd1f209`、`d287707`、`1a3df75`

- `legacy/tv-legacy` 播放器重构是当天主线，引入或补强了 `PlayerCore`、`PlayerCoreType`、`PlayerCores`、`VlcPlayerCore`、`IjkPlayerCore`、`PlayerTrack`、`PlaybackSession` 等核心抽象。
- TV 端 `Emby` 导航和详情页补齐，覆盖 `ItemDetailActivity`、`ShowDetailActivity`、`EpisodeDetailActivity` 以及季、集、详情相关数据模型与布局资源。
- `PlayerActivity` 的 HUD / 详情布局多次迭代，Flutter 主线里的 `play_network_page`、`play_network_page_native`、`show_detail_page` 也做了联动适配。
- 弹幕渲染相关的 `danmaku_stage.dart` 有单独整理。
