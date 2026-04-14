# 预加载能力现状评估（2026-04-14 复核）

> 面向开发与重构决策的评估文档。本文基于当前仓库实现整理，不重复描述用户侧操作，而重点回答：预加载现在到底做到了什么、做到什么程度、还差什么。

## 1. 评估范围

本文评估的是播放器相关的“预加载（Preload）”能力，核心实现位于：

- `packages/lin_player_player/lib/src/preload/stream_preload_service.dart`

相关接入点位于：

- `lib/show_detail_page.dart`
- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`
- `packages/lin_player_state/lib/app_state.dart`
- `lib/settings_page.dart`

## 2. 平台范围修正

当前项目的产品目标平台应按以下范围理解：

- PC 端：Windows、macOS
- TV 端：Android TV / TV 场景
- 移动端：Android、iOS

本项目**不以 Web 端作为产品形态**。代码中虽然仍存在 `kIsWeb` 分支判断，但它更像是共享 Flutter 代码中的保护性分支，而不是产品能力承诺。

因此，本评估文档不把“Web 是否支持预加载”作为产品维度结论，只在实现细节中说明：当前预加载服务本身在 `kIsWeb` 下会直接返回失败。

## 3. 2026-04-14 复核结论（优先阅读）

本次重新对照以下代码路径后，需要把前一版结论明显收紧：

- `lib/show_detail_page.dart`
- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`
- `lib/services/preload/playback_preload_coordinator.dart`
- `lib/services/stream_proxy/local_http_stream_proxy.dart`
- `packages/lin_player_player/lib/src/preload/stream_preload_service.dart`
- `packages/lin_player_server_api/lib/services/http_stream_proxy.dart`

当前最准确的判断是：

- 预加载已经能把一部分起播数据写进共享缓存，播放也确实会走同一套 `cacheKey + loopback proxy` 语义。
- 本轮已经补上路由级 handoff：详情页 / 下一集阶段拿到的 `PreparedPlaybackPreload`，会在 MPV / Exo 播放页命中时被优先复用。
- 但“预加载完成后，进入播放器明显更快、且几乎不再缓冲”这件事，**还没有成立**。
- 问题不再只是“有没有把结果带进播放页”，而是“带进播放页之后，续播点恢复、播放源包装、播放器初始化这几段准备成本还没有完全收口”。

用户反馈中的两个现象，其实对应两类不同问题：

- “预加载完再点播放，进入播放器还是很慢”：主要卡在播放页自己的准备流程，预加载并没有覆盖这段耗时。
- “进入播放器后还在缓存 / 还在缓冲”：主要是播放器首个真实请求范围并不总被预热窗口完全覆盖，代理仍会继续拉远端 tail，或者直接出现 `range-not-covered`。

一句话概括：

- 现在的预加载更像“共享缓存预热能力已经落地”。
- 它还不是“端到端点击播放就明显提速的秒开能力”。

## 4. 更新后的能力评级

按不同层次重新评估：

- 作为“共享缓存 / HTTP 代理复用能力”：`7/10`
- 作为“用户体感上的预加载直开能力”：`4/10`
- 作为“播放器端到端统一预加载基础设施”：`5/10`

原因在于：

- 缓存层、代理层、去重层已经做了不少实事。
- 详情页 / 下一集预加载结果现在已经可以通过 `PreparedPlaybackPreload` 直接带进播放页，并在命中时跳过重新 `_buildResolvedPlaybackSource()`。
- 但进入播放页后仍然会继续执行远端/本地续播进度拉取、播放源包装、播放器初始化，因此真实体感收益仍需要手工回归验证。
- 所以如果只看缓存命中，会高估真实体感收益；如果看用户点击播放后的整体等待，当前结论必须更保守。

### 4.1 为什么这次判断比 2026-04-01 更保守

