import 'dart:convert';

import 'package:lin_player_server_api/services/emby_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BrowsingCacheSnapshot<T> {
  const BrowsingCacheSnapshot({
    required this.value,
    required this.cachedAt,
  });

  final T value;
  final DateTime cachedAt;

  bool get isFresh =>
      DateTime.now().difference(cachedAt) <= BrowsingCacheService.freshness;
}

class BrowsingCacheService {
  BrowsingCacheService._();

  static final BrowsingCacheService instance = BrowsingCacheService._();

  static const Duration freshness = Duration(minutes: 15);
  static const Duration maxRetainedAge = Duration(days: 7);
  static const int _maxEntriesPerKind = 24;
  static const String _keyPrefix = 'linplayer_browsing_cache_v1:';
  static const String _showPrefix = '${_keyPrefix}show:';
  static const String _episodePrefix = '${_keyPrefix}episode:';

  Future<BrowsingCacheSnapshot<ShowDetailCachePayload>?> readShowDetail({
    required String serverScope,
    required String itemId,
  }) {
    return _read(
      key: _entryKey(_showPrefix, serverScope, itemId),
      decode: ShowDetailCachePayload.fromJson,
    );
  }

  Future<void> writeShowDetail({
    required String serverScope,
    required String itemId,
    required ShowDetailCachePayload payload,
  }) {
    return _write(
      prefix: _showPrefix,
      key: _entryKey(_showPrefix, serverScope, itemId),
      payload: payload.toJson(),
    );
  }

  Future<BrowsingCacheSnapshot<EpisodeDetailCachePayload>?> readEpisodeDetail({
    required String serverScope,
    required String itemId,
  }) {
    return _read(
      key: _entryKey(_episodePrefix, serverScope, itemId),
      decode: EpisodeDetailCachePayload.fromJson,
    );
  }

  Future<void> writeEpisodeDetail({
    required String serverScope,
    required String itemId,
    required EpisodeDetailCachePayload payload,
  }) {
    return _write(
      prefix: _episodePrefix,
      key: _entryKey(_episodePrefix, serverScope, itemId),
      payload: payload.toJson(),
    );
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
          (key) =>
              key.startsWith(_showPrefix) || key.startsWith(_episodePrefix),
        );
    for (final key in keys.toList(growable: false)) {
      await prefs.remove(key);
    }
  }

  Future<BrowsingCacheSnapshot<T>?> _read<T>({
    required String key,
    required T Function(Map<String, dynamic> json) decode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      final map = _asMap(decoded);
      if (map == null) {
        await prefs.remove(key);
        return null;
      }

      final cachedAtMs = _readInt(map['cachedAtMs']);
      if (cachedAtMs == null || cachedAtMs <= 0) {
        await prefs.remove(key);
        return null;
      }

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
      if (DateTime.now().difference(cachedAt) > maxRetainedAge) {
        await prefs.remove(key);
        return null;
      }

      final payload = _asMap(map['payload']);
      if (payload == null) {
        await prefs.remove(key);
        return null;
      }

      return BrowsingCacheSnapshot<T>(
        value: decode(payload),
        cachedAt: cachedAt,
      );
    } catch (_) {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> _write({
    required String prefix,
    required String key,
    required Map<String, dynamic> payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final wrapped = <String, dynamic>{
      'cachedAtMs': now.millisecondsSinceEpoch,
      'payload': payload,
    };
    await prefs.setString(key, jsonEncode(wrapped));
    await _prunePrefix(prefs, prefix);
  }

  Future<void> _prunePrefix(SharedPreferences prefs, String prefix) async {
    final keys =
        prefs.getKeys().where((key) => key.startsWith(prefix)).toList();
    final candidates = <_CacheEntryMeta>[];
    final invalidKeys = <String>[];
    final now = DateTime.now();

    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) {
        invalidKeys.add(key);
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        final map = _asMap(decoded);
        final cachedAtMs = map == null ? null : _readInt(map['cachedAtMs']);
        if (cachedAtMs == null || cachedAtMs <= 0) {
          invalidKeys.add(key);
          continue;
        }
        final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
        if (now.difference(cachedAt) > maxRetainedAge) {
          invalidKeys.add(key);
          continue;
        }
        candidates.add(_CacheEntryMeta(key: key, cachedAtMs: cachedAtMs));
      } catch (_) {
        invalidKeys.add(key);
      }
    }

    for (final key in invalidKeys) {
      await prefs.remove(key);
    }

    if (candidates.length <= _maxEntriesPerKind) return;
    candidates.sort((a, b) => a.cachedAtMs.compareTo(b.cachedAtMs));
    final overflow = candidates.length - _maxEntriesPerKind;
    for (final entry in candidates.take(overflow)) {
      await prefs.remove(entry.key);
    }
  }

  static String _entryKey(String prefix, String serverScope, String itemId) {
    final serverToken = Uri.encodeComponent(_normalizeToken(serverScope));
    final itemToken = Uri.encodeComponent(_normalizeToken(itemId));
    return '$prefix$serverToken:$itemToken';
  }

  static String _normalizeToken(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? 'default' : normalized;
  }
}

