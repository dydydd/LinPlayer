import 'dart:async';
import 'dart:math' show max, min;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_interfaces.dart';
import 'player_adapter.dart';
import 'video_player_adapter.dart';
import 'media_kit_adapter.dart';

/// 播放器内核类型
enum PlayerCoreType {
  videoPlayer,  // ExoPlayer/AVPlayer
  mediaKit,     // MPV原生
}

/// 视频播放器服务
/// 
/// 支持动态切换播放器内核：
/// - video_player: 轻量稳定，适合大多数场景
/// - media_kit: MPV原生，支持PGS/SUP图形字幕、HDR
class VideoPlayerService extends ChangeNotifier {
  PlayerAdapter? _adapter;
  PlayerCoreType _coreType = PlayerCoreType.videoPlayer;
  
  Timer? _progressTimer;
  Timer? _hideControlsTimer;
  
  // 手势状态
  bool _showControls = true;
  bool _isLocked = false;
  bool _isDragging = false;
  double _dragStartX = 0;
  double _dragStartY = 0;
  Duration _dragStartPosition = Duration.zero;
  double _dragStartVolume = 1.0;
  double _currentBrightness = 1.0;
  double _dragStartBrightness = 1.0;
  
  // 播放上报
  String? _currentItemId;
  String? _mediaSourceId;
  Function(PlaybackProgressInfo)? _onProgressReport;
  Function(PlaybackStartInfo)? _onStartReport;
  Function(PlaybackStopInfo)? _onStopReport;
  
  // Getters
  bool get isPlaying => _adapter?.isPlaying ?? false;
  bool get isBuffering => _adapter?.isBuffering ?? false;
  bool get isInitialized => _adapter?.isInitialized ?? false;
  bool get hasError => _adapter?.hasError ?? false;
  String? get errorMessage => _adapter?.errorMessage;
  Duration get position => _adapter?.position ?? Duration.zero;
  Duration get duration => _adapter?.duration ?? Duration.zero;
  double get speed => _adapter?.speed ?? 1.0;
  double get volume => _adapter?.volume ?? 1.0;
  bool get showControls => _showControls;
  bool get isLocked => _isLocked;
  bool get isDragging => _isDragging;
  bool get isCompleted => _adapter?.isCompleted ?? false;
  double get progress => _adapter?.progress ?? 0.0;
  PlayerCoreType get coreType => _coreType;
  double get brightness => _currentBrightness;
  
  /// 设置播放器内核
  void setCoreType(PlayerCoreType type) {
    if (_coreType == type) return;
    _coreType = type;
    // 如果正在播放，需要重新初始化
    if (_adapter?.isInitialized ?? false) {
      // TODO: 重新加载当前视频
    }
    notifyListeners();
  }
  
  /// 创建适配器
  PlayerAdapter _createAdapter() {
    switch (_coreType) {
      case PlayerCoreType.videoPlayer:
        return VideoPlayerAdapter();
      case PlayerCoreType.mediaKit:
        return MediaKitAdapter();
    }
  }
  
  /// 初始化播放器
  Future<void> initialize({
    required String videoUrl,
    required String itemId,
    String? mediaSourceId,
    Duration? startPosition,
    PlayerCoreType? coreType,
    Function(PlaybackStartInfo)? onStart,
    Function(PlaybackProgressInfo)? onProgress,
    Function(PlaybackStopInfo)? onStop,
    bool? dolbyVisionFix,
    bool? useLibass,
  }) async {
    _currentItemId = itemId;
    _mediaSourceId = mediaSourceId ?? itemId;
    _onStartReport = onStart;
    _onProgressReport = onProgress;
    _onStopReport = onStop;
    
    if (coreType != null) {
      _coreType = coreType;
    }
    
    // 释放旧适配器
    await _adapter?.dispose();
    
    // 创建新适配器
    _adapter = _createAdapter();
    
    // 设置回调
    _adapter!.setCallbacks(PlayerStateCallbacks(
      onPositionChanged: () => notifyListeners(),
      onDurationChanged: () => notifyListeners(),
      onPlayingStateChanged: () {
        if (_adapter?.isPlaying ?? false) {
          _startHideControlsTimer();
        } else {
          _cancelHideControlsTimer();
        }
        notifyListeners();
      },
      onBufferingStateChanged: () => notifyListeners(),
      onCompleted: () {
        notifyListeners();
        // TODO: 自动播放下一集
      },
      onError: () => notifyListeners(),
    ));
    
    // 初始化
    await _adapter!.initialize(
      videoUrl: videoUrl,
      startPosition: startPosition,
      dolbyVisionFix: dolbyVisionFix ?? false,
      useLibass: useLibass ?? false,
    );
    
    // 开始播放
    await _adapter!.play();
    
    // 上报开始
    _reportStart();
    
    // 启动进度定时器
    _startProgressTimer();
    
    notifyListeners();
  }
  
