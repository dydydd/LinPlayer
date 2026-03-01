# 低版本 TV 端说明文档（Android 4.4 / API 19）

本文档面向使用者与开发者，描述低版本 TV 端的功能、页面结构、服务器配置与构建方式。

## 1. 项目简介

- 工程位置：`legacy/tv-legacy/`
- 技术栈：Java + XML/View（兼容 API 19）
- UI 风格：
  - 窗口全透明
  - 背景图：`https://bing.img.run/rand_uhd.php`（随机 UHD）
  - 组件：圆角、无边框、半透明（可调）+ 少量模糊（可调）

## 2. 服务器与数据源（Emby）

首页/喜欢/搜索/媒体库详情目前按 **Emby 官方 API** 获取数据。

### 2.1 Base URL

建议填写 Emby 服务根地址（不必带 `/emby`，带了也可以）：
- `http://192.168.1.2:8096`
- `https://example.com`
- `http://example.com/emby`（可用，App 内会规范化）

### 2.2 Token / API Key

在 “Servers / Add” 中的 `API key / token` 支持两种来源：
- 直接填写 Emby 后台生成的 API Key
- 或使用 App 内置的登录流程获取到的 AccessToken（同样可作为 `api_key` 使用）

### 2.3 服务器管理与切换

- 进入 Servers 页面：
  - 首页左上角 “服务器按钮” **长按**：进入 `Servers` 管理页
  - 或首次启动无服务器时会强制进入 `Servers`
- 切换服务器：
  - 首页左上角 “服务器按钮” **点击**：弹窗分两部分
    - 第一部分：当前链接服务器（仅图标 + 名称）
    - 第二部分：其他已添加服务器（仅图标 + 名称）
  - 点击任一服务器切换为当前服务器，并刷新首页/喜欢

## 3. 首页结构

### 3.1 顶栏

- 左侧：服务器按钮（点击切换、长按管理）
- 中间：页签切换（`首页` / `喜欢`）
- 右侧：
  - 搜索按钮：进入搜索页
  - 样式按钮：打开样式调节弹窗（透明度/模糊度）

### 3.2 首页三段内容

1) **观看记录**（Resume）
- 卡片：剧/电影封面
- 两行字：
  - 第一行：剧名（Episode 会显示 `SeriesName + SxxExx`）
  - 第二行：观看到的时间（`观看至 mm:ss` 或 `h:mm:ss`）
- 点击：直接播放，并尝试从记录的时间点续播

2) **媒体库**（Views）
- 横向滑动展示媒体库封面 + 名称
- 点击：进入媒体库详情页（网格展示库内条目）

3) **各媒体库预览**
- 每个媒体库一行，横向展示 10 个条目
- 卡片两行字：
  - 第一行：名称
  - 第二行：`★评分 + 上映年份/首播日期`
- 点击：Series 进入详情页；Movie/Episode 直接播放

## 4. 喜欢页（Favorites）

喜欢页展示用户标记为喜欢的内容，并提供三类快速筛选：
- 电视剧（Series）
- 电影（Movie）
- 集（Episode）

布局为网格卡片，卡片两行字：
- 第一行：名称（Episode 会优先显示 `SeriesName + SxxExx`）
- 第二行：`★评分 + 上映年份/首播日期`（若服务端未返回则为空）

## 5. 搜索页

- 入口：首页右上角搜索按钮
- 支持搜索：Series / Movie / Episode
- 结果展示为网格卡片
- 点击行为同首页：
  - Series → 进入详情页
  - Movie/Episode → 直接播放

## 6. 样式调节（透明度/模糊度）

入口：首页右上角样式按钮。

- 透明度：控制“玻璃面板”背景透明度（范围 5% ~ 90%）
- 模糊度：控制背景图模糊半径（范围 0 ~ 24）

说明：
- 透明度会影响：顶栏按钮、页签容器、喜欢页筛选条、卡片背景等
- 模糊度会影响：背景图（使用降采样 + blur 后再放大回屏幕尺寸）

## 7. 播放与续播

- Movie/Episode：从首页/喜欢/搜索直接打开播放器
- Series：进入旧的 Show 详情页（ShowDetail / EpisodeList 等）
- 续播：从观看记录进入时会携带进度（`position_ms`），播放器会 `seekTo()` 后播放

## 8. 代理与远程（可选）

### 8.1 内置 per-app 代理（mihomo）

- 不使用 `VpnService`
- 代理监听 `127.0.0.1`，仅本 App 请求通过 `ProxySelector` 走代理
- 订阅 URL、开关等见 Settings 页面与 `API.md` 说明

### 8.2 QR Remote（手机扫码配置）

- 在 `Servers` 页面右侧显示二维码与 URL
- 扫码后可在手机端网页中批量添加服务器、配置订阅/代理、基础播放控制
- 详细接口请看：`legacy/tv-legacy/API.md`

## 9. 开发与构建

### 9.1 环境要求

- Android Studio（建议使用自带 JDK 17+）
- Android SDK 已安装（至少包含项目所需的 build-tools / platforms）

### 9.2 构建方式

1) 用 Android Studio 打开 `legacy/tv-legacy/`
2) 确保 `local.properties` 中有 `sdk.dir=...`（Android Studio 会生成）
3) 或命令行设置环境变量后构建（Windows）：

`$env:ANDROID_HOME="$env:LOCALAPPDATA\\Android\\Sdk"; $env:ANDROID_SDK_ROOT=$env:ANDROID_HOME; cd legacy/tv-legacy; .\\gradlew.bat :app:assembleDebug`

### 9.3 常见问题

- 依赖下载失败 / TLS 握手失败：
  - 优先确认使用的是较新的 JDK（建议 17+，Android Studio 自带即可）
  - 检查网络环境（公司代理/抓包/SSL 代理可能导致握手失败）
  - 若已成功下载过依赖，可使用 `--offline` 构建

## 10. 关键入口文件

- 首页：`legacy/tv-legacy/app/src/main/java/com/linplayer/tvlegacy/MainActivity.java`
- Emby 首页/搜索/喜欢：`legacy/tv-legacy/app/src/main/java/com/linplayer/tvlegacy/emby/EmbyClient.java`
- 播放器：`legacy/tv-legacy/app/src/main/java/com/linplayer/tvlegacy/PlayerActivity.java`
- 服务器管理：`legacy/tv-legacy/app/src/main/java/com/linplayer/tvlegacy/ServersActivity.java`
- 样式偏好：`legacy/tv-legacy/app/src/main/java/com/linplayer/tvlegacy/AppPrefs.java`

