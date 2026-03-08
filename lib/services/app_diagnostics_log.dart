import 'dart:collection';

enum AppDiagnosticsLogLevel {
  debug,
  info,
  warn,
  error,
}

class AppDiagnosticsLogEntry {
  const AppDiagnosticsLogEntry({
    required this.timestamp,
    required this.level,
    required this.scope,
    required this.message,
    required this.data,
  });

  final DateTime timestamp;
  final AppDiagnosticsLogLevel level;
  final String scope;
  final String message;
  final Map<String, String> data;
}

class AppDiagnosticsLogger {
  AppDiagnosticsLogger._();

  static final AppDiagnosticsLogger instance = AppDiagnosticsLogger._();

  static const int _maxEntries = 4000;
  final List<AppDiagnosticsLogEntry> _entries = <AppDiagnosticsLogEntry>[];
  final DateTime _startedAt = DateTime.now();

  DateTime get startedAt => _startedAt;

  List<AppDiagnosticsLogEntry> snapshot() =>
      List<AppDiagnosticsLogEntry>.unmodifiable(_entries);

  void debug(
    String scope,
    String message, {
    Map<String, Object?>? data,
  }) {
    log(
      AppDiagnosticsLogLevel.debug,
      scope,
      message,
      data: data,
    );
  }

  void info(
    String scope,
    String message, {
    Map<String, Object?>? data,
  }) {
    log(
      AppDiagnosticsLogLevel.info,
      scope,
      message,
      data: data,
    );
  }

  void warn(
    String scope,
    String message, {
    Map<String, Object?>? data,
  }) {
    log(
      AppDiagnosticsLogLevel.warn,
      scope,
      message,
      data: data,
    );
  }

  void error(
    String scope,
    String message, {
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final merged = <String, Object?>{
      if (data != null) ...data,
      if (error != null) 'error': summarizeError(error),
      if (stackTrace != null) 'stack': summarizeStackTrace(stackTrace),
    };
    log(
      AppDiagnosticsLogLevel.error,
      scope,
      message,
      data: merged,
    );
  }

  void log(
    AppDiagnosticsLogLevel level,
    String scope,
    String message, {
    Map<String, Object?>? data,
  }) {
    final fixedScope = _sanitizeInline(scope, fallback: 'app');
    final fixedMessage = _sanitizeInline(message, limit: 320);
    final fixedData = SplayTreeMap<String, String>();
    if (data != null) {
      for (final entry in data.entries) {
        final key = _sanitizeInline(entry.key, limit: 40);
        if (key.isEmpty) continue;
        final value = _stringify(entry.value);
        if (value.isEmpty) continue;
        fixedData[key] = value;
      }
    }

    _entries.add(
      AppDiagnosticsLogEntry(
        timestamp: DateTime.now(),
        level: level,
        scope: fixedScope,
        message: fixedMessage,
        data: Map<String, String>.unmodifiable(fixedData),
      ),
    );

    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  String dumpText({int maxEntries = 300}) {
    if (_entries.isEmpty) return '(empty)';
    final count = maxEntries.clamp(1, _entries.length).toInt();
    final list = _entries.sublist(_entries.length - count);
    final lines = <String>[];
    for (final entry in list) {
      final buffer = StringBuffer()
        ..write(entry.timestamp.toIso8601String())
        ..write(' [')
        ..write(entry.level.name.toUpperCase())
        ..write('] ')
        ..write(entry.scope)
        ..write(': ')
        ..write(entry.message);
      if (entry.data.isNotEmpty) {
        buffer.write(' | ');
        var first = true;
        for (final data in entry.data.entries) {
          if (!first) buffer.write(', ');
          first = false;
          buffer
            ..write(data.key)
            ..write('=')
            ..write(data.value);
        }
      }
      lines.add(buffer.toString());
    }
    return lines.join('\n');
  }

  static String summarizeUrl(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return '';

    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme.isEmpty || uri.host.trim().isEmpty) {
      return _sanitizeInline(input, limit: 220);
    }

    final buffer = StringBuffer()
      ..write(uri.scheme)
      ..write('://')
      ..write(uri.host);
    if (uri.hasPort) {
      final defaultPort = (uri.scheme == 'http' && uri.port == 80) ||
          (uri.scheme == 'https' && uri.port == 443);
      if (!defaultPort) {
        buffer
          ..write(':')
          ..write(uri.port);
      }
    }

    final path = uri.path.trim().isEmpty ? '/' : uri.path.trim();
    buffer.write(_sanitizeInline(path, limit: 160));

    final query = uri.queryParametersAll;
    if (query.isNotEmpty) {
      final parts = <String>[];
      final entries = query.entries.toList(growable: false)
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in entries) {
        final key = _sanitizeInline(entry.key, limit: 40);
        if (key.isEmpty) continue;
        final values = entry.value;
        final rendered = values.isEmpty
            ? ''
            : values
                .map((v) => _maskQueryValue(key, v))
                .where((v) => v.isNotEmpty)
                .join(',');
        parts.add(rendered.isEmpty ? key : '$key=$rendered');
      }
      if (parts.isNotEmpty) {
        buffer
          ..write('?')
          ..write(parts.join('&'));
      }
    }

    if (uri.fragment.isNotEmpty) {
      buffer.write('#...');
    }
    return _sanitizeInline(buffer.toString(), limit: 240);
  }

