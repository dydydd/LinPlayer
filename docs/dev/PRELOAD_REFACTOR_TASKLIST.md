# 预加载重构任务清单

> 配套文档：`docs/dev/PRELOAD_ASSESSMENT.md`
>
> 目标不是“再做一个预加载功能”，而是把现有预加载从“页面侧 best-effort 功能”继续收敛为“播放器统一的底层能力”。

## 1. 文档目的

本文把 `PRELOAD_ASSESSMENT.md` 中的评估结论，整理为可执行的开发任务清单，便于：

- 排期
- 拆分阶段
- 明确依赖关系
- 定义验收标准
- 作为后续实现与 review 的执行清单

## 2. 当前问题摘要

当前预加载能力已经可用，但仍存在以下结构性问题：

- 预加载和真实播放没有完全共享同一条 source pipeline
- 对 STRM / 外链 / 重定向 / 本地回环代理的对齐不彻底
- 去重 key 过粗
- 熔断范围过大
- 下一集预加载没有完整继承系列级版本选择
- 缺少专门测试与运行期诊断

因此这轮任务的核心方向只有一个：

> 让预加载尽量消费“播放器最终要播放的 source 结果”，而不是自己重复做一遍选源和拼 URL。

## 3. 重构目标

### 3.1 主目标

- 统一预加载与真实播放的 source 决策链
- 降低 `play_network_page*.dart` 与 `stream_preload_service.dart` 之间的重复逻辑
- 提升 STRM / 外链 / 代理 / 多版本场景的一致性
- 建立可观测、可测试、便于手工回归的预加载基础设施

### 3.2 次目标

- 减少页面层直接拼流 URL 的代码
- 让详情页与播放页的预加载接入方式更统一
- 为后续继续扩展预读策略保留稳定接口

### 3.3 非目标

本轮不建议把范围扩大到以下方向：

- 不在本轮引入“任意时长可配置预加载”
- 不在本轮做复杂 ABR 预测
- 不在本轮追求 Web 端产品化支持
- 不在本轮重写整个播放链路

## 4. 建议实施顺序

建议按以下阶段推进：

1. Phase 0：补诊断与基线
2. Phase 1：抽出统一的播放源准备阶段
3. Phase 2：让预加载消费统一 source 描述
4. Phase 3：统一详情页 / 播放页接入
5. Phase 4：改造去重与熔断策略
6. Phase 5：补 STRM / HLS / 代理专项处理
7. Phase 6：测试与手工回归
8. Phase 7：清理旧逻辑、补文档

如果时间紧，至少优先完成：

- Phase 0
- Phase 1
- Phase 2

这三步完成后，预加载的“底层能力”属性会明显提升。

## 5. 任务总览

### 5.1 高优先级

- 统一 `play_network_page.dart`、`play_network_page_exo.dart` 与 `stream_preload_service.dart` 的 source 决策逻辑
- 建立“最终播放 source”共享模型
- 让预加载直接基于共享 source 做预热
- 补预加载诊断日志与结果标记

### 5.2 中优先级

- 缩小全局熔断范围
- 扩展去重 key
- 统一下一集预加载的版本继承逻辑
- 补 HLS / STRM / 代理专项测试

### 5.3 低优先级

- 进一步优化 HLS rendition 选择策略
- 增加更细粒度指标统计
- 对预加载任务做更丰富的优先级调度

## 6. Phase 0：补基线与诊断

### 6.1 目标

在改结构之前，先让现有预加载可观测，避免后续重构后难以判断效果是否变好。

### 6.2 任务项

- [ ] 为 `StreamPreloadService` 增加统一日志入口
- [ ] 记录每次预加载的触发来源
  - 详情页当前项
  - 详情页下一集
  - 续看恢复点
  - 播放结束前下一集
- [ ] 记录每次预加载的目标信息
  - `itemId`
  - `startPosition`
  - `mediaSourceId`
  - 是否 HLS
  - 是否外链
  - 是否走代理
- [ ] 记录执行结果
  - success
  - skippedDisabled
  - skippedAlreadyDone
  - failedDisabled
  - 非致命失败原因
- [ ] 在 `app_diagnostics_report` 中加入预加载最近状态摘要

### 6.3 建议涉及文件

