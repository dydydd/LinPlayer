import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_adapters/server_access.dart';
import 'show_detail_page.dart';

enum _LibraryItemsSortBy {
  communityRating('CommunityRating', '评分'),
  dateLastContentAdded('DateLastContentAdded', '最近更新'),
  dateCreated('DateCreated', '加入日期'),
  productionYear('ProductionYear', '发行年份'),
  premiereDate('PremiereDate', '发行日期'),
  officialRating('OfficialRating', '家长分级'),
  runtime('Runtime', '时间长度');

  const _LibraryItemsSortBy(this.serverValue, this.zhLabel);

  final String serverValue;
  final String zhLabel;

  static _LibraryItemsSortBy? tryParse(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    for (final mode in _LibraryItemsSortBy.values) {
      if (mode.serverValue == v) return mode;
    }
    return null;
  }
}

class _GridItem extends StatelessWidget {
  const _GridItem({
    required this.item,
    required this.access,
    required this.onTap,
  });

  final MediaItem item;
  final ServerAccess? access;
  final VoidCallback onTap;

  String _yearOf() {
    final y = item.productionYear;
    if (y != null && y > 0) return y.toString();
    final d = (item.premiereDate ?? '').trim();
    if (d.isEmpty) return '';
    final parsed = DateTime.tryParse(d);
    if (parsed != null) return parsed.year.toString();
    return d.length >= 4 ? d.substring(0, 4) : '';
  }

  @override
  Widget build(BuildContext context) {
    final access = this.access;
    final image = item.hasImage && access != null
        ? access.adapter.imageUrl(
            access.auth,
            itemId: item.id,
            imageType: 'Primary',
            maxWidth: 320,
          )
        : null;

    final year = _yearOf();
    final rating = item.communityRating;

    String badge = '';
    if (item.type == 'Movie') {
      badge = '电影';
    } else if (item.type == 'Series') {
      badge = '剧集';
    }

    return MediaPosterTile(
      title: item.name,
      imageUrl: image,
      year: year,
      rating: rating,
      badgeText: badge,
      onTap: onTap,
    );
  }
}

enum _LibraryItemsSortOrder {
  ascending('Ascending', Icons.arrow_upward_rounded, '升序'),
  descending('Descending', Icons.arrow_downward_rounded, '降序');

  const _LibraryItemsSortOrder(this.serverValue, this.icon, this.zhLabel);

  final String serverValue;
  final IconData icon;
  final String zhLabel;

  static _LibraryItemsSortOrder? tryParse(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    for (final mode in _LibraryItemsSortOrder.values) {
      if (mode.serverValue.toLowerCase() == v.toLowerCase()) return mode;
    }
    return null;
  }
}

enum _SeriesStatusFilter {
  all('全部'),
  continuing('连载'),
  ended('完结');

  const _SeriesStatusFilter(this.zhLabel);

  final String zhLabel;
}

enum _PlayedFilter {
  all('全部'),
  unplayed('未看'),
  played('已看');

  const _PlayedFilter(this.zhLabel);

  final String zhLabel;
}

enum _FavoriteFilter {
  all('全部'),
  notFavorite('未喜欢'),
  favorite('喜欢');

  const _FavoriteFilter(this.zhLabel);

  final String zhLabel;
}

enum LibraryItemsPageResult {
  openedItem,
}

class LibraryItemsPage extends StatefulWidget {
  const LibraryItemsPage({
    super.key,
    required this.appState,
    required this.parentId,
    required this.title,
    this.isTv = false,
    this.onOpenItem,
  });

  final AppState appState;
  final String parentId;
  final String title;
  final bool isTv;
  final ValueChanged<MediaItem>? onOpenItem;

  @override
  State<LibraryItemsPage> createState() => _LibraryItemsPageState();
}

class _LibraryItemsPageState extends State<LibraryItemsPage> {
  static const String _kPrefsPrefix = 'libraryItemsPrefs_v1:';
  static const String _kGenresCachePrefix = 'libraryGenresCache_v1:';
  static const double _kTopControlsFadeDistance = 220.0;
  static const int _kEmptyAutoLoadMaxAttempts = 3;
  // Genres rarely change compared to item lists. Cache aggressively and rely on
  // a lightweight change-detection check to refresh when the library updates.
  static const Duration _kGenresCacheMaxAge = Duration(days: 365);
  static const Duration _kYearsCacheMaxAge = Duration(hours: 24);

  final ScrollController _scroll = ScrollController();
  final TextEditingController _minRatingController = TextEditingController();
  final TextEditingController _maxRatingController = TextEditingController();
  final TextEditingController _yearFromController = TextEditingController();
  final TextEditingController _yearToController = TextEditingController();
  final TextEditingController _customPrefixInputController =
      TextEditingController();

  bool _loadingMore = false;
  bool _isRequesting = false;
  bool _pendingReload = false;
  String? _error;

  _LibraryItemsSortBy _sortBy = _LibraryItemsSortBy.dateCreated;
  _LibraryItemsSortOrder _sortOrder = _LibraryItemsSortOrder.descending;

  double? _minRating;
  double? _maxRating;
  int? _selectedYear;
  int? _yearFrom;
  int? _yearTo;
  final Set<String> _selectedGenres = <String>{};
  _SeriesStatusFilter _seriesStatus = _SeriesStatusFilter.all;
  _PlayedFilter _played = _PlayedFilter.all;
  _FavoriteFilter _favorite = _FavoriteFilter.all;
  final Map<String, String?> _customPrefixSelections = <String, String?>{};
  List<String>? _availableGenresFromServer;
  List<int>? _availableYearsFromServer;
  int? _availableGenresFetchedAtMs;
  int? _availableYearsFetchedAtMs;
  int? _availableGenresLibraryTotal;
  String? _availableGenresLibraryLatestItemId;
  int? _availableGenresLibrarySignatureAtMs;
  Future<LibraryFilterOptions>? _availableGenresInFlight;
  Future<void>? _availableGenresSignatureInFlight;
  Future<void>? _availableYearsScanInFlight;
  String _lastServerGenresKey = '';
  bool _isLoadingGenresFromServer = false;
  bool _isScanningYearsFromServer = false;
  bool _pendingGenresReload = false;

  bool _filterPanelOpen = false;
  bool _showAllGenres = false;
  bool _showAllYears = false;
  double _topControlsVisibility = 1.0;

  Timer? _filterDebounce;
  String _lastServerQueryKey = '';
  int _emptyAutoLoadAttempts = 0;
  bool _emptyAutoLoadScheduled = false;

  String get _prefsKey {
    final serverId = widget.appState.activeServerId ?? 'none';
    return '$_kPrefsPrefix$serverId:${widget.parentId}';
  }

