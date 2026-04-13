import 'dart:async';
import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:lin_player_server_api/network/lin_http_client.dart';

http.Client? _sharedAndroidClient;
CronetEngine? _sharedCronetEngine;

http.Client createEmbyHttpClient() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return LinHttpClientFactory.createClient();
  }
  final shared = _sharedAndroidClient ??= _buildAndroidClient();
  return _SharedClientLease(shared);
}

String? describeEmbyHttpRoute(Uri uri) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'platform-native(android)';
  }
  return LinHttpClientFactory.describeProxyRoute(uri);
}

@visibleForTesting
http.Client debugWrapSharedEmbyClient(http.Client delegate) {
  return _SharedClientLease(delegate);
}

http.Client _buildAndroidClient() {
  final primary = CronetClient.fromCronetEngine(
    _sharedCronetEngine ??= CronetEngine.build(
      cacheMode: CacheMode.memory,
      cacheMaxSize: 2 * 1024 * 1024,
      userAgent: LinHttpClientFactory.userAgent,
    ),
    closeEngine: false,
  );

  // Keep the old dart:io client as a narrow fallback for cases Cronet cannot
  // handle well, such as missing Cronet runtime or user-installed certificates.
  final fallback = LinHttpClientFactory.createClient();
  return _RetryOnCronetFailureClient(
    primary: primary,
    fallback: fallback,
  );
}

class _SharedClientLease extends http.BaseClient {
  _SharedClientLease(this._delegate);

  final http.Client _delegate;
  bool _isClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_isClosed) {
      throw http.ClientException(
        'HTTP request failed. Client is already closed.',
        request.url,
      );
    }
    return _delegate.send(request);
  }

  @override
  void close() {
    _isClosed = true;
  }
}

class _RetryOnCronetFailureClient extends http.BaseClient {
  _RetryOnCronetFailureClient({
    required http.Client primary,
    required http.Client fallback,
  })  : _primary = primary,
        _fallback = fallback;

  final http.Client _primary;
  final http.Client _fallback;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final snapshot = await _RequestSnapshot.capture(request);
    try {
      return await snapshot.sendWith(_primary);
    } catch (error) {
      if (!_shouldFallback(error)) rethrow;
      return snapshot.sendWith(_fallback);
    }
  }

  @override
  void close() {
    _primary.close();
    _fallback.close();
  }

  static bool _shouldFallback(Object error) {
    if (error is HandshakeException || error is TlsException) return true;

    final text = error.toString().toLowerCase();
    return text.contains('cronet') ||
        text.contains('certificate') ||
        text.contains('trust anchor') ||
        text.contains('x509') ||
        text.contains('handshake') ||
        text.contains('tls') ||
        text.contains('ssl') ||
        text.contains('play services');
  }
}

class _RequestSnapshot {
  const _RequestSnapshot({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyBytes,
    required this.followRedirects,
    required this.maxRedirects,
    required this.persistentConnection,
    required this.contentLength,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  final bool followRedirects;
  final int maxRedirects;
  final bool persistentConnection;
  final int? contentLength;

  static Future<_RequestSnapshot> capture(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    return _RequestSnapshot(
      method: request.method,
      url: request.url,
      headers: Map<String, String>.from(request.headers),
      bodyBytes: bodyBytes,
      followRedirects: request.followRedirects,
      maxRedirects: request.maxRedirects,
      persistentConnection: request.persistentConnection,
      contentLength: request.contentLength,
    );
  }

  Future<http.StreamedResponse> sendWith(http.Client client) async {
    final request = http.StreamedRequest(method, url)
      ..followRedirects = followRedirects
      ..maxRedirects = maxRedirects
      ..persistentConnection = persistentConnection;
    if (contentLength != null && contentLength! >= 0) {
      request.contentLength = contentLength!;
    }
    request.headers.addAll(headers);
    if (bodyBytes.isNotEmpty) {
      request.sink.add(bodyBytes);
    }
    unawaited(request.sink.close());
    return client.send(request);
  }
}
