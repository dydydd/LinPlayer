import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_toast.dart';
import '../../widgets/tv_control_overlay.dart';
import '../../widgets/tv_panel.dart';

/// TV 播放页
/// 全屏沉浸 + 按键呼出控制层
class TvPlayerScreen extends StatefulWidget {
  final String? mediaId;
  final String? episodeId;

  const TvPlayerScreen({super.key, this.mediaId, this.episodeId});

  @override
  State<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends State<TvPlayerScreen> {
  bool _showControls = true;
  bool _isPlaying = true;
  bool _isPaused = false;
  Duration _currentTime = const Duration(minutes: 15, seconds: 30);
  final Duration _totalTime = const Duration(minutes: 45, seconds: 0);
  double _progress = 0.34;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 视频播放器（占位）
          Container(
            color: Colors.black,
            child: const Center(
              child: Icon(
                Icons.play_circle_outline,
                color: Colors.white24,
                size: 128,
              ),
            ),
          ),
          // 控制层
          Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                _handleKeyEvent(event);
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: AnimatedOpacity(
                duration: TvDesignTokens.playerControlFadeDuration,
                opacity: _showControls ? 1.0 : 0.0,
                child: TvControlOverlay(
                  isPlaying: _isPlaying,
                  isPaused: _isPaused,
                  currentTime: _currentTime,
                  totalTime: _totalTime,
                  progress: _progress,
                  title: '剧集标题 - 第 1 集',
                  hasNextEpisode: true,
                  hasPreviousEpisode: true,
                  showSkipButton: true,
                  onPlayPause: _togglePlayPause,
                  onSeekBackward: () => _seekRelative(-10),
                  onSeekForward: () => _seekRelative(10),
                  onNextEpisode: () => TvToast.show(context, '下一集'),
                  onPreviousEpisode: () => TvToast.show(context, '上一集'),
                  onSkip: () => TvToast.show(context, '跳过片头'),
                  onMore: _showMorePanel,
                  onSubtitle: _showSubtitlePanel,
                  onAudioTrack: _showAudioTrackPanel,
                  onSeek: (value) => _seekTo(value),
                  onClose: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          // 暂停图标（暂停时显示）
          if (_isPaused)
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: 1.0,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: TvDesignTokens.brand.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.pause,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _togglePlayPause();
    } else if (event.logicalKey == LogicalKeyboardKey.mediaPlay) {
      _play();
    } else if (event.logicalKey == LogicalKeyboardKey.mediaPause) {
      _pause();
    } else if (event.logicalKey == LogicalKeyboardKey.mediaStop) {
      _stop();
    } else if (event.logicalKey == LogicalKeyboardKey.mediaFastForward ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_showControls) {
        _seekRelative(10);
      } else {
        setState(() => _showControls = true);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.mediaRewind ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_showControls) {
        _seekRelative(-10);
      } else {
        setState(() => _showControls = true);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _showControls = !_showControls);
    } else if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (_showControls) {
        setState(() => _showControls = false);
      } else {
        Navigator.pop(context);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (!_showControls) {
        setState(() => _showControls = true);
      }
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_isPlaying) {
        _isPlaying = false;
        _isPaused = true;
      } else {
        _isPlaying = true;
        _isPaused = false;
      }
    });
  }

  void _play() {
    setState(() {
      _isPlaying = true;
      _isPaused = false;
    });
  }

  void _pause() {
    setState(() {
      _isPlaying = false;
      _isPaused = true;
    });
  }

  void _stop() {
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _progress = 0.0;
      _currentTime = Duration.zero;
    });
  }

  void _seekRelative(int seconds) {
    final newTime = _currentTime + Duration(seconds: seconds);
    setState(() {
      _currentTime = Duration(
        milliseconds: newTime.inMilliseconds.clamp(0, _totalTime.inMilliseconds),
      );
      _progress = _currentTime.inMilliseconds / _totalTime.inMilliseconds;
    });
  }

  void _seekTo(double progress) {
    setState(() {
      _progress = progress;
      _currentTime = Duration(
        milliseconds: (progress * _totalTime.inMilliseconds).toInt(),
      );
    });
  }

  void _showMorePanel() {
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '更多',
        onClose: () => Navigator.pop(context),
        children: [
          const TvPanelSection(title: '播放设置'),
          TvPanelOption(
            title: '倍速',
            subtitle: '1.0x',
            onTap: () {},
          ),
          TvPanelOption(
            title: '画面比例',
            subtitle: '默认',
            onTap: () {},
          ),
          TvPanelOption(
            title: '播放器内核',
            subtitle: 'MPV',
            onTap: () {},
          ),
          const TvPanelSection(title: '其他'),
          TvPanelOption(
            title: '投屏',
            onTap: () {},
          ),
          TvPanelOption(
            title: '统计信息',
            onTap: () {},
          ),
          TvPanelOption(
            title: '定时关闭',
            onTap: () {},
          ),
          TvPanelOption(
            title: '锁定',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  void _showSubtitlePanel() {
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '字幕',
        onClose: () => Navigator.pop(context),
        children: [
          TvPanelOption(
            title: '关闭',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '中文',
            isSelected: true,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: 'English',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showAudioTrackPanel() {
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '音轨',
        onClose: () => Navigator.pop(context),
        children: [
          TvPanelOption(
            title: '原声',
            isSelected: true,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '中文配音',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