- `packages/lin_player_player/lib/src/preload/stream_preload_service.dart`
- `lib/services/app_diagnostics_report.dart`
- `lib/services/app_diagnostics_log.dart`
- `lib/show_detail_page.dart`
- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`

### 6.4 验收标准

- 能从日志中区分预加载是否触发、由谁触发、命中了什么 source、最终是否成功
- 遇到“用户说没效果”时，能快速分辨是未触发、被判重、被熔断、还是实际请求失败
- 构建后打开预加载选项，能通过手工点击路径直观看到日志与行为是否符合预期

## 7. Phase 1：抽出统一的播放源准备阶段

### 7.1 目标

把当前散落在播放页中的“播放源准备逻辑”抽成共享能力，避免 MPV / Exo / 预加载各自维护一套。

### 7.2 当前重复点

当前存在明显重复实现的区域：

- 版本选择逻辑
- `playbackInfo` 拉取
- 直链 / 转码 / `Path` 外链选择
- query 参数附加
- 同源判定
- header 选择

这些逻辑目前同时存在于：

- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`
- `packages/lin_player_player/lib/src/preload/stream_preload_service.dart`

### 7.3 任务项

- [ ] 设计一个共享的“已解析播放源”模型
- [ ] 抽一个统一 builder / resolver 服务，负责生成“播放器最终候选 source”
- [ ] 模型中至少包含以下字段
  - 原始 `itemId`
  - `playSessionId`
  - `mediaSourceId`
  - 最终 URL
  - 最终 headers
  - 是否外链
  - 是否 HLS / DASH / file / unknown
  - 码率 / size 等可选元数据
  - 是否来自 STRM
  - redirect / body-link / 代理相关信息
- [ ] 统一“同源判定 + query 参数附加”逻辑
- [ ] 统一“系列级媒体源偏好 + 手动选源 + 全局偏好”的决策逻辑
- [ ] 让 MPV 与 Exo 共同依赖这个共享 builder，而不是各自维护 `_buildStreamUrl`
- [ ] 尽量保留兼容层，避免一次性改动过大

### 7.4 推荐落点

建议新建一个共享模块，命名可以在实现时再定，但方向建议如下：

- `packages/lin_player_player/lib/src/source/`

候选文件可以包括：

- `resolved_playback_source.dart`
- `playback_source_builder.dart`
- `playback_source_request.dart`

### 7.5 建议涉及文件

- 新建共享 source 模块
- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`
- `lib/show_detail_page.dart`
- `packages/lin_player_player/lib/src/preload/stream_preload_service.dart`

### 7.6 验收标准

- MPV 与 Exo 不再各自维护独立的 `_buildStreamUrl` 主要逻辑
- 预加载不再需要自己复制一整套媒体源选择与 URL 拼装逻辑
- 真实播放与预加载都能拿到同一份 source 描述

## 8. Phase 2：让预加载直接消费共享 source

### 8.1 目标

把 `StreamPreloadService` 从“自己构造 URL 的服务”改成“对既定播放 source 做预热的服务”。

### 8.2 任务项

- [ ] 重新设计 `StreamPreloadService` 输入模型
- [ ] 新接口优先接收共享 source 描述，而不是只接收 `itemId + auth`
- [ ] 保留旧接口作为过渡 wrapper
- [ ] 旧接口内部也改为先走共享 source builder
- [ ] 让预加载逻辑优先基于“最终可播放 source”做请求
- [ ] 如果 source 已经经过 `LocalHttpStreamProxy` 包装，需要明确预加载应对“远端源”还是“本地回环源”生效
- [ ] 对 STRM / 外链 / redirect resolved source 做统一处理

### 8.3 设计建议

建议把预加载服务拆成两层：

- 上层：负责触发策略与去重
- 下层：负责对具体 source 做预热执行

这样好处是：

- 页面层只负责“什么时候预加载”
- source builder 负责“预加载哪个 source”
- preload executor 负责“怎么预加载这个 source”

### 8.4 建议涉及文件

- `packages/lin_player_player/lib/src/preload/stream_preload_service.dart`
- 新建 `packages/lin_player_player/lib/src/preload/preload_request.dart`
- 新建 `packages/lin_player_player/lib/src/preload/preload_executor.dart`
- Phase 1 中的共享 source 模块

### 8.5 验收标准

- `StreamPreloadService` 不再维护一份独立的 `_buildStreamUrl`
- STRM / 外链 / 代理命中率与真实播放 source 明显更一致

## 9. Phase 3：统一详情页与播放页接入

### 9.1 目标

减少页面层各自拼参数、各自判断代理、各自决定版本的重复代码。

### 9.2 任务项

- [ ] 统一详情页电影预加载入口
- [ ] 统一详情页剧集预加载入口
- [ ] 统一续看恢复点预加载入口
- [ ] 统一播放结束前下一集预加载入口
- [ ] 给所有入口提供统一的 `triggerSource` 标识
- [ ] 明确“当前项预加载”和“下一项预加载”所需元数据最小集合
- [ ] 统一代理传递逻辑，不再让某些入口自己猜代理、某些入口直接透传

### 9.3 重点问题

这里特别要解决两件事：

- 下一集预加载要不要继承当前剧集的 `mediaSourceId`
- 详情页预加载是否应该先通过共享 source builder 得到真实 source，再交给预加载服务

建议结论是：

- 要继承系列级版本选择
- 能拿到最终 source 时，不要再只传 `itemId`

### 9.4 建议涉及文件

- `lib/show_detail_page.dart`
- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`

