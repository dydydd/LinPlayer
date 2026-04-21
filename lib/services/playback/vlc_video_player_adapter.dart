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
  });

  const VideoPlayerValue.uninitialized()
      : isInitialized = false,
        isPlaying = false,
        isBuffering = false,
        position = Duration.zero,
        duration = Duration.zero,
        aspectRatio = 16 / 9,
        size = const Size(16, 9),
        buffered = const <DurationRange>[],
        playbackSpeed = 1.0,
        rotationCorrection = 0;

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
    return VideoPlayerController._(
      VlcPlayerController.network(
        resolvedUri.toString(),
        autoInitialize: false,
        autoPlay: false,
        hwAcc: HwAcc.auto,
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
    final token =
        (headers['X-Emby-Token'] ?? headers['X-MediaBrowser-Token'] ?? '')
            .trim();
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
        : const Size(16, 9);
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
      aspectRatio: raw.aspectRatio <= 0 ? 16 / 9 : raw.aspectRatio,
      size: size,
      buffered: bufferedEnd > Duration.zero
          ? <DurationRange>[DurationRange(Duration.zero, bufferedEnd)]
          : const <DurationRange>[],
      playbackSpeed: raw.playbackSpeed <= 0 ? 1.0 : raw.playbackSpeed,
      rotationCorrection: 0,
    );
  }

  Future<void> dispose() async {
    _controller.removeListener(_syncValueFromController);
    await _controller.stop();
    await _controller.dispose();
  }
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
