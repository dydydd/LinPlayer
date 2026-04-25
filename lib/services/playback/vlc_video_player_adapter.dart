import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

enum VideoViewType {
  textureView,
  platformView,
}

@immutable
class DurationRange {
  const DurationRange(this.start, this.end);

  final Duration start;
  final Duration end;
}

@immutable
class VideoPlayerValue {
  const VideoPlayerValue({
    required this.isInitialized,
    required this.isPlaying,
    required this.isBuffering,
    required this.position,
    required this.duration,
    required this.aspectRatio,
    required this.size,
    required this.buffered,
    required this.playbackSpeed,
    required this.rotationCorrection,
    required this.errorDescription,
  });

  const VideoPlayerValue.uninitialized()
      : isInitialized = false,
        isPlaying = false,
        isBuffering = false,
        position = Duration.zero,
        duration = Duration.zero,
        aspectRatio = 16 / 9,
        size = Size.zero,
        buffered = const <DurationRange>[],
        playbackSpeed = 1.0,
        rotationCorrection = 0,
        errorDescription = '';

  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double aspectRatio;
  final Size size;
  final List<DurationRange> buffered;
  final double playbackSpeed;
  final int rotationCorrection;
  final String errorDescription;

  bool get hasError => errorDescription.trim().isNotEmpty;
}

class VideoPlayerController {
  VideoPlayerController._(
    this._controller, {
    required this.debugSource,
  });

  factory VideoPlayerController.file(
    File file, {
    VideoViewType viewType = VideoViewType.textureView,
  }) {
    return VideoPlayerController._(
      VlcPlayerController.file(
        file,
        autoInitialize: false,
        autoPlay: false,
        hwAcc: HwAcc.auto,
      ),
      debugSource: file.path,
    );
  }

  factory VideoPlayerController.networkUrl(
    Uri uri, {
    Map<String, String>? httpHeaders,
    VideoViewType viewType = VideoViewType.textureView,
  }) {
    final resolvedUri = _withTokenQuery(uri, httpHeaders);
    final options = buildVlcPlayerOptionsFromHttpHeaders(httpHeaders);
    return VideoPlayerController._(
      VlcPlayerController.network(
        resolvedUri.toString(),
        autoInitialize: false,
        autoPlay: false,
        hwAcc: resolveVlcNetworkHwAcc(isIos: Platform.isIOS),
        options: options,
      ),
      debugSource: resolvedUri.toString(),
    );
  }

  factory VideoPlayerController.contentUri(
    Uri uri, {
    VideoViewType viewType = VideoViewType.textureView,
  }) {
    return VideoPlayerController.networkUrl(uri, viewType: viewType);
  }

  static Uri _withTokenQuery(Uri uri, Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return uri;
    final token = (_headerValue(headers, const <String>[
      'x-emby-token',
      'x-mediabrowser-token',
    ])).trim();
    if (token.isEmpty || uri.queryParameters.containsKey('api_key')) {
      return uri;
    }
    final next = Map<String, String>.from(uri.queryParameters);
    next['api_key'] = token;
    return uri.replace(queryParameters: next);
  }

  final VlcPlayerController _controller;
  final String debugSource;
  VideoPlayerValue _value = const VideoPlayerValue.uninitialized();
  bool _initialized = false;

  VlcPlayerController get rawController => _controller;
  VideoPlayerValue get value => _value;

  // Compatibility shim for copied video_player based pages.
  int get playerId => 0;

  Future<void> initialize() async {
    if (_initialized) return;
    _controller.addListener(_syncValueFromController);
    await _controller.initialize();
    _initialized = true;
    _syncValueFromController();
  }

  Future<void> play() => _controller.play();

  Future<void> pause() => _controller.pause();

  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  Future<void> setPlaybackSpeed(double speed) {
    return _controller.setPlaybackSpeed(speed);
  }

  Future<void> setLooping(bool enabled) => _controller.setLooping(enabled);

  Future<void> setVolume(double volume) {
    final normalized = (volume.clamp(0.0, 1.0) * 100).round();
    return _controller.setVolume(normalized);
  }

