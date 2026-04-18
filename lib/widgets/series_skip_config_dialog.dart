import 'package:flutter/material.dart';

enum SeriesSkipSegment { opening, ending }

@immutable
class SeriesSkipConfigResult {
  final int? seconds;

  const SeriesSkipConfigResult({required this.seconds});
}

Future<SeriesSkipConfigResult?> showSeriesSkipConfigDialog(
  BuildContext context, {
  required String seriesTitle,
  required SeriesSkipSegment segment,
  int? initialSeconds,
}) async {
  final controller = TextEditingController(
    text: formatSeriesSkipDuration(initialSeconds),
  );
  final segmentLabel = segment == SeriesSkipSegment.opening ? 'OP' : 'ED';
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  try {
    return await showGeneralDialog<SeriesSkipConfigResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.26),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return StatefulBuilder(
          builder: (context, setState) {
            String? errorText;

            void submit() {
              final seconds = parseSeriesSkipDurationInput(controller.text);
              errorText = null;

              if (controller.text.trim().isNotEmpty && seconds == null) {
                errorText = '支持 90 或 1:30';
              } else if (seconds != null && seconds > 7200) {
                errorText = '请控制在 2 小时内';
              }

              if (errorText != null) {
                setState(() {});
                return;
              }

              Navigator.of(dialogContext).pop(
                SeriesSkipConfigResult(seconds: seconds),
              );
            }

            return SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(dialogContext).viewInsets.bottom + 92,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Material(
                    color: scheme.surface,
                    elevation: 18,
                    shadowColor: Colors.black.withValues(alpha: 0.22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    segmentLabel,
                                    style:
                                        theme.textTheme.labelLarge?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '设置 $segmentLabel 跳过时长',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                  splashRadius: 18,
                                  tooltip: '关闭',
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              seriesTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: controller,
                              autofocus: true,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => submit(),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.68),
                                labelText: '$segmentLabel 时长',
                                hintText: '90 或 1:30',
                                errorText: errorText,
                                prefixIcon: const Icon(
                                  Icons.timer_outlined,
                                  size: 18,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '留空表示不设置，支持 90、1:30、1:02:03',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.of(
                                    dialogContext,
                                  ).pop(
                                    const SeriesSkipConfigResult(seconds: null),
                                  ),
                                  child: const Text('清空'),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: const Text('取消'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: submit,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 10,
                                    ),
                                  ),
                                  child: const Text('保存'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

String formatSeriesSkipDuration(int? totalSeconds) {
  if (totalSeconds == null || totalSeconds <= 0) return '';
  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '${duration.inMinutes}:${twoDigits(seconds)}';
}

int? parseSeriesSkipDurationInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final directSeconds = int.tryParse(text);
  if (directSeconds != null) {
    return directSeconds > 0 ? directSeconds : null;
  }

  final parts = text.split(':').map((part) => part.trim()).toList();
  if (parts.length < 2 || parts.length > 3) return null;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((value) => value == null || value < 0)) return null;

  if (numbers.length == 2) {
    return numbers[0]! * 60 + numbers[1]!;
  }
  return numbers[0]! * 3600 + numbers[1]! * 60 + numbers[2]!;
}
