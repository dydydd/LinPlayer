# 翻译服务设计与任务清单

> 面向当前仓库实现的开发文档。本文目标是为 LinPlayer 增加统一的“AI 翻译 + API 翻译”能力，并同时覆盖 `MPV` 与 `Exo` 两套播放器路径。

## 1. 结论先行

- 翻译能力应放在播放器上层的“统一翻译服务层”，而不是写进 `MPV` 或 `Exo` 内核内部。
- 产品层只区分两类：
  1. `AI 翻译`
  2. `API 翻译`
- `AI 翻译` 当前方案仅支持“兼容 OpenAI 接口”的服务。
- `API 翻译` 当前方案纳入以下 provider：
  - 百度通用文本翻译
  - 百度大模型翻译
  - 腾讯机器翻译
  - 阿里云机器翻译（HTTP / REST）
- 本次实现以“文本字幕翻译”为主，并同时支持 `MPV` 与 `Exo`。
- 接口文本翻译不与字幕翻译混在本次主链路里做，但整体架构要预留复用能力。

## 2. 产品定义

### 2.1 设置页形态

建议在“设置 -> 播放”或“设置 -> 翻译”下新增独立分组：

- `AI 翻译`
  - 开启 AI 翻译
  - Base URL
  - API Key
  - 模型
  - 默认 Prompt
  - 自定义 Prompt 开关
  - 字幕输出模式：原文 / 译文 / 双语
  - 源语言
  - 目标语言
  - 仅在手动触发时翻译 / 自动翻译当前字幕

- `API 翻译`
  - 开启 API 翻译
  - Provider
    - 百度通用文本翻译
    - 百度大模型翻译
    - 腾讯机器翻译
    - 阿里云机器翻译
  - 按 provider 动态显示凭证字段
  - 字幕输出模式：原文 / 译文 / 双语
  - 源语言
  - 目标语言

### 2.2 不做的事情

本次实现明确不做：

- `PGS / SUP / VobSub / DVB` 这类图形字幕 OCR 翻译
- 音频实时转写翻译
- 播放过程中逐句实时调用远端翻译接口
- 把所有 provider 都伪装成 `baseUrl + apiKey` 一种配置模型

## 3. 为什么要放在统一翻译层

如果把翻译能力写进播放器内核，会出现几个问题：

- `MPV` 和 `Exo` 需要各写一套逻辑，重复度高。
- 字幕翻译、接口文本翻译无法复用同一套 provider 抽象。
- 设置页、缓存、错误处理、密钥存储会散落到不同播放页。
- 后续扩展新 provider 时，需要同时改播放器逻辑和设置逻辑，耦合太高。

因此推荐结构是：

```text
设置页 / 播放页 / 页面文本
  -> TranslationService
    -> AiTranslationProvider / ApiTranslationProvider
      -> OpenAI-compatible / Baidu / Tencent / Aliyun
  -> SubtitleTranslationService
    -> 字幕读取 / 解析 / 翻译 / 生成外挂字幕
  -> MPV / Exo 只负责挂载翻译后的字幕文件
```

## 4. 当前代码落点建议

### 4.1 状态与配置

建议放到：

- `packages/lin_player_state/lib/app_state.dart`

职责：

- 持久化翻译开关
- 持久化 provider 配置
- 持久化目标语言 / 源语言 / 输出模式
- 持久化 prompt

### 4.2 设置页

建议落点：

- `lib/settings_page.dart`

职责：

- 展示 AI 翻译配置
- 展示 API 翻译配置
- 根据 provider 动态切换字段
- 提供“测试连接 / 测试翻译”按钮

### 4.3 翻译服务层

建议新增目录：

- `lib/services/translation/`

建议文件：

- `translation_models.dart`
- `translation_provider.dart`
- `translation_service.dart`
- `subtitle_translation_service.dart`
- `providers/openai_compatible_translation_provider.dart`
- `providers/baidu_general_translation_provider.dart`
- `providers/baidu_llm_translation_provider.dart`
- `providers/tencent_translation_provider.dart`
- `providers/aliyun_translation_provider.dart`

