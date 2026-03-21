import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as webview_windows;

import 'plugin_manager.dart';
import 'plugin_runtime_policy_v1.dart';

class PluginRuntimeException implements Exception {
  PluginRuntimeException(this.message);

  final String message;

  @override
  String toString() => 'PluginRuntimeException: $message';
}

bool pluginRuntimeSupportedV1() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => true,
    TargetPlatform.iOS => true,
    TargetPlatform.macOS => true,
    TargetPlatform.windows => true,
    TargetPlatform.linux => true,
    _ => false,
  };
}

abstract class _PluginWebBackendV1 {
  Future<void> init({required ValueChanged<Object?> onMessage});

  Future<void> runJavaScript(String js);

  Widget buildView();

  Future<void> dispose();
}

class _FlutterWebBackendV1 implements _PluginWebBackendV1 {
  _FlutterWebBackendV1({required this.channelName});

  static const String _blankHtml =
      '<!DOCTYPE html><html><head><meta charset="utf-8" /></head><body></body></html>';

  final String channelName;

  final WebViewController _controller = WebViewController();

  @override
  Future<void> init({required ValueChanged<Object?> onMessage}) async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(const Color(0x00000000));
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (req) => NavigationDecision.prevent,
      ),
    );
    _controller.addJavaScriptChannel(
      channelName,
      onMessageReceived: (msg) => onMessage(msg.message),
    );
    await _controller.loadHtmlString(_blankHtml);
  }

  @override
  Future<void> runJavaScript(String js) => _controller.runJavaScript(js);

  @override
  Widget buildView() => WebViewWidget(controller: _controller);

  @override
  Future<void> dispose() async {}
}

class _WindowsWebBackendV1 implements _PluginWebBackendV1 {
  static const String _blankHtml =
      '<!DOCTYPE html><html><head><meta charset="utf-8" /></head><body></body></html>';

  final webview_windows.WebviewController _controller =
      webview_windows.WebviewController();

  StreamSubscription? _sub;

  @override
  Future<void> init({required ValueChanged<Object?> onMessage}) async {
    final version = await webview_windows.WebviewController.getWebViewVersion();
    if (version == null || version.trim().isEmpty) {
      throw PluginRuntimeException(
        '未检测到 WebView2 Runtime，请先安装后重启软件：'
        'https://developer.microsoft.com/microsoft-edge/webview2/',
      );
    }

    await _controller.initialize();
    await _controller
        .setPopupWindowPolicy(webview_windows.WebviewPopupWindowPolicy.deny);
    await _controller.setBackgroundColor(const Color(0x00000000));
    _sub = _controller.webMessage.listen(onMessage, onError: (_) {});
    await _controller.loadStringContent(_blankHtml);
  }

  @override
  Future<void> runJavaScript(String js) async {
    await _controller.executeScript(js);
  }

  @override
  Widget buildView() => webview_windows.Webview(_controller);

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.dispose();
  }
}

class _FlutterJsBackendV1 implements _PluginWebBackendV1 {
  _FlutterJsBackendV1({required this.channelName});

  final String channelName;
  JavascriptRuntime? _runtime;

  @override
  Future<void> init({required ValueChanged<Object?> onMessage}) async {
    final rt = getJavascriptRuntime(xhr: false);
    _runtime = rt;

    rt.onMessage(channelName, (dynamic args) {
      onMessage(args);
    });

    // Ensure "window" exists for plugin scripts.
    rt.evaluate(
      '''
(function () {
  try { if (typeof window === 'undefined') { globalThis.window = globalThis; } } catch (_) {}
})();''',
    );

    rt.executePendingJob();
  }

  @override
  Future<void> runJavaScript(String js) async {
    final rt = _runtime;
    if (rt == null) throw PluginRuntimeException('运行时未初始化');
    final res = rt.evaluate(js);
    rt.executePendingJob();
    if (res.isError) throw PluginRuntimeException(res.stringResult);
  }

  @override
  Widget buildView() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    _runtime?.dispose();
    _runtime = null;
  }
}

class PluginRuntimeV1 {
  PluginRuntimeV1({
    required this.plugin,
    required this.manifest,
  }) : target = currentPluginTarget();

  static const String _channelName = 'LinPlayerPluginBridgeV1';
  static const Duration _defaultHostCallTimeout = Duration(seconds: 25);
  static const int _maxResponseBytes = 4 * 1024 * 1024;

  final InstalledPluginV1 plugin;
  final PluginManifestV1 manifest;
  final PluginTarget target;

  _PluginWebBackendV1? _backend;

