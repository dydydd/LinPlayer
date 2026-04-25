import 'package:lin_player_server_api/services/emby_api.dart';

import '../lin/lin_emby_adapter.dart';
import '../server_adapter.dart';

class UhdEmbyLikeAdapter extends LinEmbyAdapter {
  UhdEmbyLikeAdapter({required super.serverType, required super.deviceId});

  static final RegExp _ulidRegex = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');

  static bool _looksLikeUlid(String input) => _ulidRegex.hasMatch(input.trim());

  static bool _looksLikeUhdItemId(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return false;
    if (_looksLikeUlid(v)) return true;
    if (v.length == 27 && _looksLikeUlid(v.substring(1))) return true;
    return false;
  }

  static String _normalizeImageId(String itemId) {
    final id = itemId.trim();
    if (id.length == 27 && _looksLikeUlid(id.substring(1))) {
      return id.substring(1);
    }
    return id;
  }

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

  static String _effectiveStreamApiPrefix(ServerAuthSession auth) {
    final configured = _normalizeApiPrefix(auth.apiPrefix);
    final desired = configured.isEmpty ? 'emby' : configured;

    final baseUri = Uri.tryParse(auth.baseUrl.trim());
    if (baseUri == null) return desired;
    final segments =
        baseUri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty) return desired;

