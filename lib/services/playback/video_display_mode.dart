import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 移动端画面比例 / 缩放模式（持久化，全局生效）。
enum VideoDisplayMode {
  adapt(
    storageKey: 'adapt',
    label: '适应',
    description: '完整显示画面，保持比例，可能有黑边',
    boxFit: BoxFit.contain,
    fixedAspectRatio: null,
  ),
  stretch(
    storageKey: 'stretch',
    label: '拉伸',
    description: '拉伸填满区域，可能变形',
    boxFit: BoxFit.fill,
    fixedAspectRatio: null,
  ),
  cover(
    storageKey: 'cover',
    label: '填充',
    description: '保持比例铺满，可能裁切边缘',
    boxFit: BoxFit.cover,
    fixedAspectRatio: null,
  ),
  ratio16_9(
    storageKey: 'ar16_9',
    label: '16:9',
    description: '在 16:9 区域内适应显示',
    boxFit: BoxFit.contain,
    fixedAspectRatio: 16 / 9,
  ),
  ratio4_3(
    storageKey: 'ar4_3',
    label: '4:3',
    description: '在 4:3 区域内适应显示',
    boxFit: BoxFit.contain,
    fixedAspectRatio: 4 / 3,
  );

  const VideoDisplayMode({
    required this.storageKey,
    required this.label,
    required this.description,
    required this.boxFit,
    required this.fixedAspectRatio,
  });

  final String storageKey;
  final String label;
  final String description;
  final BoxFit boxFit;

  /// 当非空时，在固定比例容器内使用 [boxFit] 显示视频。
  final double? fixedAspectRatio;

  bool get usesFixedAspectRatio => fixedAspectRatio != null;

  /// 将视频组件置于合适容器中（含固定比例时的 [AspectRatio] 包裹）。
  Widget wrapVideo(Widget video) {
    if (!usesFixedAspectRatio) return video;
    final ar = fixedAspectRatio!;
    return Center(
      child: AspectRatio(
        aspectRatio: ar,
        child: video,
      ),
    );
  }

  static VideoDisplayMode fromStorageKey(String? value) {
    final key = (value ?? '').trim().toLowerCase();
    for (final mode in values) {
      if (mode.storageKey == key) return mode;
    }
    return _migrateLegacyStorageKey(key);
  }

  static VideoDisplayMode _migrateLegacyStorageKey(String key) {
    return switch (key) {
      'fill' => VideoDisplayMode.adapt,
      'original' => VideoDisplayMode.adapt,
      'pad' => VideoDisplayMode.cover,
      _ => VideoDisplayMode.adapt,
    };
  }
}

class VideoDisplayModePreferences {
  static const String _prefsKey = 'mobileVideoDisplayMode_v2';

  static Future<VideoDisplayMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey) ?? prefs.getString(_legacyPrefsKey);
    return VideoDisplayMode.fromStorageKey(raw);
  }

  static Future<void> save(VideoDisplayMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.storageKey);
  }

  static const String _legacyPrefsKey = 'mobileVideoDisplayMode_v1';
}
