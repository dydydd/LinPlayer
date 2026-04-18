import 'package:flutter/material.dart';

import '../services/series_skip_preferences.dart';

Future<SeriesSkipProfile?> showSeriesSkipConfigDialog(
  BuildContext context, {
  required String seriesTitle,
  required SeriesSkipProfile initialProfile,
}) async {
  final openingController = TextEditingController(
    text: formatSeriesSkipDuration(initialProfile.openingSeconds),
  );
  final endingController = TextEditingController(
    text: formatSeriesSkipDuration(initialProfile.endingSeconds),
  );

  try {
    return await showDialog<SeriesSkipProfile>(
      context: context,
      builder: (dialogContext) {
        String? openingError;
        String? endingError;

        SeriesSkipProfile? validate() {
          final openingSeconds = parseSeriesSkipDurationInput(
            openingController.text,
          );
          final endingSeconds = parseSeriesSkipDurationInput(
            endingController.text,
          );
          openingError = null;
          endingError = null;

          if (openingController.text.trim().isNotEmpty && openingSeconds == null) {
            openingError = '支持 90 或 1:30';
          }
          if (endingController.text.trim().isNotEmpty && endingSeconds == null) {
            endingError = '支持 90 或 1:30';
          }
          if (openingSeconds != null && openingSeconds > 7200) {
            openingError = '请控制在 2 小时内';
          }
          if (endingSeconds != null && endingSeconds > 7200) {
            endingError = '请控制在 2 小时内';
          }

          if (openingError != null || endingError != null) {
            return null;
          }

          return SeriesSkipProfile(
            openingSeconds: openingSeconds,
            endingSeconds: endingSeconds,
          );
        }

        return StatefulBuilder(
          builder: (context, setState) {
            void submit() {
              final next = validate();
              if (next == null) {
                setState(() {});
                return;
              }
              Navigator.of(dialogContext).pop(next);
            }

            return AlertDialog(
              title: Text('设置 $seriesTitle 的 OP / ED'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: openingController,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'OP 时长',
                      hintText: '如 90 或 1:30',
                      helperText: '留空表示不设置',
                      errorText: openingError,
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endingController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'ED 时长',
                      hintText: '如 90 或 1:30',
                      helperText: '留空表示不设置',
                      errorText: endingError,
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '点击 OP/ED 按钮会按当前时刻向前跳过对应时长，长按按钮可重新修改。',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    const SeriesSkipProfile(),
                  ),
                  child: const Text('清空'),
                ),
                FilledButton(
                  onPressed: submit,
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    openingController.dispose();
    endingController.dispose();
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
