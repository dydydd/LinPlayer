import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lin_player_server_api/network/lin_http_client.dart';

const String _kBangumiHost = 'api.bgm.tv';

enum BangumiSubjectSort {
  match('match'),
  heat('heat'),
  rank('rank'),
  score('score');

  const BangumiSubjectSort(this.apiValue);

  final String apiValue;
}

class BangumiApiException implements Exception {
  BangumiApiException(
    this.message, {
    this.statusCode,
    this.body,
  });

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() {
    final code = statusCode;
    if (code == null) return message;
    return '$message (HTTP $code)';
  }
}

class BangumiImages {
  const BangumiImages({
    this.small,
    this.grid,
    this.large,
    this.medium,
    this.common,
  });

  final String? small;
  final String? grid;
  final String? large;
  final String? medium;
  final String? common;

  factory BangumiImages.fromJson(Map<String, dynamic> json) {
    String? readUrl(String key) {
      final raw = json[key];
      if (raw is! String) return null;
      final v = raw.trim();
      return v.isEmpty ? null : v;
    }

    return BangumiImages(
      small: readUrl('small'),
      grid: readUrl('grid'),
      large: readUrl('large'),
      medium: readUrl('medium'),
      common: readUrl('common'),
    );
  }

  String? get best => large ?? common ?? medium ?? grid ?? small;
}

class BangumiRating {
  const BangumiRating({
    this.score,
    this.rank,
  });

  final double? score;
  final int? rank;

  factory BangumiRating.fromJson(Map<String, dynamic> json) {
    final score = (json['score'] as num?)?.toDouble();
    final rank = (json['rank'] as num?)?.toInt();
    return BangumiRating(
      score: score,
      rank: rank,
    );
  }
}

class BangumiSubject {
  const BangumiSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    this.type,
    this.url,
    this.images,
    this.rating,
    this.rank,
    this.airDate,
    this.tags = const [],
    this.metaTags = const [],
  });

  final int id;
  final String name;
  final String nameCn;
  final int? type;
  final String? url;
  final BangumiImages? images;
  final BangumiRating? rating;
  final int? rank;
  final String? airDate;
  final List<String> tags;
  final List<String> metaTags;

  String get displayName {
    final cn = nameCn.trim();
    if (cn.isNotEmpty) return cn;
    return name.trim();
  }

  String? get imageUrl => images?.best;

  int? get effectiveRank {
    final root = rank;
    if (root != null && root > 0) return root;
    final r = rating?.rank;
    if (r != null && r > 0) return r;
    return null;
  }

  double? get effectiveScore {
    final s = rating?.score;
    if (s == null || s <= 0) return null;
    return s;
  }

  bool get isJapanAnime {
    bool isJapanTag(String t) {
      final v = t.trim();
      if (v.isEmpty) return false;
      if (v.contains('日本')) return true;
      if (v.toLowerCase() == 'japan') return true;
      return false;
    }

    for (final t in metaTags) {
      if (isJapanTag(t)) return true;
    }
    for (final t in tags) {
      if (isJapanTag(t)) return true;
    }
    return false;
  }

  factory BangumiSubject.fromJson(Map<String, dynamic> json) {
    final imagesRaw = json['images'];
    final ratingRaw = json['rating'];

    List<String> readStringList(Object? raw) {
      if (raw is! List) return const [];
      final out = <String>[];
      for (final e in raw) {
        if (e is! String) continue;
        final v = e.trim();
        if (v.isEmpty) continue;
        out.add(v);
      }
      return out;
    }

    List<String> readTagNames(Object? raw) {
      if (raw is! List) return const [];
      final out = <String>[];
      for (final e in raw) {
        if (e is String) {
          final v = e.trim();
          if (v.isNotEmpty) out.add(v);
          continue;
        }
        if (e is! Map) continue;
        final name = e['name'];
        if (name is! String) continue;
        final v = name.trim();
        if (v.isEmpty) continue;
        out.add(v);
      }
      return out;
    }

    return BangumiSubject(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: (json['type'] as num?)?.toInt(),
      url: (json['url'] as String?)?.trim(),
      name: (json['name'] as String?)?.trim() ?? '',
      nameCn: (json['name_cn'] as String?)?.trim() ?? '',
      images: imagesRaw is Map
          ? BangumiImages.fromJson(imagesRaw.cast<String, dynamic>())
          : null,
      rating: ratingRaw is Map
          ? BangumiRating.fromJson(ratingRaw.cast<String, dynamic>())
          : null,
      rank: (json['rank'] as num?)?.toInt(),
      airDate: (json['air_date'] as String?)?.trim(),
      tags: readTagNames(json['tags']),
      metaTags: readStringList(json['meta_tags']),
    );
  }
}