### 4.4 播放器接入点

建议接入文件：

- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`
- 可选：`lib/player_screen.dart`
- 可选：`lib/player_screen_exo.dart`

职责：

- 读取当前可翻译的文本字幕源
- 请求翻译服务生成外挂字幕
- 把翻译结果注入当前播放器
- 在字幕面板中增加“原文 / 译文 / 双语 / 关闭翻译”切换入口

## 5. 文本字幕翻译总体方案

### 5.1 核心原则

不要从“当前画面上正在显示的 cue 文本”逐句抓取再翻译。

推荐方案是：

1. 读取完整文本字幕源
2. 解析成标准 cue 列表
3. 批量调用翻译服务
4. 生成翻译后的外挂字幕文件
5. 再把外挂字幕挂回播放器

好处：

- `MPV` 与 `Exo` 共用一套流程
- 可复用到本地/网络播放
- 容易做双语字幕
- 成本更可控

### 5.2 本次实现支持的字幕类型

本次实现优先支持：

- `SRT`
- `VTT / WebVTT`
- 服务端返回的普通文本 subtitle stream

可选增强：

- `ASS / SSA` 的标签保留翻译

本次暂不纳入：

- `PGS / SUP / VobSub / DVB`

### 5.3 生成结果形式

建议统一生成当前播放会话可直接挂载的本地外挂字幕文件：

- `translated.srt`
- 或 `translated.vtt`

不建议本次直接回写服务端，也不建议直接修改原字幕轨。

这里的目标只是“当前会话可用”，不要求做长期缓存。

### 5.4 双语模式

双语模式建议按 cue 生成：

```text
原文
译文
```

如果源字幕是 `ASS / SSA`，当前方案建议先降级导出成普通 `SRT` 双语字幕，而不是强保原样式。

## 6. AI 翻译设计

### 6.1 产品定位

`AI 翻译` 仅支持兼容 OpenAI 接口的服务。

推荐支持字段：

- `baseUrl`
- `apiKey`
- `model`
- `prompt`
- `temperature` 可选
- `maxTokens` 可选

### 6.2 默认 Prompt

默认 prompt 建议项目内置，同时允许用户覆盖。

推荐默认 prompt 方向：

- 保留原句含义
- 尽量简洁自然
- 不解释、不扩写
- 不输出额外说明
- 保留专有名词
- 输出必须与输入分段一一对应

建议系统 prompt 以“批量翻译字幕数组”为目标，而不是逐句自然对话。

### 6.3 模型选择

设置层支持：

- 用户手填模型名
- 可选提供“获取模型列表”按钮

但模型列表获取失败时，不能阻塞手动输入。

### 6.4 请求协议

AI 翻译实现建议兼容：

- `POST /v1/chat/completions`

当前方案先兼容这条主流路径即可，不强依赖 `responses`。

### 6.5 输入格式与适配原则

这里需要区分两层，不应混在一起：

1. 外部 HTTP 请求格式
2. 应用内部标准数据模型

外部 HTTP 请求格式必须以 provider 官方文档为准，不能由项目自行规定。

以当前 `AI 翻译` 方案为例，外部协议应遵循兼容 OpenAI 的 Chat Completions 形态：

- `POST /v1/chat/completions`
- 顶层包含 `model`
- 对话输入通过 `messages`

也就是说，项目不能把下面这种结构直接当成“外部 API 统一请求体”来要求 provider 接受：

```json
[
  {"id": 1, "text": "Hello"},
  {"id": 2, "text": "How are you?"}
]
```

上面这种结构如果要使用，也只能作为“应用内部标准数据模型”存在，再由 provider adapter 映射到官方接口要求的字段。

正确的分层应该是：

```text
字幕 cue 列表
  -> SubtitleTranslationBatchRequest（项目内部模型）
    -> OpenAICompatibleTranslationProvider
      -> 按官方 Chat Completions 协议组装 model / messages / 其他参数
