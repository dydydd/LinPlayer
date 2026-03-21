import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as webview_windows;

import '../services/plugins/plugin_runtime_policy_v1.dart';

bool pluginVisibleWebViewSupportedV1() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => true,
    TargetPlatform.iOS => true,
    TargetPlatform.macOS => true,
    TargetPlatform.windows => true,
    _ => false,
  };
}

class PluginWebViewNode extends StatefulWidget {
  const PluginWebViewNode({
    super.key,
    required this.props,
    required this.allowedDomains,
  });

  final Map<String, Object?> props;
  final List<String> allowedDomains;

  @override
  State<PluginWebViewNode> createState() => _PluginWebViewNodeState();
}

class _PluginWebViewNodeState extends State<PluginWebViewNode> {
  WebViewController? _flutterController;
  webview_windows.WebviewController? _windowsController;

  StreamSubscription<String>? _windowsUrlSub;
  StreamSubscription<webview_windows.LoadingState>? _windowsLoadingSub;
  StreamSubscription<webview_windows.WebErrorStatus>? _windowsErrorSub;
  StreamSubscription<webview_windows.HistoryChanged>? _windowsHistorySub;

  int _loadEpoch = 0;
  bool _loading = true;
  bool _windowsCanGoBack = false;
  bool _handlingBlockedNavigation = false;

  double? _progress;
  String? _error;
  Uri? _lastAllowedUri;

  double? get _height => _readPositiveDouble(widget.props['height']);
  String get _title => (widget.props['title'] as String? ?? '').trim();
  bool get _showProgress => widget.props['showProgress'] as bool? ?? true;
  bool get _allowExternalNavigation =>
      widget.props['allowExternalNavigation'] as bool? ?? false;

  @override
  void initState() {
    super.initState();
    unawaited(_restart());
  }

