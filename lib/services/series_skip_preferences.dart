import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class SeriesSkipProfile {
  final int? openingSeconds;
  final int? endingSeconds;

  const SeriesSkipProfile({
    this.openingSeconds,
    this.endingSeconds,
  });

  bool get hasOpening => openingSeconds != null && openingSeconds! > 0;
  bool get hasEnding => endingSeconds != null && endingSeconds! > 0;
  bool get isEmpty => !hasOpening && !hasEnding;

  Map<String, dynamic> toJson() => {
        if (hasOpening) 'openingSeconds': openingSeconds,
        if (hasEnding) 'endingSeconds': endingSeconds,
      };

  static int? _readSeconds(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    if (value is num) {
      final rounded = value.round();
      return rounded > 0 ? rounded : null;
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed != null && parsed > 0 ? parsed : null;
    }
    return null;
  }

  factory SeriesSkipProfile.fromJson(Map<String, dynamic> json) {
    return SeriesSkipProfile(
      openingSeconds: _readSeconds(json['openingSeconds']),
      endingSeconds: _readSeconds(json['endingSeconds']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SeriesSkipProfile &&
        other.openingSeconds == openingSeconds &&
        other.endingSeconds == endingSeconds;
  }

  @override
  int get hashCode => Object.hash(openingSeconds, endingSeconds);
}

class SeriesSkipPreferences {
  static const String _prefsKey = 'seriesSkipProfiles_v1';

  static String? buildSeriesKey({
    required String serverId,
    String? seriesId,
    String? seriesName,
  }) {
    final sid = serverId.trim();
    if (sid.isEmpty) return null;

    final normalizedSeriesId = (seriesId ?? '').trim();
    if (normalizedSeriesId.isNotEmpty) {
      return '$sid::id::$normalizedSeriesId';
    }

    final normalizedSeriesName = _normalizeSeriesName(seriesName);
    if (normalizedSeriesName.isEmpty) return null;
    return '$sid::name::$normalizedSeriesName';
  }

  static Future<SeriesSkipProfile> load({
    required String serverId,
    String? seriesId,
    String? seriesName,
  }) async {
    final key = buildSeriesKey(
      serverId: serverId,
      seriesId: seriesId,
      seriesName: seriesName,
    );
    if (key == null) return const SeriesSkipProfile();

    final prefs = await SharedPreferences.getInstance();
    final map = _readAllFromPrefs(prefs);
    return map[key] ?? const SeriesSkipProfile();
  }

  static Future<void> save({
    required String serverId,
    String? seriesId,
    String? seriesName,
    required SeriesSkipProfile profile,
  }) async {
    final key = buildSeriesKey(
      serverId: serverId,
      seriesId: seriesId,
      seriesName: seriesName,
    );
    if (key == null) return;

    final prefs = await SharedPreferences.getInstance();
    final map = _readAllFromPrefs(prefs);
    if (profile.isEmpty) {
      map.remove(key);
    } else {
      map[key] = profile;
    }

    if (map.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }

    await prefs.setString(
      _prefsKey,
      jsonEncode(
        map.map((entryKey, entryValue) => MapEntry(entryKey, entryValue.toJson())),
      ),
    );
  }

  static Map<String, SeriesSkipProfile> _readAllFromPrefs(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, SeriesSkipProfile>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, SeriesSkipProfile>{};

      final out = <String, SeriesSkipProfile>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty || entry.value is! Map) continue;
        final profile = SeriesSkipProfile.fromJson(
          (entry.value as Map).map(
            (mapKey, mapValue) => MapEntry(mapKey.toString(), mapValue),
          ),
        );
        if (profile.isEmpty) continue;
        out[key] = profile;
      }
      return out;
    } catch (_) {
      return <String, SeriesSkipProfile>{};
    }
  }

  static String _normalizeSeriesName(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'\s+'), ' ');
  }
}
