import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VideoDisplayMode {
  fill(
    storageKey: 'fill',
    label: '填充',
    description: '保持比例完整显示，可能会留黑边',
    boxFit: BoxFit.contain,
  ),
  original(
    storageKey: 'original',
    label: '原始',
    description: '按原始大小显示，超出时自动缩小',
    boxFit: BoxFit.scaleDown,
  ),
  stretch(
    storageKey: 'stretch',
    label: '拉伸',
    description: '拉伸到整个画面区域，可能会变形',
    boxFit: BoxFit.fill,
  ),
  cover(
    storageKey: 'cover',
    label: '铺满',
    description: '保持比例铺满画面，可能会裁切边缘',
    boxFit: BoxFit.cover,
  );

  const VideoDisplayMode({
    required this.storageKey,
    required this.label,
    required this.description,
    required this.boxFit,
  });

  final String storageKey;
  final String label;
  final String description;
  final BoxFit boxFit;

  static VideoDisplayMode fromStorageKey(String? value) {
    final key = (value ?? '').trim().toLowerCase();
    for (final mode in values) {
      if (mode.storageKey == key) return mode;
    }
    return VideoDisplayMode.fill;
  }
}

class VideoDisplayModePreferences {
  static const String _prefsKey = 'mobileVideoDisplayMode_v1';

  static Future<VideoDisplayMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    return VideoDisplayMode.fromStorageKey(prefs.getString(_prefsKey));
  }

  static Future<void> save(VideoDisplayMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.storageKey);
  }
}
