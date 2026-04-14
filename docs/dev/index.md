# 开发者文档（Developer Docs）

本目录包含 **二次开发 / 构建发布 / 维护** 相关内容；用户使用说明请看：`/guide/quickstart` 与 `docs/` 下的用户文档。

## 快速开始

建议使用 Flutter stable 3.x，并先运行 `flutter doctor -v` 确认环境正常。

```bash
flutter pub get
flutter run
```

## 常用命令

```bash
flutter analyze
flutter test

# Android（含 split-per-abi）
flutter build apk --split-per-abi

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# iOS（无签名）
flutter build ios --release --no-codesign

# Linux
flutter build linux --release
```

> Windows 如提示 “Building with plugins requires symlink support”，请在系统设置中开启“开发者模式”。

## Android 签名（OTA 覆盖安装）

见：`/dev/ANDROID_SIGNING`

## Android TV：内置代理资源

Android TV 的内置代理使用 `mihomo + metacubexd`。CI 会自动拉取/打包相关资源；本地从源码构建如需更新可运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/fetch_tv_proxy_assets.ps1
```

> 如遇 GitHub API 限流，可设置环境变量 `GITHUB_TOKEN` 或 `GH_TOKEN`。

路线图与实现说明：`/dev/TV_PROXY_ROADMAP`

## 源码导览

- 项目结构与各模块职责：`/dev/ARCHITECTURE`
- 桌面端 UI 专项重构说明：`/dev/DESKTOP_UI_ARCHITECTURE`
- 播放内核优化建议：`/dev/PLAYER_CORE_OPTIMIZATION`
- 翻译服务设计与任务清单：`/dev/TRANSLATION_SERVICE_TASKLIST`
- 预加载能力现状评估：`/dev/PRELOAD_ASSESSMENT`
- 预加载重构任务清单：`/dev/PRELOAD_REFACTOR_TASKLIST`

> 预加载当前口径：`EXO` 基线仍未恢复，`MPV` 前半段仍疑似未真正复用预加载；排查与验收请优先看 `PRELOAD_REFACTOR_TASKLIST`。

## 插件文档

- 宿主开发清单：`/dev/PLUGIN_HOST_V1`
- 插件作者规范：`/dev/PLUGIN_SPEC_V1`

## 维护记录

- 最近更新日志（2026-03）：`/dev/RECENT_CHANGELOG`

## CI / 发布

- Nightly 构建：`.github/workflows/build-all.yml`
- Stable 发布：`.github/workflows/release-latest.yml`
