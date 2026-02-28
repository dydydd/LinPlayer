import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_server_api/services/ass_api.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'ass_server_access.dart';

class AssPlayPage extends StatefulWidget {
  const AssPlayPage({
    super.key,
    required this.appState,
    required this.ani,
    required this.item,
    this.initialSubtitle,
  });

  final AppState appState;
  final AssAni ani;
  final AssPlayItem item;
  final AssSubtitle? initialSubtitle;

  @override
  State<AssPlayPage> createState() => _AssPlayPageState();
}

class _AssPlayPageState extends State<AssPlayPage> {
  final PlayerService _playerService = getPlayerService();
  StreamSubscription<String>? _errorSub;
  bool _loading = true;
  String? _playError;

  AssSubtitle? _selectedSubtitle;
  final Map<String, String> _tempSubtitlePaths = <String, String>{};

  @override
  void initState() {
    super.initState();
    _selectedSubtitle = widget.initialSubtitle;
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_errorSub?.cancel());
    unawaited(_playerService.dispose());
    super.dispose();
  }

  static String _formatEpisode(double? ep) {
    if (ep == null || ep <= 0) return '';
    final rounded = ep.roundToDouble();
    if ((ep - rounded).abs() < 0.00001) return '第${rounded.toInt()}集';
    return '第$ep集';
  }

  String _title() {
    final base = widget.ani.title.trim().isEmpty ? '播放' : widget.ani.title;
    final ep = _formatEpisode(widget.item.episode);
    return ep.isEmpty ? base : '$base  $ep';
  }

  Future<void> _start() async {
    final access = resolveAssServerAccess(appState: widget.appState);
    if (access == null) {
      setState(() {
        _loading = false;
        _playError = 'ASS server not ready.';
      });
      return;
    }

    final filename = widget.item.filename.trim();
    if (filename.isEmpty) {
      setState(() {
        _loading = false;
        _playError = 'Missing filename';
      });
      return;
    }

    setState(() {
      _loading = true;
      _playError = null;
    });

    try {
      final url = access.api.fileUri(filename).toString();
      final headers = access.api.buildAuthHeaders();

      await _playerService.initialize(
        null,
        networkUrl: url,
        httpHeaders: headers,
        isTv: DeviceType.isTv,
        hardwareDecode: widget.appState.preferHardwareDecode,
        mpvCacheSizeMb: widget.appState.mpvCacheSizeMb,
        bufferBackRatio: widget.appState.playbackBufferBackRatio,
        unlimitedStreamCache: widget.appState.unlimitedStreamCache,
        externalMpvPath: widget.appState.externalMpvPath,
      );

      if (!mounted) return;
      if (_playerService.isExternalPlayback) {
        setState(() {
          _loading = false;
          _playError =
              _playerService.externalPlaybackMessage ?? '已使用外部播放器播放';
        });
        return;
      }

      _errorSub = _playerService.player.stream.error.listen((msg) {
        if (!mounted) return;
        setState(() => _playError = msg);
      });

      if (_selectedSubtitle != null) {
        unawaited(_applySubtitle(_selectedSubtitle!, showToast: false));
      }

      setState(() => _loading = false);
      unawaited(_playerService.play());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _playError = e.toString();
      });
    }
  }

  Future<String?> _subtitleSource(AssSubtitle s) async {
    final access = resolveAssServerAccess(appState: widget.appState);
    if (access == null) return null;

    final url = s.url.trim();
    if (url.isNotEmpty) {
      return access.api.resolveSubtitleUri(url)?.toString();
    }

    final content = s.content;
    if (content.trim().isEmpty) return null;

    final key = '${s.name}|${s.type}|${content.hashCode}';
    final cached = _tempSubtitlePaths[key];
    if (cached != null && cached.trim().isNotEmpty) return cached;

    final ext = s.type.trim().toLowerCase();
    final suffix = switch (ext) {
      'srt' => 'srt',
      'ass' => 'ass',
      'ssa' => 'ssa',
      'vtt' => 'vtt',
      _ => 'ass',
    };

    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'linplayer_ass_${DateTime.now().microsecondsSinceEpoch}.$suffix',
    );
    await file.writeAsString(content);
    _tempSubtitlePaths[key] = file.path;
    return file.path;
  }

  Future<void> _applySubtitle(
    AssSubtitle s, {
    required bool showToast,
  }) async {
    if (!_playerService.isInitialized) return;
    final source = await _subtitleSource(s);
    if (!mounted) return;
    if (source == null || source.trim().isEmpty) {
      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法加载字幕')),
        );
      }
      return;
    }

    try {
      await _playerService.player.setSubtitleTrack(
        SubtitleTrack.uri(
          source,
          title: s.name.trim().isEmpty ? s.type.trim() : s.name.trim(),
        ),
      );
      if (!mounted) return;
      setState(() => _selectedSubtitle = s);
    } catch (e) {
      if (!mounted) return;
      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换字幕失败：$e')),
        );
      }
    }
  }

  Future<void> _pickSubtitle() async {
    final subs = widget.item.subtitles;
    if (subs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无字幕')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            children: [
              ListTile(
                leading: const Icon(Icons.subtitles_off_outlined),
                title: const Text('关闭字幕'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (!_playerService.isInitialized) return;
                  await _playerService.player.setSubtitleTrack(SubtitleTrack.no());
                  if (!mounted) return;
                  setState(() => _selectedSubtitle = null);
                },
              ),
              const Divider(),
              for (final s in subs)
                ListTile(
                  leading: Icon(
                    _selectedSubtitle == s
                        ? Icons.check_circle_outline
                        : Icons.subtitles_outlined,
                  ),
                  title: Text(s.name.trim().isEmpty ? '字幕' : s.name.trim()),
                  subtitle: Text(
                    [
                      if (s.type.trim().isNotEmpty) s.type.trim(),
                      if (s.url.trim().isNotEmpty) 'URL',
                      if (s.content.trim().isNotEmpty) '内容',
                    ].join('  '),
                  ),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _applySubtitle(s, showToast: true);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration d) {
    final total = d.inSeconds.clamp(0, 24 * 3600);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String pad2(int v) => v.toString().padLeft(2, '0');
    if (h > 0) return '${pad2(h)}:${pad2(m)}:${pad2(s)}';
    return '${pad2(m)}:${pad2(s)}';
  }

  Widget _buildControls() {
    if (!_playerService.isInitialized) return const SizedBox.shrink();

    return StreamBuilder<Duration>(
      stream: _playerService.player.stream.position,
      initialData: _playerService.player.state.position,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = _playerService.player.state.duration;

        final maxMs = dur.inMilliseconds;
        final posMs = pos.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : 0);

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          color: Colors.black.withValues(alpha: 0.55),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: maxMs <= 0 ? 0 : posMs.toDouble(),
                min: 0,
                max: maxMs <= 0 ? 1 : maxMs.toDouble(),
                onChanged: maxMs <= 0
                    ? null
                    : (v) => _playerService.seek(
                          Duration(milliseconds: v.round()),
                        ),
              ),
              Row(
                children: [
                  StreamBuilder<bool>(
                    stream: _playerService.player.stream.playing,
                    initialData: _playerService.player.state.playing,
                    builder: (context, ps) {
                      final playing = ps.data ?? false;
                      return IconButton(
                        tooltip: playing ? '暂停' : '播放',
                        onPressed: () {
                          if (playing) {
                            unawaited(_playerService.pause());
                          } else {
                            unawaited(_playerService.play());
                          }
                        },
                        icon: Icon(
                          playing
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_filled_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '字幕',
                    onPressed: _pickSubtitle,
                    icon: Icon(
                      _selectedSubtitle == null
                          ? Icons.subtitles_off_outlined
                          : Icons.subtitles_outlined,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _title();

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_playError != null)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _playError!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: Video(controller: _playerService.controller),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildControls(),
                  ),
                ],
              );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '字幕',
            onPressed: _loading ? null : _pickSubtitle,
            icon: Icon(
              _selectedSubtitle == null
                  ? Icons.subtitles_off_outlined
                  : Icons.subtitles_outlined,
            ),
          ),
        ],
      ),
      body: content,
    );
  }
}
