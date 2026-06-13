import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/app_providers.dart';
import 'theme/tv_theme.dart';
import 'routes/tv_router.dart';

/// TV 端应用入口
/// 强制深色模式，TV 专属主题
class LinPlayerTvApp extends ConsumerWidget {
  const LinPlayerTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'LinPlayer TV',
      debugShowCheckedModeBanner: false,
      theme: TvTheme.theme,
      darkTheme: TvTheme.theme,
      themeMode: ThemeMode.dark, // TV 端强制深色模式
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en'),
      ],
      routerConfig: tvRouter,
    );
  }
}