class ShowDetailCachePayload {
  const ShowDetailCachePayload({
    required this.detail,
    required this.seasons,
    required this.seasonsVirtual,
    required this.similar,
    required this.featuredEpisode,
    required this.episodesBySeason,
    required this.playInfo,
    required this.chapters,
    required this.selectedSeasonId,
    required this.selectedMediaSourceId,
    required this.selectedAudioStreamIndex,
    required this.selectedSubtitleStreamIndex,
  });

  final MediaItem detail;
  final List<MediaItem> seasons;
  final bool seasonsVirtual;
  final List<MediaItem> similar;
  final MediaItem? featuredEpisode;
  final Map<String, List<MediaItem>> episodesBySeason;
  final PlaybackInfoResult? playInfo;
  final List<ChapterInfo> chapters;
  final String? selectedSeasonId;
  final String? selectedMediaSourceId;
  final int? selectedAudioStreamIndex;
  final int? selectedSubtitleStreamIndex;

  factory ShowDetailCachePayload.fromJson(Map<String, dynamic> json) {
    final detail = _mediaItemFromJson(json['detail']);
    if (detail == null) {
      throw const FormatException('Missing show detail cache payload');
    }

    return ShowDetailCachePayload(
      detail: detail,
      seasons: _mediaItemListFromJson(json['seasons']),
      seasonsVirtual: json['seasonsVirtual'] == true,
      similar: _mediaItemListFromJson(json['similar']),
      featuredEpisode: _mediaItemFromJson(json['featuredEpisode']),
      episodesBySeason: _episodesBySeasonFromJson(json['episodesBySeason']),
      playInfo: _playbackInfoFromJson(json['playInfo']),
      chapters: _chaptersFromJson(json['chapters']),
      selectedSeasonId: _readString(json['selectedSeasonId']),
      selectedMediaSourceId: _readString(json['selectedMediaSourceId']),
      selectedAudioStreamIndex: _readInt(json['selectedAudioStreamIndex']),
      selectedSubtitleStreamIndex:
          _readInt(json['selectedSubtitleStreamIndex']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'detail': detail.toJson(),
        'seasons': seasons.map((item) => item.toJson()).toList(growable: false),
        'seasonsVirtual': seasonsVirtual,
        'similar': similar.map((item) => item.toJson()).toList(growable: false),
        'featuredEpisode': featuredEpisode?.toJson(),
        'episodesBySeason': episodesBySeason.map(
          (key, items) => MapEntry(
            key,
            items.map((item) => item.toJson()).toList(growable: false),
          ),
        ),
        'playInfo': _playbackInfoToJson(playInfo),
        'chapters': chapters.map((chapter) => _chapterToJson(chapter)).toList(),
        'selectedSeasonId': selectedSeasonId,
        'selectedMediaSourceId': selectedMediaSourceId,
        'selectedAudioStreamIndex': selectedAudioStreamIndex,
        'selectedSubtitleStreamIndex': selectedSubtitleStreamIndex,
      };
}

class EpisodeDetailCachePayload {
  const EpisodeDetailCachePayload({
    required this.detail,
    required this.playInfo,
    required this.chapters,
    required this.seriesId,
    required this.seriesName,
    required this.seasons,
    required this.seasonsVirtual,
    required this.selectedSeasonId,
    required this.episodesBySeason,
    required this.selectedMediaSourceId,
    required this.selectedAudioStreamIndex,
    required this.selectedSubtitleStreamIndex,
  });

  final MediaItem detail;
  final PlaybackInfoResult? playInfo;
  final List<ChapterInfo> chapters;
  final String? seriesId;
  final String seriesName;
  final List<MediaItem> seasons;
  final bool seasonsVirtual;
  final String? selectedSeasonId;
  final Map<String, List<MediaItem>> episodesBySeason;
  final String? selectedMediaSourceId;
  final int? selectedAudioStreamIndex;
  final int? selectedSubtitleStreamIndex;

  factory EpisodeDetailCachePayload.fromJson(Map<String, dynamic> json) {
    final detail = _mediaItemFromJson(json['detail']);
    if (detail == null) {
      throw const FormatException('Missing episode detail cache payload');
    }

    return EpisodeDetailCachePayload(
      detail: detail,
      playInfo: _playbackInfoFromJson(json['playInfo']),
      chapters: _chaptersFromJson(json['chapters']),
      seriesId: _readString(json['seriesId']),
      seriesName: _readString(json['seriesName']) ?? '',
      seasons: _mediaItemListFromJson(json['seasons']),
      seasonsVirtual: json['seasonsVirtual'] == true,
      selectedSeasonId: _readString(json['selectedSeasonId']),
      episodesBySeason: _episodesBySeasonFromJson(json['episodesBySeason']),
      selectedMediaSourceId: _readString(json['selectedMediaSourceId']),
      selectedAudioStreamIndex: _readInt(json['selectedAudioStreamIndex']),
      selectedSubtitleStreamIndex:
          _readInt(json['selectedSubtitleStreamIndex']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'detail': detail.toJson(),
        'playInfo': _playbackInfoToJson(playInfo),
        'chapters': chapters.map((chapter) => _chapterToJson(chapter)).toList(),
        'seriesId': seriesId,
        'seriesName': seriesName,
        'seasons': seasons.map((item) => item.toJson()).toList(growable: false),
        'seasonsVirtual': seasonsVirtual,
        'selectedSeasonId': selectedSeasonId,
        'episodesBySeason': episodesBySeason.map(
          (key, items) => MapEntry(
            key,
            items.map((item) => item.toJson()).toList(growable: false),
          ),
        ),
        'selectedMediaSourceId': selectedMediaSourceId,
        'selectedAudioStreamIndex': selectedAudioStreamIndex,
        'selectedSubtitleStreamIndex': selectedSubtitleStreamIndex,
      };
}

class _CacheEntryMeta {
  const _CacheEntryMeta({
    required this.key,
    required this.cachedAtMs,
  });

  final String key;
  final int cachedAtMs;
}

Map<String, dynamic>? _asMap(dynamic raw) {
  if (raw is! Map) return null;
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

String? _readString(dynamic raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

int? _readInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

MediaItem? _mediaItemFromJson(dynamic raw) {
  final map = _asMap(raw);
  if (map == null) return null;
  return MediaItem.fromJson(map);
}

List<MediaItem> _mediaItemListFromJson(dynamic raw) {
  if (raw is! List) return const <MediaItem>[];
  final items = <MediaItem>[];
  for (final entry in raw) {
    final item = _mediaItemFromJson(entry);
    if (item != null && item.id.trim().isNotEmpty) {
      items.add(item);
    }
  }
  return items;
}

Map<String, List<MediaItem>> _episodesBySeasonFromJson(dynamic raw) {
  if (raw is! Map) return const <String, List<MediaItem>>{};
  final output = <String, List<MediaItem>>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) continue;
    output[key] = _mediaItemListFromJson(entry.value);
  }
  return output;
}

Map<String, dynamic>? _playbackInfoToJson(PlaybackInfoResult? info) {
  if (info == null) return null;
  return <String, dynamic>{
    'playSessionId': info.playSessionId,
    'mediaSourceId': info.mediaSourceId,
    'mediaSources': info.mediaSources,
  };
}

PlaybackInfoResult? _playbackInfoFromJson(dynamic raw) {
  final map = _asMap(raw);
  if (map == null) return null;
  final mediaSources = map['mediaSources'];
  return PlaybackInfoResult(
    playSessionId: _readString(map['playSessionId']) ?? '',
    mediaSourceId: _readString(map['mediaSourceId']) ?? '',
    mediaSources: mediaSources is List ? List<dynamic>.from(mediaSources) : [],
  );
}

Map<String, dynamic> _chapterToJson(ChapterInfo chapter) {
  return <String, dynamic>{
    'Name': chapter.name,
    'StartPositionTicks': chapter.startTicks,
  };
}

List<ChapterInfo> _chaptersFromJson(dynamic raw) {
  if (raw is! List) return const <ChapterInfo>[];
  final output = <ChapterInfo>[];
  for (final entry in raw) {
    final map = _asMap(entry);
    if (map == null) continue;
    output.add(ChapterInfo.fromJson(map));
  }
  return output;
}