### 9.5 验收标准

- 详情页 / 播放页所有预加载调用点都改为走统一入口
- 页面对预加载的直接参数拼装明显减少

## 10. Phase 4：重做去重与熔断策略

### 10.1 目标

让预加载在实际使用中更稳，避免“一个坏片源打死整轮会话”。

### 10.2 去重改造任务

- [ ] 扩展去重 key
- [ ] 至少纳入以下字段
  - `itemId`
  - `startPositionSec`
  - `mediaSourceId`
  - `audioStreamIndex`
  - `subtitleStreamIndex`
  - source URL 指纹
  - 代理标识
- [ ] 明确“当前项”和“下一项”是否共享去重空间
- [ ] 明确“详情页预热”和“播放页兜底预热”是否应该共用命中记录

### 10.3 熔断改造任务

- [ ] 把全局 `_permanentlyDisabled` 改为更细粒度状态
- [ ] 候选策略一：按 server/baseUrl 熔断
- [ ] 候选策略二：按错误类型熔断
- [ ] 候选策略三：按时间窗口 + 连续失败次数熔断
- [ ] 对不可恢复错误与临时网络错误做区分
- [ ] 为熔断恢复设计 TTL 或重试窗口

### 10.4 建议涉及文件

- `packages/lin_player_player/lib/src/preload/stream_preload_service.dart`

### 10.5 验收标准

- 单个片源持续失败，不再导致本次运行内所有其它内容全部失去预加载能力
- 用户切换版本后，不会因为 key 过粗被误判为“已经预加载”

## 11. Phase 5：补 STRM / HLS / 代理专项处理

### 11.1 目标

补齐最容易让预加载“看似触发了但实际收益很差”的几类场景。

### 11.2 STRM / 外链专项任务

- [ ] 确认共享 source builder 已正确复用 `stream_resolver`
- [ ] 复用 redirect resolved 结果
- [ ] 复用 body-link resolved 结果
- [ ] 对 cross-origin header 做统一裁剪策略
- [ ] 确认依赖 cookie / referer 的链接在预加载时不丢失必要 header

### 11.3 本地回环代理专项任务

- [ ] 明确预加载应命中远端 URL，还是命中本地回环代理后的 URL
- [ ] 若预加载远端 URL，需要保证与真实播放 source 的 header / redirect 语义一致
- [ ] 若预加载本地回环代理 URL，需要验证本地代理不会吞掉预热收益

### 11.4 HLS 专项任务

- [ ] 检查共享 source builder 能否提供更准确的 HLS 元数据
- [ ] 评估是否保留“最高带宽 variant”逻辑
- [ ] 评估是否应优先命中播放器最终预计使用的 rendition
- [ ] 保留当前“最多 3 段”的安全上限，但把策略配置收拢到统一位置

### 11.5 建议涉及文件

- `lib/services/stream_resolver/`
- `lib/services/stream_proxy/local_http_stream_proxy.dart`
- `packages/lin_player_server_api/lib/services/http_stream_proxy.dart`
- `packages/lin_player_player/lib/src/preload/stream_preload_service.dart`
- Phase 1 中的共享 source 模块

### 11.6 验收标准

- STRM 多跳场景下，预加载与真实播放指向同一最终 source 的概率明显提高
- 代理和外链场景中，预加载成功率不再明显落后于真实播放成功率

## 12. Phase 6：测试与手工回归

### 12.1 目标

以“改完直接构建，打开预加载选项做手工回归”为主，必要时只补最值钱的自动化测试。

### 12.2 首选手工回归流程

建议每完成一个阶段，就直接构建对应平台包或运行调试构建，然后：

1. 打开应用
2. 进入设置页，开启“预加载”
3. 分别验证电影、剧集、续看、下一集尾声触发等主路径
4. 对照日志确认触发来源、目标 source、结果状态
5. 对有问题的样本重点回放并修正

### 12.3 手工回归清单

- [ ] 电影详情页进入播放
- [ ] 剧集详情页进入播放
- [ ] 从续看历史恢复
- [ ] 剧集尾声切到下一集
- [ ] 手动切换不同版本后播放下一集
- [ ] 自定义播放代理开启
- [ ] Android Exo 路径
- [ ] Android / TV MPV 路径
- [ ] Windows / macOS 网络播放路径
- [ ] iOS 网络播放路径

### 12.4 可选自动化测试补点

如果后面某些逻辑经常改、又容易回归，再补下面这些自动化测试；这部分不是当前推进的阻塞条件。

