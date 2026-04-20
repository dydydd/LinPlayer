import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:lin_player_core/app_config/app_config.dart';
import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_server_api/services/emby_api.dart';
import 'package:lin_player_server_api/services/http_stream_proxy.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'desktop_ui/desktop_shell.dart';
import 'home_page.dart';
import 'server_page.dart';
import 'webdav_home_page.dart';
import 'services/app_back_intent.dart';
import 'services/app_diagnostics_log.dart';
import 'services/app_update_flow.dart';
import 'services/built_in_proxy/built_in_proxy_service.dart';
import 'services/app_route_observer.dart';
import 'services/emby_http_client_factory.dart';
import 'services/plugins/plugin_governance_flow.dart';
import 'services/system_http_proxy_service.dart';
import 'services/tv_remote/tv_remote_command_dispatcher.dart';
import 'services/tv_remote/tv_remote_service.dart';
import 'tv/tv_background.dart';
import 'tv/tv_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
const Duration _bootstrapChannelTimeout = Duration(seconds: 3);
const Duration _bootstrapStorageTimeout = Duration(seconds: 4);
bool _bootstrapFailureAppShown = false;

final class _SnappedTextScaler implements TextScaler {
  const _SnappedTextScaler(
    this.scaler, {
    required this.devicePixelRatio,
  });

  final TextScaler scaler;
  final double devicePixelRatio;

  @override
  double scale(double fontSize) {
    final scaled = scaler.scale(fontSize);
    final dpr = devicePixelRatio;
    if (dpr <= 0) return scaled;
    return (scaled * dpr).roundToDouble() / dpr;
  }

  @override
  double get textScaleFactor => scaler.scale(1.0);

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) {
    if (minScaleFactor == 0 && maxScaleFactor == double.infinity) {
      return this;
    }
    final clamped = scaler.clamp(
      minScaleFactor: minScaleFactor,
      maxScaleFactor: maxScaleFactor,
    );
    if (identical(clamped, scaler)) return this;
    return _SnappedTextScaler(clamped, devicePixelRatio: devicePixelRatio);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _SnappedTextScaler &&
        other.scaler == scaler &&
        other.devicePixelRatio == devicePixelRatio;
  }

  @override
  int get hashCode => Object.hash(scaler, devicePixelRatio);

  @override
  String toString() => 'snapped($scaler @${devicePixelRatio}x)';
}

void main() async {
  _installDiagnosticsHooks();
  await runZonedGuarded(
    () async {
      try {
        await _bootstrapApp();
      } catch (error, stackTrace) {
        AppDiagnosticsLogger.instance.error(
          'bootstrap',
          'Application bootstrap failed',
          error: error,
          stackTrace: stackTrace,
        );
        _showBootstrapFailureApp(error, stackTrace);
      }
    },
    (error, stackTrace) {
      AppDiagnosticsLogger.instance.error(
        'zone',
        'Unhandled zone error',
        error: error,
        stackTrace: stackTrace,
      );
      _showBootstrapFailureApp(error, stackTrace);
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        AppDiagnosticsLogger.instance.debug(
          'stdout',
          line,
        );
        parent.print(zone, line);
      },
    ),
  );
}