- 前一版评估更偏向“缓存层已经复用到什么程度”。
- 当前代码虽然可以证明某些场景下“前缀不重复下载”成立，但还不能证明“进入播放器明显更快”已经成立。
- `docs/dev/PRELOAD_REFACTOR_TASKLIST.md` 里最关键的手工回归项仍未全部完成，这和当前用户反馈是一致的。

## 5. 架构文档中的设计目标

`docs/dev/ARCHITECTURE.md` 中对预加载的定义大致是：

- 开关：`AppState.preloadEnabled`
- 服务：`StreamPreloadService`
- 详情页加载后预取当前集 / 下一集前 3 秒
- 播放结束前兜底预取下一集前 3 秒
- 单次最多 3 次尝试
- 同一 source / proxy scope 连续失败后短时熔断，TTL 后恢复
- 直链优先走 Range，HLS 走初始化段 + 前若干分片

从代码看，这些目标大部分已经有实际落地，而不只是文档规划。

## 6. 现在到底接到了哪些链路

### 6.1 开关与持久化

预加载开关已经具备完整的设置链路：

- 状态存储：`AppState.preloadEnabled`
- 持久化 key：`preloadEnabled_v1`
- 设置页入口：`settings_page.dart`
- TV remote 状态同步也已接入

这说明它不是临时实验开关，而是正式用户偏好项。

### 6.2 详情页触发

详情页侧已经做了两类预加载：

- 电影详情：预加载当前电影前 3 秒
- 剧集详情：预加载当前剧集前 3 秒

并且剧集详情页会进一步尝试：

- 预加载当前剧集所在季的下一集
- 如果当前季已到结尾，再尝试预加载下一季第一集

这说明它已经不是“只顾当前条目”的最小实现，而是明显面向连续播放体验设计过。

### 6.3 播放页兜底触发

播放页又补了两条关键兜底路径：

- 续看进入时，如果存在历史进度，则从历史进度位置附近做预加载
- 播放剩余时长小于等于 5 秒时，触发下一集前 3 秒预加载

而且这两条逻辑同时存在于：

- `play_network_page.dart`（MPV 路径）
- `play_network_page_exo.dart`（Exo 路径）

这点很重要，说明预加载已经不是“详情页单点增强”，而是同时覆盖了“从详情页进入”和“非详情页直接播放”两类主流程。

## 7. 服务本体现在做了什么

`StreamPreloadService` 的职责已经比较清晰：

### 7.1 输入

它接收以下关键输入：

- `adapter`
- `auth`
- `itemId`
- `startPosition`
- `exoPlayer`
- `selectedMediaSourceId`
- `audioStreamIndex`
- `subtitleStreamIndex`
- `preferredVideoVersion`
- `httpProxyUrl`

这意味着它并不是简单地“拿 itemId 发个 HEAD”，而是试图对齐播放器版本、音轨、字幕和不同内核路径。

### 7.2 播放信息拉取

预加载前会重新调用一次：

- `adapter.fetchPlaybackInfo(...)`

然后根据返回的 `mediaSources` 选择媒体源。

### 7.3 媒体源选择

服务内部已经实现了一套版本选择逻辑：

- 优先使用 `selectedMediaSourceId`
- 否则按 `preferredVideoVersion` 选最高分辨率 / 最低码率 / 偏好 HEVC / 偏好 AVC / 默认版本

这说明它不是“无脑预取第一路源”，而是有一定版本意识。

### 7.4 URL 组装

服务会自行构造待预取流地址，支持以下来源：

- `DirectStreamUrl`
- `TranscodingUrl`（Exo 路径可用）
- `Path` 中暴露出的绝对可播放 URL
- 最后回退到 `Videos/{id}/stream?static=true...`

### 7.5 Header 处理

若预加载目标与服务器同源，则会附带：

- 认证相关流 headers
- 专用 UA：`preload-linplayer`

若跨域 / 外链，则不会强行附加服务端认证头。

这个处理方向是正确的，说明它考虑过“外链被错误加 token / 认证头”的问题。

### 7.6 预取策略

对于普通直链：

