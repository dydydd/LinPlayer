import 'package:flutter/material.dart';

double? computeTrafficRateBytesPerSecond({
  required int totalBytes,
  required int? previousBytes,
  required DateTime sampleAt,
  required DateTime? previousAt,
}) {
  if (previousBytes == null || previousAt == null) return null;

  final dtMs = sampleAt.difference(previousAt).inMilliseconds;
  final delta = totalBytes - previousBytes;
  if (dtMs <= 0 || delta < 0) return null;

  return delta * 1000.0 / dtMs;
}

double smoothNetworkSpeedBytesPerSecond(
  double next, {
  double? previous,
  double previousWeight = 0.7,
}) {
  if (previous == null || !previous.isFinite || previous < 0) return next;
  if (!next.isFinite || next < 0) return previous;

  final keep = previousWeight.clamp(0.0, 1.0);
  return previous * keep + next * (1.0 - keep);
}

String formatBytesPerSecond(double bytesPerSecond) {
  if (!bytesPerSecond.isFinite || bytesPerSecond < 0) return '—';
  final v = bytesPerSecond;
  if (v == 0) return '0 B/s';

  const k = 1024.0;
  if (v < k) return '${v.toStringAsFixed(0)} B/s';
  if (v < k * k) return '${(v / k).toStringAsFixed(1)} KB/s';
  if (v < k * k * k) return '${(v / (k * k)).toStringAsFixed(1)} MB/s';
  return '${(v / (k * k * k)).toStringAsFixed(1)} GB/s';
}

class NetSpeedBadge extends StatelessWidget {
  const NetSpeedBadge({
    super.key,
    required this.text,
    this.icon = Icons.download_outlined,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.85)),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