    final last = segments.last.toLowerCase();
    if (last == desired.toLowerCase()) return '';
    return desired;
  }

  static String _effectiveAssetBaseUrl(ServerAuthSession auth) {
    final raw = auth.baseUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;

    final segments = uri.pathSegments.toList(growable: true);

    // Users sometimes paste the web UI url: /web or /web/index.html.
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

    // Assets are hosted at the root (without /emby suffix).
    while (segments.isNotEmpty && segments.last.toLowerCase() == 'emby') {
      segments.removeLast();
    }

    final normalizedPath = segments.isEmpty ? '' : '/${segments.join('/')}';
    return uri
        .replace(path: normalizedPath, query: null, fragment: null)
        .toString();
  }

  static String _urlJoin(String baseUrl, String path) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final fixedPath =
        path.trim().startsWith('/') ? path.trim() : '/${path.trim()}';
    return '$base$fixedPath';
  }

  static String _urlWithPrefix(
    String baseUrl,
    String apiPrefix,
    String path,
  ) {
    final fixedPrefix = _normalizeApiPrefix(apiPrefix);
    final prefixPart = fixedPrefix.isEmpty ? '' : '/$fixedPrefix';
    final fixedPath =
        path.trim().startsWith('/') ? path.trim() : '/${path.trim()}';
    return _urlJoin(baseUrl, '$prefixPart$fixedPath');
  }

  static String _uhdImageKind(String imageType) {
    switch (imageType.trim().toLowerCase()) {
      case 'backdrop':
        return 'backdrop';
      case 'thumb':
        return 'thumb';
      case 'logo':
        return 'logo';
      case 'banner':
        return 'banner';
      case 'primary':
      default:
        return 'poster';
    }
  }

  static String _normalizeContainer(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty) return 'mkv';
    return v.startsWith('.') ? v.substring(1) : v;
  }

  static String _computeVideoId({
    required String itemId,
    required String itemType,
  }) {
    final rawId = itemId.trim();
    if (rawId.isEmpty) return rawId;

    // Some backends use prefixed ids like "e{ULID}" for episodes.
    if (rawId.length == 27 && _looksLikeUlid(rawId.substring(1))) {
      return rawId;
    }
    if (!_looksLikeUlid(rawId)) {
      return rawId;
    }

    switch (itemType.trim().toLowerCase()) {
      case 'episode':
        return 'e$rawId';
      case 'movie':
        return 'm$rawId';
      default:
        return rawId;
    }
  }

  static String buildOriginalStreamUrl(
    ServerAuthSession auth, {
    required String videoId,
    required String container,
  }) {
    final base = _urlWithPrefix(
      auth.baseUrl,
      _effectiveStreamApiPrefix(auth),
      'videos/$videoId/original.$container',
    );
    final uri = Uri.parse(base);
    return uri.replace(
      queryParameters: <String, String>{
        'token': auth.token,
        'api_key': auth.token,
      },
    ).toString();
  }

  static MediaItem _copyWithHasImage(MediaItem item, bool hasImage) {
    return MediaItem(
      id: item.id,
      name: item.name,
      type: item.type,
      overview: item.overview,
      communityRating: item.communityRating,
      premiereDate: item.premiereDate,
      productionYear: item.productionYear,
      status: item.status,
      genres: item.genres,
      tags: item.tags,
      runTimeTicks: item.runTimeTicks,
      sizeBytes: item.sizeBytes,
      container: item.container,
      providerIds: item.providerIds,
      seriesId: item.seriesId,
      seriesName: item.seriesName,
      seasonName: item.seasonName,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      hasImage: hasImage,
      playbackPositionTicks: item.playbackPositionTicks,
      played: item.played,
      favorite: item.favorite,
      people: item.people,
      parentId: item.parentId,
    );
  }

  static MediaItem _maybeForceHasImage(MediaItem item) {
    if (item.hasImage) return item;
    if (!_looksLikeUhdItemId(item.id)) return item;
    return _copyWithHasImage(item, true);
  }

  @override
  String imageUrl(
    ServerAuthSession auth, {
    required String itemId,
    String imageType = 'Primary',
    int? maxWidth,
  }) {
    final id = _normalizeImageId(itemId);
    final kind = _uhdImageKind(imageType);
    final width = (maxWidth != null && maxWidth > 0) ? '@${maxWidth}_' : '';
    final base = _effectiveAssetBaseUrl(auth);
    return _urlJoin(base, 'img/$kind/$id/img.webp$width');
  }

  @override
  String personImageUrl(
    ServerAuthSession auth, {
    required String personId,
    int? maxWidth,
  }) {
    final id = _normalizeImageId(personId);
    final width = (maxWidth != null && maxWidth > 0) ? '@${maxWidth}_' : '';
    final base = _effectiveAssetBaseUrl(auth);
    return _urlJoin(base, 'img/person/$id/img.webp$width');
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
  }) async {
    final result = await super.fetchItems(
      auth,
      parentId: parentId,
      startIndex: startIndex,
      limit: limit,
      includeItemTypes: includeItemTypes,
      searchTerm: searchTerm,
      recursive: recursive,
      excludeFolders: excludeFolders,
      sortBy: sortBy,
      sortOrder: sortOrder,
      fields: fields,
      genres: genres,
      years: years,
      personIds: personIds,
    );
    return PagedResult(
      result.items.map(_maybeForceHasImage).toList(growable: false),
      result.total,
    );
  }

  @override
  Future<PagedResult<MediaItem>> fetchContinueWatching(
    ServerAuthSession auth, {
    int limit = 30,
  }) async {
    final result = await super.fetchContinueWatching(auth, limit: limit);
    return PagedResult(
      result.items.map(_maybeForceHasImage).toList(growable: false),
      result.total,
    );
  }

  @override
  Future<MediaItem> fetchItemDetail(
    ServerAuthSession auth, {
    required String itemId,
  }) async {
    final item = await super.fetchItemDetail(auth, itemId: itemId);
    return _maybeForceHasImage(item);
  }

  @override
  Future<PagedResult<MediaItem>> fetchSeasons(
    ServerAuthSession auth, {
    required String seriesId,
  }) async {
    final result = await super.fetchSeasons(auth, seriesId: seriesId);
    return PagedResult(
      result.items.map(_maybeForceHasImage).toList(growable: false),
      result.total,
    );
  }

  @override
  Future<PagedResult<MediaItem>> fetchEpisodes(
    ServerAuthSession auth, {
    required String seasonId,
  }) async {
    final result = await super.fetchEpisodes(auth, seasonId: seasonId);
    return PagedResult(
      result.items.map(_maybeForceHasImage).toList(growable: false),
      result.total,
    );
  }

  @override
  Future<PagedResult<MediaItem>> fetchSimilar(
    ServerAuthSession auth, {
    required String itemId,
    int limit = 10,
  }) async {
    final result = await super.fetchSimilar(auth, itemId: itemId, limit: limit);
    return PagedResult(
      result.items.map(_maybeForceHasImage).toList(growable: false),
      result.total,
    );
  }

  @override
  Future<PlaybackInfoResult> fetchPlaybackInfo(
    ServerAuthSession auth, {
    required String itemId,
    PlaybackInfoProfileKind profile = PlaybackInfoProfileKind.defaultProfile,
  }) async {
    MediaItem? detail;
    try {
      detail = await super.fetchItemDetail(auth, itemId: itemId);
    } catch (_) {}

    final itemType = detail?.type ?? '';
    final containerFromDetail = _normalizeContainer(detail?.container);
    final videoId = _computeVideoId(itemId: itemId, itemType: itemType);

    try {
      final info = await super.fetchPlaybackInfo(
        auth,
        itemId: itemId,
        profile: profile,
      );

      final patched = <dynamic>[];
      for (final entry in info.mediaSources) {
        if (entry is Map) {
          final ms = Map<String, dynamic>.from(entry);
          final c = _normalizeContainer(ms['Container']?.toString());
          ms['DirectStreamUrl'] = buildOriginalStreamUrl(
            auth,
            videoId: videoId,
            container: c.isEmpty ? containerFromDetail : c,
          );
          patched.add(ms);
        } else {
          patched.add(entry);
        }
      }
      return PlaybackInfoResult(
        playSessionId: info.playSessionId,
        mediaSourceId: info.mediaSourceId,
        mediaSources: patched,
      );
    } catch (_) {
      return PlaybackInfoResult(
        playSessionId: '',
        mediaSourceId: videoId,
        mediaSources: [
          {
            'Id': videoId,
            'Container': containerFromDetail,
            'Size': detail?.sizeBytes,
            'DirectStreamUrl': buildOriginalStreamUrl(
              auth,
              videoId: videoId,
              container: containerFromDetail,
            ),
          },
        ],
      );
    }
  }
}
