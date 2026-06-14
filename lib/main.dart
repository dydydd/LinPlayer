import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/providers/app_providers.dart';
import 'core/utils/platform_utils.dart';
import 'desktop/desktop_app.dart';
import 'desktop/window/desktop_window_chrome.dart';
import 'tv/tv_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit 仅在非 Android 平台初始化
  // Android 使用原生 MPV (libplayer.so) 通过平台通道调用
  if (!Platform.isAndroid) {
    MediaKit.ensureInitialized();
  }

  await initializeAppPreferences();

  // 桌面端：初始化无边框窗口 + 自绘标题栏
  if (isDesktopPlatform && !isTvPlatform) {
    await initDesktopWindow();
  }

  if (isTvPlatform) {
    // TV 端入口
    runApp(
      const ProviderScope(
        child: LinPlayerTvApp(),
      ),
    );
  } else if (isDesktopPlatform) {
    runApp(
      const ProviderScope(
        child: LinPlayerDesktopApp(),
      ),
    );
  } else {
    runApp(
      const ProviderScope(
        child: LinPlayerApp(),
      ),
    );
  }
}