  static String summarizeHeaderKeys(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return '-';
    final keys = headers.keys
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    return keys.join('|');
  }

  static String summarizeError(Object error) {
    return _sanitizeInline(error.toString(), limit: 220);
  }

  static String summarizeStackTrace(StackTrace stackTrace) {
    final lines = stackTrace
        .toString()
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(4)
        .map((e) => _sanitizeInline(e, limit: 180))
        .toList(growable: false);
    return lines.join(' <- ');
  }

  static String _maskQueryValue(String key, String value) {
    final fixedKey = key.trim().toLowerCase();
    final fixedValue = value.trim();
    if (fixedValue.isEmpty) return '';
    const sensitiveKeys = <String>{
      'access_token',
      'account',
      'api_key',
      'apikey',
      'auth',
      'authorization',
      'cookie',
      'key',
      'password',
      'sign',
      'signature',
      'token',
    };
    if (sensitiveKeys.contains(fixedKey) ||
        fixedKey.contains('token') ||
        fixedKey.contains('auth') ||
        fixedKey.contains('sign') ||
        fixedKey.contains('pass')) {
      return _maskMiddle(fixedValue);
    }
    if (fixedValue.length <= 16) {
      return _sanitizeInline(fixedValue, limit: 20);
    }
    return _maskMiddle(fixedValue);
  }

  static String _maskMiddle(String input) {
    final v = _sanitizeInline(input, limit: 64);
    if (v.length <= 8) return '***';
    return '${v.substring(0, 4)}...${v.substring(v.length - 4)}';
  }

  static String _stringify(Object? value) {
    if (value == null) return '';
    if (value is bool || value is num) return value.toString();
    if (value is Uri) return summarizeUrl(value.toString());
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      final rendered = value.entries
          .map((e) =>
              '${_sanitizeInline(e.key.toString(), limit: 24)}:${_sanitizeInline(e.value.toString(), limit: 80)}')
          .join('|');
      return _sanitizeInline(rendered, limit: 220);
    }
    if (value is Iterable) {
      final rendered =
          value.map((e) => _sanitizeInline(e.toString(), limit: 80)).join('|');
      return _sanitizeInline(rendered, limit: 220);
    }
    return _sanitizeInline(value.toString(), limit: 220);
  }

  static String _sanitizeInline(
    String raw, {
    int limit = 120,
    String fallback = '',
  }) {
    final cleaned =
        raw.replaceAll(RegExp(r'\s+'), ' ').replaceAll('|', '/').trim();
    if (cleaned.isEmpty) return fallback;
    if (cleaned.length <= limit) return cleaned;
    return '${cleaned.substring(0, limit - 3)}...';
  }
}
