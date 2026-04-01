import 'package:flutter/foundation.dart';

import '../source/resolved_playback_source.dart';

@immutable
class PreloadRequest {
  const PreloadRequest({
    required this.resolvedSource,
    required this.triggerSource,
    this.startPosition = Duration.zero,
    this.dedupeFingerprint,
    this.httpProxyUrl,
  });

  final ResolvedPlaybackSource resolvedSource;
  final String triggerSource;
  final Duration startPosition;
  final String? dedupeFingerprint;
  final String? httpProxyUrl;
}