- 先请求一段范围数据做嗅探
- 如果不是 HLS，则直接以读取到字节为成功依据
- 如果带有续看起点，则按码率估算 byte offset，再从对应位置拉一段

对于 HLS：

- 识别 m3u8
- 如果是主播放列表，会继续解析子播放列表
- 请求初始化段（若存在）
- 请求从目标位置开始的最多 3 个分片，累计约 3 秒

### 7.7 码率与字节估算

服务会根据：

- `Bitrate`
- 或 `Size / RunTimeTicks`

估算码率，再推导应预取字节数，并做上下限钳制：

- 最小：`256 KB`
- 最大：`24 MB`

这是一种务实做法，说明它已经考虑过“码率过低没意义”和“码率过高导致预热过重”的平衡。

## 8. 它现在已经做得比较好的地方

### 8.1 不是空壳，是真正进入主链路了

预加载已经不是一个单独工具类，而是被：

- 状态层
- 设置页
- 详情页
- MPV 播放页
- Exo 播放页

共同接入。

从工程成熟度看，这远高于“实验性分支功能”。

### 8.2 MPV / Exo 两条播放路径都覆盖了

这是当前实现里很重要的一点。很多类似功能只会先做一条播放器链路，但这里两条网络播放页都接了：

- MPV 路径有续看预热和下一集兜底预热
- Exo 路径同样具备对应能力

说明作者在设计时已经把它视为通用播放增强，而不是某个特定内核专属 feature。

### 8.3 触发时机设计是合理的

现有触发点基本对应真实用户体感最敏感的位置：

- 进入详情页后，提前拉当前项和下一项
- 从历史进度恢复时，优先热身恢复点附近
- 播放尾声时，兜底拉下一集

这些时机都属于“投入少、收益可能高”的位置，没有明显为了预加载而预加载。

### 8.4 做了并发去重

服务内部有：

- `_doneKeys`
- `_inFlight`

这意味着：

- 同一目标不会重复预取
- 同一目标正在执行时，后续请求会复用同一 Future

这对详情页与播放页可能同时触发的场景很有价值，能避免重复打流。

### 8.5 失败处理比较克制

它不是强依赖能力，而是典型的 best-effort：

- 成功最好
- 失败不阻塞播放
- 会重试
- 最后给用户一个明确“后续不再尝试”的提示

从用户体验角度，这种定位是对的。

## 9. 目前最核心的短板

下面这些问题，决定了它暂时还不能算“播放器统一底层能力”。

### 9.1 预加载和真实播放已共享大部分 source pipeline，但还没有完全收口到最终播放对象

这是当前最重要、但也已经明显改善的一点。

播放器真正播放前，会经过一套更完整的流程：

- 拉 `playbackInfo`
- 选择实际媒体源
- 识别直链 / 转码 / 外链 / STRM
- 构建共享 `ResolvedPlaybackSource`
- 对部分 HTTP 源走本地回环代理 `LocalHttpStreamProxy`

现在预加载链路已经不再自己复制一整套“版本选择 + URL 拼装 + 外链处理”，而是先经过：

- `PlaybackSourceBuilder`
- `ResolvedPlaybackSource`
- `PlaybackPreloadCoordinator`

也就是说，媒体源选择、URL 构建、STRM / redirect / body-link 解析已经和真实播放共享了主干逻辑。

这会带来几个后果：

- 预加载命中的源，与真实播放最终 source 的一致性已经明显提高
- 播放页后续对 source 决策链做改动时，预加载更不容易漂移
- 剩余差距主要集中在“最终播放对象”的最后一跳，而不是前面的 source 选择阶段

换句话说：

- 现在的预加载已经不再是“完全平行的一套实现”
- 但它还不是“直接消费播放器最终播放对象”的终态架构

### 9.1.1 详情页预加载结果已经开始被直接带进播放页

这轮改动后，最关键的补齐点是：**路由跳转时已经开始把 prepared result 传下去了**。

