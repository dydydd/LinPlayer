<div align="center">
  <img src="assets/app_icon.jpg" width="120" alt="LinPlayer" />
  <h1>LinPlayer</h1>
  <p>跨平台媒体播放器：本地 / Emby / Jellyfin / WebDAV（含 Plex PIN 登录）</p>
  <p><sub>Windows / macOS / Linux / Android / Android TV</sub></p>
  <p>
    <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white" />
    <img alt="Platforms" src="https://img.shields.io/badge/Platforms-Windows%20%7C%20macOS%20%7C%20Android%20%7C%20Android%20TV-informational?style=flat-square" />
    <img alt="Sources" src="https://img.shields.io/badge/Sources-Local%20%7C%20Emby%2FJellyfin%20%7C%20WebDAV-informational?style=flat-square" />
    <img alt="Player" src="https://img.shields.io/badge/Player-MPV%20%7C%20Exo-informational?style=flat-square" />
    <img alt="Danmaku" src="https://img.shields.io/badge/Danmaku-Local%20XML%20%7C%20Dandanplay-informational?style=flat-square" />
  </p>
  <p>
    <a href="../../releases/latest">
      <img alt="Release" src="https://img.shields.io/github/v/release/zzzwannasleep/LinPlayer?style=flat-square&display_name=tag&label=Release" />
    </a>
    <a href="../../releases">
      <img alt="Downloads" src="https://img.shields.io/github/downloads/zzzwannasleep/LinPlayer/total?style=flat-square&label=Downloads" />
    </a>
    <a href="../../stargazers">
      <img alt="Stars" src="https://img.shields.io/github/stars/zzzwannasleep/LinPlayer?style=flat-square&label=Stars" />
    </a>
    <a href="https://t.me/MikuContactGroup">
      <img alt="Telegram Group" src="https://img.shields.io/badge/Telegram-Group-26A5E4?style=flat-square&logo=telegram&logoColor=white" />
    </a>
  </p>
  <p>
    <a href="#download">下载</a> ·
    <a href="#quickstart">快速上手</a> ·
    <a href="#tv">Android TV</a> ·
    <a href="#faq">常见问题</a> ·
    <a href="#docs">文档</a> ·
    <a href="#star-history">Star History</a>
  </p>
</div>

> 说明：项目仍在持续迭代中，如遇到问题欢迎带日志/截图反馈。

## <a id="download"></a>下载

- 进入 [Releases](../../releases) 下载对应平台的安装包。
- Android / Android TV：通常优先选择 `arm64-v8a`。

## <a id="quickstart"></a>快速上手

1. 本地播放：从首页选择本地文件/目录。
2. 服务器播放：在“设置”里添加 Emby/Jellyfin/WebDAV/Plex 服务器。
3. 可选：使用“批量导入”从分享文本中快速添加多个服务器（见文档）。

## <a id="tv"></a>Android TV

### 手机扫码控制 / 网页设置

- TV 端：设置 → TV 专区 → 打开“手机扫码控制”，按提示扫码。
- 手机打开网页后，可进行遥控、添加服务器、调整 TV 相关设置。

### 内置代理（mihomo）（仅 Android TV）

- TV 端：设置 → TV 专区 → 打开“内置代理（mihomo）”。
- “订阅地址（可选）”：可在 TV 端设置，也可在扫码后的网页设置里填写；保存后若内置代理正在运行会自动重启生效，否则下次开启内置代理生效。
- “添加线路”：可自定义媒体服务器域名/IP/CIDR；保存后写入规则组并自动重启内置代理生效（避免漏走直连导致卡顿）。
- 代理面板（metacubexd）：开启后可在 TV 本机访问 `http://127.0.0.1:9090/ui/`。

## <a id="faq"></a>常见问题

- DNS 解析失败 / Host lookup：先用系统浏览器确认域名可访问；必要时改填 IP 或切换 http/端口（如 8096/8920）。
- 播放 404：请先确认服务端网页端能正常播放同一条目。
- 批量导入解析不到地址：请确认分享文本包含 http(s) URL 或域名/IP（也支持无 scheme，如 `example.com 443`）。

## <a id="docs"></a>文档

- Wiki（VitePress）：https://linplayer.902541.xyz
- 本地预览 Wiki：`cd docs && npm install && npm run dev`
- 用户文档：`docs/SERVER_IMPORT.md`
- 桌面端播放页快捷键 / 鼠标侧键：`docs/guide/playback.md`（可在设置 → 交互设置中自定义）
- 开发者文档：`docs/dev/README.md`
- 部署 Wiki（Cloudflare Pages）：`docs/deploy/cloudflare-pages.md`

## <a id="star-history"></a>Star History

<a href="https://star-history.com/#zzzwannasleep/LinPlayer&Date">
  <img alt="Star History" src="https://api.star-history.com/svg?repos=zzzwannasleep/LinPlayer&type=Date" width="100%" />
</a>

## 鸣谢与参考

### 引用 / 上游

- Anime4K：https://github.com/bloc97/Anime4K（本项目内置部分 GLSL shader：`assets/shaders/anime4k/`）
- TV Remote（web UI / base assets）：https://github.com/synamedia-senza/remote（ISC）；本项目内置静态资源：`assets/tv_remote/`

### 文档

- Emby 项目与文档：https://dev.emby.media/doc/restapi/index.html
- Jellyfin API 文档：https://api.jellyfin.org/
- Plex 开发者文档：https://developer.plex.tv/pms/
