import 'package:flutter/material.dart';

/// 播放器适配器接口
/// 
/// 抽象所有播放器内核的通用操作，支持切换不同实现
abstract class PlayerAdapter {
  /// 是否已初始化
  bool get isInitialized;
  
  /// 是否正在播放
  bool get isPlaying;
  
  /// 是否缓冲中
  bool get isBuffering;
  
  /// 是否播放完成
  bool get isCompleted;
  
  /// 当前位置
  Duration get position;
  
  /// 总时长
  Duration get duration;
  
  /// 当前播放速度
  double get speed;
  
  /// 当前音量
  double get volume;
  
  /// 播放进度 0.0-1.0
  double get progress;
  
  /// 是否有错误
  bool get hasError;
  
  /// 错误信息
  String? get errorMessage;
  
  /// 视频渲染Widget
  Widget buildVideoWidget();
  
  /// 初始化播放器
  Future<void> initialize({
    required String videoUrl,
    Duration? startPosition,
    bool dolbyVisionFix = false,
    bool useLibass = false,
  });
  
  /// 播放
  Future<void> play();
  
  /// 暂停
  Future<void> pause();
  
  /// 跳转到指定位置
  Future<void> seekTo(Duration position);
  
  /// 设置播放速度
  Future<void> setSpeed(double speed);
  
  /// 设置音量
  Future<void> setVolume(double volume);
  
  /// 设置状态回调
  void setCallbacks(PlayerStateCallbacks callbacks);
  
  /// 释放资源
  Future<void> dispose();
}

/// 播放器状态回调
class PlayerStateCallbacks {
  final VoidCallback? onPositionChanged;
  final VoidCallback? onDurationChanged;
  final VoidCallback? onPlayingStateChanged;
  final VoidCallback? onBufferingStateChanged;
  final VoidCallback? onCompleted;
  final VoidCallback? onError;
  
  const PlayerStateCallbacks({
    this.onPositionChanged,
    this.onDurationChanged,
    this.onPlayingStateChanged,
    this.onBufferingStateChanged,
    this.onCompleted,
    this.onError,
  });
}
