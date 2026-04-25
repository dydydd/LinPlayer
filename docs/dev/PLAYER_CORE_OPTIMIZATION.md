# MPV / Exo 播放内核优化建议

> 面向当前仓库实现的开发文档。目标不是泛谈播放器原理，而是结合现有代码，明确 LinPlayer 里 `MPV` 与 `Exo` 的职责边界、现状问题和可执行优化项。

## 1. 结论先行

- `MPV` 应继续作为高兼容主内核。
- `Exo` 适合作为 Android 侧的轻量/系统兼容内核，不适合承担“万能片源兼容”职责。
- 如果目标是尽量覆盖 `PGS/SUP`、`ASS 特效字幕`、`Dolby Vision P5/P8`、`DTS/E-AC-3/TrueHD`，优先级应该是：
  1. 先把 `MPV` 做强。
  2. 再把 `Exo` 做成“明确边界、尽量不误伤”的备用方案。

## 2. 当前代码结构

### 2.1 MPV 路径

- 页面：
  - `lib/player_screen.dart`
  - `lib/play_network_page.dart`
- 封装：
  - `packages/lin_player_player/lib/player_service.dart`
- patched 依赖：
  - `packages/media_kit_patched`

当前特征：

- 通过 `media_kit` / `libmpv` 承担播放。
- 已有 `Dolby Vision / HDR` 的 best-effort 规避逻辑。
- 已有 `libass`、ASS 兼容参数、外部 `mpv` 拉起策略。
- 已有网络缓存、代理、Anime4K、轨道选择等封装。

### 2.2 Exo 路径

- 页面：
  - `lib/player_screen_native.dart`
  - `lib/play_network_page_native.dart`
- patched 依赖：
  - `packages/video_player_android_patched`

当前特征：

- 仅 Android 可用。
- 基于 `video_player_android` 的本地增强版。
- 已增强音轨/字幕轨枚举与切换。
- 目前字幕渲染是“文本化显示”，不是完整的 subtitle compositor。

## 3. 当前能力判断

### 3.1 字幕

#### MPV

优点：

- 已启用 `libass`。
- 桌面端额外开启：
  - `embeddedfonts=yes`
  - `sub-ass-vsfilter-aspect-compat=yes`
  - `sub-ass-vsfilter-blur-compat=yes`
- 对 `ASS/SSA` 特效字幕的方向是正确的。

现有短板：

- `play_network_page.dart` 里对 Emby 外挂字幕注入时，只接受“文本字幕流”。
- 这意味着服务端外挂的 `PGS/SUP` 类图形字幕不会被这条注入链路带进 mpv。
- 播放页手动外挂字幕的 UI 也偏向文本字幕场景。

#### Exo

优点：

- 已具备字幕轨枚举、选择、关闭、外挂字幕添加能力。
- 对普通 `SRT / VTT / 简单 ASS` 文本场景可用。

现有短板：

- `VideoPlayer.java` 将 `CueGroup` 统一压平成 `String`。
- `PlatformVideoView.java` 与 Flutter texture overlay 都只显示纯文本。
- 这会导致：
  - `ASS/SSA` 的定位、旋转、karaoke、渐变、边框、字体样式等特效丢失。
  - `PGS/SUP` 这类 bitmap cue 基本无法正确显示。
- 当前 Exo 路径不应被定义为“特效字幕兼容内核”。

### 3.2 Dolby Vision / HDR

#### MPV

优点：

- 已能探测 `Dolby Vision` 与 `HDR`。
- Android 上会在杜比/HDR 场景切 `gpu-next`。
- 杜比场景会尝试关闭硬解，规避绿紫偏色。
- 桌面端检测到 `DV Profile 5` 时会优先拉起外部 `mpv`。

现有短板：

- 桌面端如果没有可用的外部 `mpv`，`P5` 仍不能保证稳。
- 当前对杜比视界的用户提示还偏“被动”，缺少更直观的诊断信息。
- 还没有“基于片源能力自动推荐/自动切核”的统一策略。

#### Exo

优点：

- 走 Android 平台解码链，普通 SDR/HDR10 机型上有时能获得更低功耗。

现有短板：

- 项目里没有任何针对 `Dolby Vision / HDR 偏色` 的专项补救逻辑。
- 结果强依赖设备 SoC、MediaCodec、厂商调色链。
- 不适合对 `P5/P8` 做“不偏色”承诺。

### 3.3 音频

#### MPV

优点：

- `media_kit_patched` 上游格式清单覆盖 `DTS / DTS-HD / E-AC-3 / TrueHD`。
- Android 侧 changelog 明确写了 `static link FFmpeg w/ libmpv`。
- 这类高兼容音频仍应主要由 MPV 承担。

#### Exo

优点：

- 对系统常见的 `AAC / AC3 / E-AC-3` 场景可利用平台解码。

现有短板：

- 当前仅集成 `media3-exoplayer` 本体与流媒体模块。
- 没有软件解码扩展，没有兜底链路。
- `DTS / DTS-HD / TrueHD` 完全不能按“项目级稳定兼容”来定义。