  String get _genresCacheKey {
    final serverId = widget.appState.activeServerId ?? 'none';
    final types = _serverIncludeItemTypes();
    return '$_kGenresCachePrefix$serverId:${widget.parentId}:$types';
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_restorePrefsAndLoad());
  }

  void _onScroll() {
    if (_loadingMore) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
      _load(reset: false);
    }
  }

  Future<void> _restorePrefsAndLoad() async {
    await _restorePrefs();
    if (!mounted) return;
    await _restoreGenresCache();
    if (!mounted) return;
    final pinned = widget.appState.libraryFilterPanelPinned;
    final cachedYearsEmpty =
        _availableYearsFromServer != null && _availableYearsFromServer!.isEmpty;
    _maybeReloadServerGenres(
      force: !_isGenresCacheFresh() || (pinned && cachedYearsEmpty),
    );
    await _load(reset: true);
    if (!mounted) return;
    _maybeScanYearsFromServer(requestKey: _serverGenresKey());
    _checkLibraryChangedAndMaybeReloadGenres();
  }

  bool _isGenresCacheFresh() {
    final at = _availableGenresFetchedAtMs;
    if (at == null || at <= 0) return false;
    if (_availableYearsFromServer == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - at;
    return age >= 0 && age <= _kGenresCacheMaxAge.inMilliseconds;
  }

  bool _isYearsCacheFresh() {
    final at = _availableYearsFetchedAtMs;
    if (at == null || at <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - at;
    return age >= 0 && age <= _kYearsCacheMaxAge.inMilliseconds;
  }

  Future<void> _restoreGenresCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_genresCacheKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final rawGenres = decoded['genres'];
      final rawYears = decoded['years'];
      if (rawGenres is! List && rawYears is! List) return;

      final outGenres = <String>[];
      if (rawGenres is List) {
        final seen = <String>{};
        for (final entry in rawGenres) {
          if (entry == null) continue;
          final v = entry.toString().trim();
          if (v.isEmpty) continue;
          final key = v.toLowerCase();
          if (seen.add(key)) outGenres.add(v);
        }
        outGenres.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }

      final outYears = <int>[];
      if (rawYears is List) {
        final seen = <int>{};
        for (final entry in rawYears) {
          if (entry == null) continue;
          final parsed = entry is int
              ? entry
              : int.tryParse(entry.toString().trim());
          if (parsed == null || parsed <= 0) continue;
          if (seen.add(parsed)) outYears.add(parsed);
        }
        outYears.sort((a, b) => b.compareTo(a));
      }

      final fetchedAt = decoded['fetchedAt'];
      final fetchedAtMs = fetchedAt is int
          ? fetchedAt
          : int.tryParse((fetchedAt ?? '').toString().trim());

      final yearsFetchedAt = decoded['yearsFetchedAt'];
      final yearsFetchedAtMs = yearsFetchedAt is int
          ? yearsFetchedAt
          : int.tryParse((yearsFetchedAt ?? '').toString().trim());
      final fallbackYearsFetchedAtMs =
          yearsFetchedAtMs ?? (outYears.isNotEmpty ? fetchedAtMs : null);

      final rawLibraryTotal = decoded['libraryTotal'];
      final libraryTotal = rawLibraryTotal is int
          ? rawLibraryTotal
          : int.tryParse((rawLibraryTotal ?? '').toString().trim());
      final rawLatestItemId = decoded['libraryLatestItemId'];
      final latestItemId = rawLatestItemId?.toString().trim();
      final rawSignatureAt = decoded['librarySignatureAt'];
      final signatureAtMs = rawSignatureAt is int
          ? rawSignatureAt
          : int.tryParse((rawSignatureAt ?? '').toString().trim());

      if (!mounted) return;
      setState(() {
        _availableGenresFromServer = rawGenres is List ? outGenres : null;
        _availableYearsFromServer = rawYears is List ? outYears : null;
        _availableGenresFetchedAtMs = fetchedAtMs;
        _availableYearsFetchedAtMs = fallbackYearsFetchedAtMs;
        _availableGenresLibraryTotal = libraryTotal;
        _availableGenresLibraryLatestItemId = latestItemId;
        _availableGenresLibrarySignatureAtMs = signatureAtMs;
        _lastServerGenresKey = _serverGenresKey();
      });
    } catch (_) {
      // Best-effort; ignore broken cache.
    }
  }

  Future<void> _persistGenresCache({
    List<String>? genres,
    List<int>? years,
    int? fetchedAtMs,
    int? yearsFetchedAtMs,
    int? libraryTotal,
    String? libraryLatestItemId,
    int? librarySignatureAtMs,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingRaw = prefs.getString(_genresCacheKey);
      final merged = <String, Object?>{};
      if (existingRaw != null && existingRaw.trim().isNotEmpty) {
        try {
          final existingDecoded = jsonDecode(existingRaw);
          if (existingDecoded is Map) {
            for (final entry in existingDecoded.entries) {
              final key = entry.key?.toString();
              if (key == null || key.trim().isEmpty) continue;
              merged[key] = entry.value;
            }
          }
        } catch (_) {
          // Ignore broken cache; overwrite with fresh values below.
        }
      }

      if (genres != null) merged['genres'] = genres;
      if (years != null) merged['years'] = years;
      if (fetchedAtMs != null) merged['fetchedAt'] = fetchedAtMs;
      if (yearsFetchedAtMs != null) merged['yearsFetchedAt'] = yearsFetchedAtMs;
      if (libraryTotal != null) merged['libraryTotal'] = libraryTotal;
      if (libraryLatestItemId != null) {
        merged['libraryLatestItemId'] = libraryLatestItemId;
      }
      if (librarySignatureAtMs != null) {
        merged['librarySignatureAt'] = librarySignatureAtMs;
      }

      await prefs.setString(_genresCacheKey, jsonEncode(merged));
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _restorePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final restoredSortBy = _LibraryItemsSortBy.tryParse(
        decoded['sortBy']?.toString(),
      );
      final restoredSortOrder = _LibraryItemsSortOrder.tryParse(
        decoded['sortOrder']?.toString(),
      );
      final restoredMinRating = (decoded['minRating'] as num?)?.toDouble();
      final restoredMaxRating = (decoded['maxRating'] as num?)?.toDouble();
      final restoredSelectedYear = decoded['selectedYear'] as int?;
      final restoredYearFrom = decoded['yearFrom'] as int?;
      final restoredYearTo = decoded['yearTo'] as int?;
      final restoredGenres = (decoded['selectedGenres'] is List)
          ? (decoded['selectedGenres'] as List)
              .where((e) => e != null)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
          : const <String>{};
      final restoredSeriesStatus =
          switch (decoded['seriesStatus']?.toString()) {
        'continuing' => _SeriesStatusFilter.continuing,
        'ended' => _SeriesStatusFilter.ended,
        _ => _SeriesStatusFilter.all,
      };
      final restoredPlayed = switch (decoded['played']?.toString()) {
        'unplayed' => _PlayedFilter.unplayed,
        'played' => _PlayedFilter.played,
        _ => _PlayedFilter.all,
      };
      final restoredFavorite = switch (decoded['favorite']?.toString()) {
        'notFavorite' => _FavoriteFilter.notFavorite,
        'favorite' => _FavoriteFilter.favorite,
        _ => _FavoriteFilter.all,
      };
      final restoredCustomPrefixSelections =
          (decoded['customPrefixSelections'] is Map)
              ? (decoded['customPrefixSelections'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v?.toString()))
              : const <String, String?>{};

      if (!mounted) return;
      setState(() {
        _sortBy = restoredSortBy ?? _sortBy;
        _sortOrder = restoredSortOrder ?? _sortOrder;
        _minRating = restoredMinRating;
        _maxRating = restoredMaxRating;
        _selectedYear = restoredSelectedYear;
        _yearFrom = restoredYearFrom;
        _yearTo = restoredYearTo;
        _selectedGenres
          ..clear()
          ..addAll(restoredGenres);
        _seriesStatus = restoredSeriesStatus;
        _played = restoredPlayed;
        _favorite = restoredFavorite;
        _customPrefixSelections
          ..clear()
          ..addAll(restoredCustomPrefixSelections);
      });

      _minRatingController.text =
          restoredMinRating == null ? '' : restoredMinRating.toString();
      _maxRatingController.text =
          restoredMaxRating == null ? '' : restoredMaxRating.toString();
      _yearFromController.text =
          restoredYearFrom == null ? '' : restoredYearFrom.toString();
      _yearToController.text =
          restoredYearTo == null ? '' : restoredYearTo.toString();
    } catch (_) {
      // Best-effort; ignore broken prefs.
    }
  }

  Future<void> _persistPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customPrefixSelections = Map<String, String>.fromEntries(
        _customPrefixSelections.entries
            .where((e) => e.key.trim().isNotEmpty)
            .map((e) => MapEntry(e.key, (e.value ?? '').trim()))
            .where((e) => e.value.isNotEmpty),
      );
      final data = <String, dynamic>{
        'sortBy': _sortBy.serverValue,
        'sortOrder': _sortOrder.serverValue,
        'minRating': _minRating,
        'maxRating': _maxRating,
        'selectedYear': _selectedYear,
        'yearFrom': _yearFrom,
        'yearTo': _yearTo,
        'selectedGenres': _selectedGenres.toList(growable: false),
        'seriesStatus': switch (_seriesStatus) {
          _SeriesStatusFilter.continuing => 'continuing',
          _SeriesStatusFilter.ended => 'ended',
          _ => 'all',
        },
        'played': switch (_played) {
          _PlayedFilter.unplayed => 'unplayed',
          _PlayedFilter.played => 'played',
          _ => 'all',
        },
        'favorite': switch (_favorite) {
          _FavoriteFilter.notFavorite => 'notFavorite',
          _FavoriteFilter.favorite => 'favorite',
          _ => 'all',
        },
        if (customPrefixSelections.isNotEmpty)
          'customPrefixSelections': customPrefixSelections,
      };
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (_) {
      // Best-effort; ignore failures.
    }
  }

  void _setTopControlsVisibility(double value) {
    final next = value.clamp(0.0, 1.0).toDouble();
    if ((next - _topControlsVisibility).abs() <= 0.001 || !mounted) return;
    setState(() => _topControlsVisibility = next);
  }

  void _updateTopControlsVisibilityByScrollDelta(double delta) {
    if (delta.abs() < 0.1) return;
    final next = _topControlsVisibility - (delta / _kTopControlsFadeDistance);
    _setTopControlsVisibility(next);
  }

  bool _handleGridScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final axis = axisDirectionToAxis(notification.metrics.axisDirection);
    if (axis != Axis.vertical) return false;

    final pixels = notification.metrics.pixels;
    if (pixels <= 0) {
      _setTopControlsVisibility(1.0);
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      _updateTopControlsVisibilityByScrollDelta(delta);
      return false;
    }

    if (notification is OverscrollNotification) {
      _updateTopControlsVisibilityByScrollDelta(notification.overscroll);
      return false;
    }

    if (notification is ScrollEndNotification && pixels <= 1) {
      _setTopControlsVisibility(1.0);
      return false;
    }

    return false;
  }

  double? _parseRating(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    return v.clamp(0.0, 10.0).toDouble();
  }

  int? _parseYear(String raw) {
    final v = int.tryParse(raw.trim());
    if (v == null) return null;
    return v.clamp(1800, 3000);
  }

  void _scheduleFilterApply() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      _applyFilterValuesFromControllers();
      _onFiltersChanged();
    });
  }

  void _applyFilterValuesFromControllers() {
    final nextMin = _parseRating(_minRatingController.text);
    final nextMax = _parseRating(_maxRatingController.text);
    final nextYearFrom = _parseYear(_yearFromController.text);
    final nextYearTo = _parseYear(_yearToController.text);

    final shouldClearSelectedYear =
        (nextYearFrom != null || nextYearTo != null) && _selectedYear != null;

    if (nextMin == _minRating &&
        nextMax == _maxRating &&
        nextYearFrom == _yearFrom &&
        nextYearTo == _yearTo &&
        !shouldClearSelectedYear) {
      return;
    }

    setState(() {
      _minRating = nextMin;
      _maxRating = nextMax;
      _yearFrom = nextYearFrom;
      _yearTo = nextYearTo;
      if (nextYearFrom != null || nextYearTo != null) {
        _selectedYear = null;
      }
    });
  }

  String _serverIncludeItemTypes() {
    if (_seriesStatus == _SeriesStatusFilter.all) return 'Series,Movie';
    return 'Series';
  }

  List<String>? _serverGenres() {
    if (_selectedGenres.isEmpty) return null;
    final list = _selectedGenres.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<int>? _serverYears() {
    if (_selectedYear != null) return <int>[_selectedYear!];
    if (_yearFrom == null || _yearTo == null) return null;
    final from = _yearFrom!;
    final to = _yearTo!;
    final minY = from <= to ? from : to;
    final maxY = from <= to ? to : from;
    if ((maxY - minY) > 100) return null;
    return <int>[for (int y = minY; y <= maxY; y++) y];
  }

  double? _serverMinCommunityRating() {
    final min = _minRating;
    final max = _maxRating;
    if (min == null) return null;
    if (max == null) return min;
    return min <= max ? min : max;
  }

  bool? _serverIsPlayed() {
    switch (_played) {
      case _PlayedFilter.all:
        return null;
      case _PlayedFilter.played:
        return true;
      case _PlayedFilter.unplayed:
        return false;
    }
  }

  bool? _serverIsFavorite() {
    switch (_favorite) {
      case _FavoriteFilter.all:
        return null;
      case _FavoriteFilter.favorite:
        return true;
      case _FavoriteFilter.notFavorite:
        return false;
    }
  }

  List<String>? _serverSeriesStatus() {
    switch (_seriesStatus) {
      case _SeriesStatusFilter.all:
        return null;
      case _SeriesStatusFilter.continuing:
        return const <String>['Continuing'];
      case _SeriesStatusFilter.ended:
        return const <String>['Ended'];
    }
  }

  String _serverQueryKey() {
    return jsonEncode(<String, Object?>{
      'types': _serverIncludeItemTypes(),
      'genres': _serverGenres(),
      'years': _serverYears(),
      'minRating': _serverMinCommunityRating(),
      'isPlayed': _serverIsPlayed(),
      'isFavorite': _serverIsFavorite(),
      'seriesStatus': _serverSeriesStatus(),
      'sortBy': _sortBy.serverValue,
      'sortOrder': _sortOrder.serverValue,
    });
  }

  String _serverGenresKey() {
    final serverId = widget.appState.activeServerId ?? 'none';
    return jsonEncode(<String, Object?>{
      'serverId': serverId,
      'parentId': widget.parentId,
      'types': _serverIncludeItemTypes(),
    });
  }

  void _maybeReloadServerGenres({bool force = false}) {
    final access = resolveServerAccess(appState: widget.appState);
    if (access == null) return;

    final nextKey = _serverGenresKey();
    final hasCurrentData =
        nextKey == _lastServerGenresKey &&
        (_availableGenresFromServer != null || _availableYearsFromServer != null);
    if (!force && hasCurrentData && _isGenresCacheFresh()) return;

    final inFlight = _availableGenresInFlight;
    if (inFlight != null) {
      _pendingGenresReload = true;
      return;
    }

    setState(() => _isLoadingGenresFromServer = true);

    final requestKey = nextKey;
    final request = access.adapter.fetchAvailableFilters(
      access.auth,
      parentId: widget.parentId,
      includeItemTypes: _serverIncludeItemTypes(),
      recursive: true,
    );
    _availableGenresInFlight = request;

    request.then((filters) {
      if (!mounted) return;
      if (requestKey != _serverGenresKey()) return;
      final currentYears = _availableYearsFromServer;
      final genres = filters.genres;
      final years = filters.years;
      final fetchedAtMs = DateTime.now().millisecondsSinceEpoch;
      final reuseExistingYears = requestKey == _lastServerGenresKey;
      final nextYears =
          years.isNotEmpty
              ? years
              : (reuseExistingYears ? (currentYears ?? years) : years);
      final nextYearsFetchedAtMs =
          years.isNotEmpty
              ? fetchedAtMs
              : (reuseExistingYears ? _availableYearsFetchedAtMs : null);
      setState(() {
        _availableGenresFromServer = genres;
        _availableYearsFromServer = nextYears;
        _availableGenresFetchedAtMs = fetchedAtMs;
        _availableYearsFetchedAtMs = nextYearsFetchedAtMs;
        _lastServerGenresKey = requestKey;
        _isLoadingGenresFromServer = false;
      });
      unawaited(
        _persistGenresCache(
          genres: genres,
          years: nextYears,
          fetchedAtMs: fetchedAtMs,
          yearsFetchedAtMs: nextYearsFetchedAtMs,
          libraryTotal: _availableGenresLibraryTotal,
          libraryLatestItemId: _availableGenresLibraryLatestItemId,
          librarySignatureAtMs: _availableGenresLibrarySignatureAtMs,
        ),
      );
      _maybeScanYearsFromServer(requestKey: requestKey);
    }).catchError((_) {
      if (!mounted) return;
      if (requestKey != _serverGenresKey()) return;
      setState(() => _isLoadingGenresFromServer = false);
      _maybeScanYearsFromServer(requestKey: requestKey);
    }).whenComplete(() {
      if (_availableGenresInFlight == request) {
        _availableGenresInFlight = null;
      }
      if (mounted && _isLoadingGenresFromServer) {
        setState(() => _isLoadingGenresFromServer = false);
      }
      if (mounted && _pendingGenresReload) {
        _pendingGenresReload = false;
        _maybeReloadServerGenres(force: true);
      }
    });
  }

  void _maybeScanYearsFromServer({
    required String requestKey,
    bool force = false,
  }) {
    if (!mounted) return;
    if (requestKey != _serverGenresKey()) return;

    if (!force && _availableYearsFromServer != null && _isYearsCacheFresh()) {
      return;
    }

    final inFlight = _availableYearsScanInFlight;
    if (inFlight != null) return;

    final access = resolveServerAccess(appState: widget.appState);
    if (access == null) return;

    setState(() => _isScanningYearsFromServer = true);

    final future = _scanAvailableYearsFromServer(
      access: access,
      requestKey: requestKey,
    );
    _availableYearsScanInFlight = future;

    future.catchError((_) {
      // Best-effort.
    }).whenComplete(() {
      if (_availableYearsScanInFlight == future) {
        _availableYearsScanInFlight = null;
      }
      if (mounted && _isScanningYearsFromServer) {
        setState(() => _isScanningYearsFromServer = false);
      }
    });
  }

  Future<void> _scanAvailableYearsFromServer({
    required ServerAccess access,
    required String requestKey,
  }) async {
    const pageSize = 500;
    final seen = <int>{};
    int startIndex = 0;
    int total = 0;

    while (true) {
      if (!mounted) return;
      if (requestKey != _serverGenresKey()) return;

      final result = await access.adapter.fetchItems(
        access.auth,
        parentId: widget.parentId,
        startIndex: startIndex,
        limit: pageSize,
        includeItemTypes: _serverIncludeItemTypes(),
        recursive: true,
        excludeFolders: true,
        fields: 'ProductionYear,PremiereDate',
      );

      for (final item in result.items) {
        final y = _itemYear(item);
        if (y != null) seen.add(y);
      }

      total = result.total;
      startIndex += result.items.length;

      if (result.items.isEmpty) break;
      if (total != 0 && startIndex >= total) break;
    }

    final years = seen.toList()..sort((a, b) => b.compareTo(a));
    final fetchedAtMs = DateTime.now().millisecondsSinceEpoch;

    if (!mounted) return;
    if (requestKey != _serverGenresKey()) return;

    setState(() {
      _availableYearsFromServer = years;
      _availableYearsFetchedAtMs = fetchedAtMs;
      _lastServerGenresKey = requestKey;
    });
    unawaited(
      _persistGenresCache(
        years: years,
        yearsFetchedAtMs: fetchedAtMs,
      ),
    );
  }

  void _checkLibraryChangedAndMaybeReloadGenres() {
    final access = resolveServerAccess(appState: widget.appState);
    if (access == null) return;

    final inFlight = _availableGenresSignatureInFlight;
    if (inFlight != null) return;

    final requestKey = _serverGenresKey();
    final previousTotal = _availableGenresLibraryTotal;
    final previousLatestItemId = _availableGenresLibraryLatestItemId;

    final request = access.adapter.fetchItems(
      access.auth,
      parentId: widget.parentId,
      startIndex: 0,
      limit: 1,
      includeItemTypes: _serverIncludeItemTypes(),
      recursive: true,
      excludeFolders: false,
      sortBy: _LibraryItemsSortBy.dateCreated.serverValue,
      sortOrder: _LibraryItemsSortOrder.descending.serverValue,
    );

    final future = request.then((result) {
      if (!mounted) return;
      if (requestKey != _serverGenresKey()) return;

      final total = result.total;
      final latestItemId = result.items.isEmpty ? '' : result.items.first.id;
      final signatureAtMs = DateTime.now().millisecondsSinceEpoch;

      final changed = (previousTotal != null && previousTotal != total) ||
          (previousLatestItemId != null &&
              previousLatestItemId != latestItemId);

      setState(() {
        _availableGenresLibraryTotal = total;
        _availableGenresLibraryLatestItemId = latestItemId;
        _availableGenresLibrarySignatureAtMs = signatureAtMs;
      });
      unawaited(
        _persistGenresCache(
          libraryTotal: total,
          libraryLatestItemId: latestItemId,
          librarySignatureAtMs: signatureAtMs,
        ),
      );

      if (changed) {
        _maybeReloadServerGenres(force: true);
      }
    }).catchError((_) {
      // Best-effort.
    }).whenComplete(() {
      _availableGenresSignatureInFlight = null;
    });

    _availableGenresSignatureInFlight = future;
  }

  void _maybeReloadServer() {
    final nextKey = _serverQueryKey();
    if (nextKey == _lastServerQueryKey) return;

    if (_isRequesting) {
      _pendingReload = true;
      return;
    }

    _emptyAutoLoadAttempts = 0;
    unawaited(_scrollToTop());
    unawaited(_load(reset: true));
  }

  void _scheduleEmptyAutoLoadMore() {
    if (_emptyAutoLoadScheduled) return;
    _emptyAutoLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emptyAutoLoadScheduled = false;
      if (!mounted) return;
      if (_isRequesting) return;
      if (_emptyAutoLoadAttempts >= _kEmptyAutoLoadMaxAttempts) return;

      final loaded = widget.appState.getItems(widget.parentId).length;
      final total = widget.appState.getTotal(widget.parentId);
      if (total != 0 && loaded >= total) return;

      _emptyAutoLoadAttempts++;
      unawaited(_load(reset: false, limit: 200));
    });
  }

  Future<void> _load({required bool reset, int limit = 30}) async {
    if (_isRequesting) return;
    final items = widget.appState.getItems(widget.parentId);
    final total = widget.appState.getTotal(widget.parentId);
    final start = reset ? 0 : items.length;
    if (!reset && items.length >= total && total != 0) return;

    setState(() {
      _isRequesting = true;
      _loadingMore = true;
      if (reset) _error = null;
    });

    if (reset) {
      _lastServerQueryKey = _serverQueryKey();
    }

    try {
      await widget.appState.loadItems(
        parentId: widget.parentId,
        startIndex: start,
        limit: limit,
        includeItemTypes: _serverIncludeItemTypes(),
        recursive: true,
        excludeFolders: false,
        sortBy: _sortBy.serverValue,
        sortOrder: _sortOrder.serverValue,
        genres: _serverGenres(),
        years: _serverYears(),
        minCommunityRating: _serverMinCommunityRating(),
        isPlayed: _serverIsPlayed(),
        isFavorite: _serverIsFavorite(),
        seriesStatus: _serverSeriesStatus(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
          _loadingMore = false;
        });
      }
      if (mounted && _pendingReload) {
        _pendingReload = false;
        _maybeReloadServer();
      }
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scroll.hasClients) return;
    try {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // ignore scroll errors
    }
  }

  void _toggleSortOrder() {
    final next = _sortOrder == _LibraryItemsSortOrder.ascending
        ? _LibraryItemsSortOrder.descending
        : _LibraryItemsSortOrder.ascending;
    _setSort(sortBy: _sortBy, sortOrder: next);
  }

  void _setSort({
    required _LibraryItemsSortBy sortBy,
    required _LibraryItemsSortOrder sortOrder,
  }) {
    if (_sortBy == sortBy && _sortOrder == sortOrder) return;
    setState(() {
      _sortBy = sortBy;
      _sortOrder = sortOrder;
      _error = null;
    });
    _emptyAutoLoadAttempts = 0;
    unawaited(_persistPrefs());
    _maybeReloadServer();
  }

  int? _itemYear(MediaItem item) {
    final y = item.productionYear;
    if (y != null && y > 0) return y;
    final d = (item.premiereDate ?? '').trim();
    if (d.isEmpty) return null;
    final parsed = DateTime.tryParse(d);
    return parsed?.year;
  }

  MapEntry<String, String>? _parseCustomPrefix(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    final idxAscii = v.indexOf(':');
    final idxZh = v.indexOf('：');
    int idx = -1;
    if (idxAscii > 0) idx = idxAscii;
    if (idxZh > 0 && (idx == -1 || idxZh < idx)) idx = idxZh;
    if (idx <= 0 || idx >= v.length - 1) return null;
    final prefix = v.substring(0, idx).trim();
    final value = v.substring(idx + 1).trim();
    if (prefix.isEmpty || value.isEmpty) return null;
    return MapEntry(prefix, value);
  }

  void _addCustomPrefixFromInput() {
    final parsed = _parseCustomPrefix(_customPrefixInputController.text);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('格式：前缀:值（如 语言:中文）')),
      );
      return;
    }

    setState(() {
      _customPrefixSelections[parsed.key] = parsed.value;
      _customPrefixInputController.text = '';
    });
    _onFiltersChanged();
  }

  bool _matchesRating(MediaItem item) {
    if (_minRating == null && _maxRating == null) return true;
    final rating = item.communityRating;
    if (rating == null) return false;
    final min = _minRating;
    final max = _maxRating;
    if (min != null && max != null) {
      final low = min <= max ? min : max;
      final high = min <= max ? max : min;
      return rating >= low && rating <= high;
    }
    if (min != null && rating < min) return false;
    if (max != null && rating > max) return false;
    return true;
  }

  bool _matchesYear(MediaItem item) {
    if (_selectedYear == null && _yearFrom == null && _yearTo == null) {
      return true;
    }
    final year = _itemYear(item);
    if (year == null) return false;
    final selected = _selectedYear;
    if (selected != null) return year == selected;
    if (_yearFrom != null && _yearTo != null) {
      final from = _yearFrom!;
      final to = _yearTo!;
      final minY = from <= to ? from : to;
      final maxY = from <= to ? to : from;
      return year >= minY && year <= maxY;
    }
    if (_yearFrom != null && year < _yearFrom!) return false;
    if (_yearTo != null && year > _yearTo!) return false;
    return true;
  }

  bool _matchesGenres(MediaItem item) {
    if (_selectedGenres.isEmpty) return true;
    return item.genres.any(_selectedGenres.contains);
  }

  bool _matchesSeriesStatus(MediaItem item) {
    final filter = _seriesStatus;
    if (filter == _SeriesStatusFilter.all) return true;
    if (item.type != 'Series') return false;
    final s = (item.status ?? '').trim().toLowerCase();
    if (s.isEmpty) return false;
    switch (filter) {
      case _SeriesStatusFilter.continuing:
        return s.contains('continu');
      case _SeriesStatusFilter.ended:
        return s.contains('ended');
      case _SeriesStatusFilter.all:
        return true;
    }
  }

  bool _matchesPlayed(MediaItem item) {
    switch (_played) {
      case _PlayedFilter.all:
        return true;
      case _PlayedFilter.unplayed:
        return !item.played;
      case _PlayedFilter.played:
        return item.played;
    }
  }

  bool _matchesFavorite(MediaItem item) {
    switch (_favorite) {
      case _FavoriteFilter.all:
        return true;
      case _FavoriteFilter.notFavorite:
        return !item.favorite;
      case _FavoriteFilter.favorite:
        return item.favorite;
    }
  }

  bool _matchesCustomPrefixes(MediaItem item) {
    if (_customPrefixSelections.isEmpty) return true;
    for (final entry in _customPrefixSelections.entries) {
      final prefix = entry.key.trim();
      final selected = (entry.value ?? '').trim();
      if (prefix.isEmpty || selected.isEmpty) continue;

      bool matched = false;
      for (final raw in <String>[...item.genres, ...item.tags]) {
        final parsed = _parseCustomPrefix(raw);
        if (parsed == null) continue;
        if (parsed.key == prefix && parsed.value == selected) {
          matched = true;
          break;
        }
      }
      if (!matched) return false;
    }
    return true;
  }

  bool _matchesAllFilters(
    MediaItem item, {
    required bool customPrefixEnabled,
  }) {
    if (!_matchesRating(item)) return false;
    if (!_matchesYear(item)) return false;
    if (!_matchesGenres(item)) return false;
    if (!_matchesSeriesStatus(item)) return false;
    if (!_matchesPlayed(item)) return false;
    if (!_matchesFavorite(item)) return false;
    if (customPrefixEnabled && !_matchesCustomPrefixes(item)) return false;
    return true;
  }

  int _activeFilterCount({required bool customPrefixEnabled}) {
    int count = 0;
    if (_minRating != null || _maxRating != null) count++;
    if (_selectedYear != null || _yearFrom != null || _yearTo != null) count++;
    if (_selectedGenres.isNotEmpty) count++;
    if (_seriesStatus != _SeriesStatusFilter.all) count++;
    if (_played != _PlayedFilter.all) count++;
    if (_favorite != _FavoriteFilter.all) count++;
    if (customPrefixEnabled) {
      count += _customPrefixSelections.entries
          .map((e) => (e.value ?? '').trim())
          .where((v) => v.isNotEmpty)
          .length;
    }
    return count;
  }

  void _onFiltersChanged() {
    _emptyAutoLoadAttempts = 0;
    unawaited(_persistPrefs());
    _maybeReloadServerGenres();
    _maybeReloadServer();
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _minRatingController.dispose();
    _maxRatingController.dispose();
    _yearFromController.dispose();
    _yearToController.dispose();
    _customPrefixInputController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _isTv(BuildContext context) => DeviceType.isTv;

  Widget _pill(
    BuildContext context, {
    required double uiScale,
    required Widget child,
    required VoidCallback? onTap,
    bool selected = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = selected
        ? scheme.primary.withValues(alpha: 0.16)
        : scheme.surface.withValues(alpha: 0.10);
    final border = selected
        ? scheme.primary.withValues(alpha: 0.55)
        : scheme.outline.withValues(alpha: 0.35);
    final fg = selected ? scheme.primary : theme.iconTheme.color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 36 * uiScale,
          padding: EdgeInsets.symmetric(horizontal: 12 * uiScale),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: fg, size: 18 * uiScale),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
                fontSize: 13,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Color _optionSelectedBackground(ThemeData theme) {
    final scheme = theme.colorScheme;
    final alpha = theme.brightness == Brightness.dark ? 0.18 : 0.08;
    return scheme.onSurface.withValues(alpha: alpha);
  }

  Widget _optionChip(
    BuildContext context, {
    required double uiScale,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final fg =
        selected ? theme.colorScheme.onSurface : theme.textTheme.bodyMedium?.color;
    final weight = selected ? FontWeight.w600 : FontWeight.w400;
    final bg = selected ? _optionSelectedBackground(theme) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 10 * uiScale,
            vertical: 6 * uiScale,
          ),
          decoration: BoxDecoration(color: bg),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: weight,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberField(
    BuildContext context, {
    required double uiScale,
    required TextEditingController controller,
    required String hintText,
    required bool decimal,
    double width = 92,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(
        width: width * uiScale,
        height: 34 * uiScale,
      ),
      child: TextField(
        controller: controller,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 8 * uiScale,
            vertical: 9 * uiScale,
          ),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
        onChanged: (_) => _scheduleFilterApply(),
      ),
    );
  }

  Widget _filterRow(
    BuildContext context, {
    required double uiScale,
    required String label,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 10 * uiScale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76 * uiScale,
            child: Text(
              '$label：',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8 * uiScale,
              runSpacing: 8 * uiScale,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final allItems = widget.appState.getItems(widget.parentId);
        final customPrefixEnabled =
            widget.appState.libraryCustomPrefixFiltersEnabled;
        final pinned = widget.appState.libraryFilterPanelPinned;

        final genres = <String>{};
        final years = <int>{};
        for (final item in allItems) {
          final y = _itemYear(item);
          if (y != null) years.add(y);

          for (final raw in item.genres) {
            final normalized = raw.trim();
            if (normalized.isEmpty) continue;
            genres.add(normalized);
          }
        }
        final localGenreList = genres.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final serverGenreList = _availableGenresFromServer;
        final usingServerGenreList =
            serverGenreList != null && serverGenreList.isNotEmpty;
        final genreSource =
            usingServerGenreList ? serverGenreList : localGenreList;

        final mergedGenreList = <String>[];
        final mergedGenreSeen = <String>{};
        void addGenre(
          String raw, {
          required bool allowCustomPrefix,
        }) {
          final v = raw.trim();
          if (v.isEmpty) return;
          if (!allowCustomPrefix &&
              customPrefixEnabled &&
              _parseCustomPrefix(v) != null) {
            return;
          }
          final key = v.toLowerCase();
          if (mergedGenreSeen.add(key)) mergedGenreList.add(v);
        }

        for (final g in genreSource) {
          addGenre(g, allowCustomPrefix: false);
        }
        for (final g in _selectedGenres) {
          addGenre(g, allowCustomPrefix: true);
        }
        mergedGenreList
            .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final genreList = mergedGenreList;

        final localYearList = years.toList()..sort((a, b) => b.compareTo(a));
        final serverYearList = _availableYearsFromServer;
        final usingServerYearList =
            serverYearList != null && serverYearList.isNotEmpty;
        final yearSource = usingServerYearList ? serverYearList : localYearList;

        final mergedYearList = <int>[];
        final mergedYearSeen = <int>{};
        void addYear(int raw) {
          final y = raw;
          if (y <= 0) return;
          if (mergedYearSeen.add(y)) mergedYearList.add(y);
        }

        for (final y in yearSource) {
          addYear(y);
        }
        final selectedYear = _selectedYear;
        if (selectedYear != null) addYear(selectedYear);

        mergedYearList.sort((a, b) => b.compareTo(a));
        final yearList = mergedYearList;

        final items = allItems
            .where(
              (item) => _matchesAllFilters(
                item,
                customPrefixEnabled: customPrefixEnabled,
              ),
            )
            .toList(growable: false);

        final access = resolveServerAccess(appState: widget.appState);
        final uiScale = context.uiScale;
        final isTv = _isTv(context);
        final enableBlur = !isTv && widget.appState.enableBlurEffects;
        final maxCrossAxisExtent = (isTv ? 160.0 : 180.0) * uiScale;

        PopupMenuItem<_LibraryItemsSortBy> sortItem({
          required _LibraryItemsSortBy value,
        }) {
          return CheckedPopupMenuItem<_LibraryItemsSortBy>(
            value: value,
            checked: _sortBy == value,
            child: Text(value.zhLabel),
          );
        }

        Widget sortButton() {
          return PopupMenuButton<_LibraryItemsSortBy>(
            tooltip: '排序',
            onSelected: (v) => _setSort(sortBy: v, sortOrder: _sortOrder),
            itemBuilder: (context) => [
              sortItem(value: _LibraryItemsSortBy.communityRating),
              sortItem(value: _LibraryItemsSortBy.dateLastContentAdded),
              sortItem(value: _LibraryItemsSortBy.dateCreated),
              sortItem(value: _LibraryItemsSortBy.productionYear),
              sortItem(value: _LibraryItemsSortBy.premiereDate),
              sortItem(value: _LibraryItemsSortBy.officialRating),
              sortItem(value: _LibraryItemsSortBy.runtime),
              const PopupMenuDivider(),
              CheckedPopupMenuItem<_LibraryItemsSortBy>(
                value: _sortBy,
                enabled: false,
                checked: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Text('方向：${_sortOrder.zhLabel}'),
                    ),
                    Icon(_sortOrder.icon, size: 18 * uiScale),
                  ],
                ),
              ),
            ],
            child: _pill(
              context,
              uiScale: uiScale,
              onTap: null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort_rounded),
                  SizedBox(width: 8 * uiScale),
                  Text('排序：${_sortBy.zhLabel}'),
                  SizedBox(width: 8 * uiScale),
                  InkWell(
                    onTap: _toggleSortOrder,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: EdgeInsets.all(4 * uiScale),
                      child: Icon(_sortOrder.icon, size: 18 * uiScale),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        Widget filterButton() {
          final active =
              _activeFilterCount(customPrefixEnabled: customPrefixEnabled);
          final label = active == 0 ? '筛选' : '筛选（$active）';
          final selected = pinned || _filterPanelOpen;

          return _pill(
            context,
            uiScale: uiScale,
            selected: selected,
            onTap: pinned
                ? null
                : () {
                    final next = !_filterPanelOpen;
                    setState(() => _filterPanelOpen = next);
                    if (next) {
                      final cachedYearsEmpty = _availableYearsFromServer != null &&
                          _availableYearsFromServer!.isEmpty;
                      _maybeReloadServerGenres(force: cachedYearsEmpty);
                    }
                  },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune_rounded),
                SizedBox(width: 8 * uiScale),
                Text(label),
              ],
            ),
          );
        }

        Widget filterPanel() {
          final show = pinned || _filterPanelOpen;
          if (!show) return const SizedBox.shrink();

          final total = widget.appState.getTotal(widget.parentId);
          final canLoadMore = total == 0 || allItems.length < total;

          final displayGenres = _showAllGenres
              ? genreList
              : (genreList.length <= 18
                  ? genreList
                  : genreList.take(18).toList());
          final displayYears = _showAllYears
              ? yearList
              : (yearList.length <= 20 ? yearList : yearList.take(20).toList());

          final noRatingFilter = _minRating == null && _maxRating == null;
          final noYearFilter =
              _selectedYear == null && _yearFrom == null && _yearTo == null;

          return Padding(
            padding: EdgeInsets.only(top: 10 * uiScale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _filterRow(
                  context,
                  uiScale: uiScale,
                  label: '评分',
                  children: [
                    _optionChip(
                      context,
                      uiScale: uiScale,
                      label: '全部',
                      selected: noRatingFilter,
                      onTap: () {
                        if (noRatingFilter) return;
                        _filterDebounce?.cancel();
                        _minRatingController.text = '';
                        _maxRatingController.text = '';
                        setState(() {
                          _minRating = null;
                          _maxRating = null;
                        });
                        _onFiltersChanged();
                      },
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _numberField(
                          context,
                          uiScale: uiScale,
                          controller: _minRatingController,
                          hintText: '最低',
                          decimal: true,
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6 * uiScale),
                          child: const Text('~'),
                        ),
                        _numberField(
                          context,
                          uiScale: uiScale,
                          controller: _maxRatingController,
                          hintText: '最高',
                          decimal: true,
                        ),
                      ],
                    ),
                  ],
                ),
                _filterRow(
                  context,
                  uiScale: uiScale,
                  label: '年份',
                  children: [
                    _optionChip(
                      context,
                      uiScale: uiScale,
                      label: '全部',
                      selected: noYearFilter,
                      onTap: () {
                        if (noYearFilter) return;
                        _filterDebounce?.cancel();
                        _yearFromController.text = '';
                        _yearToController.text = '';
                        setState(() {
                          _selectedYear = null;
                          _yearFrom = null;
                          _yearTo = null;
                        });
                        _onFiltersChanged();
                      },
                    ),
                    if (!usingServerYearList &&
                        canLoadMore &&
                        !_isLoadingGenresFromServer &&
                        !_isScanningYearsFromServer)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: '从服务器获取',
                        selected: false,
                        onTap: () => _maybeReloadServerGenres(force: true),
                      ),
                    if (_isLoadingGenresFromServer || _isScanningYearsFromServer)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4 * uiScale),
                        child: SizedBox(
                          width: 14 * uiScale,
                          height: 14 * uiScale,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    for (final y in displayYears)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: y.toString(),
                        selected: _selectedYear == y,
                        onTap: () {
                          _filterDebounce?.cancel();
                          final next = _selectedYear == y ? null : y;
                          _yearFromController.text = '';
                          _yearToController.text = '';
                          setState(() {
                            _selectedYear = next;
                            _yearFrom = null;
                            _yearTo = null;
                          });
                          _onFiltersChanged();
                        },
                      ),
                    if (yearList.length > displayYears.length)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: _showAllYears ? '收起' : '更多',
                        selected: _showAllYears,
                        onTap: () =>
                            setState(() => _showAllYears = !_showAllYears),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _numberField(
                          context,
                          uiScale: uiScale,
                          controller: _yearFromController,
                          hintText: '从',
                          decimal: false,
                          width: 78,
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6 * uiScale),
                          child: const Text('~'),
                        ),
                        _numberField(
                          context,
                          uiScale: uiScale,
                          controller: _yearToController,
                          hintText: '到',
                          decimal: false,
                          width: 78,
                        ),
                      ],
                    ),
                  ],
                ),
                _filterRow(
                  context,
                  uiScale: uiScale,
                  label: '类型',
                  children: [
                    _optionChip(
                      context,
                      uiScale: uiScale,
                      label: '全部',
                      selected: _selectedGenres.isEmpty,
                      onTap: () {
                        if (_selectedGenres.isEmpty) return;
                        setState(() => _selectedGenres.clear());
                        _onFiltersChanged();
                      },
                    ),
                    if (!usingServerGenreList && !_isLoadingGenresFromServer)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: '从服务器获取',
                        selected: false,
                        onTap: () => _maybeReloadServerGenres(force: true),
                      ),
                    if (_isLoadingGenresFromServer)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4 * uiScale),
                        child: SizedBox(
                          width: 14 * uiScale,
                          height: 14 * uiScale,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    for (final g in displayGenres)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: g,
                        selected: _selectedGenres.contains(g),
                        onTap: () {
                          setState(() {
                            if (_selectedGenres.contains(g)) {
                              _selectedGenres.remove(g);
                            } else {
                              _selectedGenres.add(g);
                            }
                          });
                          _onFiltersChanged();
                        },
                      ),
                    if (genreList.length > displayGenres.length)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: _showAllGenres ? '收起' : '更多(${genreList.length})',
                        selected: _showAllGenres,
                        onTap: () =>
                            setState(() => _showAllGenres = !_showAllGenres),
                      ),
                  ],
                ),
                _filterRow(
                  context,
                  uiScale: uiScale,
                  label: '完结状态',
                  children: [
                    for (final v in _SeriesStatusFilter.values)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: v.zhLabel,
                        selected: _seriesStatus == v,
                        onTap: () {
                          if (_seriesStatus == v) return;
                          setState(() => _seriesStatus = v);
                          _onFiltersChanged();
                        },
                      ),
                  ],
                ),
                _filterRow(
                  context,
                  uiScale: uiScale,
                  label: '观看',
                  children: [
                    for (final v in _PlayedFilter.values)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: v.zhLabel,
                        selected: _played == v,
                        onTap: () {
                          if (_played == v) return;
                          setState(() => _played = v);
                          _onFiltersChanged();
                        },
                      ),
                  ],
                ),
                _filterRow(
                  context,
                  uiScale: uiScale,
                  label: '喜欢',
                  children: [
                    for (final v in _FavoriteFilter.values)
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: v.zhLabel,
                        selected: _favorite == v,
                        onTap: () {
                          if (_favorite == v) return;
                          setState(() => _favorite = v);
                          _onFiltersChanged();
                        },
                      ),
                  ],
                ),
                if (customPrefixEnabled)
                  _filterRow(
                    context,
                    uiScale: uiScale,
                    label: '自定义前缀',
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints.tightFor(
                          width: 220 * uiScale,
                          height: 34 * uiScale,
                        ),
                        child: TextField(
                          controller: _customPrefixInputController,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '前缀:值（如 语言:中文）',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8 * uiScale,
                              vertical: 9 * uiScale,
                            ),
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          onSubmitted: (_) => _addCustomPrefixFromInput(),
                        ),
                      ),
                      _optionChip(
                        context,
                        uiScale: uiScale,
                        label: '添加',
                        selected: false,
                        onTap: _addCustomPrefixFromInput,
                      ),
                      if (_customPrefixSelections.isNotEmpty)
                        _optionChip(
                          context,
                          uiScale: uiScale,
                          label: '清空',
                          selected: false,
                          onTap: () {
                            setState(() => _customPrefixSelections.clear());
                            _onFiltersChanged();
                          },
                        ),
                      for (final entry in (_customPrefixSelections.entries.toList()
                        ..sort((a, b) =>
                            a.key.toLowerCase().compareTo(b.key.toLowerCase()))))
                        _optionChip(
                          context,
                          uiScale: uiScale,
                          label: '${entry.key}:${(entry.value ?? '').trim()} ×',
                          selected: true,
                          onTap: () {
                            setState(() => _customPrefixSelections.remove(entry.key));
                            _onFiltersChanged();
                          },
                        ),
                    ],
                  ),
              ],
            ),
          );
        }

        Widget content() {
          if (allItems.isEmpty && _loadingMore) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_error != null && allItems.isEmpty) {
            return Center(child: Text(_error!));
          }

          if (items.isEmpty && allItems.isNotEmpty) {
            final total = widget.appState.getTotal(widget.parentId);
            final canLoadMore = total == 0 || allItems.length < total;
            final canAutoLoad = _emptyAutoLoadAttempts < _kEmptyAutoLoadMaxAttempts;
            if (canLoadMore && !_isRequesting && !_loadingMore && canAutoLoad) {
              _scheduleEmptyAutoLoadMore();
            }

            final showLoading = canLoadMore && (_loadingMore || _isRequesting);
            final showManualLoad = canLoadMore && !canAutoLoad;

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (canLoadMore && canAutoLoad)
                          ? '没有匹配的项目，继续加载中…'
                          : '没有匹配的项目',
                    ),
                    if (showLoading) ...[
                      const SizedBox(height: 12),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    if (showManualLoad) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loadingMore
                            ? null
                            : () => unawaited(_load(reset: false, limit: 200)),
                        child: const Text('继续加载'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(12),
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleGridScrollNotification,
              child: GridView.builder(
                controller: _scroll,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxCrossAxisExtent,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.7,
                ),
                itemCount: items.length + (_loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= items.length) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final item = items[index];
                  return _GridItem(
                    item: item,
                    access: access,
                    onTap: () {
                      final openItem = widget.onOpenItem;
                      if (openItem != null) {
                        openItem(item);
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context)
                              .pop(LibraryItemsPageResult.openedItem);
                        }
                        return;
                      }

                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShowDetailPage(
                            itemId: item.id,
                            title: item.name,
                            appState: widget.appState,
                            isTv: isTv,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );
        }

        return Scaffold(
          appBar: GlassAppBar(
            enableBlur: enableBlur,
            child: AppBar(
              title: Text(widget.title),
            ),
          ),
          body: Column(
            children: [
              if (!isTv)
                ClipRect(
                  child: Align(
                    alignment: Alignment.topLeft,
                    heightFactor: _topControlsVisibility,
                    child: Opacity(
                      opacity: _topControlsVisibility,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          10 * uiScale,
                          12,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10 * uiScale,
                              runSpacing: 10 * uiScale,
                              children: [
                                sortButton(),
                                filterButton(),
                              ],
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (child, anim) {
                                return FadeTransition(
                                  opacity: anim,
                                  child: SizeTransition(
                                    sizeFactor: anim,
                                    axisAlignment: -1,
                                    child: child,
                                  ),
                                );
                              },
                              child: (pinned || _filterPanelOpen)
                                  ? Container(
                                      key: const ValueKey('filterPanel'),
                                      child: filterPanel(),
                                    )
                                  : const SizedBox(
                                      key: ValueKey('filterPanelClosed'),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(child: content()),
            ],
          ),
        );
      },
    );
  }
}
