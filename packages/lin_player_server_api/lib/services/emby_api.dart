import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:lin_player_core/state/media_server_type.dart';
import '../network/lin_http_client.dart';

class DomainInfo {
  final String name;
  final String url;

  DomainInfo({required this.name, required this.url});

  factory DomainInfo.fromJson(Map<String, dynamic> json) {
    return DomainInfo(
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

class LibraryInfo {
  final String id;
  final String name;
  final String type;
  LibraryInfo({required this.id, required this.name, required this.type});

  factory LibraryInfo.fromJson(Map<String, dynamic> json) => LibraryInfo(
        id: json['Id'] as String? ?? '',
        name: json['Name'] as String? ?? '',
        type: json['CollectionType'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'Id': id,
        'Name': name,
        'CollectionType': type,
      };
}

class AuthResult {
  final String token;
  final String baseUrlUsed;
  final String userId;
  final String apiPrefixUsed;
  AuthResult(
      {required this.token,
      required this.baseUrlUsed,
      required this.userId,
      this.apiPrefixUsed = 'emby'});
}

class _AuthSocketFailure implements Exception {
  const _AuthSocketFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

bool _hasAnyImageData(Map<String, dynamic> json) {
  if ((json['ImageTags'] as Map?)?.isNotEmpty == true) return true;
  if ((json['BackdropImageTags'] as List?)?.isNotEmpty == true) return true;
  if ((json['PrimaryImageTag'] ?? '').toString().trim().isNotEmpty) return true;
  if ((json['ThumbImageTag'] ?? '').toString().trim().isNotEmpty) return true;
  if ((json['ParentThumbImageTag'] ?? '').toString().trim().isNotEmpty) {
    return true;
  }
  if ((json['SeriesPrimaryImageTag'] ?? '').toString().trim().isNotEmpty) {
    return true;
  }
  return false;
}

String _stringFromListOrName(dynamic raw) {
  if (raw == null) return '';
  if (raw is String) return raw;
  if (raw is Map) {
    final name = raw['Name'] ?? raw['name'];
    if (name != null) return name.toString();
  }
  return raw.toString();
}

List<String> _normalizeStringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  final out = <String>[];
  final seen = <String>{};
  for (final entry in raw) {
    final v = _stringFromListOrName(entry).trim();
    if (v.isEmpty) continue;
    final key = v.toLowerCase();
    if (seen.add(key)) out.add(v);
  }
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

List<String> _stringListPreserveOrder(dynamic raw) {
  if (raw is! List) return const <String>[];
  final out = <String>[];
  final seen = <String>{};
  for (final entry in raw) {
    final v = _stringFromListOrName(entry).trim();
    if (v.isEmpty) continue;
    final key = v.toLowerCase();
    if (seen.add(key)) out.add(v);
  }
  return out;
}

int? _intFromListOrName(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is Map) {
    final name = raw['Name'] ?? raw['name'];
    if (name != null) return int.tryParse(name.toString().trim());
  }
  return int.tryParse(raw.toString().trim());
}

List<int> _normalizeIntList(dynamic raw) {
  if (raw is! List) return const <int>[];
  final out = <int>[];
  final seen = <int>{};
  for (final entry in raw) {
    final v = _intFromListOrName(entry);
    if (v == null || v <= 0) continue;
    if (seen.add(v)) out.add(v);
  }
  out.sort((a, b) => b.compareTo(a));
  return out;
}

class LibraryFilterOptions {
  const LibraryFilterOptions({
    this.genres = const <String>[],
    this.years = const <int>[],
  });

  final List<String> genres;
  final List<int> years;
}

class MediaItem {
  final String id;
  final String name;
  final String type;
  final String overview;
  final double? communityRating;
  final String? officialRating;
  final String? premiereDate;
  final int? productionYear;
  final String? status;
  final List<String> genres;
  final List<String> tags;
  final int? runTimeTicks;
  final int? sizeBytes;
  final String? container;
  final Map<String, String> providerIds;
  final String? seriesId;
  final String seriesName;
  final String seasonName;
  final int? seasonNumber;
  final int? episodeNumber;
  final bool hasImage;
  final String? parentId;
  final int playbackPositionTicks;
  final bool played;
  final bool favorite;
  final List<MediaPerson> people;
  MediaItem({
    required this.id,
    required this.name,
    required this.type,
    required this.overview,
    required this.communityRating,
    this.officialRating,
    required this.premiereDate,
    this.productionYear,
    this.status,
    required this.genres,
    this.tags = const <String>[],
    required this.runTimeTicks,
    required this.sizeBytes,
    required this.container,
    required this.providerIds,
    required this.seriesId,
    required this.seriesName,
    required this.seasonName,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.hasImage,
    required this.playbackPositionTicks,
    this.played = false,
    this.favorite = false,
    required this.people,
    this.parentId,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['Id'] as String? ?? '',
        name: json['Name'] as String? ?? '',
        type: json['Type'] as String? ?? '',
        overview: json['Overview'] as String? ?? '',
        communityRating: (json['CommunityRating'] as num?)?.toDouble(),
        officialRating: json['OfficialRating'] as String?,
        premiereDate: json['PremiereDate'] as String?,
        productionYear: json['ProductionYear'] as int?,
        status: json['Status'] as String?,
        genres: _stringListPreserveOrder(
          json['Genres'] ??
              json['genres'] ??
              json['GenreItems'] ??
              json['genreItems'],
        ),
        tags: _stringListPreserveOrder(
          json['Tags'] ?? json['tags'] ?? json['TagItems'] ?? json['tagItems'],
        ),
        runTimeTicks: json['RunTimeTicks'] as int?,
        sizeBytes: json['Size'] as int?,
        container: json['Container'] as String?,
        providerIds: (json['ProviderIds'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ) ??
            const {},
        seriesId: json['SeriesId'] as String?,
        seriesName: json['SeriesName'] as String? ?? '',
        seasonName: json['SeasonName'] as String? ?? '',
        seasonNumber: json['ParentIndexNumber'] as int?,
        episodeNumber: json['IndexNumber'] as int?,
        hasImage: _hasAnyImageData(json),
        playbackPositionTicks:
            (json['UserData'] as Map?)?['PlaybackPositionTicks'] as int? ?? 0,
        played: (json['UserData'] as Map?)?['Played'] == true,
        favorite: (json['UserData'] as Map?)?['IsFavorite'] == true,
        people: (json['People'] as List?)
                ?.map((e) => MediaPerson.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        parentId: json['ParentId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'Id': id,
        'Name': name,
        'Type': type,
        'Overview': overview,
        'CommunityRating': communityRating,
        'OfficialRating': officialRating,
        'PremiereDate': premiereDate,
        'ProductionYear': productionYear,
        'Status': status,
        'Genres': genres,
        'Tags': tags,
        'RunTimeTicks': runTimeTicks,
        'Size': sizeBytes,
        'Container': container,
        'ProviderIds': providerIds,
        'SeriesId': seriesId,
        'SeriesName': seriesName,
        'SeasonName': seasonName,
        'ParentIndexNumber': seasonNumber,
        'IndexNumber': episodeNumber,
        'ImageTags': hasImage ? const {'Primary': 'cached'} : const {},
        'UserData': {
          'PlaybackPositionTicks': playbackPositionTicks,
          'Played': played,
          'IsFavorite': favorite,
        },
        'People': people.map((e) => e.toJson()).toList(),
        'ParentId': parentId,
      };
}

class PagedResult<T> {
  final List<T> items;
  final int total;
  PagedResult(this.items, this.total);
}

class ItemCounts {
  final int movieCount;
  final int seriesCount;
  final int episodeCount;

  const ItemCounts({
    required this.movieCount,
    required this.seriesCount,
    required this.episodeCount,
  });

  factory ItemCounts.fromJson(Map<String, dynamic> json) => ItemCounts(
        movieCount: json['MovieCount'] as int? ?? 0,
        seriesCount: json['SeriesCount'] as int? ?? 0,
        episodeCount: json['EpisodeCount'] as int? ?? 0,
      );
}

class MediaPerson {
  final String name;
  final String role;
  final String type;
  final String id;
  final String? primaryImageTag;
  MediaPerson({
    required this.name,
    required this.role,
    required this.type,
    required this.id,
    required this.primaryImageTag,
  });

  factory MediaPerson.fromJson(Map<String, dynamic> json) => MediaPerson(
        name: json['Name'] as String? ?? '',
        role: json['Role'] as String? ?? '',
        type: json['Type'] as String? ?? '',
        id: json['Id'] as String? ?? '',
        primaryImageTag: json['PrimaryImageTag'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'Name': name,
        'Role': role,
        'Type': type,
        'Id': id,
        'PrimaryImageTag': primaryImageTag,
      };
}

class ChapterInfo {
  final String name;
  final int startTicks;
  ChapterInfo({required this.name, required this.startTicks});

  Duration get start => Duration(microseconds: (startTicks / 10).round());

  factory ChapterInfo.fromJson(Map<String, dynamic> json) => ChapterInfo(
        name: json['Name'] as String? ?? '',
        startTicks: json['StartPositionTicks'] as int? ?? 0,
      );
}

class IntroTimestamps {
  final int startTicks;
  final int endTicks;

  const IntroTimestamps({required this.startTicks, required this.endTicks});

  Duration get start => Duration(microseconds: (startTicks / 10).round());
  Duration get end => Duration(microseconds: (endTicks / 10).round());

  bool get isValid => startTicks >= 0 && endTicks > startTicks;

  static int? _readTicks(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static IntroTimestamps? tryParse(Map<String, dynamic> json) {
    final start = _readTicks(
      json['IntroStartPositionTicks'] ??
          json['IntroStartTicks'] ??
          json['IntroStart'] ??
          json['StartPositionTicks'] ??
          json['StartTicks'] ??
          json['Start'],
    );
    final end = _readTicks(
      json['IntroEndPositionTicks'] ??
          json['IntroEndTicks'] ??
          json['IntroEnd'] ??
          json['EndPositionTicks'] ??
          json['EndTicks'] ??
          json['End'],
    );
    if (start == null || end == null) return null;
    final out = IntroTimestamps(startTicks: start, endTicks: end);
    return out.isValid ? out : null;
  }
}

class PlaybackInfoResult {
  final String playSessionId;
  final String mediaSourceId;
  final List<dynamic> mediaSources;
  PlaybackInfoResult({
    required this.playSessionId,
    required this.mediaSourceId,
    required this.mediaSources,
  });
}

typedef EmbyApiClientFactory = http.Client Function();
typedef EmbyApiRouteLabelBuilder = String? Function(Uri uri);

class EmbyApi {
  static String appVersion = '1.0.0';
  static String userAgentProduct = 'LinPlayer';
  static String defaultClientName = 'LinPlayer';
  static EmbyApiClientFactory? _clientFactory;
  static EmbyApiRouteLabelBuilder? _routeLabelBuilder;

  static String get userAgent => LinHttpClientFactory.userAgent;

  static void _syncUserAgent() {
    LinHttpClientFactory.setUserAgent('$userAgentProduct/$appVersion');
  }

  static void setUserAgentProduct(String product) {
    final v = product.trim();
    if (v.isNotEmpty) {
      userAgentProduct = v;
      _syncUserAgent();
    }
  }

  static void setDefaultClientName(String name) {
    final v = name.trim();
    if (v.isNotEmpty) defaultClientName = v;
  }

  static void setAppVersion(String version) {
    final v = version.trim();
    if (v.isNotEmpty) {
      appVersion = v;
      _syncUserAgent();
    }
  }

  static void setClientFactory(EmbyApiClientFactory? factory) {
    _clientFactory = factory;
  }

  static void setRouteLabelBuilder(EmbyApiRouteLabelBuilder? builder) {
    _routeLabelBuilder = builder;
  }

  static http.Client _defaultClient() {
    final factory = _clientFactory;
    return factory == null ? LinHttpClientFactory.createClient() : factory();
  }

  static String? describeRequestRoute(Uri uri) {
    final builder = _routeLabelBuilder;
    if (builder != null) return builder(uri);
    return LinHttpClientFactory.describeProxyRoute(uri);
  }

  static String _authorizationValue({
    required MediaServerType serverType,
    required String deviceId,
    String? client,
    String device = 'Flutter',
    String? version,
    String? userId,
    String? token,
  }) {
    final v = (version == null || version.trim().isEmpty)
        ? appVersion
        : version.trim();

    final scheme =
        serverType == MediaServerType.jellyfin ? 'MediaBrowser' : 'Emby';

    final clientName = (client == null || client.trim().isEmpty)
        ? defaultClientName
        : client.trim();

    final parts = <String>[
      if (userId != null && userId.trim().isNotEmpty)
        'UserId="${userId.trim()}"',
      'Client="$clientName"',
      'Device="$device"',
      'DeviceId="$deviceId"',
      'Version="$v"',
      if (token != null && token.trim().isNotEmpty) 'Token="${token.trim()}"',
    ];
    return '$scheme ${parts.join(', ')}';
  }

  static Map<String, String> buildAuthorizationHeaders({
    required MediaServerType serverType,
    required String deviceId,
    String? client,
    String device = 'Flutter',
    String? version,
    String? userId,
    String? token,
  }) {
    final value = _authorizationValue(
      serverType: serverType,
      deviceId: deviceId,
      client: client,
      device: device,
      version: version,
      userId: userId,
      token: token,
    );

    // Emby doc uses "Authorization: Emby ...". Jellyfin commonly uses
    // "X-Emby-Authorization: MediaBrowser ...". Keep compatibility with both.
    return switch (serverType) {
      MediaServerType.jellyfin => {
          'X-Emby-Authorization': value,
        },
      _ => {
          'Authorization': value,
          'X-Emby-Authorization': value,
        },
    };
  }

  EmbyApi({
    required String hostOrUrl,
    required String preferredScheme,
    String? port,
    String apiPrefix = 'emby',
    this.serverType = MediaServerType.emby,
    String? deviceId,
    String? clientName,
    String? deviceName,
    http.Client? client,
  })  : _hostOrUrl = hostOrUrl.trim(),
        _preferredScheme = preferredScheme,
        _port = port?.trim(),
        apiPrefix = _normalizeApiPrefix(apiPrefix),
        deviceId = (deviceId == null || deviceId.trim().isEmpty)
            ? _randomId()
            : deviceId.trim(),
        clientName = (clientName == null || clientName.trim().isEmpty)
            ? defaultClientName
            : clientName.trim(),
        deviceName = (deviceName == null || deviceName.trim().isEmpty)
            ? 'Flutter'
            : deviceName.trim(),
        _client = client ?? _defaultClient();

  final String _hostOrUrl;
  final String _preferredScheme;
  final String? _port;
  final String apiPrefix;
  final MediaServerType serverType;
  final String deviceId;
  final String clientName;
  final String deviceName;
  final http.Client _client;

  static String _normalizeApiPrefix(String raw) {
    var v = raw.trim();
    while (v.startsWith('/')) {
      v = v.substring(1);
    }
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  static String _apiUrlWithPrefix(
    String baseUrl,
    String apiPrefix,
    String path,
  ) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    final fixedPrefix = _normalizeApiPrefix(apiPrefix);
    final prefixPart = fixedPrefix.isEmpty ? '' : '/$fixedPrefix';

    final fixedPath =
        path.trim().startsWith('/') ? path.trim() : '/${path.trim()}';
    return '$base$prefixPart$fixedPath';
  }

  String _apiUrl(String baseUrl, String path) {
    return _apiUrlWithPrefix(baseUrl, apiPrefix, path);
  }

  bool _shouldAppendApiKey(String? token) =>
      serverType == MediaServerType.uhd && (token ?? '').trim().isNotEmpty;

  Uri _withApiKey(Uri uri, String token) {
    if (!_shouldAppendApiKey(token)) return uri;
    final query = uri.query;
    if (RegExp(r'(^|&)api_key=', caseSensitive: false).hasMatch(query)) {
      return uri;
    }
    final encoded = Uri.encodeQueryComponent(token.trim());
    final newQuery =
        query.isEmpty ? 'api_key=$encoded' : '$query&api_key=$encoded';
    return uri.replace(query: newQuery);
  }

  Uri _apiUri(String baseUrl, String path, {String? token}) {
    final uri = Uri.parse(_apiUrl(baseUrl, path));
    if (token == null) return uri;
    return _withApiKey(uri, token);
  }

  Uri _apiUriWithPrefix(
    String baseUrl,
    String apiPrefix,
    String path, {
    String? token,
  }) {
    final uri = Uri.parse(_apiUrlWithPrefix(baseUrl, apiPrefix, path));
    if (token == null) return uri;
    return _withApiKey(uri, token);
  }

  // Simple device id generator to satisfy Emby header requirements
  static String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    return List.generate(16, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Map<String, String> _authHeader({
    String? deviceId,
    MediaServerType serverType = MediaServerType.emby,
  }) {
    final id = (deviceId == null || deviceId.trim().isEmpty)
        ? this.deviceId
        : deviceId.trim();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': userAgent,
      ...buildAuthorizationHeaders(
        serverType: serverType,
        deviceId: id,
        client: clientName,
        device: deviceName,
        version: appVersion,
      ),
    };
  }

  Map<String, String> _jsonHeaders({
    required String token,
    String? userId,
    String? deviceId,
    bool includeContentType = false,
  }) {
    final resolvedDeviceId = (deviceId == null || deviceId.trim().isEmpty)
        ? this.deviceId
        : deviceId.trim();
    final headers = <String, String>{
      'X-Emby-Token': token,
      'Accept': 'application/json',
      'User-Agent': userAgent,
      ...buildAuthorizationHeaders(
        serverType: serverType,
        deviceId: resolvedDeviceId,
        client: clientName,
        device: deviceName,
        version: appVersion,
        userId: userId,
      ),
    };
    if (includeContentType) headers['Content-Type'] = 'application/json';
    return headers;
  }

  static Uri _normalizeAuthBase(Uri uri) {
    final segments = uri.pathSegments.toList(growable: true);

    // Users often paste the web UI url: /web or /web/index.html.
    while (segments.isNotEmpty) {
      final last = segments.last.toLowerCase();
      final secondLast = segments.length >= 2
          ? segments[segments.length - 2].toLowerCase()
          : null;

      if (secondLast == 'web' && last == 'index.html') {
        segments.removeLast();
        segments.removeLast();
        continue;
      }
      if (last == 'web') {
        segments.removeLast();
        continue;
      }
      break;
    }

    // Normalize to the "root" before the API prefix. We will try both:
    //   {root}/emby/... (normal deployments)
    //   {root}/emby/emby/... (when server base URL is set to /emby)
    while (segments.isNotEmpty && segments.last.toLowerCase() == 'emby') {
      segments.removeLast();
    }

    final normalizedPath = segments.isEmpty ? '' : '/${segments.join('/')}';
    return uri.replace(path: normalizedPath, query: null, fragment: null);
  }

  static Iterable<String> _expandAuthBaseVariants(String rawBase) sync* {
    final normalized = _normalizeAuthBase(Uri.parse(rawBase));

    // Base without "/emby" suffix.
    yield normalized.toString();

    // Base with one "/emby" suffix. The API paths in this project always add
    // another "/emby", so this makes requests like:
    //   {base}/emby/...  -> /emby/emby/... when baseUrl ends with /emby
    final withEmbySegments = [...normalized.pathSegments, 'emby'];
    final withEmby = normalized.replace(path: '/${withEmbySegments.join('/')}');
    if (withEmby.toString() != normalized.toString()) {
      yield withEmby.toString();
    }
  }

  static String _normalizedCandidateScheme(String raw) {
    final scheme = raw.trim().toLowerCase();
    return scheme == 'http' ? 'http' : 'https';
  }

  static List<String> _expandCandidateBases(Iterable<String> rawBases) {
    final expanded = rawBases
        .map((c) => _expandAuthBaseVariants(c).toList(growable: false))
        .toList(growable: false);

    final seen = <String>{};
    final result = <String>[];
    var maxLen = 0;
    for (final list in expanded) {
      if (list.length > maxLen) maxLen = list.length;
    }
    for (var i = 0; i < maxLen; i++) {
      for (final list in expanded) {
        if (i >= list.length) continue;
        final v = list[i];
        if (seen.add(v)) result.add(v);
      }
    }
    return result;
  }

  List<String> _candidateBasesForHostPath({
    required String host,
    required String path,
    required String preferredScheme,
    String? explicitPort,
  }) {
    final primaryScheme = _normalizedCandidateScheme(preferredScheme);
    final secondaryScheme = primaryScheme == 'http' ? 'https' : 'http';
    final fixedPort = (explicitPort ?? '').trim();
    final fixedPath = (path.isNotEmpty && path != '/') ? path : '';

    String build(String scheme, {String? port}) {
      final fixedScheme = _normalizedCandidateScheme(scheme);
      final fixedPortText = (port ?? '').trim();
      final portPart = fixedPortText.isEmpty ? '' : ':$fixedPortText';
      return '$fixedScheme://$host$portPart$fixedPath';
    }

    if (fixedPort.isNotEmpty) {
      return _expandCandidateBases([build(primaryScheme, port: fixedPort)]);
    }

    return _expandCandidateBases(
        [build(primaryScheme), build(secondaryScheme)]);
  }

  static String _describeSocketException(SocketException e) {
    final raw = e.message.trim();
    final lower = raw.toLowerCase();
    if (lower.contains('failed host lookup') ||
        lower.contains('name or service not known') ||
        lower.contains('nodename nor servname') ||
        lower.contains('no address associated with hostname')) {
      return 'DNS 解析失败 ($raw)';
    }
    if (lower.contains('connection refused')) {
      return '连接被拒绝 ($raw)';
    }
    if (lower.contains('network is unreachable')) {
      return '网络不可达 ($raw)';
    }
    if (lower.contains('timed out')) {
      return '连接超时 ($raw)';
    }
    return '网络异常 ($raw)';
  }

  static String _socketTargetHint(SocketException e) {
    final host = (e.address?.host ?? '').trim();
    final ip = (e.address?.address ?? '').trim();
    final port = e.port ?? 0;

    final parts = <String>[];
    if (host.isNotEmpty) parts.add(host);
    if (ip.isNotEmpty && ip != host) parts.add(ip);

    final endpoint = parts.join('/');
    if (endpoint.isEmpty && port <= 0) return '';
    final portText = port > 0 ? ':$port' : '';
    return ' [socket=${endpoint.isEmpty ? '?' : endpoint}$portText]';
  }

  static String _describeSocketExceptionDetailed(SocketException e) {
    final target = _socketTargetHint(e);
    final message = _describeSocketException(e);
    if (target.isEmpty) return message;
    return '$message$target';
  }

  static String _summarizeAuthErrors(List<String> errors) {
    final unique = <String>[];
    final seen = <String>{};
    for (final entry in errors) {
      final value = entry.trim();
      if (value.isEmpty) continue;
      if (seen.add(value)) unique.add(value);
    }
    if (unique.isEmpty) return '未能连接到服务器';
    if (unique.length == 1) return unique.first;
    return unique.take(2).join(' | ');
  }

  List<String> _candidates() {
    // If user pasted full URL with scheme, honor it first but still allow
    // the usual direct-port fallbacks when no explicit port was provided.
    final parsed = Uri.tryParse(_hostOrUrl);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      final path =
          parsed.path.isNotEmpty && parsed.path != '/' ? parsed.path : '';
      final explicitPort = parsed.hasPort
          ? parsed.port.toString()
          : (_port != null && _port!.trim().isNotEmpty ? _port!.trim() : null);
      return _candidateBasesForHostPath(
        host: parsed.host,
        path: path,
        preferredScheme: parsed.scheme,
        explicitPort: explicitPort,
      );
    }

    // handle host/path form without scheme
    String hostPart = _hostOrUrl;
    String pathPart = '';
    if (_hostOrUrl.contains('/')) {
      final split = _hostOrUrl.split('/');
      hostPart = split.first;
      pathPart = '/${split.skip(1).join('/')}';
    }

    return _candidateBasesForHostPath(
      host: hostPart,
      path: pathPart,
      preferredScheme: _preferredScheme,
      explicitPort: _port,
    );
  }

  Future<AuthResult> authenticate({
    required String username,
    required String password,
    String? deviceId,
    MediaServerType serverType = MediaServerType.emby,
  }) async {
    final errors = <String>[];
    for (final base in _candidates()) {
      final prefixes = switch (serverType) {
        MediaServerType.jellyfin => const ['', 'jellyfin', 'emby'],
        MediaServerType.uhd => const ['', 'emby'],
        _ => const ['emby'],
      };
      for (final prefix in prefixes) {
        final url = Uri.parse(
          _apiUrlWithPrefix(base, prefix, 'Users/AuthenticateByName'),
        );
        final routeHint = describeRequestRoute(url);
        final routeLabel =
            routeHint == null ? '[route=default]' : '[route=$routeHint]';
        final body = jsonEncode({
          'Username': username,
          'Pw': password,
          'Password': password,
        });

        try {
          final resp = await _client
              .post(
                url,
                headers:
                    _authHeader(deviceId: deviceId, serverType: serverType),
                body: body,
              )
              .timeout(const Duration(seconds: 6))
              .catchError((Object error) {
            if (error is SocketException) {
              throw _AuthSocketFailure(
                _describeSocketExceptionDetailed(error),
              );
            }
            throw error;
          });
          if (resp.statusCode != 200) {
            errors.add(
              '${url.toString()} $routeLabel: HTTP ${resp.statusCode}',
            );
            continue;
          }
          final map = jsonDecode(resp.body) as Map<String, dynamic>;
          final token = (map['AccessToken'] ??
                  map['accessToken'] ??
                  map['Token'] ??
                  map['token'])
              ?.toString();
          var userId = '';
          final userObj = map['User'];
          if (userObj is Map) {
            final id = userObj['Id'] ??
                userObj['id'] ??
                userObj['UserId'] ??
                userObj['userId'];
            userId = (id ?? '').toString().trim();
          } else if (userObj != null) {
            userId = userObj.toString().trim();
          }
          if (userId.isEmpty) {
            final id = map['UserId'] ?? map['userId'];
            userId = (id ?? '').toString().trim();
          }
          if ((token ?? '').trim().isEmpty) {
            errors.add('${url.origin}: 未返回 token');
            continue;
          }
          if (userId.isEmpty) {
            userId = (await fetchCurrentUserId(
                  token: token!.trim(),
                  baseUrl: base,
                  apiPrefixOverride: prefix,
                )) ??
                '';
          }
          return AuthResult(
            token: token!.trim(),
            baseUrlUsed: base,
            userId: userId,
            apiPrefixUsed: _normalizeApiPrefix(prefix),
          );
        } catch (e) {
          if (e is _AuthSocketFailure) {
            errors.add('${url.origin} $routeLabel: $e');
            continue;
          }
          if (e is SocketException) {
            errors.add(
              '${url.origin} $routeLabel: ${_describeSocketExceptionDetailed(e)}',
            );
          } else {
            errors.add('${url.origin} $routeLabel: $e');
          }
        }
      }
    }
    throw Exception('登录失败：${_summarizeAuthErrors(errors)}');
  }

  Future<String?> fetchCurrentUserId({
    required String token,
    required String baseUrl,
    String? apiPrefixOverride,
  }) async {
    final fixedToken = token.trim();
    final fixedBase = baseUrl.trim();
    if (fixedToken.isEmpty || fixedBase.isEmpty) return null;

    final prefix = apiPrefixOverride ?? apiPrefix;
    final candidates = <String>[
      'Users/Me',
      'Users/Me?format=json',
    ];

    for (final path in candidates) {
      try {
        final url = _apiUriWithPrefix(
          fixedBase,
          prefix,
          path,
          token: fixedToken,
        );
        final resp = await _client
            .get(
              url,
              headers: _jsonHeaders(token: fixedToken),
            )
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode != 200) continue;
        final decoded = jsonDecode(resp.body);
        final map = decoded is Map ? decoded : null;
        if (map == null) continue;
        final id = (map['Id'] ?? map['id'] ?? map['UserId'] ?? map['userId'])
            ?.toString()
            .trim();
        if (id != null && id.isNotEmpty) return id;
      } catch (_) {
        // best-effort
      }
    }

    return null;
  }

  Future<String?> fetchServerName(
    String baseUrl, {
    String? token,
  }) async {
    final urls = [
      _apiUri(baseUrl, 'System/Info/Public', token: token),
      _apiUri(baseUrl, 'System/Info', token: token),
    ];

    for (final url in urls) {
      try {
        final headers = <String, String>{
          'Accept': 'application/json',
          'User-Agent': userAgent,
          ...buildAuthorizationHeaders(
            serverType: serverType,
            deviceId: deviceId,
            client: clientName,
            device: deviceName,
            version: appVersion,
          ),
          if (token != null && token.trim().isNotEmpty)
            'X-Emby-Token': token.trim(),
        };
        final resp = await _client.get(url, headers: headers);
        if (resp.statusCode != 200) continue;
        final map = jsonDecode(resp.body);
        if (map is! Map) continue;
        final name =
            (map['ServerName'] ?? map['Name'] ?? map['ApplicationName'])
                ?.toString();
        if (name != null && name.trim().isNotEmpty) {
          return name.trim();
        }
      } catch (_) {
        // best-effort
      }
    }

    return null;
  }

  Future<List<DomainInfo>> fetchDomains(
    String token,
    String baseUrl, {
    bool allowFailure = true,
  }) async {
    final url = _apiUri(baseUrl, 'System/Ext/ServerDomains', token: token);
    try {
      final resp = await _client.get(url, headers: {
        ..._jsonHeaders(token: token),
      });
      if (resp.statusCode != 200) {
        if (allowFailure) return [];
        throw Exception('拉取线路失败（${resp.statusCode}）');
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (map['data'] as List<dynamic>? ?? [])
          .map((e) => DomainInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (e) {
      if (allowFailure) return [];
      rethrow;
    }
  }

  Future<List<LibraryInfo>> fetchLibraries({
    required String token,
    required String baseUrl,
    required String userId,
  }) async {
    // Emby 官方推荐获取视图的接口：/Users/{userId}/Views
    final url = _apiUri(baseUrl, 'Users/$userId/Views', token: token);
    final resp = await _client.get(
      url,
      headers: _jsonHeaders(token: token, userId: userId),
    );
    if (resp.statusCode != 200) {
      throw Exception('拉取媒体库失败（${resp.statusCode}）');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (map['Items'] as List<dynamic>? ?? [])
        .map((e) => LibraryInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<ItemCounts> fetchItemCounts({
    required String token,
    required String baseUrl,
    required String userId,
  }) async {
    final candidates = <String>[
      'Items/Counts?UserId=$userId',
      'Users/$userId/Items/Counts',
    ];

    http.Response? lastResp;
    for (final path in candidates) {
      try {
        final url = _apiUri(baseUrl, path, token: token);
        final resp = await _client.get(url,
            headers: _jsonHeaders(token: token, userId: userId));
        lastResp = resp;
        if (resp.statusCode != 200) continue;
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        return ItemCounts.fromJson(map);
      } catch (_) {
        continue;
      }
    }

    final code = lastResp?.statusCode;
    throw Exception('获取媒体统计失败${code == null ? '' : '（$code）'}');
  }

  Future<PagedResult<MediaItem>> fetchItems({
    required String token,
    required String baseUrl,
    required String userId,
    String? parentId,
    int startIndex = 0,
    int limit = 30,
    String? includeItemTypes,
    String? searchTerm,
    bool recursive = false,
    bool excludeFolders = true,
    String? sortBy,
    String sortOrder = 'Descending',
    String? fields,
    List<String>? genres,
    List<int>? years,
    List<String>? personIds,
    double? minCommunityRating,
    bool? isPlayed,
    bool? isFavorite,
    List<String>? seriesStatus,
  }) async {
    final resolvedFields = (fields == null || fields.trim().isEmpty)
        ? 'Overview,ParentId,ParentIndexNumber,IndexNumber,SeriesName,SeasonName,ImageTags,PrimaryImageTag,ThumbImageTag,ParentThumbImageTag,SeriesPrimaryImageTag,BackdropImageTags,PrimaryImageAspectRatio,RunTimeTicks,Size,Container,Genres,Tags,CommunityRating,PremiereDate,ProductionYear,Status,UserData'
        : fields.trim();
    final params = <String>[
      if (parentId != null && parentId.isNotEmpty) 'ParentId=$parentId',
      'Fields=$resolvedFields',
      'StartIndex=$startIndex',
      'Limit=$limit',
      'Recursive=$recursive',
    ];
    if (excludeFolders) {
      params.add('Filters=IsNotFolder');
    }
    if (includeItemTypes != null) {
      params.add('IncludeItemTypes=$includeItemTypes');
    }
    final resolvedGenres = genres
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (resolvedGenres != null && resolvedGenres.isNotEmpty) {
      params.add('Genres=${Uri.encodeComponent(resolvedGenres.join('|'))}');
    }
    final resolvedYears =
        years?.where((value) => value > 0).toSet().toList(growable: false);
    if (resolvedYears != null && resolvedYears.isNotEmpty) {
      resolvedYears.sort();
      params.add('Years=${resolvedYears.join(',')}');
    }
    final resolvedPersonIds = personIds
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (resolvedPersonIds != null && resolvedPersonIds.isNotEmpty) {
      params
          .add('PersonIds=${Uri.encodeComponent(resolvedPersonIds.join(','))}');
    }
    if (sortBy != null && sortBy.isNotEmpty) {
      params.addAll(['SortBy=$sortBy', 'SortOrder=$sortOrder']);
    }
    if (searchTerm != null && searchTerm.isNotEmpty) {
      params.add('SearchTerm=${Uri.encodeComponent(searchTerm)}');
    }
    if (minCommunityRating != null) {
      params.add('MinCommunityRating=$minCommunityRating');
    }
    if (isPlayed != null) {
      params.add('IsPlayed=$isPlayed');
    }
    if (isFavorite != null) {
      params.add('IsFavorite=$isFavorite');
    }
    final resolvedSeriesStatus = seriesStatus
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (resolvedSeriesStatus != null && resolvedSeriesStatus.isNotEmpty) {
      resolvedSeriesStatus
          .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      params.add(
        'SeriesStatus=${Uri.encodeComponent(resolvedSeriesStatus.join(','))}',
      );
    }
    final url = _apiUri(baseUrl, 'Users/$userId/Items?${params.join('&')}',
        token: token);
    final resp = await _client.get(url,
        headers: _jsonHeaders(token: token, userId: userId));
    if (resp.statusCode != 200) {
      throw Exception('拉取媒体列表失败（${resp.statusCode}）');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (map['Items'] as List<dynamic>? ?? [])
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = map['TotalRecordCount'] as int? ?? items.length;
    return PagedResult(items, total);
  }

  Future<List<String>> fetchAvailableGenres({
    required String token,
    required String baseUrl,
    required String userId,
    String? parentId,
    String? includeItemTypes,
    bool recursive = true,
  }) async {
    final filters = await fetchAvailableFilters(
      token: token,
      baseUrl: baseUrl,
      userId: userId,
      parentId: parentId,
      includeItemTypes: includeItemTypes,
      recursive: recursive,
    );
    return filters.genres;
  }

  Future<LibraryFilterOptions> fetchAvailableFilters({
    required String token,
    required String baseUrl,
    required String userId,
    String? parentId,
    String? includeItemTypes,
    bool recursive = true,
  }) async {
    final resolvedParentId = (parentId ?? '').trim();
    final resolvedTypes = (includeItemTypes ?? '').trim();

    final params = <String>[
      'UserId=$userId',
      if (resolvedParentId.isNotEmpty)
        'ParentId=${Uri.encodeComponent(resolvedParentId)}',
      if (resolvedTypes.isNotEmpty)
        'IncludeItemTypes=${Uri.encodeComponent(resolvedTypes)}',
      'Recursive=$recursive',
    ];

    final paramsWithoutUserId = params
        .where((p) => !p.trim().toLowerCase().startsWith('userid='))
        .toList(growable: false);

    final candidates = <String>[
      'Items/Filters?${params.join('&')}',
      'Users/$userId/Items/Filters?${paramsWithoutUserId.join('&')}',
      // Some servers expose genres as a separate endpoint. Try this as a
      // fallback, so the genre filter UI does not need to page through Items.
      'Genres?${params.join('&')}',
      'Users/$userId/Genres?${paramsWithoutUserId.join('&')}',
    ];

    http.Response? lastResp;
    Object? lastError;
    var sawSuccess200 = false;
    var bestGenres = const <String>[];
    var bestYears = const <int>[];
    for (final path in candidates) {
      try {
        final url = _apiUri(baseUrl, path, token: token);
        final resp = await _client.get(
          url,
          headers: _jsonHeaders(token: token, userId: userId),
        );
        lastResp = resp;
        if (resp.statusCode != 200) continue;
        sawSuccess200 = true;

        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        final lowerPath = path.toLowerCase();
        final isGenreEndpoint = lowerPath.contains('genres');
        final genres = _normalizeStringList(
          map['Genres'] ??
              map['genres'] ??
              map['GenreItems'] ??
              map['genreItems'] ??
              (isGenreEndpoint ? (map['Items'] ?? map['items']) : null),
        );
        if (bestGenres.isEmpty && genres.isNotEmpty) bestGenres = genres;

        final years = _normalizeIntList(
          map['Years'] ??
              map['years'] ??
              map['ProductionYears'] ??
              map['productionYears'],
        );
        if (bestYears.isEmpty && years.isNotEmpty) bestYears = years;

        if (bestGenres.isNotEmpty && bestYears.isNotEmpty) {
          return LibraryFilterOptions(genres: bestGenres, years: bestYears);
        }
      } catch (e) {
        lastError = e;
        continue;
      }
    }

    if (sawSuccess200) {
      return LibraryFilterOptions(genres: bestGenres, years: bestYears);
    }

    final code = lastResp?.statusCode;
    final suffix = code == null ? '' : ' ($code)';
    if (lastError != null) {
      throw Exception('Failed to fetch filters$suffix: $lastError');
    }
    throw Exception('Failed to fetch filters$suffix');
  }

  Future<PagedResult<MediaItem>> fetchRandomRecommendations({
    required String token,
    required String baseUrl,
    required String userId,
    int limit = 6,
    String includeItemTypes = 'Movie,Series',
  }) {
    return fetchItems(
      token: token,
      baseUrl: baseUrl,
      userId: userId,
      includeItemTypes: includeItemTypes,
      limit: limit,
      recursive: true,
      sortBy: 'Random',
      sortOrder: 'Ascending',
    );
  }

  Future<PagedResult<MediaItem>> fetchSeasons({
    required String token,
    required String baseUrl,
    required String userId,
    required String seriesId,
  }) async {
    if (serverType == MediaServerType.uhd) {
      final url = _apiUri(baseUrl, 'Shows/$seriesId/Seasons', token: token);
      final resp = await _client.get(
        url,
        headers: _jsonHeaders(token: token, userId: userId),
      );
      if (resp.statusCode != 200) {
        throw Exception('Failed to fetch seasons (${resp.statusCode})');
      }
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      final rawItems = (map['Items'] as List<dynamic>?) ??
          (map['items'] as List<dynamic>?) ??
          const <dynamic>[];
      final items = rawItems
          .whereType<Map>()
          .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final total = map['TotalRecordCount'] as int? ?? items.length;
      return PagedResult(items, total);
    }

    return fetchItems(
      token: token,
      baseUrl: baseUrl,
      userId: userId,
      parentId: seriesId,
      includeItemTypes: 'Season',
      excludeFolders: false,
      limit: 100,
      sortBy: 'SortName',
      sortOrder: 'Ascending',
    );
  }

  Future<PagedResult<MediaItem>> fetchEpisodes({
    required String token,
    required String baseUrl,
    required String userId,
    required String seasonId,
  }) {
    return fetchItems(
      token: token,
      baseUrl: baseUrl,
      userId: userId,
      parentId: seasonId,
      includeItemTypes: 'Episode',
      limit: 200,
      sortBy: 'IndexNumber',
      sortOrder: 'Ascending',
    );
  }

  Future<PagedResult<MediaItem>> fetchContinueWatching({
    required String token,
    required String baseUrl,
    required String userId,
    int limit = 30,
  }) async {
    final url = _apiUri(
      baseUrl,
      'Users/$userId/Items'
      '?Filters=IsResumable'
      '&IncludeItemTypes=Episode,Movie'
      '&Recursive=true'
      '&SortBy=DatePlayed'
      '&SortOrder=Descending'
      '&Limit=$limit'
      '&Fields=Overview,ParentId,SeriesId,ParentIndexNumber,IndexNumber,SeriesName,SeasonName,ImageTags,PrimaryImageTag,ThumbImageTag,ParentThumbImageTag,SeriesPrimaryImageTag,BackdropImageTags,UserData',
      token: token,
    );
    final resp = await _client.get(url,
        headers: _jsonHeaders(token: token, userId: userId));
    if (resp.statusCode != 200) {
      throw Exception('获取继续观看失败（${resp.statusCode}）');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final parsed = (map['Items'] as List<dynamic>? ?? [])
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // Prefer items with real progress. Some servers may omit UserData (or return 0)
    // even when `IsResumable` is requested; in that case, keep the raw list.
    final withProgress =
        parsed.where((e) => e.playbackPositionTicks > 0).toList();
    final items = withProgress.isNotEmpty ? withProgress : parsed;
    final total = map['TotalRecordCount'] as int? ?? items.length;
    return PagedResult(items, total);
  }

  Future<PagedResult<MediaItem>> fetchNextUp({
    required String token,
    required String baseUrl,
    required String userId,
    int limit = 30,
    String? seriesId,
  }) async {
    final resolvedSeriesId = (seriesId ?? '').trim();
    final url = _apiUri(
      baseUrl,
      'Shows/NextUp'
      '?UserId=$userId'
      '&Limit=$limit'
      '${resolvedSeriesId.isEmpty ? '' : '&SeriesId=${Uri.encodeComponent(resolvedSeriesId)}'}'
      '&EnableUserData=true'
      '&EnableImages=true'
      '&ImageTypeLimit=1'
      '&EnableImageTypes=Primary,Thumb,Backdrop'
      '&Fields=Overview,ParentId,ProviderIds',
      token: token,
    );
    final resp = await _client.get(url,
        headers: _jsonHeaders(token: token, userId: userId));
    if (resp.statusCode != 200) {
      throw Exception('FetchNextUp failed (${resp.statusCode})');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (map['Items'] as List<dynamic>? ?? [])
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = map['TotalRecordCount'] as int? ?? items.length;
    return PagedResult(items, total);
  }

  Future<PagedResult<MediaItem>> fetchLatestMovies({
    required String token,
    required String baseUrl,
    required String userId,
    int limit = 30,
  }) =>
      fetchItems(
        token: token,
        baseUrl: baseUrl,
        userId: userId,
        parentId:
            userId, // Emby ignores ParentId when searching latest with types
        includeItemTypes: 'Movie',
        limit: limit,
        startIndex: 0,
        searchTerm: null,
      );

  Future<PagedResult<MediaItem>> fetchLatestEpisodes({
    required String token,
    required String baseUrl,
    required String userId,
    int limit = 30,
  }) =>
      fetchItems(
        token: token,
        baseUrl: baseUrl,
        userId: userId,
        parentId: userId,
        includeItemTypes: 'Episode',
        limit: limit,
        startIndex: 0,
        searchTerm: null,
      );

  Future<PagedResult<MediaItem>> fetchLatestFromLibrary({
    required String token,
    required String baseUrl,
    required String userId,
    required String libraryId,
    int limit = 12,
    bool onlyEpisodes = true,
  }) async {
    final url = _apiUri(
      baseUrl,
      'Users/$userId/Items'
      '?ParentId=$libraryId'
      '&IncludeItemTypes=${onlyEpisodes ? 'Episode' : 'Episode,Movie'}'
      '&Recursive=true'
      '&SortBy=DateCreated'
      '&SortOrder=Descending'
      '&Fields=Overview,ParentId,ParentIndexNumber,IndexNumber,SeriesName,SeasonName,ImageTags,PrimaryImageTag,ThumbImageTag,ParentThumbImageTag,SeriesPrimaryImageTag,BackdropImageTags,UserData'
      '&Limit=$limit',
      token: token,
    );
    final resp = await _client.get(url, headers: {
      ..._jsonHeaders(token: token, userId: userId),
    });
    if (resp.statusCode != 200) {
      throw Exception('获取库最新内容失败（${resp.statusCode}）');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (map['Items'] as List<dynamic>? ?? [])
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = map['TotalRecordCount'] as int? ?? items.length;
    return PagedResult(items, total);
  }

  Future<PlaybackInfoResult> fetchPlaybackInfo({
    required String token,
    required String baseUrl,
    required String userId,
    required String deviceId,
    required String itemId,
    bool exoPlayer = false,
  }) async {
    final profileName = exoPlayer ? '$clientName-Exo' : clientName;
    final deviceProfile = exoPlayer
        ? {
            "Name": profileName,
            "MaxStreamingBitrate": 120000000,
            "DirectPlayProfiles": [
              {
                "Container": "mp4,mkv,mov,avi,ts,flv,webm",
                "Type": "Video",
                "AudioCodec": "aac,mp3",
              },
              {
                "Container": "mp3,aac,m4a",
                "Type": "Audio",
                "AudioCodec": "aac,mp3",
              },
            ],
            "TranscodingProfiles": [
              {
                "Container": "ts",
                "Type": "Video",
                "Protocol": "hls",
                "VideoCodec": "h264",
                "AudioCodec": "aac",
                "Context": "Streaming",
              },
            ],
            "DeviceId": deviceId,
          }
        : {
            "Name": profileName,
            "MaxStreamingBitrate": 120000000,
            "DirectPlayProfiles": [
              {"Container": "mp4,mkv,mov,avi,ts,flv,webm", "Type": "Video"},
              {"Container": "mp3,aac,flac,wav,ogg", "Type": "Audio"}
            ],
            "TranscodingProfiles": [],
            "DeviceId": deviceId,
          };

    Future<http.Response> postReq() => _client.post(
          _apiUri(baseUrl, 'Items/$itemId/PlaybackInfo', token: token),
          headers: _jsonHeaders(
            token: token,
            userId: userId,
            deviceId: deviceId,
            includeContentType: true,
          ),
          body: jsonEncode({
            'UserId': userId,
            'DeviceProfile': deviceProfile,
          }),
        );
    Future<http.Response> getReq() => _client.get(
          _apiUri(
            baseUrl,
            'Items/$itemId/PlaybackInfo?UserId=$userId&DeviceId=$deviceId',
            token: token,
          ),
          headers:
              _jsonHeaders(token: token, userId: userId, deviceId: deviceId),
        );

    // For ExoPlayer we must POST with DeviceProfile, otherwise the server may
    // return a direct-play URL for an audio codec Exo can't decode (video-only).
    http.Response resp = exoPlayer ? await postReq() : await getReq();
    if (exoPlayer && resp.statusCode != 200) {
      // Some servers/proxies only allow GET on this endpoint.
      resp = await getReq();
      if (resp.statusCode >= 500 || resp.statusCode == 404) {
        resp = await postReq();
      }
    } else if (!exoPlayer &&
        (resp.statusCode >= 500 || resp.statusCode == 404)) {
      resp = await postReq();
    }
    if (resp.statusCode != 200) {
      throw Exception('获取播放信息失败(${resp.statusCode})');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    var session = map['PlaySessionId'] as String? ?? '';
    var sources = (map['MediaSources'] as List?) ?? [];

    if (session.isEmpty || sources.isEmpty) {
      // Fallback: some servers return 200 but require POST body to include DeviceProfile.
      final resp2 = await postReq();
      if (resp2.statusCode == 200) {
        final map2 = jsonDecode(resp2.body) as Map<String, dynamic>;
        session = map2['PlaySessionId'] as String? ?? '';
        sources = (map2['MediaSources'] as List?) ?? [];
      }
    }
    if (session.isEmpty || sources.isEmpty) {
      throw Exception('播放信息缺失');
    }
    final ms = sources.first as Map<String, dynamic>;
    final mediaSourceId = ms['Id'] as String? ?? itemId;
    return PlaybackInfoResult(
      playSessionId: session,
      mediaSourceId: mediaSourceId,
      mediaSources: sources,
    );
  }

  Future<void> reportPlaybackStart({
    required String token,
    required String baseUrl,
    required String deviceId,
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
    bool isPaused = false,
    String? userId,
  }) async {
    await _postPlaybackEvent(
      token: token,
      baseUrl: baseUrl,
      deviceId: deviceId,
      userId: userId,
      path: 'Sessions/Playing',
      body: <String, dynamic>{
        if (userId != null && userId.isNotEmpty) 'UserId': userId,
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PlaySessionId': playSessionId,
        'PositionTicks': positionTicks,
        'IsPaused': isPaused,
        'CanSeek': true,
      },
    );
  }

  Future<void> reportPlaybackProgress({
    required String token,
    required String baseUrl,
    required String deviceId,
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
    bool isPaused = false,
    String? userId,
  }) async {
    await _postPlaybackEvent(
      token: token,
      baseUrl: baseUrl,
      deviceId: deviceId,
      userId: userId,
      path: 'Sessions/Playing/Progress',
      body: <String, dynamic>{
        if (userId != null && userId.isNotEmpty) 'UserId': userId,
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PlaySessionId': playSessionId,
        'PositionTicks': positionTicks,
        'IsPaused': isPaused,
        'CanSeek': true,
        'EventName': 'TimeUpdate',
      },
    );
  }

  Future<void> reportPlaybackStopped({
    required String token,
    required String baseUrl,
    required String deviceId,
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
    String? userId,
  }) async {
    await _postPlaybackEvent(
      token: token,
      baseUrl: baseUrl,
      deviceId: deviceId,
      userId: userId,
      path: 'Sessions/Playing/Stopped',
      body: <String, dynamic>{
        if (userId != null && userId.isNotEmpty) 'UserId': userId,
        'ItemId': itemId,
        'MediaSourceId': mediaSourceId,
        'PlaySessionId': playSessionId,
        'PositionTicks': positionTicks,
      },
    );
  }

  Future<void> updatePlaybackPosition({
    required String token,
    required String baseUrl,
    required String userId,
    required String itemId,
    required int positionTicks,
    bool? played,
  }) async {
    final url =
        _apiUri(baseUrl, 'Users/$userId/Items/$itemId/UserData', token: token);
    final body = <String, dynamic>{
      'PlaybackPositionTicks': positionTicks,
      if (played != null) 'Played': played,
    };
    final resp = await _client.post(
      url,
      headers: _jsonHeaders(
        token: token,
        userId: userId,
        includeContentType: true,
      ),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('UpdateUserData failed (${resp.statusCode})');
    }
  }

  Future<void> _postPlaybackEvent({
    required String token,
    required String baseUrl,
    required String deviceId,
    String? userId,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final resp = await _client.post(
      _apiUri(baseUrl, path, token: token),
      headers: _jsonHeaders(
        token: token,
        userId: userId,
        deviceId: deviceId,
        includeContentType: true,
      ),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw Exception('PlaybackEvent failed ($path, ${resp.statusCode})');
    }
  }

  Future<MediaItem> fetchItemDetail({
    required String token,
    required String baseUrl,
    required String userId,
    required String itemId,
  }) async {
    final url = _apiUri(
      baseUrl,
      'Users/$userId/Items/$itemId'
      '?Fields=Overview,ParentId,ParentIndexNumber,IndexNumber,SeriesName,SeasonName,ImageTags,PrimaryImageTag,ThumbImageTag,ParentThumbImageTag,SeriesPrimaryImageTag,BackdropImageTags,UserData,ProviderIds,CommunityRating,PremiereDate,ProductionYear,Genres,People,RunTimeTicks,Size,Container',
      token: token,
    );
    final resp = await _client.get(url,
        headers: _jsonHeaders(token: token, userId: userId));
    if (resp.statusCode != 200) {
      throw Exception('获取详情失败(${resp.statusCode})');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return MediaItem.fromJson(map);
  }

  static String imageUrl({
    required String baseUrl,
    required String itemId,
    required String token,
    String apiPrefix = 'emby',
    String imageType = 'Primary',
    int? maxWidth,
  }) {
    final mw = maxWidth != null ? '&maxWidth=$maxWidth' : '';
    return _apiUrlWithPrefix(
      baseUrl,
      apiPrefix,
      'Items/$itemId/Images/$imageType?quality=90$mw&api_key=$token',
    );
  }

  static String personImageUrl({
    required String baseUrl,
    required String personId,
    required String token,
    String apiPrefix = 'emby',
    int? maxWidth,
  }) {
    final mw = maxWidth != null ? '&maxWidth=$maxWidth' : '';
    return _apiUrlWithPrefix(
      baseUrl,
      apiPrefix,
      'Items/$personId/Images/Primary?quality=90$mw&api_key=$token',
    );
  }

  Future<List<ChapterInfo>> fetchChapters({
    required String token,
    required String baseUrl,
    required String itemId,
    String? userId,
  }) async {
    final url = _apiUri(baseUrl, 'Items/$itemId/Chapters', token: token);
    final resp = await _client.get(url,
        headers: _jsonHeaders(token: token, userId: userId));
    // 404 means the item has no chapters on many servers.
    if (resp.statusCode == 404) {
      return const [];
    }
    if (resp.statusCode != 200) {
      throw Exception('获取章节失败(${resp.statusCode})');
    }
    final list = (jsonDecode(resp.body)['Items'] as List?) ?? [];
    return list
        .map((e) => ChapterInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<IntroTimestamps?> fetchIntroTimestamps({
    required String token,
    required String baseUrl,
    required String itemId,
    String? userId,
  }) async {
    final headers = _jsonHeaders(token: token, userId: userId);
    final uid = (userId ?? '').trim();

    Uri withUser(Uri uri) {
      if (uid.isEmpty) return uri;
      final params = <String, String>{...uri.queryParameters, 'UserId': uid};
      return uri.replace(queryParameters: params);
    }

    final candidates = [
      'Episodes/$itemId/IntroTimestamps',
      'Items/$itemId/IntroTimestamps',
      'Videos/$itemId/IntroTimestamps',
    ];

    for (final path in candidates) {
      final uri = withUser(_apiUri(baseUrl, path, token: token));
      final resp = await _client.get(uri, headers: headers);
      if (resp.statusCode == 404) continue;
      if (resp.statusCode == 204) return null;
      if (resp.statusCode != 200) {
        throw Exception('获取片头信息失败(${resp.statusCode})');
      }
      final decoded = jsonDecode(resp.body);
      final map = decoded is Map<String, dynamic> ? decoded : null;
      if (map == null) return null;
      return IntroTimestamps.tryParse(map);
    }

    return null;
  }

  Future<PagedResult<MediaItem>> fetchSimilar({
    required String token,
    required String baseUrl,
    required String userId,
    required String itemId,
    int limit = 10,
  }) async {
    final url = _apiUri(
      baseUrl,
      'Users/$userId/Items/$itemId/Similar?Limit=$limit&Fields=Overview,ImageTags,PrimaryImageTag,ThumbImageTag,SeriesPrimaryImageTag,BackdropImageTags,ProviderIds,CommunityRating,Genres,ProductionYear',
      token: token,
    );
    final resp = await _client.get(url,
        headers: _jsonHeaders(token: token, userId: userId));
    if (resp.statusCode == 404) {
      return PagedResult(const [], 0);
    }
    if (resp.statusCode != 200) {
      throw Exception('获取相似条目失败(${resp.statusCode})');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (map['Items'] as List<dynamic>? ?? [])
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = map['TotalRecordCount'] as int? ?? items.length;
    return PagedResult(items, total);
  }
}
