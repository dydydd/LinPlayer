import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 循环方式（与 [PlaylistMode] 对应，持久化）。
enum MobilePlaybackLoopMode {
  none('none'),
  single('single'),
  list('list');

  const MobilePlaybackLoopMode(this.storageKey);
  final String storageKey;

  static MobilePlaybackLoopMode fromStorageKey(String? raw) {
    final key = (raw ?? '').trim().toLowerCase();
    for (final v in values) {
      if (v.storageKey == key) return v;
    }
    return MobilePlaybackLoopMode.none;
  }

  PlaylistMode get playlistMode => switch (this) {
        MobilePlaybackLoopMode.none => PlaylistMode.none,
        MobilePlaybackLoopMode.single => PlaylistMode.single,
        MobilePlaybackLoopMode.list => PlaylistMode.loop,
      };
}

class MobilePlaybackPreferences {
  static const String _prefsListenVideo = 'mobilePlayback_listenVideo_v1';
  static const String _prefsAutoNext = 'mobilePlayback_autoNextEpisode_v1';
  static const String _prefsLoop = 'mobilePlayback_loopMode_v1';
  static const String _prefsPlayerVolume = 'mobilePlayback_playerVolume_v1';

  static double normalizePlayerVolume(double value) {
    final normalized = value.clamp(0.0, 1.0).toDouble();
    return normalized.isFinite ? normalized : 1.0;
  }

  static Future<bool> loadListenVideoOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsListenVideo) ?? false;
  }

  static Future<void> saveListenVideoOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsListenVideo, value);
  }

  static Future<bool> loadAutoPlayNextEpisode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsAutoNext) ?? false;
  }

  static Future<void> saveAutoPlayNextEpisode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoNext, value);
  }

  static Future<MobilePlaybackLoopMode> loadLoopMode() async {
    final prefs = await SharedPreferences.getInstance();
    return MobilePlaybackLoopMode.fromStorageKey(prefs.getString(_prefsLoop));
  }

  static Future<void> saveLoopMode(MobilePlaybackLoopMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLoop, mode.storageKey);
  }

  static Future<double> loadPlayerVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizePlayerVolume(prefs.getDouble(_prefsPlayerVolume) ?? 1.0);
  }

  static Future<void> savePlayerVolume(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsPlayerVolume, normalizePlayerVolume(value));
  }
}
