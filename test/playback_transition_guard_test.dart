import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/playback/playback_transition_guard.dart';

void main() {
  test('buildPlayerReplacementRoute uses zero-duration transitions', () {
    final route = PlaybackTransitionGuard.buildPlayerReplacementRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );

    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });
}
