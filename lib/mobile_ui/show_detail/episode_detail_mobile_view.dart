import 'package:flutter/material.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'mobile_text_widgets.dart';

class EpisodeDetailMobileView extends StatelessWidget {
  const EpisodeDetailMobileView({
    super.key,
    required this.title,
    required this.overview,
    required this.runtimeText,
    this.mediaBadges = const <String>[],
    required this.coverUrl,
    required this.backdropUrl,
    required this.versionValue,
    required this.audioValue,
    required this.subtitleValue,
    required this.playLabel,
    required this.onRefresh,
    required this.onPlay,
    required this.onMore,
    required this.sections,
    this.onPickVersion,
    this.onPickAudio,
    this.onPickSubtitle,
  });

  final String title;
  final String overview;
  final String runtimeText;
  final List<String> mediaBadges;
  final String coverUrl;
  final String backdropUrl;
  final String versionValue;
  final String audioValue;
  final String subtitleValue;
  final String playLabel;
  final Future<void> Function() onRefresh;
  final VoidCallback onPlay;
  final VoidCallback onMore;
  final VoidCallback? onPickVersion;
  final VoidCallback? onPickAudio;
  final VoidCallback? onPickSubtitle;
  final List<Widget> sections;

  static const _surfaceTop = Color(0xEE151D27);
  static const _surfaceBottom = Color(0xEE0B1016);
  static const _accentA = Color(0xFF8CC6FF);
  static const _accentB = Color(0xFF7BE0C3);

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(child: _background(context)),
          RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, topInset + 16, 16, 28),
              children: [
                _heroCard(context),
                const SizedBox(height: 14),
                _selectorCard(context),
                const SizedBox(height: 14),
                _actionRow(context),
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  ..._spacedSections(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Iterable<Widget> _spacedSections() sync* {
    for (var i = 0; i < sections.length; i++) {
      yield sections[i];
      if (i != sections.length - 1) {
        yield const SizedBox(height: 18);
      }
    }
  }

  Widget _background(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = backdropUrl.isNotEmpty ? backdropUrl : coverUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl.isNotEmpty)
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.28),
              BlendMode.darken,
            ),
            child: LinNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              errorWidget: const ColoredBox(
                color: Color(0xFF0C1015),
              ),
            ),
          )
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1C2632),
                  Color(0xFF0F141B),
                  Color(0xFF070A0E),
                ],
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.28, 0.7, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.38),
                const Color(0xFF10161D).withValues(alpha: 0.95),
                const Color(0xFF080B0F),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: const Offset(0, -80),
            child: FractionallySizedBox(
              widthFactor: 1.15,
              child: SizedBox(
                height: 240,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.9),
                      radius: 1.0,
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: 0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroCard(BuildContext context) {
    final theme = Theme.of(context);
    final badges = mediaBadges
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (badges.isEmpty && runtimeText.trim().isNotEmpty) {
      badges.add(runtimeText.trim());
    }
    final description = overview.trim().isEmpty ? '暂无简介' : overview.trim();

    return _panel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _coverImage(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.12,
            ),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: badges.map(_metaChip).toList(growable: false),
            ),
          ],
          const SizedBox(height: 14),
          ExpandableText(
            description,
            collapsedLines: 4,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              height: 1.5,
            ),
            actionColor: Colors.white.withValues(alpha: 0.86),
          ),
        ],
      ),
    );
  }

  Widget _coverImage(BuildContext context) {
    if (coverUrl.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accentA.withValues(alpha: 0.24),
              _accentB.withValues(alpha: 0.20),
              Colors.black.withValues(alpha: 0.50),
            ],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.movie_outlined,
            color: Colors.white70,
            size: 40,
          ),
        ),
      );
    }

    return LinNetworkImage(
      imageUrl: coverUrl,
      fit: BoxFit.cover,
      errorWidget: const ColoredBox(color: Color(0x33000000)),
    );
  }

  Widget _selectorCard(BuildContext context) {
    return _panel(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          _selectorRow(
            context,
            icon: Icons.movie_filter_rounded,
            label: '版本选择',
            value: versionValue,
            onTap: onPickVersion,
          ),
          const SizedBox(height: 4),
          _selectorRow(
            context,
            icon: Icons.audiotrack_rounded,
            label: '音频选择',
            value: audioValue,
            onTap: onPickAudio,
          ),
          const SizedBox(height: 4),
          _selectorRow(
            context,
            icon: Icons.closed_caption_rounded,
            label: '字幕选择',
            value: subtitleValue,
            onTap: onPickSubtitle,
          ),
        ],
      ),
    );
  }

  Widget _selectorRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final theme = Theme.of(context);
    final textColor =
        enabled ? Colors.white : Colors.white.withValues(alpha: 0.42);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: enabled ? 0.10 : 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: textColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  value.trim().isEmpty ? '默认' : value.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor.withValues(alpha: enabled ? 0.86 : 0.42),
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: textColor.withValues(alpha: enabled ? 0.82 : 0.38),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionRow(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _accentA.withValues(alpha: 0.92),
                    _accentB.withValues(alpha: 0.88),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accentB.withValues(alpha: 0.22),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onPlay,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        color: Color(0xFF0A1218),
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          playLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: const Color(0xFF0A1218),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: SizedBox(
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withValues(alpha: 0.08),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: onMore,
                  child: const Center(
                    child: Icon(
                      Icons.more_horiz_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _surfaceTop.withValues(alpha: 0.90),
            _surfaceBottom.withValues(alpha: 0.94),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _metaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
