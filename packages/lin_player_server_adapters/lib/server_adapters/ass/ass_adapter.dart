import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';
import 'package:lin_player_server_api/services/ass_api.dart';
import 'package:lin_player_server_api/services/emby_api.dart';

import '../server_adapter.dart';

class AssServerAdapter implements MediaServerAdapter {
  AssServerAdapter({required this.serverType, required this.deviceId});

  @override
  final MediaServerType serverType;

  @override
  final String deviceId;

  @override
  Map<String, String> buildStreamHeaders(ServerAuthSession auth) {
    final token = auth.token.trim();
    if (token.isEmpty) {
      return <String, String>{
        'User-Agent': LinHttpClientFactory.userAgent,
      };
    }

    // The upstream OpenAPI spec does not define auth headers. We try a few
    // common patterns (safe even if ignored by the server).
    return <String, String>{
      'User-Agent': LinHttpClientFactory.userAgent,
      'Authorization': 'Bearer $token',
      'X-Token': token,
      'Cookie': 'token=$token',
    };
  }

  @override
  String imageUrl(
    ServerAuthSession auth, {
    required String itemId,
    String imageType = 'Primary',
    int? maxWidth,
  }) {
    throw UnimplementedError('ASS adapter does not provide Emby item images');
  }

  @override
  String personImageUrl(
    ServerAuthSession auth, {
    required String personId,
    int? maxWidth,
  }) {
    throw UnimplementedError('ASS adapter does not provide person images');
  }