当前代码里，详情页 / 剧集页预加载完成后，跳转到播放页时不再只传：

- `itemId`
- `startPosition`
- `mediaSourceId`
- `audioStreamIndex`
- `subtitleStreamIndex`

而是已经可以额外把下面这些结果一起 handoff 给播放页：

- 已准备好的 `PreparedPlaybackPreload`
- 已确定的 `ResolvedPlaybackSource`
- 已收口的 `playerCore / playSessionId / mediaSources / stream choice` 等播放入口元数据

对应地，播放页命中 handoff 时已经不再重新执行：

- `_buildResolvedPlaybackSource()`

但播放页初始化仍会继续执行一整段后续准备链路：

- `_serverProgressSync.fetchServerProgressDurationBestEffort()`
- `_readLocalProgressDuration()`
- `_buildPlaybackSource()`
- `_playerService.initialize(...)` 或 `controller.initialize()`

这意味着：

- 详情页已经跑完预加载后，播放页现在终于可以“直接拿现成 source 结果开播准备”
- 之前缺的“页面跳转后的 prepared result handoff”已经开始收口
- 现在剩余的主要问题，集中在 handoff 之后的准备耗时，而不是 handoff 本身缺失

### 9.1.2 播放页里的当前项 warmup 更像补偿措施，不是入场闭环

MPV 和 Exo 播放页都会在进入后再次调用当前项 warmup，但这一步是：

- 在播放页里重新确定起播点之后才触发
- `unawaited(...)` 异步触发
- 更偏向“补偿性兜底”，而不是“保证首帧前必须完成的前置阶段”

所以它能帮助减少部分后续等待，但并不能证明“点击播放后就一定直接起播”。

### 9.2 STRM / 外链 / 重定向场景的一致性已明显改善，但仍需继续验证最后一跳

真实播放链路里已经有：

- `PlayableSource`
- `stream_resolver`
- `LocalHttpStreamProxy`
- redirect / body-link / header 处理

这轮重构后，共享 source builder 已经复用了 redirect / body-link 解析能力，并通过共享 `ResolvedPlaybackSource` 把结果传给预加载服务。

因此在以下场景里，预加载效果可能明显变弱：

- 播放器最终是否应该命中远端 URL，还是命中本地回环代理 URL
- HLS 最终实际选择的 rendition 与预加载选择不一致
- 特殊代理链路下，预热收益是否能真正被播放器复用

这并不意味着 STRM / 外链已经不可靠，而是说明剩余的不确定性主要从“解析是否一致”转成了“最后一跳是否完全复用”。

### 9.3 失败熔断粒度过大

原始策略是：

- 单次任务最多尝试 3 次
- 如果最终失败，则 `_permanentlyDisabled = true`
- 之后本次运行内所有后续预加载都停止

这个策略能避免用户一直被失败骚扰，但副作用也比较明显；这也是后续重构里已经优先收敛的点之一：

- 某一个片源失败，可能拖累整个应用本次运行内的全部预加载
- 某个临时网络故障，也会直接让后续同类任务失去机会

从工程角度看，这个熔断范围偏大，更像“全局总开关熔断”，而不是“按站点 / 路由 / 片源类型 / 错误类型熔断”。

### 9.4 去重 key 已明显收敛，但还不是最终播放对象级别

当前去重 key 已经纳入：

- `itemId`
- `startSec`
- `mediaSourceId`
- `AudioStreamIndex`
- `SubtitleStreamIndex`
- source URL 指纹
- header 指纹
- 代理标识
- `targetKind` 命名空间（`currentItem` / `nextItem` 分开）

同时当前实现已经明确：

- `currentItem` 与 `nextItem` 不共享去重空间
- 详情页预热与播放页兜底预热对同一语义目标共用命中记录（`triggerSource` 不进 key）

这已经显著降低了“切换版本后仍被判成已预加载”的概率。

剩余差距主要在于：

- 尚未与播放器最终 `PlayableSource` / 本地回环后的最终对象完全绑定
- 页面级 end-to-end 回归仍需要继续补足

