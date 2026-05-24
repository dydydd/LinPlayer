import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'core/services/app_logger.dart';
import 'core/services/cache_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();
  log.i('Main', 'media_kit 初始化完成');

  CacheService.configureMemoryCache();

  await CacheService.runStartupCleanup();
  log.i('Main', '缓存清理完成');

  log.i('Main', '应用启动');
  log.i('Main', 'Flutter ${WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio}x');

  FlutterError.onError = (FlutterErrorDetails details) {
    log.eWithStack('Flutter', '未捕获的Flutter错误', details.exception, details.stack);
    FlutterError.presentError(details);
  };

  runApp(
    const ProviderScope(
      child: LinPlayerApp(),
    ),
  );
}