  static String _normalizeBaseUrl(Uri uri) {
    final segments = uri.pathSegments
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: true);
    while (segments.isNotEmpty && segments.last.toLowerCase() == 'api') {
      segments.removeLast();
    }
    final path = segments.isEmpty ? '' : '/${segments.join('/')}';
    return uri.replace(path: path, query: null, fragment: null).toString();
  }

  static Iterable<String> _candidateBaseUrls({
    required String hostOrUrl,
    required String scheme,
    String? port,
  }) sync* {
    final raw = hostOrUrl.trim();
    if (raw.isEmpty) throw const FormatException('Missing hostOrUrl');

    final parsed = Uri.tryParse(raw);
    if (parsed != null &&
        parsed.hasScheme &&
        parsed.host.isNotEmpty &&
        (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      final effective = port != null && port.trim().isNotEmpty && !parsed.hasPort
          ? parsed.replace(port: int.tryParse(port.trim()) ?? parsed.port)
          : parsed;
      yield _normalizeBaseUrl(effective);
      return;
    }

    var hostPart = raw;
    var pathPart = '';
    if (raw.contains('/')) {
      final idx = raw.indexOf('/');
      hostPart = raw.substring(0, idx);
      pathPart = raw.substring(idx);
    }

    final fixedPort = (port ?? '').trim();
    final primaryScheme =
        scheme.trim().toLowerCase() == 'http' ? 'http' : 'https';
    final fallbackScheme = primaryScheme == 'http' ? 'https' : 'http';
    final schemes = <String>[primaryScheme, fallbackScheme];

    for (final s in schemes) {
      final base = fixedPort.isEmpty
          ? '$s://$hostPart$pathPart'
          : '$s://$hostPart:$fixedPort$pathPart';
      final uri = Uri.tryParse(base);
      if (uri == null || uri.host.isEmpty) continue;
      yield _normalizeBaseUrl(uri);
    }
  }

  @override
  Future<ServerAuthSession> authenticate({
    required String hostOrUrl,
    required String scheme,
    String? port,
    required String username,
    required String password,
  }) async {
    final errors = <String>[];
    final fixedUsername = username.trim();
    if (fixedUsername.isEmpty) {
      throw const FormatException('Missing username');
    }
    for (final base in _candidateBaseUrls(
      hostOrUrl: hostOrUrl,
      scheme: scheme,
      port: port,
    )) {
      try {
        final api = AssApi(baseUrl: base);
        final token = await api.login(
          username: fixedUsername,
          password: password,
        );
        final preferredScheme =
            Uri.tryParse(base)?.scheme.trim().toLowerCase() == 'http'
                ? 'http'
                : 'https';
        return ServerAuthSession(
          token: token,
          baseUrl: base,
          userId: fixedUsername,
          apiPrefix: '',
          preferredScheme: preferredScheme,
        );
      } catch (e) {
        errors.add('$base: $e');
      }
    }
    if (errors.isEmpty) {
      throw AssApiException('No candidate base url');
    }
    throw AssApiException(errors.join('\n'));
  }

  @override
  Future<String?> fetchServerName(ServerAuthSession auth) async {
    return null;
  }

  @override
  Future<List<DomainInfo>> fetchDomains(
    ServerAuthSession auth, {
    required bool allowFailure,
  }) async {
    return const <DomainInfo>[];
  }

  @override
  Future<List<LibraryInfo>> fetchLibraries(ServerAuthSession auth) async {
    return const <LibraryInfo>[];
  }

  @override
  Future<PagedResult<MediaItem>> fetchItems(
    ServerAuthSession auth, {
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
  }) {
    throw UnimplementedError('ASS adapter does not support Emby media browsing');
  }

  @override
  Future<List<String>> fetchAvailableGenres(
    ServerAuthSession auth, {
    String? parentId,
    String? includeItemTypes,
    bool recursive = true,
  }) {
    throw UnimplementedError('ASS adapter does not support library filters');
  }

  @override
  Future<LibraryFilterOptions> fetchAvailableFilters(
    ServerAuthSession auth, {
    String? parentId,
    String? includeItemTypes,
    bool recursive = true,
  }) {
    throw UnimplementedError('ASS adapter does not support library filters');
  }

  @override
  Future<PagedResult<MediaItem>> fetchContinueWatching(
    ServerAuthSession auth, {
    int limit = 30,
  }) {
    throw UnimplementedError('ASS adapter does not support continue watching');
  }

  @override
  Future<MediaItem> fetchItemDetail(
    ServerAuthSession auth, {
    required String itemId,
  }) {
    throw UnimplementedError('ASS adapter does not support item details');
  }

  @override
  Future<PagedResult<MediaItem>> fetchSeasons(
    ServerAuthSession auth, {
    required String seriesId,
  }) {
    throw UnimplementedError('ASS adapter does not support seasons');
  }

  @override
  Future<PagedResult<MediaItem>> fetchEpisodes(
    ServerAuthSession auth, {
    required String seasonId,
  }) {
    throw UnimplementedError('ASS adapter does not support episodes');
  }

  @override
  Future<PagedResult<MediaItem>> fetchSimilar(
    ServerAuthSession auth, {
    required String itemId,
    int limit = 10,
  }) {
    throw UnimplementedError('ASS adapter does not support similar items');
  }

  @override
  Future<PlaybackInfoResult> fetchPlaybackInfo(
    ServerAuthSession auth, {
    required String itemId,
    bool exoPlayer = false,
  }) {
    throw UnimplementedError('ASS adapter does not support playback info');
  }

  @override
  Future<List<ChapterInfo>> fetchChapters(
    ServerAuthSession auth, {
    required String itemId,
  }) {
    throw UnimplementedError('ASS adapter does not support chapters');
  }

  @override
  Future<IntroTimestamps?> fetchIntroTimestamps(
    ServerAuthSession auth, {
    required String itemId,
  }) {
    throw UnimplementedError('ASS adapter does not support intro detection');
  }

  @override
  Future<void> reportPlaybackStart(
    ServerAuthSession auth, {
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
    bool isPaused = false,
  }) {
    throw UnimplementedError('ASS adapter does not support playback reporting');
  }

  @override
  Future<void> reportPlaybackProgress(
    ServerAuthSession auth, {
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
    bool isPaused = false,
  }) {
    throw UnimplementedError('ASS adapter does not support playback reporting');
  }

  @override
  Future<void> reportPlaybackStopped(
    ServerAuthSession auth, {
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required int positionTicks,
  }) {
    throw UnimplementedError('ASS adapter does not support playback reporting');
  }

  @override
  Future<void> updatePlaybackPosition(
    ServerAuthSession auth, {
    required String itemId,
    required int positionTicks,
    bool? played,
  }) {
    throw UnimplementedError('ASS adapter does not support playback reporting');
  }
}
