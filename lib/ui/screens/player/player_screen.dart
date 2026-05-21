import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../core/services/video_player_service.dart';

/// 播放页
class PlayerScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String? mediaSourceId;
  
  const PlayerScreen({super.key, required this.itemId, this.mediaSourceId});
  
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver {
  late VideoPlayerService _playerService;
  bool _showRemaining = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playerService = VideoPlayerService();
    _playerService.addListener(_onPlayerUpdate);
    _initializePlayer();
  }
  
  Future<void> _initializePlayer() async {
    final api = ref.read(apiClientProvider);
    final item = await api.media.getItemDetails(widget.itemId);
    
    // 获取播放信息
    final playbackInfo = await api.playback.getPlaybackInfo(widget.itemId);
    final mediaSource = playbackInfo.mediaSources.firstOrNull;
    
    // 获取视频流URL
    final videoUrl = api.playback.getVideoStreamUrl(widget.itemId);
    
    // 计算开始位置
    Duration? startPosition;
    if (item.userData?.playbackPositionTicks != null) {
      startPosition = Duration(
        milliseconds: (item.userData!.playbackPositionTicks! / 10000).round(),
      );
    }
    
    // 设置状态
    ref.read(currentPlayingItemProvider.notifier).state = item;
    
    // 读取用户选择的播放器内核
    final coreString = ref.read(playerCoreProvider);
    final coreType = coreString == 'media_kit'
        ? PlayerCoreType.mediaKit
        : PlayerCoreType.videoPlayer;
    
    // 读取播放器高级设置
    final dolbyVisionFix = coreType == PlayerCoreType.mediaKit 
        ? ref.read(mpvDolbyVisionFixProvider) 
        : false;
    final useLibass = coreType == PlayerCoreType.videoPlayer 
        ? ref.read(exoLibassProvider) 
        : false;
    
    // 初始化播放器
    await _playerService.initialize(
      videoUrl: videoUrl,
      itemId: widget.itemId,
      mediaSourceId: mediaSource?.id,
      startPosition: startPosition,
      coreType: coreType,
      dolbyVisionFix: dolbyVisionFix,
      useLibass: useLibass,
      onStart: (info) async {
        try {
          await api.playback.reportPlaybackStart(info);
        } catch (_) {}
      },
      onProgress: (info) async {
        try {
          await api.playback.reportPlaybackProgress(info);
        } catch (_) {}
      },
      onStop: (info) async {
        try {
          await api.playback.reportPlaybackStopped(info);
        } catch (_) {}
      },
    );
    
    // 设置全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  
  void _onPlayerUpdate() {
    setState(() {});
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _playerService.pause();
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerService.removeListener(_onPlayerUpdate);
    _playerService.dispose();
    
    // 恢复系统UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentPlayingItemProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTap: _playerService.toggleControls,
            onDoubleTap: _onDoubleTap,
            onHorizontalDragStart: (details) => _playerService.onDragStart(details, constraints),
            onHorizontalDragUpdate: (details) => _playerService.onDragUpdate(details, constraints),
            onHorizontalDragEnd: _playerService.onDragEnd,
            onVerticalDragStart: (details) => _playerService.onDragStart(details, constraints),
            onVerticalDragUpdate: (details) => _playerService.onDragUpdate(details, constraints),
            onVerticalDragEnd: _playerService.onDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 视频区域
                _buildVideoArea(),
                
                // 缓冲指示器
                if (_playerService.isBuffering)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                
                // 错误提示
                if (_playerService.hasError)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          '播放失败: ${_playerService.errorMessage}',
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _initializePlayer,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                
                // 控制层
                if (_playerService.showControls && !_playerService.isLocked)
                  _buildControlsOverlay(item),
                
                // 锁定按钮（始终显示）
                if (_playerService.isLocked)
                  Positioned(
                    top: 40,
                    left: 16,
                    child: IconButton(
                      icon: const Icon(Icons.lock, color: Colors.white),
                      onPressed: _playerService.toggleLock,
                    ),
                  ),
                
                // 拖动进度提示
                if (_playerService.isDragging)
                  _buildDragIndicator(),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildVideoArea() {
    return _playerService.buildVideoWidget();
  }
  
  void _onDoubleTap() {
    if (_playerService.isLocked) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = screenWidth / 2; // 简化处理，实际应该获取点击位置
    
    if (tapX < screenWidth / 3) {
      // 左侧双击：后退
      _playerService.seekBy(Duration(seconds: -ref.read(skipForwardStepProvider)));
    } else if (tapX > screenWidth * 2 / 3) {
      // 右侧双击：前进
      _playerService.seekBy(Duration(seconds: ref.read(skipForwardStepProvider)));
    } else {
      // 中间双击：播放/暂停
      _playerService.togglePlay();
    }
  }
  
  Widget _buildControlsOverlay(MediaItem? item) {
    return AnimatedOpacity(
      opacity: _playerService.showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              _buildTopBar(item),
              
              // 中间区域
              Expanded(
                child: Row(
                  children: [
                    // 左侧（截图/锁定）
                    SizedBox(
                      width: 60,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.white),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: Icon(
                              _playerService.isLocked ? Icons.lock : Icons.lock_open,
                              color: Colors.white,
                            ),
                            onPressed: _playerService.toggleLock,
                          ),
                        ],
                      ),
                    ),
                    
                    // 中间（播放/暂停按钮）
                    Expanded(
                      child: Center(
                        child: IconButton(
                          icon: Icon(
                            _playerService.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 64,
                          ),
                          onPressed: _playerService.togglePlay,
                        ),
                      ),
                    ),
                    
                    // 右侧（倍速条）
                    SizedBox(
                      width: 60,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add, color: Colors.white),
                            onPressed: () {
                              final newSpeed = (_playerService.speed + 0.25).clamp(0.25, 4.0);
                              _playerService.setSpeed(newSpeed);
                            },
                          ),
                          Text(
                            '${_playerService.speed}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove, color: Colors.white),
                            onPressed: () {
                              final newSpeed = (_playerService.speed - 0.25).clamp(0.25, 4.0);
                              _playerService.setSpeed(newSpeed);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // 进度条
              _buildProgressBar(),
              
              // 底部控制栏
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildTopBar(MediaItem? item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Text(
              item?.name ?? widget.itemId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          if (item?.type == 'Episode') ...[
            TextButton.icon(
              onPressed: () => _showEpisodeSelector(item!),
              icon: const Icon(Icons.playlist_play, color: Colors.white, size: 20),
              label: Text(
                'S${item?.parentIndexNumber}E${item?.indexNumber}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _showMoreMenu,
          ),
        ],
      ),
    );
  }
  
  Widget _buildProgressBar() {
    final currentTime = _formatDuration(_playerService.position);
    final remainingTime = _formatDuration(_playerService.duration - _playerService.position);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showRemaining = !_showRemaining),
                child: Text(
                  _showRemaining ? '-$remainingTime' : currentTime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF5B8DEF),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                    thumbColor: const Color(0xFF5B8DEF),
                    overlayColor: const Color(0xFF5B8DEF).withValues(alpha: 0.2),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _playerService.progress.clamp(0.0, 1.0),
                    onChanged: (value) {
                      final position = Duration(
                        milliseconds: (value * _playerService.duration.inMilliseconds).round(),
                      );
                      _playerService.seekTo(position);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDuration(_playerService.duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildBottomBar() {
    final isPlaying = _playerService.isPlaying;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white),
            onPressed: () => _playPrevious(),
          ),
          IconButton(
            icon: const Icon(Icons.replay_10, color: Colors.white),
            onPressed: () => _playerService.seekBy(const Duration(seconds: -10)),
          ),
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 40,
            ),
            onPressed: _playerService.togglePlay,
          ),
          IconButton(
            icon: const Icon(Icons.forward_10, color: Colors.white),
            onPressed: () => _playerService.seekBy(const Duration(seconds: 10)),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white),
            onPressed: () => _playNext(),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            onPressed: () => _showDanmakuSettings(),
          ),
          IconButton(
            icon: const Icon(Icons.subtitles, color: Colors.white),
            onPressed: () => _showSubtitleSettings(),
          ),
          IconButton(
            icon: const Icon(Icons.audiotrack, color: Colors.white),
            onPressed: () => _showAudioSettings(),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_play, color: Colors.white),
            onPressed: () => _showEpisodeSelector(ref.read(currentPlayingItemProvider)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDragIndicator() {
    final isForward = _playerService.position > _playerService.duration ~/ 2;
    
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isForward ? Icons.forward_10 : Icons.replay_10,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(_playerService.position),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  Future<void> _playPrevious() async {
    // TODO: 实现上一集逻辑
  }
  
  Future<void> _playNext() async {
    final autoPlay = ref.read(autoPlayNextProvider);
    if (!autoPlay) return;
    
    // TODO: 实现下一集逻辑
    // 获取当前剧集的下一集
    final currentItem = ref.read(currentPlayingItemProvider);
    if (currentItem?.seriesId != null) {
      final episodes = await ref.read(apiClientProvider).media.getEpisodes(
        currentItem!.seriesId!,
        seasonId: currentItem.seasonId,
      );
      final currentIndex = episodes.indexWhere((e) => e.id == currentItem.id);
      if (currentIndex >= 0 && currentIndex < episodes.length - 1) {
        final nextEpisode = episodes[currentIndex + 1];
        if (mounted) {
          context.replace('/player/${nextEpisode.id}');
        }
      }
    }
  }
  
  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.route, color: Colors.white),
              title: const Text('线路切换', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.screen_rotation, color: Colors.white),
              title: const Text('旋转屏幕', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _toggleOrientation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.white),
              title: const Text('定时关闭', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showTimerDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.memory, color: Colors.white),
              title: const Text('内核切换', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showCoreSwitchDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.analytics, color: Colors.white),
              title: const Text('统计信息', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showStats();
              },
            ),
            ListTile(
              leading: const Icon(Icons.aspect_ratio, color: Colors.white),
              title: const Text('画面比例', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showAspectRatioDialog();
              },
            ),
          ],
        ),
      ),
    );
  }
  
  void _toggleOrientation() {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }
  
  void _showStats() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('播放统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('播放速度: ${_playerService.speed}x'),
            Text('音量: ${(_playerService.volume * 100).toInt()}%'),
            Text('播放状态: ${_playerService.isPlaying ? "播放中" : "已暂停"}'),
            Text('当前位置: ${_formatDuration(_playerService.position)} / ${_formatDuration(_playerService.duration)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }
  
  void _showDanmakuSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const _DanmakuSettingsSheet(),
    );
  }
  
  void _showSubtitleSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const _SubtitleSettingsSheet(),
    );
  }
  
  void _showAudioSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const _AudioSettingsSheet(),
    );
  }
  
  void _showEpisodeSelector(MediaItem? item) {
    if (item?.seriesId == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return _EpisodeSelectorSheet(
            scrollController: scrollController,
            seriesId: item!.seriesId!,
            currentEpisodeId: item.id,
          );
        },
      ),
    );
  }

  void _showTimerDialog() {
    final options = [15, 30, 45, 60, 90, 120];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('定时关闭'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((minutes) => ListTile(
            title: Text('$minutes 分钟后关闭'),
            onTap: () {
              Navigator.pop(context);
              _startSleepTimer(Duration(minutes: minutes));
            },
          )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ],
      ),
    );
  }

  void _startSleepTimer(Duration duration) {
    Future.delayed(duration, () {
      if (mounted) {
        _playerService.pause();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已定时关闭播放')),
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已设置 ${duration.inMinutes} 分钟后关闭')),
    );
  }

  void _showCoreSwitchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换播放器内核'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('ExoPlayer/AVPlayer'),
              subtitle: const Text('当前内核', style: TextStyle(fontSize: 12)),
              leading: Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
              onTap: () {
                ref.read(playerCoreProvider.notifier).state = 'video_player';
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已切换到 ExoPlayer/AVPlayer，下次播放生效')),
                );
              },
            ),
            ListTile(
              title: const Text('MPV (media_kit)'),
              subtitle: const Text('支持PGS/SUP字幕、HDR', style: TextStyle(fontSize: 12)),
              onTap: () {
                ref.read(playerCoreProvider.notifier).state = 'media_kit';
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已切换到 MPV，下次播放生效')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAspectRatioDialog() {
    final ratios = ['自动', '16:9', '4:3', '21:9', '全屏', '原始'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('画面比例'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ratios.map((ratio) => ListTile(
            title: Text(ratio),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('画面比例: $ratio')),
              );
            },
          )).toList(),
        ),
      ),
    );
  }
}

