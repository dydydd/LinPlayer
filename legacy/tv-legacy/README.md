# LinPlayer 低版本 TV 端（Android 4.4 / API 19）

独立 Android 工程（Java + XML/View），用于 **Android 4.4（API 19）** 的电视/盒子设备。

核心目标：
- **全透明窗口 + 背景图**：背景图 API 为 `https://bing.img.run/rand_uhd.php`，并支持模糊/透明度调节。
- **玻璃拟态 UI**：圆角、无边框、半透明（可调）+ 轻微模糊。
- **Emby 首页**：按 Emby 官方 API 拉取首页数据（观看记录 / 媒体库 / 媒体库预览）+ 喜欢 + 搜索。
- **内置 per-app 代理**（无需 `VpnService`）：mihomo 监听 `127.0.0.1`，仅本 App 走代理。
- 统一 `User-Agent`：`LinPlayer/<versionName>`（App HTTP + 播放请求）。

## 说明文档

- 使用说明（推荐先看）：`legacy/tv-legacy/TV_GUIDE.md`
- 接口/约定：`legacy/tv-legacy/API.md`

## 打开与构建

用 Android Studio 打开 `legacy/tv-legacy/`。

命令行构建（Windows）：
- 先确保 SDK 路径可用：`local.properties` 中的 `sdk.dir=...`（Android Studio 会自动生成），或设置 `ANDROID_HOME/ANDROID_SDK_ROOT`
- 执行：`.\gradlew.bat :app:assembleDebug`

## 页面概览（WIP）

- 首页：顶部（服务器切换 / 首页-喜欢 / 搜索 / 样式）+ 三段内容（观看记录 / 媒体库 / 各媒体库预览）
- 喜欢页：电视剧 / 电影 / 集 三类切换
- 搜索页：关键字搜索（Series/Movie/Episode）
- 媒体库详情页：进入媒体库后用网格展示条目
- 详情/播放：Show 详情/剧集列表/播放（旧页面仍保留）
- Servers：服务器管理 + 右侧 QR Remote（手机扫码快速配置）
- Settings：代理/订阅等设置（样式调节在首页右上角）

## 备注

- `local.properties` 不提交；Android Studio 会生成。
- 如需使用内置 mihomo 代理，请放置 `armeabi-v7a` 的 mihomo：`app/src/main/jniLibs/armeabi-v7a/libmihomo.so`
- mihomo 配置运行时生成：`<app filesDir>/mihomo/config.yaml`
