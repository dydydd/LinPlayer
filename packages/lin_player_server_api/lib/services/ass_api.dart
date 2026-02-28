import 'dart:convert';

import 'package:http/http.dart' as http;

import '../network/lin_http_client.dart';

class AssApiException implements Exception {
  AssApiException(this.message, {this.httpStatusCode});

  final String message;
  final int? httpStatusCode;

  @override
  String toString() => message;
}

class AssApiResult<T> {
  const AssApiResult({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final T data;
}

class AssTmdb {
  const AssTmdb({
    required this.id,
    required this.name,
    required this.originalName,
    required this.overview,
    required this.voteAverage,
    required this.posterPath,
    required this.backdropPath,
  });

  final String id;
  final String name;
  final String originalName;
  final String overview;
  final String voteAverage;
  final String posterPath;
  final String backdropPath;

  factory AssTmdb.fromJson(Map<String, dynamic> json) {
    return AssTmdb(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      originalName: (json['originalName'] ?? '').toString(),
      overview: (json['overview'] ?? '').toString(),
      voteAverage: (json['voteAverage'] ?? '').toString(),
      posterPath: (json['posterPath'] ?? '').toString(),
      backdropPath: (json['backdropPath'] ?? '').toString(),
    );
  }
}

class AssAni {
  AssAni({
    required this.raw,
    required this.id,
    required this.title,
    required this.jpTitle,
    required this.image,
    required this.cover,
    required this.subgroup,
    required this.currentEpisodeNumber,
    required this.totalEpisodeNumber,
    required this.score,
    required this.tmdb,
  });

  final Map<String, dynamic> raw;
  final String id;
  final String title;
  final String jpTitle;
  final String image;
  final String cover;
  final String subgroup;
  final int? currentEpisodeNumber;
  final int? totalEpisodeNumber;
  final double? score;
  final AssTmdb? tmdb;

  factory AssAni.fromJson(Map<String, dynamic> json) {
    return AssAni(
      raw: json,
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      jpTitle: (json['jpTitle'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
      cover: (json['cover'] ?? '').toString(),
      subgroup: (json['subgroup'] ?? '').toString(),
      currentEpisodeNumber: _readIntOpt(json['currentEpisodeNumber']),
      totalEpisodeNumber: _readIntOpt(json['totalEpisodeNumber']),
      score: _readDoubleOpt(json['score']),
      tmdb: json['tmdb'] is Map
          ? AssTmdb.fromJson((json['tmdb'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  Map<String, dynamic> toJson() => raw;
}

class AssSubtitle {
  AssSubtitle({
    required this.raw,
    required this.name,
    required this.url,
    required this.content,
    required this.type,
    required this.html,
  });

  final Map<String, dynamic> raw;
  final String name;
  final String url;
  final String content;
  final String type;
  final String html;

  factory AssSubtitle.fromJson(Map<String, dynamic> json) {
    return AssSubtitle(
      raw: json,
      name: (json['name'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      html: (json['html'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => raw;
}

class AssPlayItem {
  AssPlayItem({
    required this.raw,
    required this.title,
    required this.filename,
    required this.name,
    required this.lastModify,
    required this.episode,
    required this.size,
    required this.extName,
    required this.subtitles,
  });

  final Map<String, dynamic> raw;
  final String title;
  final String filename;
  final String name;
  final int? lastModify;
  final double? episode;
  final String size;
  final String extName;
  final List<AssSubtitle> subtitles;

  factory AssPlayItem.fromJson(Map<String, dynamic> json) {
    final subs = (json['subtitles'] is List)
        ? (json['subtitles'] as List)
            .whereType<Map>()
            .map((e) => AssSubtitle.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false)
        : const <AssSubtitle>[];

    return AssPlayItem(
      raw: json,
      title: (json['title'] ?? '').toString(),
      filename: (json['filename'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      lastModify: _readIntOpt(json['lastModify']),
      episode: _readDoubleOpt(json['episode']),
      size: (json['size'] ?? '').toString(),
      extName: (json['extName'] ?? '').toString(),
      subtitles: subs,
    );
  }

  Map<String, dynamic> toJson() => raw;
}

class AssApi {
  AssApi({
    required String baseUrl,
    String? token,
    http.Client? client,
  })  : _baseUri = _normalizeBaseUri(baseUrl),
        token = (token ?? '').trim(),
        _client = client ?? LinHttpClientFactory.createClient();

  final Uri _baseUri;
  final http.Client _client;
  final String token;

  static Uri _normalizeBaseUri(String raw) {
    final fixed = raw.trim();
    if (fixed.isEmpty) throw const FormatException('Missing baseUrl');
    final uri = Uri.parse(fixed);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw FormatException('Invalid baseUrl scheme: ${uri.scheme}');
    }
    if (uri.host.isEmpty) throw const FormatException('Invalid baseUrl host');

    // Normalize path: strip query/fragment and ensure trailing slash for resolve().
    final trimmedSegments = uri.pathSegments
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: true);
    while (trimmedSegments.isNotEmpty &&
        trimmedSegments.last.trim().toLowerCase() == 'api') {
      trimmedSegments.removeLast();
    }

    final normalizedPath =
        trimmedSegments.isEmpty ? '/' : '/${trimmedSegments.join('/')}/';
    return uri.replace(path: normalizedPath, query: null, fragment: null);
  }

  Uri endpoint(String path, {Map<String, String>? query}) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final resolved = _baseUri.resolve(normalized);
    if (query == null || query.isEmpty) return resolved;
    return resolved.replace(queryParameters: query);
  }

  Uri fileUri(String filenameBase64) {
    final fixed = filenameBase64.trim();
    return endpoint(
      'api/file',
      query: <String, String>{
        'filename': fixed,
      },
    );
  }

  Uri? resolveSubtitleUri(String rawUrl) {
    final fixed = rawUrl.trim();
    if (fixed.isEmpty) return null;
    final parsed = Uri.tryParse(fixed);
    if (parsed != null && parsed.hasScheme) return parsed;
    if (fixed.startsWith('/')) return _baseUri.replace(path: fixed);
    return _baseUri.resolve(fixed);
  }

  Map<String, String> buildAuthHeaders({bool includeContentType = false}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': LinHttpClientFactory.userAgent,
    };
    if (includeContentType) headers['Content-Type'] = 'application/json';
    if (token.isNotEmpty) {
      // The OpenAPI spec does not define auth headers. We try common patterns.
      headers['Authorization'] = 'Bearer $token';
      headers['X-Token'] = token;
      headers['Cookie'] = 'token=$token';
    }
    return headers;
  }

  Future<AssApiResult<T>> _post<T>(
    String path, {
    Object? body,
    required T Function(Object? data) decodeData,
  }) async {
    final uri = endpoint(path);
    final resp = await _client.post(
      uri,
      headers: buildAuthHeaders(includeContentType: body != null),
      body: body == null ? null : jsonEncode(body),
    );

    if (resp.statusCode != 200) {
      throw AssApiException(
        '${uri.toString()}: HTTP ${resp.statusCode}',
        httpStatusCode: resp.statusCode,
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw AssApiException('${uri.toString()}: Invalid JSON response');
    }
    final map = decoded.cast<String, dynamic>();
    final code = _readInt(map['code'], fallback: resp.statusCode);
    final message = (map['message'] ?? '').toString();
    if (code != 200) {
      throw AssApiException(
        '${uri.toString()}: $code ${message.isEmpty ? 'Error' : message}',
        httpStatusCode: resp.statusCode,
      );
    }

    return AssApiResult<T>(
      code: code,
      message: message,
      data: decodeData(map['data']),
    );
  }

  Future<String> login({
    required String username,
    required String password,
  }) async {
    final uri = endpoint('api/login');
    final resp = await _client.post(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'User-Agent': LinHttpClientFactory.userAgent,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'username': username.trim(),
        'password': password,
      }),
    );

    if (resp.statusCode != 200) {
      throw AssApiException(
        '${uri.toString()}: HTTP ${resp.statusCode}',
        httpStatusCode: resp.statusCode,
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw AssApiException('${uri.toString()}: Invalid JSON response');
    }
    final map = decoded.cast<String, dynamic>();
    final code = _readInt(map['code'], fallback: resp.statusCode);
    final message = (map['message'] ?? '').toString();
    if (code != 200) {
      throw AssApiException(
        '${uri.toString()}: $code ${message.isEmpty ? 'Login failed' : message}',
        httpStatusCode: resp.statusCode,
      );
    }
    final token = (map['data'] ?? '').toString().trim();
    if (token.isEmpty || token.toLowerCase() == 'null') {
      throw AssApiException('${uri.toString()}: Missing token');
    }
    return token;
  }

  Future<List<AssAni>> listAni() async {
    final result = await _post<List<AssAni>>(
      'api/listAni',
      decodeData: (data) {
        if (data is! List) return const <AssAni>[];
        return data
            .whereType<Map>()
            .map((e) => AssAni.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
      },
    );
    return result.data;
  }

  Future<List<AssPlayItem>> playList({required AssAni ani}) async {
    final result = await _post<List<AssPlayItem>>(
      'api/playList',
      body: ani.toJson(),
      decodeData: (data) {
        if (data is! List) return const <AssPlayItem>[];
        return data
            .whereType<Map>()
            .map((e) => AssPlayItem.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
      },
    );
    return result.data;
  }
}

int _readInt(dynamic value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

int? _readIntOpt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? _readDoubleOpt(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

