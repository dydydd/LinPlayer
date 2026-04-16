import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> showThemeSheet(
  BuildContext context, {
  required Listenable listenable,
  required ThemeMode Function() themeMode,
  required FutureOr<void> Function(ThemeMode mode) setThemeMode,
  required bool Function() useDynamicColor,
  required FutureOr<void> Function(bool value) setUseDynamicColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return AnimatedBuilder(
        animation: listenable,
        builder: (context, _) {
          final mode = themeMode();
          final dynamicColor = useDynamicColor();
          final isDesktopBinaryTheme = !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.macOS);
          final modeSegments = isDesktopBinaryTheme
              ? const <ButtonSegment<ThemeMode>>[
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ]
              : const <ButtonSegment<ThemeMode>>[
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
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
                Text('Theme', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: modeSegments,
                  selected: {selectedMode},
                  onSelectionChanged: (s) => setThemeMode(s.first),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: dynamicColor,
                  onChanged: (v) => setUseDynamicColor(v),
                  title: const Text('Material You colors'),
                  subtitle: const Text(
                    'Available on Android 12+ when the device supports it.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
