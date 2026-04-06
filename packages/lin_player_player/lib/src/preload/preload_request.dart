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
    this.ownerKey,
    this.scopeKey,
  });

  final ResolvedPlaybackSource resolvedSource;
  final String triggerSource;
  final Duration startPosition;
  final Duration preloadDuration;

  /// Optional extra namespace for dedupe/hit records.
  /// When present it is combined with the resolved source fingerprint instead
  /// of replacing it, so callers can separate semantic targets like
  /// "current item" vs "next item" without losing source-level identity.
  final String? dedupeFingerprint;
  final String? httpProxyUrl;

  /// Optional lifecycle owner for cancellable preload work.
  /// Typical values are a detail-page instance or a playback-session token.
  final String? ownerKey;

  /// Optional semantic scope inside the owner, mainly for diagnostics.
  /// Typical values are "detail_current", "detail_next",
  /// "playback_current", and "playback_next".
  final String? scopeKey;
}
