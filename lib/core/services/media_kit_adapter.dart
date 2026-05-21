import 'dart:async';
import 'dart:math' show max, min;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'player_adapter.dart';

/// media_kit 适配器
/// 
/// 基于 libmpv (MPV原生) 实现
/// 优势：完整支持PGS/SUP图形字幕、HDR、硬解、几乎所有格式
class MediaKitAdapter implements PlayerAdapter {
  Player? _player;
  VideoController? _videoController;
  
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _bufferingSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _completedSub;
  StreamSubscription? _errorSub;
  
  bool _isInitialized = false;
  bool _isCompleted = false;
  String? _errorMessage;
  
  PlayerStateCallbacks? _callbacks;
  
  @override
  bool get isInitialized => _isInitialized;
  
  @override
  bool get isPlaying => _player?.state.playing ?? false;
  
  @override
  bool get isBuffering => _player?.state.buffering ?? false;
  
  @override
  bool get isCompleted => _isCompleted;
  
  @override
  Duration get position => _player?.state.position ?? Duration.zero;
  
  @override
  Duration get duration => _player?.state.duration ?? Duration.zero;
  
  @override
  double get speed => _player?.state.rate ?? 1.0;
  
  @override
  double get volume {
    final vol = _player?.state.volume ?? 100.0;
    return vol / 100.0;
  }
  
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
    if (!_isInitialized || _videoController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Video(
      controller: _videoController!,
      controls: NoVideoControls,
      fit: BoxFit.contain,
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
      
      _isInitialized = false;
      _isCompleted = false;
      _errorMessage = null;
      
      // 创建 MPV 播放器，根据设置配置参数
      final configuration = PlayerConfiguration(
        vo: dolbyVisionFix ? 'gpu-next' : null,
      );
      _player = Player(configuration: configuration);
      _videoController = VideoController(_player!);
      
      // 监听状态
      _positionSub = _player!.stream.position.listen((_) {
        _callbacks?.onPositionChanged?.call();
      });
      
      _durationSub = _player!.stream.duration.listen((_) {
        _callbacks?.onDurationChanged?.call();
      });
      
      _bufferingSub = _player!.stream.buffering.listen((_) {
        _callbacks?.onBufferingStateChanged?.call();
      });
      
      _playingSub = _player!.stream.playing.listen((_) {
        _callbacks?.onPlayingStateChanged?.call();
      });
      
      _completedSub = _player!.stream.completed.listen((completed) {
        if (completed) {
          _isCompleted = true;
          _callbacks?.onCompleted?.call();
        }
      });
      
      // 打开媒体
      await _player!.open(Media(videoUrl));
      
      // 设置初始位置
      if (startPosition != null && startPosition > Duration.zero) {
        await _player!.seek(startPosition);
      }
      
      _isInitialized = true;
      _callbacks?.onDurationChanged?.call();
    } catch (e) {
      _errorMessage = e.toString();
      _isInitialized = false;
      _callbacks?.onError?.call();
    }
  }
  
  @override
  Future<void> play() async {
    if (_player == null) return;
    await _player!.play();
    _isCompleted = false;
  }
  
  @override
  Future<void> pause() async {
    if (_player == null) return;
    await _player!.pause();
  }
  
  @override
  Future<void> seekTo(Duration position) async {
    if (_player == null || !_isInitialized) return;
    final clamped = Duration(
      milliseconds: max(0, min(position.inMilliseconds, duration.inMilliseconds)),
    );
    await _player!.seek(clamped);
    _isCompleted = false;
  }
  
  @override
  Future<void> setSpeed(double speed) async {
    if (_player == null || !_isInitialized) return;
    final clamped = speed.clamp(0.25, 4.0);
    await _player!.setRate(clamped);
  }
  
  @override
  Future<void> setVolume(double volume) async {
    if (_player == null || !_isInitialized) return;
    final clamped = volume.clamp(0.0, 1.0);
    await _player!.setVolume(clamped * 100); // media_kit 使用 0-100
  }
  
  @override
  Future<void> dispose() async {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferingSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    
    _positionSub = null;
    _durationSub = null;
    _bufferingSub = null;
    _playingSub = null;
    _completedSub = null;
    _errorSub = null;
    
    _videoController = null;
    
    _player?.dispose();
    _player = null;
    
    _isInitialized = false;
  }
}
