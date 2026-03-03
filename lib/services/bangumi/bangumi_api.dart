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
  const BangumiRating({this.score});

  final double? score;

  factory BangumiRating.fromJson(Map<String, dynamic> json) {
    final score = (json['score'] as num?)?.toDouble();
    return BangumiRating(score: score);
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

  String get displayName {
    final cn = nameCn.trim();
    if (cn.isNotEmpty) return cn;
    return name.trim();
  }

  String? get imageUrl => images?.best;

  factory BangumiSubject.fromJson(Map<String, dynamic> json) {
    final imagesRaw = json['images'];
    final ratingRaw = json['rating'];

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

  Future<List<BangumiSubject>> topAnimeRanking({
    required BangumiSubjectSort sort,
    int limit = 10,
    int offset = 0,
    bool japanOnly = true,
  }) async {
    final baseFilter = <String, dynamic>{
      'type': const [2],
      'nsfw': false,
    };

    final candidates = <Map<String, dynamic>>[
      if (japanOnly)
        {
          'meta_tags': const ['日本']
        },
      if (japanOnly)
        {
          'tag': const ['日本']
        },
      const <String, dynamic>{},
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
        if (resp.data.isNotEmpty) return resp.data;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) {
      // ignore: only_throw_errors
      throw lastError;
    }
    return const [];
  }
}