  void _syncValueFromController() {
    final raw = _controller.value;
    final rawSize = raw.size;
    final size = (rawSize.width > 0 && rawSize.height > 0)
        ? Size(rawSize.width.toDouble(), rawSize.height.toDouble())
        : Size.zero;
    final duration = raw.duration;
    final position = raw.position;
    final bufferPercent = raw.bufferPercent.clamp(0.0, 100.0).toDouble();
    final bufferedEnd = duration > Duration.zero
        ? Duration(
            milliseconds:
                (duration.inMilliseconds * (bufferPercent / 100)).round(),
          )
        : position;
    _value = VideoPlayerValue(
      isInitialized: raw.isInitialized,
      isPlaying: raw.isPlaying,
      isBuffering: raw.isBuffering,
      position: position,
      duration: duration,
      aspectRatio: raw.aspectRatio > 0
          ? raw.aspectRatio
          : (size.width > 0 && size.height > 0
              ? size.width / size.height
              : 16 / 9),
      size: size,
      buffered: bufferedEnd > Duration.zero
          ? <DurationRange>[DurationRange(Duration.zero, bufferedEnd)]
          : const <DurationRange>[],
      playbackSpeed: raw.playbackSpeed <= 0 ? 1.0 : raw.playbackSpeed,
      rotationCorrection: 0,
      errorDescription: raw.errorDescription.trim(),
    );
  }

  Future<void> dispose() async {
    _controller.removeListener(_syncValueFromController);
    await _controller.stop();
    await _controller.dispose();
  }
}

String _headerValue(Map<String, String>? headers, List<String> keys) {
  if (headers == null || headers.isEmpty) return '';
  final lowerKeys = keys.map((key) => key.toLowerCase()).toSet();
  for (final entry in headers.entries) {
    if (!lowerKeys.contains(entry.key.toLowerCase())) continue;
    final value = entry.value.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

@visibleForTesting
HwAcc resolveVlcNetworkHwAcc({required bool isIos}) {
  // Keep iOS network playback on the safer software-decoding path. This is a
  // VLC-specific stability policy for authenticated Emby streams.
  return isIos ? HwAcc.disabled : HwAcc.auto;
}

const Set<String> _hopByHopVlcHeaderNames = <String>{
  'accept-encoding',
  'connection',
  'content-length',
  'host',
  'if-range',
  'range',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
};

bool _shouldForwardGenericVlcHeader(String name) {
  final lower = name.trim().toLowerCase();
  if (lower.isEmpty) return false;
  if (_hopByHopVlcHeaderNames.contains(lower)) return false;
  if (lower == 'cookie') return false;
  if (lower == 'origin') return false;
  if (lower == 'referer' || lower == 'referrer') return false;
  if (lower == 'user-agent') return false;
  return true;
}

@visibleForTesting
VlcPlayerOptions? buildVlcPlayerOptionsFromHttpHeaders(
  Map<String, String>? headers,
) {
  if (headers == null || headers.isEmpty) return null;

  final httpOptions = <String>[];
  final extraOptions = <String>[];

  final userAgent = _headerValue(headers, const <String>['user-agent']);
  if (userAgent.isNotEmpty) {
    httpOptions.add(VlcHttpOptions.httpUserAgent(userAgent));
  }

  final referer = _headerValue(headers, const <String>[
    'referer',
    'referrer',
  ]);
  if (referer.isNotEmpty) {
    httpOptions.add(VlcHttpOptions.httpReferrer(referer));
  }

  final origin = _headerValue(headers, const <String>['origin']);
  if (origin.isNotEmpty) {
    extraOptions.add(':http-origin=$origin');
  }

  final cookie = _headerValue(headers, const <String>['cookie']);
  if (cookie.isNotEmpty) {
    extraOptions.add(':http-cookie=$cookie');
    httpOptions.add(VlcHttpOptions.httpForwardCookies(true));
  }

  for (final entry in headers.entries) {
    final name = entry.key.trim();
    final value = entry.value.trim();
    if (name.isEmpty || value.isEmpty) continue;
    if (!_shouldForwardGenericVlcHeader(name)) continue;
    extraOptions.add(':http-header=$name: $value');
  }

  if (httpOptions.isEmpty && extraOptions.isEmpty) {
    return null;
  }

  return VlcPlayerOptions(
    http: httpOptions.isEmpty ? null : VlcHttpOptions(httpOptions),
    extras:
        extraOptions.isEmpty ? null : List<String>.unmodifiable(extraOptions),
  );
}

class VideoPlayer extends StatelessWidget {
  const VideoPlayer(this.controller, {super.key});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = controller.value.aspectRatio <= 0
        ? 16 / 9
        : controller.value.aspectRatio;
    return VlcPlayer(
      controller: controller.rawController,
      aspectRatio: aspectRatio,
      placeholder: const ColoredBox(color: Colors.black),
    );
  }
}