## 4. 推荐定位

建议把两套内核的产品定位写死，不再模糊：

- `MPV`
  - 主打：高兼容、本地高码率、复杂字幕、复杂音频、DV/HDR 疑难片源。
- `Exo`
  - 主打：Android 普通在线播放、普通字幕、普通音频、系统解码优先、功耗友好。

一旦定位明确，后面的优化方向就不会互相拉扯。

## 5. 优化优先级

### P0：应该尽快做

#### P0.1 自动切核策略

目标：

- 在进入播放前，根据片源能力自动推荐或自动切换 `MPV / Exo`。

建议命中条件：

- 命中以下任一条件时优先 `MPV`：
  - 字幕含 `PGS / SUP / DVB / VobSub`
  - 字幕含 `ASS/SSA` 且标题明显是特效字幕组版本
  - 音频含 `DTS / DTS-HD / TrueHD`
  - 视频命中 `Dolby Vision`
  - 容器或流信息不完整、服务端误报“不可直放”

落点建议：

- `show_detail_page.dart`
- `play_network_page.dart`
- `play_network_page_native.dart`
- `AppState` 中补“自动选内核策略”偏好

#### P0.2 Exo 字幕渲染重做

目标：

- 不再把字幕简单压平成纯文本。

建议方向：

- Android `platformView` 路径优先接入原生 `SubtitleView` 或等价实现。
- 保留 `Cue` 的样式信息，而不是 `cue.text.toString()`。
- 对 bitmap cue 做渲染，至少不要把 `PGS/SUP` 静默吞掉。

验收标准：

- `ASS` 基础样式不丢。
- `PGS/SUP` 至少可见。
- 平台视图与 texture 视图行为尽量一致。

#### P0.3 MPV 外挂图形字幕链路补全

目标：

- 让 MPV 路径能处理 Emby/Jellyfin 外挂 `PGS/SUP`。

建议方向：

- 放宽 `_isTextSubtitleStream(...)` 的过滤策略。
- 为 `sup/pgs` 构建明确的 subtitle stream URL 与 mime/format 传递策略。
- UI 层允许 `.sup` 类型外挂字幕。

### P1：高价值但不阻塞主线

#### P1.1 播放诊断面板

目标：

- 让用户和开发者一眼看到当前到底在播什么。

建议展示：

- 当前内核：`MPV / Exo`
- 视频 codec / profile / bit depth / HDR / DV profile
- 音频 codec / channels
- 字幕 codec / text vs bitmap
- 当前是否硬解
- 当前是否外部 `mpv`

价值：

- 这会直接降低“为什么偏色 / 为什么没字幕 / 为什么没声音”的排障成本。

#### P1.2 桌面端外部 mpv 体验补齐

目标：

- 让 `DV P5` 的最佳路径默认可用，而不是靠用户手动配置。

建议方向：

- 自动探测常见安装路径。
- 设置页展示当前探测结果。
- 未找到外部 `mpv` 时给出明确提示，而不是静默退回内部路径。

#### P1.3 Exo 能力边界显式提示

目标：

- 不让用户误以为 Exo 是高兼容内核。

建议方向：

- 在切换到 Exo 时给一句简明说明：
  - 适合普通在线播放
  - 复杂字幕 / DTS / 杜比片源建议改用 MPV

### P2：中长期项

#### P2.1 Exo 音频兜底策略

两个方向二选一：

- 方向 A：继续把 Exo 定位成“普通片源内核”，不补软件解码，只做清晰提示与自动切核。
- 方向 B：如果坚持把 Exo 往高兼容做，就需要评估引入软件解码扩展或自定义 FFmpeg-based 兜底方案。

就当前项目定位，建议优先选方向 A。

#### P2.2 样本片源回归集

建议准备最小样本集：

- `ASS 特效字幕`
- `PGS/SUP`
- `DV P5`
- `DV P8`
- `HDR10`
- `DTS`
- `DTS-HD`
- `E-AC-3`
- `TrueHD`

每次改内核能力时跑一轮人工回归，至少保证“不倒退”。

## 6. 建议实施顺序

建议按下面顺序推进：

1. 先做自动切核。
2. 再补 MPV 对外置图形字幕的处理。
3. 再重做 Exo 字幕渲染。
4. 补播放诊断面板。
5. 最后再决定 Exo 是否值得继续做软件解码兜底。

这个顺序的原因很简单：

- 自动切核可以最快降低用户踩坑概率。
- MPV 本身已经是更强内核，补它的短板收益最高。
- Exo 的深度兼容改造成本高，应该放在“边界明确”之后再做。

## 7. 最终建议

如果只做一件事：

- 做“自动切到 MPV”的策略。

如果做三件事：

- 自动切核
- MPV 外挂图形字幕补全
- Exo 字幕渲染重做

如果做完整方案：

- 把 `MPV` 做成高兼容内核
- 把 `Exo` 做成边界清晰、失败可预期的 Android 备用内核
- 再加一层“播放前智能决策 + 播放中诊断信息”

这样这两套内核不是彼此竞争，而是各司其职。