### 9.5 剧集链路没有完整继承“剧集版本偏好”

播放页真正选择媒体源时，会结合：

- 当前手动选择的 `selectedMediaSourceId`
- 系列级持久化的 `seriesMediaSourceIndex`
- 全局 `preferredVideoVersion`

但下一集预加载并没有完整继承这套信息。

当前实现里：

- 当前集续看预加载通常能拿到 `selectedMediaSourceId`
- 但下一集预加载大多只带了音轨 / 字幕 / preferredVideoVersion
- 并未把“当前系列正在使用哪一路 media source”稳定带过去

结果就是：

- 当前集播放的是 A 版本
- 下一集预加载有可能命中 B 版本

这种不一致在多版本片源、不同编码版本共存时会比较明显。

### 9.6 代理对齐策略已进一步明确，但还没收口到最终播放对象

现在 MPV、Exo、详情页预加载入口都已经通过 `PlaybackPreloadCoordinator` 收口代理决策，并把 `proxyUrl` 写入 `ResolvedPlaybackSource`：

- 会根据最终 source URL 统一推导 `httpProxyUrl`
- 会把该代理继续传给预加载服务
- 代理信息也会作为共享 source 元数据保留下来
- 预加载固定命中远端 URL，并在需要时通过 `httpProxyUrl` 继承真实播放的 HTTP 代理语义

剩余问题主要不再是“有没有把代理传过去”，而是：

- 本地回环代理带来的最终收益复用，仍未与播放器最终对象完全统一
- 个别平台特例下是否还存在只在真实播放链路里发生的最后一跳包装
- 对自定义 / 内置代理的页面级手工回归还需要继续补齐

所以代理相关一致性目前更准确的描述应是：

- 决策入口已经统一
- “远端 URL + `httpProxyUrl`”这条命中策略已经明确，并有自动化测试覆盖
- 与最终 `PlayableSource` 的完全等价仍未做透

### 9.7 HLS 处理已经有，但仍偏简化

HLS 支持是有的，这是优点。

但当前实现仍然比较“工程近似”：

- 主播放列表固定选择最高带宽 variant
- HLS media playlist 直达预热已经有自动化覆盖
- 最多只抓 3 个 segment，且这一策略常量已经收口在 preload service
- 不复用播放器实际 ABR 选择结果

这意味着：

- 它能起到一定预热作用
- 但不保证热到的就是播放器最终命中的那一路流

因此 HLS 预加载应理解为“有一定帮助的 best-effort”，而不是“播放器级精确预热”。

## 10. 现在最可能真正受益的场景

从当前实现推断，预加载最可能有效的场景是：

- Emby / Jellyfin 同源直链流
- STRM / body-link / redirect 已经能被共享 source builder 解析的场景
- MediaSource 信息完整、可稳定估算码率的片源
- 从详情页进入播放、且网络连接稳定
- 播放器最终流 URL 与共享 `ResolvedPlaybackSource` 高度一致

在这些场景下，它有较大概率改善：

- 首次开播首段等待
- 续看恢复时的前几秒反应
- 下一集自动切换前的首段进入速度

## 11. 现在最容易打折扣的场景

以下场景下，当前预加载的收益可能不稳定，甚至基本无感：

- 播放器最终实际命中的是本地回环代理，而预加载收益没有被充分复用
- 版本繁多、且用户经常手动切换版本的剧集
- HLS 主从播放列表复杂，播放器实际选择的 rendition 与预加载不一致
- 某个片源刚好触发全局熔断后，本次运行内其它内容全部失去预加载能力（也是后续已重点修正的问题）

## 12. 当前实现的工程定位

综合来看，当前预加载最适合被定义为：

- “共享 source 决策之上的网络预热执行层”

而不是：

- “已经完全等同于播放器最终播放对象的底层预读阶段”

这个定位不是坏事，反而解释了为什么它现在已经可以工作：

