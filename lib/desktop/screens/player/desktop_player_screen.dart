import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/media_providers.dart';
import '../../../ui/screens/player/player_screen.dart';

/// 桌面端播放器包装器 - 添加键盘快捷键支持
/// 
/// 包装现有的 PlayerScreen，添加桌面端特定的键盘控制：
/// - Space: 播放/暂停
/// - ←/→: 快退/快进
/// - ↑/↓: 音量增减
/// - F: 全屏切换
/// - Esc: 退出全屏/返回
/// - M: 静音切换
class DesktopPlayerScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String? mediaSourceId;

  const DesktopPlayerScreen({
    super.key,
    required this.itemId,
    this.mediaSourceId,
  });

  @override
  ConsumerState<DesktopPlayerScreen> createState() => _DesktopPlayerScreenState();
}

class _DesktopPlayerScreenState extends ConsumerState<DesktopPlayerScreen> {
  bool _isFullscreen = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
          _togglePlayPause();
          break;
        case LogicalKeyboardKey.arrowLeft:
          _seekBackward();
          break;
        case LogicalKeyboardKey.arrowRight:
          _seekForward();
          break;
        case LogicalKeyboardKey.arrowUp:
          _increaseVolume();
          break;
        case LogicalKeyboardKey.arrowDown:
          _decreaseVolume();
          break;
        case LogicalKeyboardKey.keyF:
          _toggleFullscreen();
          break;
        case LogicalKeyboardKey.escape:
          if (_isFullscreen) {
            _toggleFullscreen();
          } else {
            context.pop();
          }
          break;
        case LogicalKeyboardKey.keyM:
          _toggleMute();
          break;
      }
    }
  }

  void _togglePlayPause() {
    final isPlaying = ref.read(isPlayingProvider);
    ref.read(isPlayingProvider.notifier).state = !isPlaying;
  }

  void _seekBackward() {
    final progress = ref.read(playbackProgressProvider);
    ref.read(playbackProgressProvider.notifier).state = 
        (progress - 0.05).clamp(0.0, 1.0);
  }

  void _seekForward() {
    final progress = ref.read(playbackProgressProvider);
    ref.read(playbackProgressProvider.notifier).state = 
        (progress + 0.05).clamp(0.0, 1.0);
  }

  void _increaseVolume() {
    final volume = ref.read(volumeProvider);
    ref.read(volumeProvider.notifier).state = 
        (volume + 0.1).clamp(0.0, 1.0);
  }

  void _decreaseVolume() {
    final volume = ref.read(volumeProvider);
    ref.read(volumeProvider.notifier).state = 
        (volume - 0.1).clamp(0.0, 1.0);
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      // 进入全屏
    } else {
      // 退出全屏
    }
  }

  void _toggleMute() {
    final volume = ref.read(volumeProvider);
    if (volume > 0) {
      ref.read(volumeProvider.notifier).state = 0.0;
    } else {
      ref.read(volumeProvider.notifier).state = 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: PlayerScreen(
        itemId: widget.itemId,
        mediaSourceId: widget.mediaSourceId,
      ),
    );
  }
}