```

因此本项目在设计上应明确：

- `id + text` 这类批量结构仅作为内部翻译任务模型
- OpenAI 兼容服务实际发出的 HTTP body 必须是官方协议
- provider 适配器负责把内部模型映射为外部请求
- provider 适配器负责把外部响应再还原为内部统一结果

### 6.6 AI 翻译内部批处理模型建议

虽然外部协议必须遵循官方文档，但在项目内部，仍然建议把字幕翻译统一成批处理模型。

内部模型建议形态：

```json
[
  {"id": 1, "text": "Hello"},
  {"id": 2, "text": "How are you?"}
]
```

内部结果建议形态：

```json
[
  {"id": 1, "text": "你好"},
  {"id": 2, "text": "你好吗？"}
]
```

这个内部模型的意义是：

- 便于结果校验
- 便于失败重试
- 便于未来扩展到不同 provider

但再次强调：这不是外部 provider 的通用 HTTP 协议，只是项目内部的统一抽象。

## 7. API 翻译设计

### 7.1 产品定位

`API 翻译` 是“非 OpenAI 兼容”的官方翻译接口集合。

本项目不再纠结“是否属于大模型/机器翻译”语义差异，统一归入 `API 翻译`。

### 7.2 Provider 范围

纳入：

- 百度通用文本翻译
- 百度大模型翻译
- 腾讯机器翻译
- 阿里云机器翻译

不纳入：

- Microsoft Translator Text API
- DeepL API Free
- 华为翻译

### 7.3 provider 字段建议

#### 百度通用文本翻译

建议字段：

- `appId`
- `appKey` 或 `secret`
- 可选：`domain`

特点：

- 不是 OpenAI 兼容协议
- 需要独立签名逻辑

#### 百度大模型翻译

建议字段：

- `appId`
- `appKey` 或 `secret`
- 可选：模型/产品线
- 可选：自定义指令

特点：

- 仍建议单独 provider 处理
- 不与 OpenAI 兼容 provider 合并

#### 腾讯机器翻译

建议字段：

- `secretId`
- `secretKey`
- `region`
- `projectId`

特点：

- 走 `TC3-HMAC-SHA256`
- 不适合用“Base URL + API Key”抽象

#### 阿里云机器翻译

建议字段：

- `accessKeyId`
- `accessKeySecret`
- `endpoint`
- `scene` 或 edition

特点：

- 走阿里云签名逻辑
- 需要独立 HTTP 实现

### 7.4 外部协议必须遵循官方文档

`API 翻译` 这一层尤其不能自定义外部请求格式。

接入原则应写死：

- 百度通用文本翻译按百度官方文档字段和签名方式实现
- 百度大模型翻译按百度官方文档字段和鉴权方式实现
- 腾讯机器翻译按官方 `TextTranslate` 接口字段实现
  - 例如官方请求体使用 `SourceText`、`Source`、`Target`、`ProjectId`
- 阿里云机器翻译按官方 REST / HTTP 文档实现
  - 包括 endpoint、签名方式、请求体或参数格式

也就是说：

- 项目内部可以统一成 `TranslationRequest`
- 但外部绝不能要求所有 provider 都接受同一套 HTTP body
- provider adapter 必须负责“内部模型 -> 官方协议”的转换
- 响应解析也必须由 provider adapter 负责“官方响应 -> 内部统一结果”的转换

### 7.4 为什么要单独做 provider

如果把这些官方翻译接口硬塞进统一的 `baseUrl + apiKey` 模式，会出现：

- 鉴权方式不统一
- 请求头和签名逻辑不统一
- 错误码和限流语义不统一
- 后续排障和 UI 提示都很混乱

因此 `API 翻译` 只在产品层统一，在实现层仍必须拆 provider。

## 8. 字幕翻译接入流程

### 8.1 MPV / Exo 共用流程

统一流程建议：

1. 识别当前字幕是否为文本字幕
2. 获取原始字幕内容或服务端文本字幕流 URL
3. 下载并解析字幕
4. 根据设置选择 `AI 翻译` 或 `API 翻译`
5. 批量翻译
6. 生成当前会话使用的外挂字幕文件
7. 通过现有外挂字幕链路注入 `MPV / Exo`
8. 更新当前页字幕选择状态

### 8.2 触发方式

建议支持：

- 手动点击“翻译当前字幕”
- 开启自动翻译后，在检测到文本字幕时自动生成翻译外挂字幕

默认建议：

- 自动翻译默认关闭
- 用户主动开启后才自动运行

### 8.3 界面交互建议

播放器字幕面板建议新增：

- 翻译当前字幕
- 使用原文字幕
- 使用译文字幕
- 使用双语字幕

设置页建议新增：

- 启用 AI 翻译
- 启用 API 翻译
- 默认目标语言
- 自动翻译文本字幕
- 双语字幕优先

## 9. 文件生成与会话复用

### 9.1 当前决定

本次实现不做完整缓存系统。

原因：

- 当前使用场景里，真正需要翻译的片源占比不高
- 翻译成本总体可接受
- 完整缓存会明显增加实现复杂度
- 当前更适合先把“翻译链路打通”

因此本次只做：

- 当前播放会话内生成外挂字幕文件
- 当前播放页生命周期内尽量复用已生成结果

不做：

- 跨会话长期缓存
- 独立缓存目录管理
- 缓存键设计
- 缓存失效策略
- 缓存清理 UI

### 9.2 最小复用策略

建议保留最小复用能力，但不要上升到完整缓存系统：

- 同一播放页内，重复切换“原文 / 译文 / 双语”时复用本次翻译结果
- 同一会话内，如果 `MPV / Exo` 因切核或播放器重建重新挂载字幕，可复用当前内存或临时文件中的结果

这里的目标只是减少当前会话内重复翻译，不做长期持久化。

### 9.3 后续可选项

如果后续实际使用证明：

- 用户频繁重复翻译同一字幕
- 翻译成本显著增加
- 网络波动明显影响体验

再把“完整缓存系统”作为后续可选增强项单独引入。

## 10. 错误处理与回退

必须保证翻译失败不会影响正常播放。

建议规则：

- 翻译失败时，保留原字幕
- provider 超时或 4xx/5xx 时，给出轻提示
- 自动翻译失败时不弹阻塞对话框
- 手动触发失败时展示可读错误信息
- 返回结果条数与输入不一致时，整批视为失败

## 11. 隐私与安全

### 11.1 风险

字幕内容属于用户正在观看的媒体文本，可能包含：

- 版权文本
- 敏感对话
- 剧透内容

因此必须在设置页明确提示：

- 启用后将把字幕文本发送到你配置的第三方翻译服务

### 11.2 凭证存储

当前实现可以先沿用当前偏好存储方式，但应在任务列表中明确：

- 后续优先迁移到更安全的凭证存储方案

### 11.3 日志要求

禁止在日志中直接打印：

- `apiKey`
- `secretKey`
- `accessKeySecret`
- 完整字幕正文

日志最多只打印：

- provider 名称
- model 名称
- 请求条数
- 目标语言
- 成功 / 失败

## 12. 整体实施清单

### 12.1 设置模型与持久化

落点：

- `packages/lin_player_state/lib/app_state.dart`

任务：

- 新增 AI 翻译设置模型
- 新增 API 翻译设置模型
- 新增 provider 枚举
- 新增持久化 key
- 新增 getter / setter

### 12.2 翻译服务抽象

落点：

- `lib/services/translation/`

任务：

- 定义 provider 接口
- 定义统一请求/响应模型
- 定义错误模型
- 定义测试连接与测试翻译入口

### 12.3 Provider 实现

任务：

- 支持 `baseUrl + apiKey + model + prompt`
- 支持批量字幕翻译
- 支持 JSON 结构输出校验
- 百度通用文本翻译
- 百度大模型翻译
- 腾讯机器翻译
- 阿里云机器翻译

### 12.4 文本字幕翻译主链路

落点：

- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`