class BangumiSearchResponse {
  const BangumiSearchResponse({
    required this.total,
    required this.limit,
    required this.offset,
    required this.data,
  });

  final int total;
  final int limit;
  final int offset;
  final List<BangumiSubject> data;

  factory BangumiSearchResponse.fromJson(Map<String, dynamic> json) {
    final raw = (json['data'] as List?) ?? const [];
    final subjects = raw
        .whereType<Map>()
        .map((e) => BangumiSubject.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList(growable: false);
    return BangumiSearchResponse(
      total: (json['total'] as num?)?.toInt() ?? subjects.length,
      limit: (json['limit'] as num?)?.toInt() ?? subjects.length,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      data: subjects,
    );
  }
}

class BangumiWeekday {
  const BangumiWeekday({
    required this.id,
    required this.cn,
    this.en = '',
    this.ja = '',
  });

  final int id;
  final String cn;
  final String en;
  final String ja;

  factory BangumiWeekday.fromJson(Map<String, dynamic> json) {
    return BangumiWeekday(
      id: (json['id'] as num?)?.toInt() ?? 0,
      cn: (json['cn'] as String?)?.trim() ?? '',
      en: (json['en'] as String?)?.trim() ?? '',
      ja: (json['ja'] as String?)?.trim() ?? '',
    );
  }
}

class BangumiCalendarDay {
  const BangumiCalendarDay({
    required this.weekday,
    required this.items,
  });

  final BangumiWeekday weekday;
  final List<BangumiSubject> items;

  factory BangumiCalendarDay.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map((e) => BangumiSubject.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList(growable: false);
    return BangumiCalendarDay(
      weekday: json['weekday'] is Map
          ? BangumiWeekday.fromJson(
              (json['weekday'] as Map).cast<String, dynamic>(),
            )
          : const BangumiWeekday(id: 0, cn: ''),
      items: items,
    );
  }
}

class BangumiApiClient {
  BangumiApiClient({http.Client? client})
      : _client = client ?? LinHttpClientFactory.createClient();

  final http.Client _client;

