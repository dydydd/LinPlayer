import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'app_diagnostics_log.dart';

class AppDiagnosticsReportBuilder {
  const AppDiagnosticsReportBuilder._();

  static Future<String> build({
    required AppState appState,
    required String currentVersionFull,
    Map<String, String>? extraSections,
  }) async {
    final logger = AppDiagnosticsLogger.instance;
    final activeServer = appState.activeServer;
    final primaryAbi = kIsWeb ? null : await DeviceType.primaryAbi();
    final now = DateTime.now();
    final version = currentVersionFull.trim().isEmpty
        ? 'unknown'
        : currentVersionFull.trim();
    final platform = _platformLabel();
    final runtimeLog = logger.dumpText(maxEntries: logger.snapshot().length);

    final buffer = StringBuffer()
      ..writeln('== LinPlayer Diagnostics ==')
      ..writeln('time: ${now.toIso8601String()}')
      ..writeln('sessionStartedAt: ${logger.startedAt.toIso8601String()}')
      ..writeln('appVersion: $version')
      ..writeln('platform: $platform')
      ..writeln('isTv: ${DeviceType.isTv}')
      ..writeln('primaryAbi: ${primaryAbi ?? ''}')
      ..writeln('');

    buffer
      ..writeln('settings:')
      ..writeln('  playerCore: ${appState.playerCore.name}')
      ..writeln('  preferHardwareDecode: ${appState.preferHardwareDecode}')
      ..writeln('  mpvCacheSizeMb: ${appState.mpvCacheSizeMb}')
      ..writeln(
          '  playbackBufferBackRatio: ${appState.playbackBufferBackRatio}')
      ..writeln('  unlimitedStreamCache: ${appState.unlimitedStreamCache}')
      ..writeln('  preloadEnabled: ${appState.preloadEnabled}')
      ..writeln('  autoSkipIntro: ${appState.autoSkipIntro}')
      ..writeln('  playbackProxyMode: ${appState.playbackProxyMode.name}')
      ..writeln(
          '  playbackProxyUrl: ${AppDiagnosticsLogger.summarizeUrl(appState.playbackProxyUrl)}')
      ..writeln('  tvBuiltInProxyEnabled: ${appState.tvBuiltInProxyEnabled}')
      ..writeln('  externalMpvPath: ${_maskPath(appState.externalMpvPath)}')
      ..writeln('');

    buffer
      ..writeln('servers:')
      ..writeln('  total: ${appState.servers.length}')
      ..writeln('  active: ${_summarizeServer(activeServer)}');
    if (activeServer != null) {
      buffer
        ..writeln('  activeLastErrorCode: ${activeServer.lastErrorCode ?? ''}')
        ..writeln(
            '  activeLastErrorMessage: ${_safe(activeServer.lastErrorMessage ?? '')}');
    }

    if (extraSections != null && extraSections.isNotEmpty) {
      final sections = extraSections.entries.toList(growable: false)
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final section in sections) {
        final title = section.key.trim();
        final body = section.value.trim();
        if (title.isEmpty || body.isEmpty) continue;
        buffer
          ..writeln('')
          ..writeln('== $title ==')
          ..writeln(body);
      }
    }

    buffer
      ..writeln('')
      ..writeln('== Runtime Log ==')
      ..writeln(runtimeLog);

    return buffer.toString();
  }

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static String _summarizeServer(ServerProfile? server) {
    if (server == null) return '(none)';
    return [
      'name=${_safe(server.name)}',
      'type=${server.serverType.name}',
      'base=${AppDiagnosticsLogger.summarizeUrl(server.baseUrl)}',
      'apiPrefix=${_safe(server.apiPrefix)}',
      'username=${_safe(server.username)}',
    ].join(', ');
  }

  static String _maskPath(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return '';
    if (kIsWeb) return _safe(input);
    try {
      final file = File(input);
      final base =
          file.uri.pathSegments.isEmpty ? input : file.uri.pathSegments.last;
      return _safe(base);
    } catch (_) {
      return _safe(input);
    }
  }

  static String _safe(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
