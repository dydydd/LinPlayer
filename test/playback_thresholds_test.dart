import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/playback/playback_thresholds.dart';

void main() {
  test('normalizePlaybackThresholdPercent clamps to supported range', () {
    expect(normalizePlaybackThresholdPercent(10), 75);
    expect(normalizePlaybackThresholdPercent(90), 90);
    expect(normalizePlaybackThresholdPercent(120), 100);
  });

  test('isPlaybackThresholdReached returns false for invalid duration', () {
    expect(
      isPlaybackThresholdReached(
        position: const Duration(seconds: 30),
        duration: Duration.zero,
        thresholdPercent: 90,
      ),
      isFalse,
    );
  });

  test('isPlaybackThresholdReached respects the configured threshold', () {
    expect(
      isPlaybackThresholdReached(
        position: const Duration(seconds: 89),
        duration: const Duration(seconds: 100),
        thresholdPercent: 90,
      ),
      isFalse,
    );
    expect(
      isPlaybackThresholdReached(
        position: const Duration(seconds: 90),
        duration: const Duration(seconds: 100),
        thresholdPercent: 90,
      ),
      isTrue,
    );
  });

  test('isPlaybackThresholdReached supports exact-end thresholds', () {
    expect(
      isPlaybackThresholdReached(
        position: const Duration(seconds: 99),
        duration: const Duration(seconds: 100),
        thresholdPercent: 100,
      ),
      isFalse,
    );
    expect(
      isPlaybackThresholdReached(
        position: const Duration(seconds: 100),
        duration: const Duration(seconds: 100),
        thresholdPercent: 100,
      ),
      isTrue,
    );
  });
}
