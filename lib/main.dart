import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/providers/app_providers.dart';
import 'core/utils/platform_utils.dart';
import 'desktop/desktop_app.dart';
import 'tv/tv_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await initializeAppPreferences();

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
