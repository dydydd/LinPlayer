import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player_player/lin_player_player.dart';

void main() {
  group('computeTrafficRateBytesPerSecond', () {
    test('returns bytes per second from cumulative traffic samples', () {
      final start = DateTime(2026, 1, 1, 12);
      final end = start.add(const Duration(milliseconds: 500));

      final rate = computeTrafficRateBytesPerSecond(
        totalBytes: 4096,
        previousBytes: 1024,
        sampleAt: end,
        previousAt: start,
      );

      expect(rate, 6144);
    });

    test('returns null for missing or invalid samples', () {
      final now = DateTime(2026, 1, 1, 12);

      expect(
        computeTrafficRateBytesPerSecond(
          totalBytes: 1024,
          previousBytes: null,
          sampleAt: now,
          previousAt: now.subtract(const Duration(seconds: 1)),
        ),
        isNull,
      );
      expect(
        computeTrafficRateBytesPerSecond(
          totalBytes: 1024,
          previousBytes: 2048,
          sampleAt: now,
          previousAt: now.subtract(const Duration(seconds: 1)),
        ),
        isNull,
      );
    });
  });

  group('smoothNetworkSpeedBytesPerSecond', () {
    test('returns next value when there is no usable previous sample', () {
      expect(smoothNetworkSpeedBytesPerSecond(2048), 2048);
      expect(
        smoothNetworkSpeedBytesPerSecond(2048, previous: double.nan),
        2048,
      );
    });

    test('blends previous and next values', () {
      final smoothed = smoothNetworkSpeedBytesPerSecond(
        1000,
        previous: 4000,
        previousWeight: 0.75,
      );

      expect(smoothed, 3250);
    });
  });
}
