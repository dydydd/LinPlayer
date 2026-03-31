import 'package:flutter/foundation.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

class SystemHttpProxyService {
  SystemHttpProxyService._();

  static final SystemHttpProxyService instance = SystemHttpProxyService._();

  Future<void> refresh() async {
    final resolver = await _loadResolver();
    LinHttpClientFactory.configure(
      LinHttpClientFactory.config.copyWith(proxyResolver: resolver),
    );
  }

  Future<LinProxyResolver?> _loadResolver() async {
    final proxyUri = await _detectProxyUri();
    if (proxyUri == null) return null;

    final host = proxyUri.host.trim();
    final port = proxyUri.port;
    if (host.isEmpty || port <= 0 || port > 65535) return null;

    return (Uri uri) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'http' && scheme != 'https') return 'DIRECT';

      final targetHost = uri.host.trim().toLowerCase();
      if (targetHost.isEmpty) return 'DIRECT';
      if (targetHost == 'localhost' ||
          targetHost == '127.0.0.1' ||
          targetHost == '::1') {
        return 'DIRECT';
      }
      if (_isPrivateIpv4Host(targetHost)) return 'DIRECT';

      return 'PROXY $host:$port';
    };
  }

  Future<Uri?> _detectProxyUri() async {
    final native = await DeviceType.systemHttpProxyUrl();
    final parsedNative = _normalizeProxyUri(native);
    if (parsedNative != null) return parsedNative;
    if (kIsWeb) return null;
    return null;
  }

  static Uri? _normalizeProxyUri(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;

    Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.host.trim().isEmpty || uri.port <= 0) {
      uri = Uri.tryParse('http://$value');
    }
    if (uri == null) return null;

    final host = uri.host.trim();
    final port = uri.port;
    if (host.isEmpty || port <= 0 || port > 65535) return null;

    return Uri(
      scheme: uri.scheme.trim().isEmpty ? 'http' : uri.scheme.trim(),
      host: host,
      port: port,
    );
  }

  static bool _isPrivateIpv4Host(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;

    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }

    final a = octets[0];
    final b = octets[1];
    if (a == 10) return true;
    if (a == 127) return true;
    if (a == 169 && b == 254) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }
}