  @override
  void didUpdateWidget(covariant PluginWebViewNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.props, widget.props) ||
        !_sameStringList(oldWidget.allowedDomains, widget.allowedDomains)) {
      unawaited(_restart());
    }
  }

  @override
  void dispose() {
    _loadEpoch++;
    unawaited(_disposeControllers());
    super.dispose();
  }

  Future<void> _restart() async {
    final epoch = ++_loadEpoch;
    await _disposeControllers();
    if (!mounted || epoch != _loadEpoch) return;

    setState(() {
      _loading = true;
      _progress = null;
      _error = null;
      _windowsCanGoBack = false;
      _handlingBlockedNavigation = false;
      _lastAllowedUri = null;
    });

    final height = _height;
    if (height == null || height <= 0) {
      _finishWithError(epoch, 'webview.height 必须是正数');
      return;
    }

    final src = _readHttpUri(widget.props['src']);
    if (src == null) {
      _finishWithError(epoch, 'webview.src 必须是绝对 http/https URL');
      return;
    }
    if (!pluginUrlAllowedV1(widget.allowedDomains, src)) {
      _finishWithError(epoch, 'webview 域名未授权：${src.host}');
      return;
    }
    if (!pluginVisibleWebViewSupportedV1()) {
      _finishWithError(epoch, '当前平台暂不支持插件 webview');
      return;
    }

    _lastAllowedUri = src;

    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        await _initWindows(epoch, src);
        return;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        await _initFlutter(epoch, src);
        return;
      default:
        _finishWithError(epoch, '当前平台暂不支持插件 webview');
        return;
    }
  }

  Future<void> _initFlutter(int epoch, Uri src) async {
    final controller = WebViewController();
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted || epoch != _loadEpoch) return;
            setState(() {
              _loading = true;
              _progress = null;
              _error = null;
            });
          },
          onProgress: (progress) {
            if (!mounted || epoch != _loadEpoch) return;
            setState(() {
              _progress = (progress.clamp(0, 100)) / 100.0;
              _loading = progress < 100;
            });
          },
          onPageFinished: (_) {
            if (!mounted || epoch != _loadEpoch) return;
            setState(() {
              _loading = false;
              _progress = 1;
              _error = null;
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            _finishWithError(
              epoch,
              _cleanErrorMessage(error.description, fallback: '网页加载失败'),
            );
          },
          onNavigationRequest: (request) async {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final uri = Uri.tryParse(request.url);
            if (uri != null && pluginUrlAllowedV1(widget.allowedDomains, uri)) {
              _lastAllowedUri = uri;
              return NavigationDecision.navigate;
            }
            await _handleBlockedNavigation(uri);
            return NavigationDecision.prevent;
          },
        ),
      );
      if (!mounted || epoch != _loadEpoch) return;
      setState(() => _flutterController = controller);
      await controller.loadRequest(src);
    } catch (e) {
      _finishWithError(epoch, _cleanErrorMessage(e.toString(), fallback: '网页加载失败'));
    }
  }

  Future<void> _initWindows(int epoch, Uri src) async {
    final version = await webview_windows.WebviewController.getWebViewVersion();
    if (version == null || version.trim().isEmpty) {
      _finishWithError(
        epoch,
        '未检测到 WebView2 Runtime，请先安装后重启软件',
      );
      return;
    }

    final controller = webview_windows.WebviewController();
    StreamSubscription<String>? urlSub;
    StreamSubscription<webview_windows.LoadingState>? loadingSub;
    StreamSubscription<webview_windows.WebErrorStatus>? errorSub;
    StreamSubscription<webview_windows.HistoryChanged>? historySub;
    try {
      await controller.initialize();
      await controller
          .setPopupWindowPolicy(webview_windows.WebviewPopupWindowPolicy.deny);
      await controller.setBackgroundColor(const Color(0x00000000));

      urlSub = controller.url.listen(
        (url) => unawaited(_handleWindowsUrlChanged(epoch, controller, url)),
        onError: (_) {},
      );
      loadingSub = controller.loadingState.listen((state) {
        if (!mounted || epoch != _loadEpoch) return;
        if (state == webview_windows.LoadingState.loading) {
          setState(() {
            _loading = true;
            _progress = null;
          });
          return;
        }
        if (state == webview_windows.LoadingState.navigationCompleted) {
          setState(() {
            _loading = false;
            _progress = 1;
            _error = null;
          });
        }
      });
      errorSub = controller.onLoadError.listen((status) {
        if (status == webview_windows.WebErrorStatus.WebErrorStatusOperationCanceled) {
          return;
        }
        _finishWithError(epoch, _windowsErrorMessage(status));
      });
      historySub = controller.historyChanged.listen((event) {
        _windowsCanGoBack = event.canGoBack;
      });

      if (!mounted || epoch != _loadEpoch) {
        await urlSub.cancel();
        await loadingSub.cancel();
        await errorSub.cancel();
        await historySub.cancel();
        await controller.dispose();
        return;
      }

      _windowsUrlSub = urlSub;
      _windowsLoadingSub = loadingSub;
      _windowsErrorSub = errorSub;
      _windowsHistorySub = historySub;
      setState(() => _windowsController = controller);
      await controller.loadUrl(src.toString());
    } catch (e) {
      await urlSub?.cancel();
      await loadingSub?.cancel();
      await errorSub?.cancel();
      await historySub?.cancel();
      await controller.dispose();
      _finishWithError(epoch, _cleanErrorMessage(e.toString(), fallback: '网页加载失败'));
    }
  }

  Future<void> _handleWindowsUrlChanged(
    int epoch,
    webview_windows.WebviewController controller,
    String rawUrl,
  ) async {
    if (!mounted || epoch != _loadEpoch || _handlingBlockedNavigation) return;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    if (pluginUrlAllowedV1(widget.allowedDomains, uri)) {
      _lastAllowedUri = uri;
      return;
    }
    await _handleBlockedNavigation(uri, windowsController: controller);
  }

  Future<void> _handleBlockedNavigation(
    Uri? uri, {
    webview_windows.WebviewController? windowsController,
  }) async {
    if (_handlingBlockedNavigation) return;
    _handlingBlockedNavigation = true;
    try {
      final canOpenExternal = uri != null &&
          _allowExternalNavigation &&
          uri.isAbsolute &&
          (uri.scheme == 'http' || uri.scheme == 'https');

      if (canOpenExternal) {
        await _openExternalUrl(uri.toString());
      } else {
        _showHint(_blockedNavigationMessage(uri));
      }

      if (windowsController != null) {
        try {
          await windowsController.stop();
        } catch (_) {}
        try {
          if (_windowsCanGoBack) {
            await windowsController.goBack();
          } else if (_lastAllowedUri != null) {
            await windowsController.loadUrl(_lastAllowedUri!.toString());
          }
        } catch (_) {}
      }
    } finally {
      _handlingBlockedNavigation = false;
    }
  }

  Future<void> _openExternalUrl(String url) async {
    final opened = await launchUrlString(url);
    if (!mounted || opened) return;
    _showHint('无法打开外部链接：$url');
  }

  void _showHint(String message) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _finishWithError(int epoch, String message) {
    if (!mounted || epoch != _loadEpoch) return;
    setState(() {
      _error = message;
      _loading = false;
      _progress = null;
    });
  }

  Future<void> _disposeControllers() async {
    final urlSub = _windowsUrlSub;
    final loadingSub = _windowsLoadingSub;
    final errorSub = _windowsErrorSub;
    final historySub = _windowsHistorySub;
    final windowsController = _windowsController;

    _windowsUrlSub = null;
    _windowsLoadingSub = null;
    _windowsErrorSub = null;
    _windowsHistorySub = null;
    _windowsController = null;
    _flutterController = null;

    await urlSub?.cancel();
    await loadingSub?.cancel();
    await errorSub?.cancel();
    await historySub?.cancel();
    await windowsController?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = _height ?? 140;
    final title = _title;
    final body = _buildBody(context);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (_showProgress && _error == null && _loading)
            Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(
                minHeight: 2,
                value: _progress == null || _progress == 1 ? null : _progress,
              ),
            ),
          if (title.isNotEmpty)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return _buildNotice(
        context,
        title: _title,
        message: _error!,
      );
    }

    final flutterController = _flutterController;
    if (flutterController != null) {
      return WebViewWidget(controller: flutterController);
    }

    final windowsController = _windowsController;
    if (windowsController != null) {
      return webview_windows.Webview(windowsController);
    }

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: const SizedBox.expand(),
    );
  }

  Widget _buildNotice(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.language_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              if (title != null && title.trim().isNotEmpty) ...[
                Text(
                  title.trim(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameStringList(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

double? _readPositiveDouble(Object? raw) {
  if (raw is num) {
    final value = raw.toDouble();
    return value > 0 ? value : null;
  }
  if (raw is String) {
    final value = double.tryParse(raw.trim());
    if (value != null && value > 0) return value;
  }
  return null;
}

Uri? _readHttpUri(Object? raw) {
  final text = (raw as String? ?? '').trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.isAbsolute) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  return uri;
}

String _cleanErrorMessage(String raw, {required String fallback}) {
  final text = raw.trim();
  if (text.isEmpty) return fallback;
  if (text.startsWith('Exception:')) {
    final cleaned = text.substring('Exception:'.length).trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }
  return text;
}

String _blockedNavigationMessage(Uri? uri) {
  if (uri == null) return '已拦截不支持的网页跳转';
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '已拦截不支持的跳转协议：${uri.scheme}';
  }
  if (uri.host.trim().isEmpty) return '已拦截不支持的网页跳转';
  return '已拦截外域跳转：${uri.host}';
}

String _windowsErrorMessage(webview_windows.WebErrorStatus status) {
  return switch (status) {
    webview_windows.WebErrorStatus.WebErrorStatusCertificateCommonNameIsIncorrect =>
      '网页证书域名不匹配',
    webview_windows.WebErrorStatus.WebErrorStatusCertificateExpired =>
      '网页证书已过期',
    webview_windows.WebErrorStatus.WebErrorStatusCertificateRevoked =>
      '网页证书已被吊销',
    webview_windows.WebErrorStatus.WebErrorStatusCertificateIsInvalid =>
      '网页证书无效',
    webview_windows.WebErrorStatus.WebErrorStatusServerUnreachable =>
      '无法连接到网页服务器',
    webview_windows.WebErrorStatus.WebErrorStatusTimeout =>
      '网页加载超时',
    webview_windows.WebErrorStatus.WebErrorStatusConnectionAborted =>
      '网页连接已中断',
    webview_windows.WebErrorStatus.WebErrorStatusConnectionReset =>
      '网页连接被重置',
    webview_windows.WebErrorStatus.WebErrorStatusDisconnected =>
      '网页连接已断开',
    webview_windows.WebErrorStatus.WebErrorStatusCannotConnect =>
      '无法建立网页连接',
    webview_windows.WebErrorStatus.WebErrorStatusHostNameNotResolved =>
      '无法解析网页域名',
    webview_windows.WebErrorStatus.WebErrorStatusRedirectFailed =>
      '网页跳转失败',
    _ => '网页加载失败',
  };
}