  /// 视频渲染Widget
  Widget buildVideoWidget() {
    if (_adapter == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('正在加载...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    return _adapter!.buildVideoWidget();
  }
  
  /// 播放
  Future<void> play() async {
    await _adapter?.play();
    _startHideControlsTimer();
    notifyListeners();
  }
  
  /// 暂停
  Future<void> pause() async {
    await _adapter?.pause();
    _cancelHideControlsTimer();
    notifyListeners();
  }
  
  /// 播放/暂停切换
  Future<void> togglePlay() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }
  
  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    await _adapter?.seekTo(position);
    notifyListeners();
  }
  
  /// 快进/快退
  Future<void> seekBy(Duration offset) async {
    await seekTo(position + offset);
  }
  
  /// 设置播放速度
  Future<void> setSpeed(double speed) async {
    await _adapter?.setSpeed(speed);
    notifyListeners();
  }
  
  /// 设置音量
  Future<void> setVolume(double volume) async {
    await _adapter?.setVolume(volume);
    notifyListeners();
  }

  /// 设置亮度
  void setBrightness(double brightness) {
    _currentBrightness = brightness.clamp(0.1, 1.0);
    notifyListeners();
  }

  /// 保存亮度到本地
  Future<void> saveBrightness() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('player_brightness', _currentBrightness);
  }

  /// 从本地加载亮度
  Future<void> loadBrightness() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBrightness = prefs.getDouble('player_brightness');
    if (savedBrightness != null) {
      _currentBrightness = savedBrightness;
      notifyListeners();
    }
  }
  
  /// 显示/隐藏控制栏
  void toggleControls() {
    if (_isLocked) return;
    _showControls = !_showControls;
    if (_showControls) {
      _startHideControlsTimer();
    } else {
      _cancelHideControlsTimer();
    }
    notifyListeners();
  }
  
  /// 锁定/解锁屏幕
  void toggleLock() {
    _isLocked = !_isLocked;
    if (_isLocked) {
      _showControls = false;
      _cancelHideControlsTimer();
    }
    notifyListeners();
  }
  
  // ========== 手势控制 ==========
  
  void onDragStart(DragStartDetails details, BoxConstraints constraints) {
    if (_isLocked || !isInitialized) return;
    _isDragging = true;
    _dragStartX = details.globalPosition.dx;
    _dragStartY = details.globalPosition.dy;
    _dragStartPosition = position;
    _dragStartVolume = volume;
    _dragStartBrightness = _currentBrightness;
    _cancelHideControlsTimer();
    notifyListeners();
  }
  
  void onDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (!_isDragging || _isLocked) return;
    
    final dx = details.globalPosition.dx - _dragStartX;
    final dy = details.globalPosition.dy - _dragStartY;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    
    if (dx.abs() > dy.abs()) {
      // 水平滑动：进度
      final progressDelta = dx / width * duration.inMilliseconds;
      final newPositionMs = max(0, min(
        _dragStartPosition.inMilliseconds + progressDelta.round(),
        duration.inMilliseconds,
      ));
      // 不实际跳转，只更新显示位置
      _dragStartPosition = Duration(milliseconds: newPositionMs);
      notifyListeners();
    } else {
      // 垂直滑动
      if (_dragStartX < width / 2) {
        // 左侧：亮度
        final brightnessDelta = -dy / height;
        final newBrightness = (_dragStartBrightness + brightnessDelta).clamp(0.1, 1.0);
        setBrightness(newBrightness);
      } else {
        // 右侧：音量
        final volumeDelta = -dy / height;
        final newVolume = (_dragStartVolume + volumeDelta).clamp(0.0, 1.0);
        setVolume(newVolume);
      }
    }
  }
  
  void onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    // 执行实际跳转
    seekTo(_dragStartPosition);
    _startHideControlsTimer();
    notifyListeners();
  }
  
  // ========== 内部方法 ==========
  
  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _reportProgress();
    });
  }
  
  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }
  
  void _startHideControlsTimer() {
    _cancelHideControlsTimer();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (isPlaying && !_isDragging) {
        _showControls = false;
        notifyListeners();
      }
    });
  }
  
  void _cancelHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = null;
  }
  
  // ========== 播放上报 ==========
  
  void _reportStart() {
    if (_onStartReport == null || _currentItemId == null) return;
    _onStartReport!(PlaybackStartInfo(
      itemId: _currentItemId!,
      mediaSourceId: _mediaSourceId ?? _currentItemId!,
    ));
  }
  
  void _reportProgress() {
    if (_onProgressReport == null || _currentItemId == null) return;
    _onProgressReport!(PlaybackProgressInfo(
      itemId: _currentItemId!,
      mediaSourceId: _mediaSourceId ?? _currentItemId!,
      positionTicks: (position.inMilliseconds * 10000).round(),
      isPaused: !isPlaying,
      volumeLevel: volume,
    ));
  }
  
  void _reportStop() {
    if (_onStopReport == null || _currentItemId == null) return;
    _onStopReport!(PlaybackStopInfo(
      itemId: _currentItemId!,
      mediaSourceId: _mediaSourceId ?? _currentItemId!,
      positionTicks: (position.inMilliseconds * 10000).round(),
    ));
  }
  
  /// 释放资源
  @override
  void dispose() {
    _reportStop();
    _stopProgressTimer();
    _cancelHideControlsTimer();
    _adapter?.dispose();
    _adapter = null;
    super.dispose();
  }
}
