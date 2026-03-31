import 'package:flutter/material.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

class ShowDetailMobileView extends StatelessWidget {
  const ShowDetailMobileView({
    super.key,
    required this.heroImageUrl,
    required this.onRefresh,
    required this.heroSection,
    required this.sections,
    this.bottomDock,
  });

  final String heroImageUrl;
  final Future<void> Function() onRefresh;
  final Widget heroSection;
  final List<Widget> sections;
  final Widget? bottomDock;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomPadding = bottomDock == null ? 28.0 : 108.0;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _background(context)),
          RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(16, topInset + 16, 16, bottomPadding),
              children: [
                heroSection,
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ..._spacedSections(),
                ],
              ],
            ),
          ),
          if (bottomDock != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: bottomDock!,
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
        yield const SizedBox(height: 14);
      }
    }
  }

  Widget _background(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget backdrop = heroImageUrl.isEmpty
        ? DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primary.withValues(alpha: 0.18),
                  const Color(0xFF171B22),
                  const Color(0xFF090B0E),
                ],
              ),
            ),
          )
        : LinNetworkImage(
            imageUrl: heroImageUrl,
            fit: BoxFit.cover,
            errorWidget: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withValues(alpha: 0.18),
                    const Color(0xFF171B22),
                    const Color(0xFF090B0E),
                  ],
                ),
              ),
            ),
          );

    backdrop = ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.16),
        BlendMode.darken,
      ),
      child: backdrop,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        backdrop,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.30, 0.72, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.22),
                  Colors.black.withValues(alpha: 0.52),
                  const Color(0xFF0D1014).withValues(alpha: 0.96),
                  const Color(0xFF060708),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.92),
                radius: 1.1,
                colors: [
                  scheme.primary.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