  Widget buildView() {
    final backend = _backend;
    if (backend == null) return const SizedBox.shrink();
    return backend.buildView();
  }

  final Completer<void> _ready = Completer<void>();
  final Map<String, Completer<Object?>> _pendingHostCalls = {};
  final http.Client _client = http.Client();

  int _hostSeq = 0;
  bool _disposed = false;

  Future<void> init() async {
    if (!pluginRuntimeSupportedV1()) {
      throw PluginRuntimeException(
        '当前平台暂不支持脚本插件运行（需要 WebView 支持）',
      );
    }

    final backend = switch (defaultTargetPlatform) {
      TargetPlatform.windows => _WindowsWebBackendV1(),
      TargetPlatform.linux => _FlutterJsBackendV1(channelName: _channelName),
      _ => _FlutterWebBackendV1(channelName: _channelName),
    };
    _backend = backend;

    final entryRel = manifest.entry.entryForTarget(target).script;
    final entryFile =
        await PluginManagerV1.instance.pluginFile(plugin, entryRel);
    if (!await entryFile.exists()) {
      throw PluginRuntimeException('入口脚本不存在：$entryRel');
    }
    final entryBytes = await entryFile.readAsBytes();

    final ctx = await _buildInitialCtx();
    final bootstrapJs = _buildBootstrapJs(ctx);
    final entryCode = utf8.decode(entryBytes);

    await backend.init(onMessage: (msg) => unawaited(_handleJsMessage(msg)));

    await backend.runJavaScript(bootstrapJs);
    await backend.runJavaScript(entryCode);
    await backend.runJavaScript("window.__lp_post({ type: 'ready' });");

    await _ready.future.timeout(const Duration(seconds: 12));
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final c in _pendingHostCalls.values) {
      if (!c.isCompleted) c.completeError(PluginRuntimeException('运行时已销毁'));
    }
    _pendingHostCalls.clear();
    _client.close();
    await _backend?.dispose();
    _backend = null;
  }

  Future<Object?> call(
    String handlerName,
    List<Object?> args, {
    Duration timeout = _defaultHostCallTimeout,
  }) async {
    if (_disposed) throw PluginRuntimeException('运行时已销毁');
    await _ready.future;
    final callId = (++_hostSeq).toString();
    final completer = Completer<Object?>();
    _pendingHostCalls[callId] = completer;
    final js = StringBuffer()
      ..write('window.__lp_hostInvoke(')
      ..write(jsonEncode(callId))
      ..write(',')
      ..write(jsonEncode(handlerName))
      ..write(',')
      ..write(jsonEncode(args))
      ..write(');');
    final backend = _backend;
    if (backend == null) throw PluginRuntimeException('运行时未初始化');
    await backend.runJavaScript(js.toString());
    try {
      return await completer.future.timeout(timeout);
    } finally {
      _pendingHostCalls.remove(callId);
    }
  }

  Future<Map<String, Object?>> _buildInitialCtx() async {
    String hostVersion = '0.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      hostVersion =
          info.version.trim().isEmpty ? hostVersion : info.version.trim();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final settingsKey = 'linplayer.plugins.settings.v1.${plugin.id}';
    Map<String, Object?> settings = const {};
    try {
      final raw = prefs.getString(settingsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) settings = Map<String, Object?>.from(decoded);
      }
    } catch (_) {}

    return {
      'target': target.name,
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      'timeZone': DateTime.now().timeZoneName,
      'hostVersion': hostVersion,
      'plugin': {'id': plugin.id, 'version': plugin.version},
      'settings': settings,
    };
  }

  String _buildBootstrapJs(Map<String, Object?> ctx) {
    final ctxJson = jsonEncode(ctx);
    return '''
(function () {
  try { if (typeof window === 'undefined') { globalThis.window = globalThis; } } catch (_) {}

  const CHANNEL = ${jsonEncode(_channelName)};
  function post(msg) {
    const raw = JSON.stringify(msg);
    try { window[CHANNEL].postMessage(raw); return; } catch (_) {}
    try {
      const wv = window.chrome && window.chrome.webview;
      if (wv && typeof wv.postMessage === 'function') {
        wv.postMessage(raw);
        return;
      }
    } catch (_) {}
    try {
      if (typeof sendMessage === 'function') {
        sendMessage(CHANNEL, raw);
        return;
      }
    } catch (_) {}
  }
  window.__lp_post = post;

  try { window.fetch = undefined; } catch (_) {}
  try { window.XMLHttpRequest = undefined; } catch (_) {}
  try { window.WebSocket = undefined; } catch (_) {}

  let nativeSeq = 0;
  const nativePending = {};
  window.__lp_nativeCall = function (method, args) {
    const id = String(++nativeSeq);
    return new Promise((resolve, reject) => {
      nativePending[id] = { resolve, reject };
      post({ type: 'nativeCall', id, method, args });
    });
  };
  window.__lp_nativeResolve = function (id, payload) {
    const cb = nativePending[id];
    if (!cb) return;
    delete nativePending[id];
    if (payload && payload.error) cb.reject(payload.error);
    else cb.resolve(payload ? payload.result : null);
  };

  window.__lp_hostInvoke = async function (callId, handlerName, argsArray) {
    try {
      let fn = globalThis[handlerName];
      if (typeof fn !== 'function') {
        try { fn = (0, eval)(handlerName); } catch (_) {}
      }
      if (typeof fn !== 'function') throw new Error('Handler not found: ' + handlerName);
      const args = Array.isArray(argsArray) ? argsArray : [];
      const result = await fn(window.__lp_ctx, ...args);
      post({ type: 'hostResponse', id: callId, result });
    } catch (e) {
      post({
        type: 'hostError',
        id: callId,
        error: {
          message: (e && e.message) ? e.message : String(e),
          stack: (e && e.stack) ? String(e.stack) : null
        }
      });
    }
  };

  const ctx = $ctxJson;
  ctx.net = {
    request: (req) => window.__lp_nativeCall('net.request', req),
  };
  ctx.storage = {
    get: (key) => window.__lp_nativeCall('storage.get', { key }),
    set: (key, value) => window.__lp_nativeCall('storage.set', { key, value }),
    remove: (key) => window.__lp_nativeCall('storage.remove', { key }),
  };
  ctx.log = (level, message, extra) => post({ type: 'log', level, message, extra });
  window.__lp_ctx = ctx;
})();
''';
  }

  Future<void> _handleJsMessage(Object? raw) async {
    if (_disposed) return;
    Object? decoded;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return;
      }
    } else {
      decoded = raw;
    }
    if (decoded is! Map) return;
    final type = (decoded['type'] as String? ?? '').trim();
    switch (type) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
        return;
      case 'hostResponse':
        final id = (decoded['id'] as String? ?? '').trim();
        final c = _pendingHostCalls[id];
        if (c != null && !c.isCompleted) {
          c.complete(decoded['result']);
        }
        return;
      case 'hostError':
        final id = (decoded['id'] as String? ?? '').trim();
        final err = decoded['error'];
        final msg = err is Map ? (err['message'] as String? ?? '') : '';
        final c = _pendingHostCalls[id];
        if (c != null && !c.isCompleted) {
          c.completeError(PluginRuntimeException(msg.isEmpty ? '脚本执行失败' : msg));
        }
        return;
      case 'nativeCall':
        final id = (decoded['id'] as String? ?? '').trim();
        final method = (decoded['method'] as String? ?? '').trim();
        final args = decoded['args'];
        unawaited(_handleNativeCall(id, method, args));
        return;
      case 'log':
        final level = (decoded['level'] as String? ?? 'info').trim();
        final message = (decoded['message'] as String? ?? '').trim();
        if (message.isNotEmpty) {
          debugPrint('[plugin:${plugin.id}] $level: $message');
        }
        return;
      default:
        return;
    }
  }

  Future<void> _handleNativeCall(String id, String method, Object? args) async {
    if (_disposed) return;
    if (id.isEmpty || method.isEmpty) return;

    try {
      final result = switch (method) {
        'net.request' => await _handleNetRequest(args),
        'storage.get' => await _handleStorageGet(args),
        'storage.set' => await _handleStorageSet(args),
        'storage.remove' => await _handleStorageRemove(args),
        _ => throw PluginRuntimeException('不支持的 native 方法：$method'),
      };
      await _replyNative(id, result: result);
    } catch (e) {
      await _replyNative(id, error: e.toString());
    }
  }

  Future<void> _replyNative(
    String id, {
    Object? result,
    String? error,
  }) async {
    final payload = <String, Object?>{
      if (error != null) 'error': error,
      if (error == null) 'result': result,
    };
    final js = StringBuffer()
      ..write('window.__lp_nativeResolve(')
      ..write(jsonEncode(id))
      ..write(',')
      ..write(jsonEncode(payload))
      ..write(');');
    final backend = _backend;
    if (backend == null) return;
    await backend.runJavaScript(js.toString());
  }

  bool _domainAllowed(String host) {
    return pluginDomainAllowedV1(manifest.permissions.network.domains, host);
  }

  Future<Object?> _handleNetRequest(Object? args) async {
    if (!manifest.permissions.network.enabled) {
      throw PluginRuntimeException('PermissionDenied');
    }
    if (args is! Map) throw PluginRuntimeException('net.request 参数格式错误');
    final urlRaw = (args['url'] as String? ?? '').trim();
    if (urlRaw.isEmpty) throw PluginRuntimeException('net.request.url 不能为空');
    Uri uri;
    try {
      uri = Uri.parse(urlRaw);
    } catch (_) {
      throw PluginRuntimeException('net.request.url 不是合法 URL');
    }
    if (!uri.isAbsolute) {
      throw PluginRuntimeException('net.request.url 必须是绝对 URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw PluginRuntimeException('net.request 仅支持 http/https');
    }
    if (!_domainAllowed(uri.host)) {
      throw PluginRuntimeException('net.request 域名不在白名单：${uri.host}');
    }

    final method = (args['method'] as String? ?? 'GET').trim().toUpperCase();
    final headers = <String, String>{};
    final headersRaw = args['headers'];
    if (headersRaw is Map) {
      for (final entry in headersRaw.entries) {
        final k = (entry.key as String? ?? '').trim();
        final v = (entry.value as String? ?? '').trim();
        if (k.isNotEmpty && v.isNotEmpty) headers[k] = v;
      }
    }

    final timeoutMs = args['timeoutMs'];
    final timeout = (timeoutMs is int && timeoutMs > 0)
        ? Duration(milliseconds: timeoutMs)
        : const Duration(seconds: 15);

    final responseType =
        (args['responseType'] as String? ?? 'text').trim().toLowerCase();

    final request = http.Request(method, uri);
    request.headers.addAll(headers);
    final body = args['body'];
    if (body != null && method != 'GET' && method != 'HEAD') {
      if (body is String) {
        request.bodyBytes = utf8.encode(body);
      } else if (body is List) {
        request.bodyBytes = body.cast<int>();
      } else {
        request.body = jsonEncode(body);
        request.headers.putIfAbsent('Content-Type', () => 'application/json');
      }
    }

    final streamed = await _client.send(request).timeout(timeout);
    final contentLength = streamed.contentLength;
    if (contentLength != null && contentLength > _maxResponseBytes) {
      throw PluginRuntimeException('net.request 响应体过大');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
      if (builder.length > _maxResponseBytes) {
        throw PluginRuntimeException('net.request 响应体过大');
      }
    }
    final bytes = builder.takeBytes();
    final outHeaders = <String, String>{};
    streamed.headers.forEach((k, v) => outHeaders[k] = v);

    Object? outBody;
    switch (responseType) {
      case 'json':
        outBody = jsonDecode(utf8.decode(bytes));
        break;
      case 'bytes':
        outBody = bytes;
        break;
      case 'text':
      default:
        outBody = utf8.decode(bytes);
        break;
    }

    return {
      'status': streamed.statusCode,
      'headers': outHeaders,
      'url': streamed.request?.url.toString() ?? uri.toString(),
      'body': outBody,
    };
  }

  static String _storageKey(String pluginId) =>
      'linplayer.plugins.storage.v1.$pluginId';

  Future<Map<String, Object?>> _readStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(plugin.id));
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } catch (_) {}
    return {};
  }

  Future<void> _writeStorage(Map<String, Object?> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(plugin.id), jsonEncode(data));
  }

  Future<Object?> _handleStorageGet(Object? args) async {
    if (args is! Map) throw PluginRuntimeException('storage.get 参数格式错误');
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) throw PluginRuntimeException('storage.get.key 不能为空');
    final data = await _readStorage();
    return data[key];
  }

  Future<Object?> _handleStorageSet(Object? args) async {
    if (args is! Map) throw PluginRuntimeException('storage.set 参数格式错误');
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) throw PluginRuntimeException('storage.set.key 不能为空');
    final value = args['value'];
    final data = await _readStorage();
    data[key] = value;
    await _writeStorage(data);
    return true;
  }

  Future<Object?> _handleStorageRemove(Object? args) async {
    if (args is! Map) throw PluginRuntimeException('storage.remove 参数格式错误');
    final key = (args['key'] as String? ?? '').trim();
    if (key.isEmpty) throw PluginRuntimeException('storage.remove.key 不能为空');
    final data = await _readStorage();
    data.remove(key);
    await _writeStorage(data);
    return true;
  }
}
