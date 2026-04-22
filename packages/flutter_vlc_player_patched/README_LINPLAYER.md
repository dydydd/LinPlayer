# LinPlayer 补丁说明（`flutter_vlc_player_patched`）

该目录是对 `flutter_vlc_player 7.4.4` 的本地补丁版本。

当前目标：

- iOS 继续保留 VLC 内核。
- Android 不再把 `flutter_vlc_player` 作为原生插件注册。
- Android 构建产物不再打包 `libvlc.so` / `libvlcjni.so`，避免 APK 体积暴涨。

当前补丁点：

- `pubspec.yaml`
  - 删除 `flutter.plugin.platforms.android` 声明。
  - 仅保留 `ios` 插件注册。

升级注意：

1. 先用上游新版本覆盖该目录。
2. 重新应用上述 `pubspec.yaml` 平台声明补丁。
3. 重新执行 `flutter pub get`。
4. 构建 Android release，确认 APK 内不再包含 `libvlc.so`。
