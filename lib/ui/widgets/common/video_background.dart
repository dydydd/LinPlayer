import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 视频背景组件 - 用于详情页 Hero 区域
/// 自动播放、静音、循环播放视频
class VideoBackground extends StatefulWidget {
  final String videoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;

  const VideoBackground({
    super.key,
    required this.videoUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  Player? _player;
  VideoController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant VideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposePlayer();
      _initializePlayer();
    }
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      final player = Player();
      final controller = VideoController(player);

      await player.setVolume(0);
      await player.setPlaylistMode(PlaylistMode.loop);

      await player.open(Media(widget.videoUrl));

      if (mounted) {
        setState(() {
          _player = player;
          _controller = controller;
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _disposePlayer() {
    _player?.dispose();
    _player = null;
    _controller = null;
    _isInitialized = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || !_isInitialized || _controller == null) {
      return widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Colors.black,
          );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Video(
        controller: _controller!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        controls: NoVideoControls,
      ),
    );
  }
}