- 它已经共享了 source 决策主干
- 页面接入仍然相对简单
- 不需要把所有播放器底层细节一次性推倒重来
- 可以快速覆盖详情页和播放页关键时机

但这也解释了为什么它还不够“彻底”：

- 与真实播放最终对象还不是完全同一份结果
- 本地回环代理与 HLS 最终命中策略还需要继续统一
- 后续维护成本会随播放链路复杂度上升

## 13. 建议的下一步演进方向

如果后续想把它真正做成“底层能力”，我建议按以下顺序推进。

### 13.1 第一优先级：从共享 source builder 继续收口到最终播放对象

目标是：

- 保持当前共享 `ResolvedPlaybackSource` 主干不回退
- 在此基础上继续把“本地回环代理 / 最后一跳包装 / 最终播放对象”也统一起来

理想状态应是：

1. 播放链路先得到共享 `ResolvedPlaybackSource`
2. 最后一跳包装生成播放器最终对象
3. 预加载服务直接消费这份最终对象，或消费与其完全等价的预热输入

这样会立刻改善：

- 代理一致性
- 本地回环收益复用
- HLS 命中一致性
- 后续维护成本

### 13.2 第二优先级：缩小熔断范围

建议把“本次运行全局禁用”改成更细粒度，例如：

- 按服务器维度熔断
- 按错误类型熔断
- 按连续失败窗口熔断

至少不要因为一个片源失败，就把整轮会话全部关闭。

### 13.3 第三优先级：扩展去重 key

建议把这些维度纳入 key：

- `mediaSourceId`
- `audioStreamIndex`
- `subtitleStreamIndex`
- 代理标识
- 可能的话再加上最终播放 URL 指纹

这样能显著减少误判“已预加载”。

### 13.4 第四优先级：补测试与诊断

当前已经有一批值钱的自动化覆盖，而且本轮又补上了：

- 代理传递与实际命中测试
- HLS media playlist 直接预热测试
- `targetKind` 去重命名空间测试

建议后续优先补：

- 页面级 end-to-end 回归
- 真实播放对象与预加载输入完全一致的断言测试

同时建议增加运行期诊断信息：

- 预加载是否触发
- 命中哪个 URL / mediaSource
- 成功还是失败
- 失败原因分类
- 是否因 scoped 熔断被跳过

没有这些数据，后续很难精确判断“用户觉得没效果”到底是没触发、没命中，还是命中了但播放器没复用到。

## 14. 最终结论

当前预加载能力的真实状态是：

- 已经完成从“概念”到“缓存层能力”的落地
- 已经接入电影、剧集、续看、下一集兜底、MPV、Exo 等关键链路
- 已经具备直链、HLS、STRM / redirect / body-link 场景下的 best-effort 预热能力

但它还没有完成从“共享缓存预热”到“端到端播放提速”的最后一步：

- 已开始把详情页 / 下一集阶段已准备好的结果直接带进播放页
- 但播放页进入后仍会继续执行续播点拉取、播放源包装、播放器初始化等准备动作
- HLS / 续播 / 探测请求仍可能让代理继续走 `cached-prefix + remote-tail` 或出现 `range-not-covered`

因此，最准确的描述应该是：

> 预加载现在已经能做到“提前把一部分可播数据写进共享缓存”；  
> 但它还做不到“预加载完成后，详情页一点播放就明显更快且基本不再缓冲”。  
> 真正还缺的，不再是“有没有把预加载结果带过页面跳转”，而是把 handoff 之后的播放页准备链路继续收口。

---

如果后续准备继续重构，建议优先做三件事：

1. 把 `PreparedPlaybackPreload` / `ResolvedPlaybackSource` 真正带进播放页，而不是进页后全部重算。
2. 把“进入播放慢”拆成明确的阶段耗时：source build、进度恢复、proxy wrap、player initialize、首请求缓存命中。
3. 继续用播放器真实首请求范围校正预热窗口，而不是只用 3 秒经验值近似。