  void close() => _client.close();

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': LinHttpClientFactory.userAgent,
    };
    if (json) headers['Content-Type'] = 'application/json';
    return headers;
  }

  Never _throwHttp(http.Response resp) {
    throw BangumiApiException(
      'Bangumi API request failed',
      statusCode: resp.statusCode,
      body: resp.body,
    );
  }

  void _ensureOk(http.Response resp) {
    final code = resp.statusCode;
    if (code < 200 || code >= 300) _throwHttp(resp);
  }

  Future<List<BangumiCalendarDay>> getCalendar() async {
    final uri = Uri.https(_kBangumiHost, '/calendar');
    final resp = await _client.get(uri, headers: _headers());
    _ensureOk(resp);

    final decoded = jsonDecode(resp.body);
    if (decoded is! List) {
      throw BangumiApiException('Unexpected calendar response');
    }
    return decoded
        .whereType<Map>()
        .map((e) => BangumiCalendarDay.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<BangumiSearchResponse> searchSubjects({
    required String keyword,
    required BangumiSubjectSort sort,
    int limit = 10,
    int offset = 0,
    Map<String, dynamic> filter = const {},
  }) async {
    final uri = Uri.https(
      _kBangumiHost,
      '/v0/search/subjects',
      <String, String>{
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );

    final body = <String, dynamic>{
      'keyword': keyword,
      'sort': sort.apiValue,
      if (filter.isNotEmpty) 'filter': filter,
    };

    final resp = await _client.post(
      uri,
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    _ensureOk(resp);

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw BangumiApiException('Unexpected search response');
    }
    return BangumiSearchResponse.fromJson(decoded.cast<String, dynamic>());
  }

  Future<BangumiSearchResponse> browseSubjects({
    required int type,
    String sort = 'rank',
    int limit = 10,
    int offset = 0,
    int? cat,
    bool? series,
    String? platform,
    int? year,
    int? month,
  }) async {
    final uri = Uri.https(
      _kBangumiHost,
      '/v0/subjects',
      <String, String>{
        'type': type.toString(),
        'sort': sort,
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (cat != null) 'cat': cat.toString(),
        if (series != null) 'series': series.toString(),
        if (platform != null && platform.trim().isNotEmpty)
          'platform': platform.trim(),
        if (year != null) 'year': year.toString(),
        if (month != null) 'month': month.toString(),
      },
    );

    final resp = await _client.get(uri, headers: _headers());
    _ensureOk(resp);

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw BangumiApiException('Unexpected browse response');
    }
    return BangumiSearchResponse.fromJson(decoded.cast<String, dynamic>());
  }

  Future<List<BangumiSubject>> topAnimeRanking({
    required BangumiSubjectSort sort,
    int limit = 10,
    int offset = 0,
    bool japanOnly = true,
  }) async {
    final resp = await topAnimeRankingResponse(
      sort: sort,
      limit: limit,
      offset: offset,
      japanOnly: japanOnly,
    );
    return resp.data;
  }

  Future<BangumiSearchResponse> topAnimeRankingResponse({
    required BangumiSubjectSort sort,
    int limit = 10,
    int offset = 0,
    bool japanOnly = true,
  }) async {
    final baseFilter = <String, dynamic>{
      'type': 2,
      'nsfw': false,
    };

    final candidates = <Map<String, dynamic>>[
      if (japanOnly)
        {
          'meta_tags': const ['日本']
        },
      if (japanOnly)
        {
          'meta_tags': const ['日本动画']
        },
      if (japanOnly)
        {
          'tag': const ['日本']
        },
      if (japanOnly)
        {
          'tag': const ['日本动画']
        },
      if (!japanOnly) const <String, dynamic>{},
    ];

    Object? lastError;
    for (final extra in candidates) {
      try {
        final resp = await searchSubjects(
          keyword: '',
          sort: sort,
          limit: limit,
          offset: offset,
          filter: <String, dynamic>{...baseFilter, ...extra},
        );
        if (resp.data.isEmpty) continue;

        final items = resp.data.toList(growable: true);
        switch (sort) {
          case BangumiSubjectSort.rank:
            int effRank(BangumiSubject s) {
              final v = s.effectiveRank;
              if (v == null || v <= 0) return 1 << 30;
              return v;
            }

            double effScore(BangumiSubject s) {
              final v = s.effectiveScore;
              if (v == null || v <= 0) return -1;
              return v;
            }

            items.sort((a, b) {
              final cmp = effRank(a).compareTo(effRank(b));
              if (cmp != 0) return cmp;
              return effScore(b).compareTo(effScore(a));
            });
            break;
          case BangumiSubjectSort.score:
            double effScore(BangumiSubject s) {
              final v = s.effectiveScore;
              if (v == null || v <= 0) return -1;
              return v;
            }

            int effRank(BangumiSubject s) {
              final v = s.effectiveRank;
              if (v == null || v <= 0) return 1 << 30;
              return v;
            }

            items.sort((a, b) {
              final cmp = effScore(b).compareTo(effScore(a));
              if (cmp != 0) return cmp;
              return effRank(a).compareTo(effRank(b));
            });
            break;
          case BangumiSubjectSort.heat:
          case BangumiSubjectSort.match:
            break;
        }

        return BangumiSearchResponse(
          total: resp.total,
          limit: resp.limit,
          offset: resp.offset,
          data: items,
        );
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      // ignore: only_throw_errors
      throw lastError;
    }
    return const BangumiSearchResponse(
      total: 0,
      limit: 0,
      offset: 0,
      data: <BangumiSubject>[],
    );
  }
}