/// 弹幕设置弹窗
class _DanmakuSettingsSheet extends StatelessWidget {
  const _DanmakuSettingsSheet();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('弹幕设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text('弹幕轨道'),
          ListTile(
            leading: const Icon(Icons.radio_button_checked),
            title: const Text('中文简体（默认）'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.radio_button_unchecked),
            title: const Text('中文繁体'),
            onTap: () {},
          ),
          const Divider(),
          const Text('字幕大小'),
          Slider(value: 0.5, onChanged: (_) {}),
          const Text('字幕位置'),
          Slider(value: 0.5, onChanged: (_) {}),
        ],
      ),
    );
  }
}

/// 字幕设置弹窗
class _SubtitleSettingsSheet extends StatelessWidget {
  const _SubtitleSettingsSheet();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('字幕设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text('字幕轨道'),
          ListTile(
            leading: const Icon(Icons.radio_button_checked),
            title: const Text('中文简体（默认）'),
            onTap: () {},
          ),
          const Divider(),
          const Text('字幕同步'),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.remove), onPressed: () {}),
              const Text('0.0s'),
              IconButton(icon: const Icon(Icons.add), onPressed: () {}),
            ],
          ),
        ],
      ),
    );
  }
}

/// 音频设置弹窗
class _AudioSettingsSheet extends StatelessWidget {
  const _AudioSettingsSheet();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('音频设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text('音频轨道'),
          ListTile(
            leading: const Icon(Icons.radio_button_checked),
            title: const Text('日语 5.1（默认）'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.radio_button_unchecked),
            title: const Text('日语 2.0'),
            onTap: () {},
          ),
          const Divider(),
          const Text('音频同步'),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.remove), onPressed: () {}),
              const Text('0.0s'),
              IconButton(icon: const Icon(Icons.add), onPressed: () {}),
            ],
          ),
        ],
      ),
    );
  }
}

