import 'package:flutter/foundation.dart';
import 'package:volume_controller/volume_controller.dart';

class MobileSystemVolume {
  MobileSystemVolume._();

  static bool get usesSystemVolumeGestures =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static double normalize(double value) {
    final normalized = value.clamp(0.0, 1.0).toDouble();
    return normalized.isFinite ? normalized : 1.0;
  }

  static void configure({bool showSystemUi = false}) {
    if (!usesSystemVolumeGestures) return;
    try {
      VolumeController.instance.showSystemUI = showSystemUi;
    } catch (_) {}
  }

  static Future<double> getVolume() async {
    if (!usesSystemVolumeGestures) return 1.0;
    configure(showSystemUi: false);
    try {
      return normalize(await VolumeController.instance.getVolume());
    } catch (_) {
      return 1.0;
    }
  }

  static Future<void> setVolume(double value) async {
    if (!usesSystemVolumeGestures) return;
    configure(showSystemUi: false);
    try {
      await VolumeController.instance.setVolume(normalize(value));
    } catch (_) {}
  }

  static void addListener(
    void Function(double volume) listener, {
    bool fetchInitialVolume = true,
  }) {
    if (!usesSystemVolumeGestures) return;
    configure(showSystemUi: false);
    try {
      VolumeController.instance.addListener(
        (volume) => listener(normalize(volume)),
        fetchInitialVolume: fetchInitialVolume,
      );
    } catch (_) {}
  }

  static void removeListener() {
    if (!usesSystemVolumeGestures) return;
    try {
      VolumeController.instance.removeListener();
    } catch (_) {}
  }
}
