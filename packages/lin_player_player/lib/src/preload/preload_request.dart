import 'package:flutter/foundation.dart';

import '../source/resolved_playback_source.dart';

@immutable
class PreloadRequest {
  static const Duration defaultPreloadDuration = Duration(seconds: 3);

  const PreloadRequest({
    required this.resolvedSource,
    required this.triggerSource,
    this.startPosition = Duration.zero,
    this.preloadDuration = defaultPreloadDuration,
    this.dedupeFingerprint,
    this.httpProxyUrl,
  });

  final ResolvedPlaybackSource resolvedSource;
  final String triggerSource;
  final Duration startPosition;
  final Duration preloadDuration;
  final String? dedupeFingerprint;
  final String? httpProxyUrl;
}
