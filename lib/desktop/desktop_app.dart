import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import 'routes/desktop_router.dart';
import 'utils/desktop_shortcuts.dart';

/// 桌面端应用入口
class LinPlayerDesktopApp extends ConsumerWidget {
  const LinPlayerDesktopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(desktopRouterProvider);
    
    return MaterialApp.router(
      title: 'LinPlayer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        // 桌面端特定主题调整
        scaffoldBackgroundColor: AppTheme.lightTheme.scaffoldBackgroundColor,
      ),
      darkTheme: AppTheme.darkTheme.copyWith(
        // 桌面端特定主题调整
        scaffoldBackgroundColor: AppTheme.darkTheme.scaffoldBackgroundColor,
      ),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        return DesktopShortcutsWrapper(child: child!);
      },
    );
  }
}
