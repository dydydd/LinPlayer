import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linplayer_mobile/core/api/api_interfaces.dart';
import 'package:linplayer_mobile/core/services/watch_history/watch_history_models.dart';
import 'package:linplayer_mobile/core/services/watch_history/watch_history_service.dart';
import 'package:linplayer_mobile/core/services/watch_history/watch_history_store.dart';

void main() {
  group('WatchHistoryService.resolveResumePositionTicks', () {
    test('prefers newer local progress when server progress is behind',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('watch-history-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = WatchHistoryStore(
        directoryResolver: () async => tempDir,
      );
      final service = WatchHistoryService(store: store);
      final item = MediaItem(
        id: 'movie-1',
        name: 'Castle in the Sky',
        type: 'Movie',
        providerIds: const {'Tmdb': '10515'},
        runTimeTicks: 72000000000,
      );

      await store.saveRecord(
        WatchHistoryRecord(
          recordId: 'local-record',
          scopeKey: 'server:user',
          mediaKind: WatchHistoryMediaKind.movie,
          canonicalKey: 'movie:tmdb:10515',
          tmdbId: '10515',
          title: item.name,
          lastPositionTicks: 28000000000,
          runTimeTicks: item.runTimeTicks,
          played: false,
          playCount: 1,
          lastPlayedAt: DateTime.utc(2026, 6, 14, 9),
          lastWriteSource: WatchHistoryWriteSource.internalPlayer,
          lastEmbyItemId: item.id,
        ),
      );

      final resolved = await service.resolveResumePositionTicks(
        scopeKey: 'server:user',
        api: _FakeApiClientFactory(),
        item: item,
        remotePositionTicks: 12000000000,
      );

      expect(resolved, 28000000000);
    });

    test('keeps server progress when local record is older', () async {
      final tempDir = await Directory.systemTemp.createTemp('watch-history-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = WatchHistoryStore(
        directoryResolver: () async => tempDir,
      );
      final service = WatchHistoryService(store: store);
      final item = MediaItem(
        id: 'movie-2',
        name: 'Perfect Blue',
        type: 'Movie',
        providerIds: const {'Tmdb': '10494'},
        runTimeTicks: 48000000000,
      );

      await store.saveRecord(
        WatchHistoryRecord(
          recordId: 'local-record',
          scopeKey: 'server:user',
          mediaKind: WatchHistoryMediaKind.movie,
          canonicalKey: 'movie:tmdb:10494',
          tmdbId: '10494',
          title: item.name,
          lastPositionTicks: 10000000000,
          runTimeTicks: item.runTimeTicks,
          played: false,
          playCount: 1,
          lastPlayedAt: DateTime.utc(2026, 6, 14, 9),
          lastWriteSource: WatchHistoryWriteSource.internalPlayer,
          lastEmbyItemId: item.id,
        ),
      );

      final resolved = await service.resolveResumePositionTicks(
        scopeKey: 'server:user',
        api: _FakeApiClientFactory(),
        item: item,
        remotePositionTicks: 22000000000,
      );

      expect(resolved, 22000000000);
    });

    test('does not resume finished items from local history', () async {
      final tempDir = await Directory.systemTemp.createTemp('watch-history-');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = WatchHistoryStore(
        directoryResolver: () async => tempDir,
      );
      final service = WatchHistoryService(store: store);
      final item = MediaItem(
        id: 'movie-3',
        name: 'Paprika',
        type: 'Movie',
        providerIds: const {'Tmdb': '4977'},
        runTimeTicks: 54000000000,
      );

      await store.saveRecord(
        WatchHistoryRecord(
          recordId: 'local-record',
          scopeKey: 'server:user',
          mediaKind: WatchHistoryMediaKind.movie,
          canonicalKey: 'movie:tmdb:4977',
          tmdbId: '4977',
          title: item.name,
          lastPositionTicks: 50000000000,
          runTimeTicks: item.runTimeTicks,
          played: true,
          playCount: 1,
          lastPlayedAt: DateTime.utc(2026, 6, 14, 9),
          lastWriteSource: WatchHistoryWriteSource.internalPlayer,
          lastEmbyItemId: item.id,
        ),
      );

      final resolved = await service.resolveResumePositionTicks(
        scopeKey: 'server:user',
        api: _FakeApiClientFactory(),
        item: item,
        remotePositionTicks: 0,
      );

      expect(resolved, isNull);
    });
  });
}

class _FakeApiClientFactory implements ApiClientFactory {
  @override
  AuthApi get auth => throw UnimplementedError();

  @override
  UserApi get user => throw UnimplementedError();

  @override
  ServerApi get server => throw UnimplementedError();

  @override
  HomeApi get home => throw UnimplementedError();

  @override
  LibraryApi get library => throw UnimplementedError();

  @override
  MediaApi get media => _FakeMediaApi();

  @override
  SearchApi get search => throw UnimplementedError();

  @override
  PlaybackApi get playback => throw UnimplementedError();

  @override
  FavoriteApi get favorite => throw UnimplementedError();

  @override
  SessionApi get session => throw UnimplementedError();

  @override
  ImageApi get image => throw UnimplementedError();

  @override
  void switchLine(String lineUrl) => throw UnimplementedError();

  @override
  String get currentLine => throw UnimplementedError();

  @override
  void setAuthToken(String token) => throw UnimplementedError();

  @override
  void clearAuth() => throw UnimplementedError();
}

class _FakeMediaApi implements MediaApi {
  @override
  Future<MediaItem> getItemDetails(String itemId) {
    throw UnimplementedError();
  }

  @override
  Future<List<MediaItem>> getSimilarItems(String itemId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Season>> getSeasons(String seriesId) {
    throw UnimplementedError();
  }

  @override
  Future<List<Episode>> getEpisodes(String seriesId, {String? seasonId}) {
    throw UnimplementedError();
  }

  @override
  Future<List<Person>> getPersonItems(String personName) {
    throw UnimplementedError();
  }
}