void _installDiagnosticsHooks() {
  FlutterError.onError = (details) {
    AppDiagnosticsLogger.instance.error(
      'flutter',
      details.exceptionAsString(),
      data: <String, Object?>{
        'library': details.library ?? '',
        'context': details.context?.toDescription() ?? '',
      },
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppDiagnosticsLogger.instance.error(
      'platform',
      'Unhandled platform error',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  };
}

Future<void> _bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPaintSizeEnabled = false;
  debugPaintBaselinesEnabled = false;
  debugPaintPointersEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugRepaintRainbowEnabled = false;
  assert(() {
    debugPaintSizeEnabled = false;
    debugPaintBaselinesEnabled = false;
    debugPaintPointersEnabled = false;
    debugPaintLayerBordersEnabled = false;
    debugRepaintRainbowEnabled = false;
    return true;
  }());
  // Ensure native media backends (mpv) are ready before any player is created.
  await _runBootstrapStep(
    'media_kit',
    'MediaKit initialization failed; continuing with degraded playback support',
    () async {
      MediaKit.ensureInitialized();
    },
  );
  await _runBootstrapStep(
    'device',
    'Device type detection failed; falling back to phone defaults',
    () => DeviceType.init().timeout(_bootstrapChannelTimeout),
  );
  final defaultDeviceName = await _runBootstrapValueStep<String>(
    'device',
    'Device name lookup failed; using platform fallback',
    () => DeviceType.deviceDisplayName().timeout(_bootstrapChannelTimeout),
    fallback: kIsWeb ? 'Web' : defaultTargetPlatform.name,
  );
  AppDiagnosticsLogger.instance.info(
    'app',
    'Application bootstrap started',
    data: <String, Object?>{
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'isTv': DeviceType.isTv,
      'deviceName': defaultDeviceName,
    },
  );

  final appConfig = AppConfig.current;
  ServerApiBootstrap.configure(
    userAgentProduct: appConfig.userAgentProduct,
    defaultClientName: appConfig.displayName,
    defaultDeviceName: defaultDeviceName,
    appVersion: '1.0.0',
  );

  try {
    final info = await PackageInfo.fromPlatform();
    ServerApiBootstrap.configure(
      userAgentProduct: appConfig.userAgentProduct,
      defaultClientName: appConfig.displayName,
      defaultDeviceName: defaultDeviceName,
      appVersion: '${info.version}+${info.buildNumber}',
    );
    AppDiagnosticsLogger.instance.info(
      'app',
      'Package info loaded',
      data: <String, Object?>{
        'version': '${info.version}+${info.buildNumber}',
        'product': appConfig.displayName,
      },
    );
  } catch (_) {
    // PackageInfo is best-effort; keep default version if unavailable.
  }

  EmbyApi.setClientFactory(EmbyHttpClientFactory.createClient);
  EmbyApi.setRouteLabelBuilder(EmbyHttpClientFactory.describeRoute);
  CoverCacheManager.configureHttpClientFactory(
      EmbyHttpClientFactory.createClient);
  HttpStreamProxyServer.instance.configureHttpClientFactory(
    EmbyHttpClientFactory.createClient,
  );

  var appState = AppState();
  final loadedState = await _runBootstrapValueStep<bool>(
    'app_state',
    'Failed to restore persisted app state; using defaults',
    () async {
      await appState.loadFromStorage().timeout(_bootstrapStorageTimeout);
      return true;
    },
    fallback: false,
  );
  if (!loadedState) {
    appState = AppState();
  }
  if (DesktopShell.isDesktopTarget) {
    await SystemHttpProxyService.instance.refresh();
  }
  AppDiagnosticsLogger.instance.info(
    'app',
    'App state loaded',
    data: <String, Object?>{
      'servers': appState.servers.length,
      'playerCore': appState.playerCore.name,
      'tvBuiltInProxyEnabled': appState.tvBuiltInProxyEnabled,
    },
  );
  if (DeviceType.isTv && !appState.hasTvRemoteEnabledPreference) {
    // Make phone scan/pairing available out-of-box on Android TV.
    try {
      await appState.setTvRemoteEnabled(true);
    } catch (_) {
      // Best-effort; ignore storage errors.
    }
  }
  if (DesktopShell.isDesktopTarget) {
    await appState.applyDesktopThemeFromSystemIfNeeded(
      systemBrightness:
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    unawaited(appState.validateActiveServerForDesktop());
  }

  TvRemoteCommandDispatcher.instance.bindNavigatorKey(_rootNavigatorKey);

  // Best-effort: request the highest refresh rate on Android devices.
  await HighRefreshRate.apply();
  // Best-effort: keep launcher icon in sync with settings (Android only).
  // ignore: unawaited_futures
  AppIconService.setIconId(appState.appIconId);

  if (DeviceType.isTv && appState.tvRemoteEnabled) {
    unawaited(TvRemoteService.instance.start(appState: appState));
  }
  if (DeviceType.isTv) {
    unawaited(BuiltInProxyService.instance.refresh());
  }
  if (DeviceType.isTv && appState.tvBuiltInProxyEnabled) {
    unawaited(() async {
      try {
        await BuiltInProxyService.instance.start();
      } catch (_) {
        // Best-effort; detailed error is shown in Settings -> TV.
      }
    }());
  }
  runApp(AppConfigScope(
    config: appConfig,
    child: LinPlayerApp(appState: appState),
  ));
}

Future<void> _runBootstrapStep(
  String scope,
  String message,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error, stackTrace) {
    AppDiagnosticsLogger.instance.warn(
      scope,
      message,
      data: <String, Object?>{
        'error': AppDiagnosticsLogger.summarizeError(error),
        'stack': AppDiagnosticsLogger.summarizeStackTrace(stackTrace),
      },
    );
  }
}

Future<T> _runBootstrapValueStep<T>(
  String scope,
  String message,
  Future<T> Function() action, {
  required T fallback,
}) async {
  try {
    return await action();
  } catch (error, stackTrace) {
    AppDiagnosticsLogger.instance.warn(
      scope,
      message,
      data: <String, Object?>{
        'error': AppDiagnosticsLogger.summarizeError(error),
        'stack': AppDiagnosticsLogger.summarizeStackTrace(stackTrace),
      },
    );
    return fallback;
  }
}

void _showBootstrapFailureApp(Object error, StackTrace stackTrace) {
  if (_bootstrapFailureAppShown) return;
  _bootstrapFailureAppShown = true;
  runApp(
    _BootstrapFailureApp(
      error: error,
      stackTrace: stackTrace,
      diagnostics: AppDiagnosticsLogger.instance.dumpText(maxEntries: 80),
    ),
  );
}

class LinPlayerApp extends StatefulWidget {
  const LinPlayerApp({super.key, required this.appState});

  final AppState appState;

  @override
  State<LinPlayerApp> createState() => _LinPlayerAppState();
}

class _LinPlayerAppState extends State<LinPlayerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(HighRefreshRate.apply(force: true));
      if (DesktopShell.isDesktopTarget) {
        unawaited(SystemHttpProxyService.instance.refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final appConfig = AppConfigScope.of(context);
        final appState = widget.appState;
        final active = appState.activeServer;
        final home = DeviceType.isTv
            ? TvShell(appState: appState)
            : (DesktopShell.isDesktopTarget
                ? DesktopShell(appState: appState)
                : switch (active) {
                    null => ServerPage(appState: appState),
                    _ when !appState.hasActiveServerProfile =>
                      ServerPage(appState: appState),
                    final s when s.serverType == MediaServerType.webdav =>
                      WebDavHomePage(appState: appState),
                    _ when appState.hasActiveServer =>
                      HomePage(appState: appState),
                    _ => ServerPage(appState: appState),
                  });
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            final useDynamic = appState.useDynamicColor;
            return MaterialApp(
              navigatorKey: _rootNavigatorKey,
              navigatorObservers: [appRouteObserver],
              key: ValueKey<String>('nav:${appState.activeServerId ?? 'none'}'),
              title: appConfig.displayName,
              debugShowCheckedModeBanner: false,
              themeMode: appState.themeMode,
              theme: AppTheme.light(
                dynamicScheme: useDynamic ? lightDynamic : null,
                compact: appState.compactMode,
              ),
              darkTheme: AppTheme.dark(
                dynamicScheme: useDynamic ? darkDynamic : null,
                compact: appState.compactMode,
              ),
              builder: (context, child) {
                if (child == null) return const SizedBox.shrink();

                final isTv = DeviceType.isTv;
                final isDesktopPlatform = !kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.windows ||
                        defaultTargetPlatform == TargetPlatform.macOS ||
                        defaultTargetPlatform == TargetPlatform.linux);

                final scale = (UiScaleScope.autoScaleFor(context) *
                        appState.uiScaleFactor *
                        (isTv ? 0.75 : 1.0))
                    .clamp(0.25, 2.0)
                    .toDouble();

                EdgeInsetsGeometry? scaleInsets(EdgeInsetsGeometry? insets) {
                  if (insets == null) return null;
                  final resolved = insets.resolve(Directionality.of(context));
                  return EdgeInsets.fromLTRB(
                    resolved.left * scale,
                    resolved.top * scale,
                    resolved.right * scale,
                    resolved.bottom * scale,
                  );
                }

                final theme = Theme.of(context);
                final scaledTheme = scale == 1.0
                    ? theme
                    : theme.copyWith(
                        iconTheme: theme.iconTheme.copyWith(
                          size: (theme.iconTheme.size ?? 24) * scale,
                        ),
                        appBarTheme: theme.appBarTheme.copyWith(
                          toolbarHeight: (theme.appBarTheme.toolbarHeight ??
                                  kToolbarHeight) *
                              scale,
                        ),
                        navigationBarTheme: theme.navigationBarTheme.copyWith(
                          height:
                              (theme.navigationBarTheme.height ?? 80) * scale,
                        ),
                        listTileTheme: theme.listTileTheme.copyWith(
                          contentPadding:
                              scaleInsets(theme.listTileTheme.contentPadding),
                          horizontalTitleGap:
                              theme.listTileTheme.horizontalTitleGap == null
                                  ? null
                                  : theme.listTileTheme.horizontalTitleGap! *
                                      scale,
                          minVerticalPadding:
                              theme.listTileTheme.minVerticalPadding == null
                                  ? null
                                  : theme.listTileTheme.minVerticalPadding! *
                                      scale,
                        ),
                        chipTheme: theme.chipTheme.copyWith(
                          padding: scaleInsets(theme.chipTheme.padding),
                          labelPadding:
                              scaleInsets(theme.chipTheme.labelPadding),
                        ),
                        inputDecorationTheme:
                            theme.inputDecorationTheme.copyWith(
                          contentPadding: scaleInsets(
                              theme.inputDecorationTheme.contentPadding),
                        ),
                        dividerTheme: theme.dividerTheme.copyWith(
                          thickness: theme.dividerTheme.thickness == null
                              ? null
                              : theme.dividerTheme.thickness! * scale,
                          space: theme.dividerTheme.space == null
                              ? null
                              : theme.dividerTheme.space! * scale,
                          indent: theme.dividerTheme.indent == null
                              ? null
                              : theme.dividerTheme.indent! * scale,
                          endIndent: theme.dividerTheme.endIndent == null
                              ? null
                              : theme.dividerTheme.endIndent! * scale,
                        ),
                      );

                final mediaQuery = MediaQuery.of(context);
                const probe = 14.0;
                final userScale = mediaQuery.textScaler.scale(probe) / probe;
                final baseTextScaler = scale == 1.0
                    ? mediaQuery.textScaler
                    : TextScaler.linear(userScale * scale);
                final textScaler = isDesktopPlatform
                    ? _SnappedTextScaler(
                        baseTextScaler,
                        devicePixelRatio: mediaQuery.devicePixelRatio,
                      )
                    : baseTextScaler;

                final style = scaledTheme.extension<AppStyle>();
                final hasBackdrop = style != null &&
                    style.backgroundIntensity > 0 &&
                    (style.background != AppBackgroundKind.none ||
                        style.pattern != AppPatternKind.none);

                final backgroundIntensity = (!hasBackdrop || isTv)
                    ? 0.0
                    : (appState.enableBlurEffects ? 1.0 : 0.65);

                final tvBackgroundEnabled =
                    isTv && appState.tvBackgroundMode != TvBackgroundMode.none;
                final effectiveTheme = tvBackgroundEnabled
                    ? scaledTheme.copyWith(
                        scaffoldBackgroundColor: Colors.transparent,
                      )
                    : scaledTheme;

                final appChild = isTv
                    ? (tvBackgroundEnabled
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              TvBackground(appState: appState),
                              child,
                            ],
                          )
                        : child)
                    : (backgroundIntensity <= 0
                        ? child
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              GlassBackground(intensity: backgroundIntensity),
                              child,
                            ],
                          ));

                final shortcutWrappedChild = isDesktopPlatform
                    ? Shortcuts(
                        shortcuts: const <ShortcutActivator, Intent>{
                          SingleActivator(LogicalKeyboardKey.escape):
                              AppBackIntent(),
                        },
                        child: Actions(
                          actions: <Type, Action<Intent>>{
                            AppBackIntent: CallbackAction<AppBackIntent>(
                              onInvoke: (_) {
                                final nav = _rootNavigatorKey.currentState;
                                if (nav == null) return null;
                                unawaited(nav.maybePop());
                                return null;
                              },
                            ),
                          },
                          child: Builder(
                            builder: (actionContext) => Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (event) {
                                final buttons = event.buttons;
                                final backDown =
                                    (buttons & kBackMouseButton) != 0;
                                final forwardDown =
                                    (buttons & kForwardMouseButton) != 0;
                                if (!backDown && !forwardDown) return;

                                final shortcuts =
                                    appState.desktopShortcutBindings;
                                final invokeContext = FocusManager
                                        .instance.primaryFocus?.context ??
                                    actionContext;

                                void handle(
                                  DesktopMouseSideButtonAction action,
                                ) {
                                  if (action !=
                                      DesktopMouseSideButtonAction.appBack) {
                                    return;
                                  }
                                  Actions.invoke(
                                    invokeContext,
                                    const AppBackIntent(),
                                  );
                                }

                                if (backDown) {
                                  handle(shortcuts.mouseBackButtonAction);
                                }
                                if (forwardDown) {
                                  handle(shortcuts.mouseForwardButtonAction);
                                }
                              },
                              child: appChild,
                            ),
                          ),
                        ),
                      )
                    : appChild;

                return UiScaleScope(
                  scale: scale,
                  child: MediaQuery(
                    data: mediaQuery.copyWith(textScaler: textScaler),
                    child: Theme(
                      data: effectiveTheme,
                      child: AppUpdateAutoChecker(
                        appState: appState,
                        child: PluginGovernanceAutoChecker(
                          child: DefaultTextStyle.merge(
                            style: const TextStyle(
                              decoration: TextDecoration.none,
                            ),
                            child: shortcutWrappedChild,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              home: home,
            );
          },
        );
      },
    );
  }
}

class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({
    required this.error,
    required this.stackTrace,
    required this.diagnostics,
  });

  final Object error;
  final StackTrace stackTrace;
  final String diagnostics;

  @override
  Widget build(BuildContext context) {
    final details = [
      'LinPlayer 启动失败。',
      '',
      '错误信息:',
      AppDiagnosticsLogger.summarizeError(error),
      '',
      '堆栈摘要:',
      AppDiagnosticsLogger.summarizeStackTrace(stackTrace),
      '',
      '诊断日志:',
      diagnostics,
    ].join('\n');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LinPlayer 启动失败',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF131722),
                      ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '应用没有正常完成启动。可以复制下面的诊断信息继续排查。',
                  style: TextStyle(
                    color: Color(0xFF4A5568),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: details));
                  },
                  child: const Text('复制诊断信息'),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD7DBE7)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        details,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFF202533),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