任务：

- 识别文本字幕流
- 下载并解析文本字幕
- 翻译并生成外挂字幕
- 注入 `MPV / Exo`

### 12.5 字幕显示与交互能力

任务：

- 生成“原文 + 译文”双语字幕
- 在播放器面板中切换显示
- 设置页增加“测试连接”
- 设置页增加“测试翻译”

### 12.6 可选增强项

以下属于可选增强，不阻塞主链路一次性完成：

- 接口文本翻译
  - 页面文案请求前后统一接入翻译服务
  - 控制页面刷新抖动
- ASS/SSA 文本提取翻译
  - 剔除特效标签，仅翻译可见文本
  - 跳过纯绘图/纯特效行
  - 在不破坏时间轴的前提下生成可读译文字幕
- 完整缓存系统
  - 设计跨会话缓存键
  - 管理翻译结果目录
  - 增加缓存失效与清理逻辑
  - 增加缓存命中统计与调试信息

## 13. 文件级任务清单

### 13.1 状态层

- `packages/lin_player_state/lib/app_state.dart`
  - 新增翻译配置字段
  - 新增存储/读取逻辑
  - 新增 provider 选择逻辑

### 13.2 UI 层

- `lib/settings_page.dart`
  - 新增 AI 翻译设置分组
  - 新增 API 翻译设置分组
  - 新增 provider 动态表单
  - 新增测试按钮

