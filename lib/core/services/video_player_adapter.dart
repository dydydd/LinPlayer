import 'dart:async';
import 'dart:math' show max, min;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'player_adapter.dart';

/// video_player 适配器
/// 
/// 基于 ExoPlayer(Android) / AVPlayer(iOS) 实现
class VideoPlayerAdapter implements PlayerAdapter {
  VideoPlayerController? _controller;
  Timer? _positionTimer;
  
  bool _isCompleted = false;
  String? _errorMessage;
  
  PlayerStateCallbacks? _callbacks;
  
  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  
  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  
  @override
  bool get isBuffering => _controller?.value.isBuffering ?? false;
  
  @override
  bool get isCompleted => _isCompleted;
  
  @override
  Duration get position => _controller?.value.position ?? Duration.zero;
  
  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;
  
  @override
  double get speed => _controller?.value.playbackSpeed ?? 1.0;
  
  @override
  double get volume => _controller?.value.volume ?? 1.0;
  
  @override
  double get progress {
    final dur = duration.inMilliseconds;
    if (dur <= 0) return 0.0;
    return position.inMilliseconds / dur;
  }
  
  @override
  bool get hasError => _errorMessage != null;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  void setCallbacks(PlayerStateCallbacks callbacks) {
    _callbacks = callbacks;
  }
  
  @override
  Widget buildVideoWidget() {
    if (!isInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
  
  @override
  Future<void> initialize({
    required String videoUrl,
    Duration? startPosition,
    bool dolbyVisionFix = false,
    bool useLibass = false,
  }) async {
    try {
      await dispose();
      
      _errorMessage = null;
      _isCompleted = false;
      
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: true,
        ),
      );
      
      await _controller!.initialize();
      
      if (startPosition != null && startPosition > Duration.zero) {
        await _controller!.seekTo(startPosition);
      }
      
      // 监听状态
      _controller!.addListener(_onControllerUpdate);
      
      // 启动位置更新定时器（video_player 位置更新不够及时）
      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _callbacks?.onPositionChanged?.call(),
      );
      
      _callbacks?.onDurationChanged?.call();
    } catch (e) {
      _errorMessage = e.toString();
      _callbacks?.onError?.call();
    }
  }
  
  @override
  Future<void> play() async {
    if (_controller == null) return;
    await _controller!.play();
    _isCompleted = false;
    _callbacks?.onPlayingStateChanged?.call();
  }
  
  @override
  Future<void> pause() async {
    if (_controller == null) return;
    await _controller!.pause();
    _callbacks?.onPlayingStateChanged?.call();
  }
  
  @override
  Future<void> seekTo(Duration position) async {
    if (_controller == null || !isInitialized) return;
    final clamped = Duration(
      milliseconds: max(0, min(position.inMilliseconds, duration.inMilliseconds)),
    );
    await _controller!.seekTo(clamped);
    _isCompleted = false;
    _callbacks?.onPositionChanged?.call();
  }
  
  @override
  Future<void> setSpeed(double speed) async {
    if (_controller == null || !isInitialized) return;
    final clamped = speed.clamp(0.25, 4.0);
    await _controller!.setPlaybackSpeed(clamped);
    _callbacks?.onPlayingStateChanged?.call();
  }
  
  @override
  Future<void> setVolume(double volume) async {
    if (_controller == null || !isInitialized) return;
    final clamped = volume.clamp(0.0, 1.0);
    await _controller!.setVolume(clamped);
  }
  
  void _onControllerUpdate() {
    if (_controller == null) return;
    
    final value = _controller!.value;
    
    if (value.isPlaying != isPlaying) {
      _callbacks?.onPlayingStateChanged?.call();
    }
    
    if (value.isBuffering != isBuffering) {
      _callbacks?.onBufferingStateChanged?.call();
    }
    
    // 检测播放完成
    if (value.position >= value.duration && value.duration > Duration.zero && !isCompleted) {
      _isCompleted = true;
      _callbacks?.onCompleted?.call();
    }
  }
  
  @override
  Future<void> dispose() async {
    _positionTimer?.cancel();
    _positionTimer = null;
    
    _controller?.removeListener(_onControllerUpdate);
    await _controller?.dispose();
    _controller = null;
  }
}