/// 选集弹窗
class _EpisodeSelectorSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final String seriesId;
  final String currentEpisodeId;
  
  const _EpisodeSelectorSheet({
    required this.scrollController,
    required this.seriesId,
    required this.currentEpisodeId,
  });
  
  @override
  ConsumerState<_EpisodeSelectorSheet> createState() => _EpisodeSelectorSheetState();
}

class _EpisodeSelectorSheetState extends ConsumerState<_EpisodeSelectorSheet> {
  String? _selectedSeasonId;
  
  @override
  Widget build(BuildContext context) {
    final seasonsAsync = ref.watch(seasonsProvider(widget.seriesId));
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          
          // 季选择
          seasonsAsync.when(
            data: (seasons) {
              if (seasons.isEmpty) return const SizedBox.shrink();
              
              return Row(
                children: [
                  const Text('季度选择'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedSeasonId ?? seasons.first.id,
                    items: seasons.map((season) => DropdownMenuItem(
                      value: season.id,
                      child: Text(season.name),
                    )).toList(),
                    onChanged: (value) {
                      setState(() => _selectedSeasonId = value);
                    },
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          
          // 集列表
          Expanded(
            child: _buildEpisodesList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEpisodesList() {
    final episodesAsync = ref.watch(episodesProvider((
      seriesId: widget.seriesId,
      seasonId: _selectedSeasonId,
    )));
    
    return episodesAsync.when(
      data: (episodes) {
        return ListView.builder(
          controller: widget.scrollController,
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final episode = episodes[index];
            final isCurrent = episode.id == widget.currentEpisodeId;
            final isWatched = episode.userData?.played ?? false;
            
            return ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isWatched
                      ? const Color(0xFF5B8DEF).withValues(alpha: 0.2)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: isWatched
                      ? const Icon(Icons.check, color: Color(0xFF5B8DEF), size: 20)
                      : Text(
                          'E${episode.indexNumber}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                ),
              ),
              title: Text(
                episode.name,
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                episode.formattedRuntime ?? '',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: isCurrent
                  ? const Icon(Icons.play_circle, color: Color(0xFF5B8DEF))
                  : null,
              selected: isCurrent,
              onTap: () {
                Navigator.pop(context);
                context.push('/player/${episode.id}');
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
    );
  }
}