- [ ] 直链预加载成功
- [ ] 直链续看 offset 预加载成功
- [ ] HLS media playlist 预加载成功
- [ ] HLS master playlist 解析与 variant 选择
- [ ] 初始化段存在时能正确请求 init segment
- [ ] in-flight 合并正确
- [ ] 去重 key 区分不同 mediaSource
- [ ] 熔断策略按新规则工作
- [ ] 代理配置能正确传入
- [ ] 外链 / 同源 header 策略正确
- [ ] STRM -> redirect -> final media 测试链
- [ ] body-link 返回直链测试链
- [ ] 播放页与预加载共享 source builder 的一致性测试

### 12.5 建议涉及文件

- `test/` 下新增 preload 专项测试文件
- 必要时为 source builder 单独建立测试文件

### 12.6 验收标准

- 每个阶段完成后，都能通过实际构建 + 开启预加载选项完成主路径手工验证
- 关键问题能通过日志快速定位
- 若后续补自动化测试，应优先覆盖最容易回归的 source 决策与预加载执行逻辑

## 13. Phase 7：清理旧逻辑与文档收口

### 13.1 目标

在新实现通过实际构建与手工回归验证后，删除旧重复逻辑，并把文档与实现收口。

### 13.2 任务项

- [ ] 确认新链路通过手工回归后，删除旧版 `_buildStreamUrl` 复制逻辑
- [ ] 清理页面层散落的预加载参数拼装代码
- [ ] 更新开发文档
  - `ARCHITECTURE.md`
  - `PRELOAD_ASSESSMENT.md`
  - 本文档

### 13.3 验收标准

- 代码库中不再并存多份意义相同的预加载 URL 选择逻辑
- 文档与实现一致

## 14. 推荐拆分到 PR 的方式

建议不要一个 PR 全做完，推荐按以下粒度拆分：

### PR 1：诊断与基线

- 只加日志与诊断
- 不改功能行为

### PR 2：共享 source 模型

- 新增共享 source builder
- 暂不切预加载

### PR 3：MPV / Exo 切共享 source builder

- 播放页先统一
- 验证真实播放不回归

### PR 4：预加载改接共享 source

- 旧接口保留作兼容 wrapper

### PR 5：去重与熔断改造

- 单独 review 风险

### PR 6：测试补齐与清理

- 删除旧逻辑
- 更新文档

## 15. 建议新增的内部模型

下面是建议引入的最小模型集合，命名可以在实现时调整。

### 15.1 `ResolvedPlaybackSource`

职责：

- 表达“播放器最终准备播放的 source”

建议字段：

- `itemId`
- `playSessionId`
- `mediaSourceId`
- `url`
- `httpHeaders`
- `isExternal`
- `mediaTypeHint`
- `fromStrm`
- `redirectChain`
- `contentTypeHint`
- `supportsByteRange`
- `bitrate`
- `sizeBytes`
- `proxyUrl`

### 15.2 `PlaybackSourceBuildRequest`

职责：

- 表达构建 source 时所需输入

建议字段：

- `adapter`
- `auth`
- `itemId`
- `startPosition`
- `playerCoreKind`
- `selectedMediaSourceId`
- `audioStreamIndex`
- `subtitleStreamIndex`
- `preferredVideoVersion`
- `seriesId`
- `serverId`
- `allowTranscoding`

### 15.3 `PreloadRequest`

职责：

- 表达一次预加载任务，不直接关心页面来源

建议字段：

- `resolvedSource`
- `triggerSource`
- `startPosition`
- `preloadDuration`
- `dedupeFingerprint`

## 16. 关键风险提示

### 16.1 最大风险

这轮重构最容易出问题的地方不是预加载本身，而是：

- 播放页真实播放 source 的兼容性回归

所以一定要坚持：

- 先抽共享 builder
- 先让真实播放稳定使用
- 再把预加载切过去

### 16.2 次级风险

- 误把本地回环代理 source 当成预加载目标，导致收益不明显
- 清理旧逻辑过早，丢失某些平台特例
- HLS 策略切换后个别源首段命中率下降

## 17. 完成定义

当满足以下条件时，可以认为“预加载底层化”基本完成：

- 真实播放与预加载共享同一套 source 构建结果
- 详情页与播放页不再各自维护一套预加载拼参逻辑
- 去重 key 与熔断策略达到可接受粒度
- STRM / 外链 / 代理场景具备基本一致性
- 预加载拥有独立测试与诊断闭环

## 18. 最终建议

如果只能做一件最重要的事，那就是：

> 先把“最终播放 source”抽成共享能力，再让预加载消费它。

这是整份任务清单里收益最大、对后续所有任务都有放大效果的一步。
