import 'package:flutter/services.dart';

double? playbackDisplayAspectForMediaSource(Map<String, dynamic>? mediaSource) {
  if (mediaSource == null) return null;

  final videoStream = _firstVideoStream(mediaSource);
  var aspect =
      _parseAspectRatio(
        videoStream?['AspectRatio'] ?? mediaSource['AspectRatio'],
      ) ??
      _parseAspectRatio(
        videoStream?['DisplayAspectRatio'] ?? mediaSource['DisplayAspectRatio'],
      ) ??
      _aspectFromDimensions(
        width: _asInt(videoStream?['Width']) ?? _asInt(mediaSource['Width']),
        height:
            _asInt(videoStream?['Height']) ?? _asInt(mediaSource['Height']),
      );

  if (aspect == null) return null;

  final rotation =
      _asInt(videoStream?['Rotation']) ??
      _asInt(videoStream?['RotationDegrees']) ??
      _asInt(videoStream?['VideoRotation']) ??
      _asInt(mediaSource['Rotation']) ??
      _asInt(mediaSource['RotationDegrees']);
  if (rotation != null && rotation.abs() % 180 != 0) {
    aspect = 1.0 / aspect;
  }

  return _normalizeAspect(aspect);
}

List<DeviceOrientation>? playbackOrientationsForMediaSource(
  Map<String, dynamic>? mediaSource,
) {
  final aspect = playbackDisplayAspectForMediaSource(mediaSource);
  if (aspect == null) return null;
  return preferredOrientationsForDisplayAspect(aspect);
}

List<DeviceOrientation> preferredOrientationsForDisplayAspect(double aspect) {
  return aspect < 1.0
      ? const [DeviceOrientation.portraitUp]
      : const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
}

Map<String, dynamic>? _firstVideoStream(Map<String, dynamic> mediaSource) {
  final streams = mediaSource['MediaStreams'];
  if (streams is! List) return null;
  for (final entry in streams) {
    if (entry is! Map) continue;
    if ((entry['Type']?.toString() ?? '').trim().toLowerCase() != 'video') {
      continue;
    }
    return Map<String, dynamic>.from(entry);
  }
  return null;
}

double? _parseAspectRatio(dynamic raw) {
  if (raw is num) {
    return _normalizeAspect(raw.toDouble());
  }

  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  if (text.contains(':')) {
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final left = double.tryParse(parts[0].trim());
    final right = double.tryParse(parts[1].trim());
    if (left == null || right == null || left <= 0 || right <= 0) {
      return null;
    }
    return _normalizeAspect(left / right);
  }

  return _normalizeAspect(double.tryParse(text));
}

double? _aspectFromDimensions({
  required int? width,
  required int? height,
}) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return _normalizeAspect(width / height);
}

double? _normalizeAspect(double? aspect) {
  if (aspect == null || !aspect.isFinite || aspect <= 0) return null;
  return aspect;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
