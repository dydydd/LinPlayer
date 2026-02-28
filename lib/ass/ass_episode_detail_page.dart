import 'package:flutter/material.dart';
import 'package:lin_player_server_api/services/ass_api.dart';
import 'package:lin_player_state/lin_player_state.dart';

import 'ass_play_page.dart';

class AssEpisodeDetailPage extends StatefulWidget {
  const AssEpisodeDetailPage({
    super.key,
    required this.appState,
    required this.ani,
    required this.item,
  });

  final AppState appState;
  final AssAni ani;
  final AssPlayItem item;

  @override
  State<AssEpisodeDetailPage> createState() => _AssEpisodeDetailPageState();
}

class _AssEpisodeDetailPageState extends State<AssEpisodeDetailPage> {
  AssSubtitle? _selectedSubtitle;

  @override
  void initState() {
    super.initState();
    final subs = widget.item.subtitles;
    _selectedSubtitle = subs.isEmpty ? null : subs.first;
  }

  static String _formatEpisode(double? ep) {
    if (ep == null || ep <= 0) return '';
    final rounded = ep.roundToDouble();
    if ((ep - rounded).abs() < 0.00001) return '第${rounded.toInt()}集';
    return '第$ep集';
  }

  static DateTime? _parseEpochMs(int? raw) {
    if (raw == null || raw <= 0) return null;
    final ms = raw < 2000000000 ? raw * 1000 : raw;
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final title = item.title.trim().isEmpty ? item.name : item.title;

    final ep = _formatEpisode(item.episode);
    final dt = _parseEpochMs(item.lastModify);
    final time = dt == null
        ? ''
        : '${dt.year.toString().padLeft(4, '0')}-'
            '${dt.month.toString().padLeft(2, '0')}-'
            '${dt.day.toString().padLeft(2, '0')}';

    final metaParts = <String>[];
    if (ep.isNotEmpty) metaParts.add(ep);
    final size = item.size.trim();
    if (size.isNotEmpty) metaParts.add('${size}MB');
    final ext = item.extName.trim();
    if (ext.isNotEmpty) metaParts.add(ext.toUpperCase());
    if (time.isNotEmpty) metaParts.add(time);

    final subs = item.subtitles;
    final hasSubs = subs.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          if (metaParts.isNotEmpty)
            Text(
              metaParts.join('  '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: item.filename.trim().isEmpty
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AssPlayPage(
                          appState: widget.appState,
                          ani: widget.ani,
                          item: item,
                          initialSubtitle: _selectedSubtitle,
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放'),
          ),
          const SizedBox(height: 18),
          Text(
            '字幕',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (!hasSubs)
            Text(
              '暂无字幕',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else
            Card(
              child: RadioGroup<AssSubtitle>(
                groupValue: _selectedSubtitle,
                onChanged: (v) => setState(() => _selectedSubtitle = v),
                child: Column(
                children: [
                  for (final s in subs)
                    RadioListTile<AssSubtitle>(
                      value: s,
                      title: Text(s.name.trim().isEmpty ? '字幕' : s.name),
                      subtitle: (() {
                        final parts = <String>[];
                        final type = s.type.trim();
                        if (type.isNotEmpty) parts.add(type);
                        if (s.url.trim().isNotEmpty) parts.add('URL');
                        if (s.content.trim().isNotEmpty) parts.add('内容');
                        return parts.isEmpty ? null : Text(parts.join('  '));
                      })(),
                      dense: true,
                    ),
                ],
              ),
              ),
            ),
        ],
      ),
    );
  }
}
