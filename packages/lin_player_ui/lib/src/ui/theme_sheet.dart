import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

Future<void> showThemeSheet(
  BuildContext context, {
  required Listenable listenable,
  required ThemeMode Function() themeMode,
  required FutureOr<void> Function(ThemeMode mode) setThemeMode,
  required String Function() themeTemplate,
  required FutureOr<void> Function(String id) setThemeTemplate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return AnimatedBuilder(
        animation: listenable,
        builder: (context, _) {
          final mode = themeMode();
          final selectedTemplate = themeTemplate();
          final isDesktopBinaryTheme = !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.macOS);
          final modeSegments = isDesktopBinaryTheme
              ? const <ButtonSegment<ThemeMode>>[
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ]
              : const <ButtonSegment<ThemeMode>>[
                  ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ];
          final selectedMode = isDesktopBinaryTheme && mode == ThemeMode.system
              ? (Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light)
              : mode;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: modeSegments,
                  selected: {selectedMode},
                  onSelectionChanged: (s) => setThemeMode(s.first),
                ),
                const SizedBox(height: 16),
                Text(
                  '配色方案',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '固定配色会直接应用到软件，iOS 和 Android 保持一致。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AppTheme.palettes
                      .map(
                        (palette) => ChoiceChip(
                          avatar: _ThemePaletteAvatar(
                            paletteId: palette.id,
                            brightness: Theme.of(context).brightness,
                          ),
                          label: Text(palette.label),
                          selected: palette.id == selectedTemplate,
                          onSelected: (_) => setThemeTemplate(palette.id),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _ThemePaletteAvatar extends StatelessWidget {
  const _ThemePaletteAvatar({
    required this.paletteId,
    required this.brightness,
  });

  final String paletteId;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final preview = AppTheme.previewScheme(
      paletteId: paletteId,
      brightness: brightness,
    );
    final colors = <Color>[
      preview.primary,
      preview.secondary,
      preview.tertiary,
    ];
    return SizedBox(
      width: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: colors
            .map(
              (color) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}
