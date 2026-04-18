int normalizePlaybackThresholdPercent(int thresholdPercent) =>
    thresholdPercent.clamp(75, 100);

bool isPlaybackThresholdReached({
  required Duration position,
  required Duration duration,
  required int thresholdPercent,
}) {
  if (duration <= Duration.zero) return false;
  final durationUs = duration.inMicroseconds;
  if (durationUs <= 0) return false;
  final positionUs = position.inMicroseconds;
  return positionUs * 100 >=
      durationUs * normalizePlaybackThresholdPercent(thresholdPercent);
}