### 13.3 服务层

- `lib/services/translation/translation_models.dart`
- `lib/services/translation/translation_provider.dart`
- `lib/services/translation/translation_service.dart`
- `lib/services/translation/subtitle_translation_service.dart`
- `lib/services/translation/providers/*.dart`

### 13.4 播放页接入

- `lib/play_network_page.dart`
- `lib/play_network_page_exo.dart`

任务：

- 增加翻译字幕入口
- 增加翻译结果挂载逻辑
- 保持当前会话内 `MPV / Exo` 切换后结果可复用

## 14. 验收标准

### 14.1 功能验收

- 在 `MPV` 下可对文本字幕完成翻译并挂载译文字幕
- 在 `Exo` 下可对文本字幕完成翻译并挂载译文字幕
- AI 翻译与 API 翻译都可独立开启/关闭
- OpenAI 兼容 provider 可使用自定义 `baseUrl`
- 用户可自定义 prompt
- 用户可手动填写模型名
- 翻译失败时播放器继续正常使用原字幕

### 14.2 体验验收

- 首次翻译有进度反馈
- 双语模式可切换
- 当前会话内切换原文 / 译文 / 双语时无需重复翻译
- 当前会话内切换内核后翻译结果仍可复用

### 14.3 技术验收

- 不在日志中泄露密钥
- 不因翻译失败导致播放中断
- provider 实现彼此解耦
- 翻译服务可单元测试

## 15. 推荐开发顺序

推荐按以下顺序推进：

1. 状态模型与设置页骨架
2. 翻译服务抽象
3. OpenAI 兼容 provider
4. 文本字幕解析与会话级文件生成
5. `MPV / Exo` 播放页挂载译文字幕
6. API 翻译 provider
7. 双语字幕与接口文本翻译

原因：

- 先把骨架搭好，后面的 provider 才能不断插入。
- 先做 OpenAI 兼容路径，能最快验证整个链路是否可用。
- API 翻译 provider 的主要难点在鉴权和签名，适合在主链路跑通后再接。

## 16. 参考资料

### AI 翻译

- OpenAI Chat Completions API
  - https://developers.openai.com/api/reference/resources/chat
- OpenAI Models / Endpoints
  - https://developers.openai.com/api/docs/models/compare

### API 翻译

- 百度通用文本翻译
  - https://api.fanyi.baidu.com/product/113
- 百度大模型翻译
  - https://api.fanyi.baidu.com/product/133
- 腾讯机器翻译简介
  - https://cloud.tencent.com/document/api/551/15611
- 腾讯文本翻译接口
  - https://cloud.tencent.com/document/product/551/15619
- 腾讯云 API v3 签名方法
  - https://cloud.tencent.com/document/product/1759/105109
- 阿里云机器翻译 REST 调用方式
  - https://help.aliyun.com/zh/machine-translation/developer-reference/using-rest-api
- 阿里云 HTTP 接口调用指南
  - https://help.aliyun.com/zh/machine-translation/developer-reference/http-interface-invoking-guideline/
