import 'api_interfaces.dart';

/// Mock API实现 - 用于UI开发和测试
/// 
/// TODO: API开发人员实现真实客户端后，替换此实现
class MockApiClient implements ApiClientFactory {
  String _currentLine = 'https://mock.example.com';
  
  @override
  AuthApi get auth => MockAuthApi();
  
  @override
  UserApi get user => MockUserApi();
  
  @override
  ServerApi get server => MockServerApi();
  
  @override
  HomeApi get home => MockHomeApi();
  
  @override
  LibraryApi get library => MockLibraryApi();
  
  @override
  MediaApi get media => MockMediaApi();
  
  @override
  SearchApi get search => MockSearchApi();
  
  @override
  PlaybackApi get playback => MockPlaybackApi();
  
  @override
  FavoriteApi get favorite => MockFavoriteApi();
  
  @override
  SessionApi get session => MockSessionApi();
  
  @override
  ImageApi get image => MockImageApi();

  @override
  void switchLine(String lineUrl) {
    _currentLine = lineUrl;
  }
  
  @override
  String get currentLine => _currentLine;
  
  @override
  void setAuthToken(String token) {}
  
  @override
  void clearAuth() {}
}

class MockAuthApi implements AuthApi {
  @override
  Future<AuthResult> login({required String username, required String password}) async {
    await Future.delayed(const Duration(seconds: 1));
    return AuthResult(
      accessToken: 'mock_token_${DateTime.now().millisecondsSinceEpoch}',
      userId: 'mock_user_id',
      serverId: 'mock_server_id',
      user: User(id: 'mock_user_id', name: username),
    );
  }
  
  @override
  Future<void> logout() async {}
  
  @override
  Future<User> getCurrentUser() async {
    return User(id: 'mock_user_id', name: 'Mock User');
  }
  
  @override
  Future<AuthResult> refreshToken() async {
    return AuthResult(
      accessToken: 'mock_refreshed_token',
      userId: 'mock_user_id',
      serverId: 'mock_server_id',
      user: User(id: 'mock_user_id', name: 'Mock User'),
    );
  }
}

class MockUserApi implements UserApi {
  @override
  Future<User> getUser(String userId) async {
    return User(id: userId, name: 'Mock User');
  }
}

class MockServerApi implements ServerApi {
  @override
  Future<ServerInfo> getPublicInfo(String baseUrl) async {
    return ServerInfo(
      id: 'mock_server',
      serverName: 'Mock Server',
      version: '4.8.0',
      productName: 'Emby Server',
    );
  }
  
  @override
  Future<ServerInfo> getSystemInfo() async {
    return ServerInfo(
      id: 'mock_server',
      serverName: 'Mock Server',
      version: '4.8.0',
    );
  }
  
  @override
  Future<bool> testConnection(String baseUrl) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }
}

class MockHomeApi implements HomeApi {
  @override
  Future<List<MediaItem>> getResumeItems() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return _generateMockItems(6, type: 'Episode');
  }
  
  @override
  Future<List<MediaItem>> getNextUp() async {
    return _generateMockItems(4, type: 'Episode');
  }
  
  @override
  Future<List<Library>> getLibraries() async {
    return [
      Library(id: 'lib1', name: '电影', collectionType: 'movies'),
      Library(id: 'lib2', name: '剧集', collectionType: 'tvshows'),
      Library(id: 'lib3', name: '动画', collectionType: 'tvshows'),
    ];
  }
  
  @override
  Future<List<MediaItem>> getLatestItems(String libraryId, {int limit = 20}) async {
    return _generateMockItems(limit, type: libraryId == 'lib1' ? 'Movie' : 'Series');
  }
  
  @override
  Future<List<MediaItem>> getRandomRecommendations({int limit = 8}) async {
    return _generateMockItems(limit, type: 'Movie', withBackdrop: true);
  }
}

class MockLibraryApi implements LibraryApi {
  @override
  Future<List<MediaItem>> getLibraryItems({
    required String libraryId,
    String? sortBy,
    String? sortOrder,
    int startIndex = 0,
    int limit = 50,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return _generateMockItems(limit, type: libraryId == 'lib1' ? 'Movie' : 'Series');
  }
  
  @override
  Future<Filters> getFilters(String libraryId) async {
    return Filters(
      genres: ['动作', '科幻', '剧情', '动画'],
      years: ['2024', '2023', '2022', '2021'],
      officialRatings: ['PG-13', 'R', 'TV-14'],
    );
  }
}

class MockMediaApi implements MediaApi {
  @override
  Future<MediaItem> getItemDetails(String itemId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return MediaItem(
      id: itemId,
      name: '进击的巨人',
      type: 'Series',
      overview: '这是一部讲述人类与巨人之间战斗的史诗故事。在巨人的威胁下，人类被迫生活在高墙之内。少年艾伦·耶格尔发誓要消灭所有巨人，为母亲报仇。',
      communityRating: 9.1,
      officialRating: 'TV-MA',
      productionYear: 2013,
      genres: ['动作', '奇幻', '动画'],
      tags: ['热血', '战斗', '生存'],
      userData: UserData(played: false, isFavorite: true),
    );
  }
  
  @override
  Future<List<MediaItem>> getSimilarItems(String itemId) async {
    return _generateMockItems(6, type: 'Series');
  }
  
  @override
  Future<List<Season>> getSeasons(String seriesId) async {
    return [
      Season(id: 's1', name: '第一季', indexNumber: 1, seriesId: seriesId),
      Season(id: 's2', name: '第二季', indexNumber: 2, seriesId: seriesId),
      Season(id: 's3', name: '第三季', indexNumber: 3, seriesId: seriesId),
    ];
  }
  
  @override
  Future<List<Episode>> getEpisodes(String seriesId, {String? seasonId}) async {
    return List.generate(12, (index) => Episode(
      id: 'ep$index',
      name: '第${index + 1}集',
      indexNumber: index + 1,
      seriesId: seriesId,
      seasonId: seasonId ?? 's1',
      runTimeTicks: 1440000000,
      userData: UserData(
        playbackPositionTicks: index == 0 ? 720000000 : null,
        played: index < 2,
      ),
      overview: '这是第${index + 1}集的简介...',
    ));
  }
  
  @override
  Future<List<Person>> getPersonItems(String personName) async {
    return _generateMockPersons(8);
  }
}

class MockSearchApi implements SearchApi {
  @override
  Future<List<MediaItem>> getSearchHints(String query) async {
    return _generateMockItems(5);
  }
  
  @override
  Future<List<MediaItem>> search(String query, {bool recursive = true}) async {
    await Future.delayed(const Duration(milliseconds: 800));
    return _generateMockItems(10);
  }
  
  @override
  Future<Map<String, List<MediaItem>>> searchAggregate(String query) async {
    return {
      '服务器A': _generateMockItems(5),
      '服务器B': _generateMockItems(3),
    };
  }
}

class MockPlaybackApi implements PlaybackApi {
  @override
  Future<PlaybackInfo> getPlaybackInfo(String itemId) async {
    return PlaybackInfo(
      itemId: itemId,
      mediaSources: [
        MediaSource(
          id: 'source1',
          name: '原盘',
          container: 'mkv',
          size: 5368709120,
          runTimeTicks: 54000000000,
          mediaStreams: [
            MediaStream(index: 0, type: 'Video', codec: 'H264', width: 1920, height: 1080, displayTitle: 'H264 1080p'),
            MediaStream(index: 1, type: 'Audio', codec: 'AAC', language: 'jpn', channels: 2, displayTitle: '日语 AAC 2ch'),
            MediaStream(index: 2, type: 'Subtitle', codec: 'ASS', language: 'chi', displayTitle: '中文简体'),
          ],
        ),
        MediaSource(
          id: 'source2',
          name: 'HEVC',
          container: 'mkv',
          size: 3221225472,
          runTimeTicks: 54000000000,
          mediaStreams: [
            MediaStream(index: 0, type: 'Video', codec: 'HEVC', width: 3840, height: 2160, displayTitle: 'HEVC 4K HDR'),
            MediaStream(index: 1, type: 'Audio', codec: 'DTS', language: 'jpn', channels: 6, displayTitle: '日语 DTS 5.1'),
            MediaStream(index: 2, type: 'Subtitle', codec: 'ASS', language: 'cht', displayTitle: '中文繁体'),
          ],
        ),
      ],
    );
  }
  
  @override
  String getVideoStreamUrl(String itemId, {String? mediaSourceId}) {
    final suffix = mediaSourceId != null && mediaSourceId.isNotEmpty
        ? '?MediaSourceId=$mediaSourceId'
        : '';
    return 'https://mock.example.com/Videos/$itemId/stream$suffix';
  }

  @override
  String getSubtitleStreamUrl(String itemId, String mediaSourceId, int index, String codec) {
    return 'https://mock.example.com/Videos/$itemId/$mediaSourceId/Subtitles/$index/Stream.$codec';
  }
  
  @override
  Future<void> reportPlaybackStart(PlaybackStartInfo info) async {}
  
  @override
  Future<void> reportPlaybackProgress(PlaybackProgressInfo info) async {}
  
  @override
  Future<void> reportPlaybackStopped(PlaybackStopInfo info) async {}
}

class MockFavoriteApi implements FavoriteApi {
  @override
  Future<void> addFavorite(String itemId) async {}
  
  @override
  Future<void> removeFavorite(String itemId) async {}
}

class MockSessionApi implements SessionApi {
  @override
  Future<List<Session>> getSessions() async {
    return [];
  }
}

class MockImageApi implements ImageApi {
  @override
  String getImageUrl({
    required String itemId,
    String? imageTag,
    String imageType = 'Primary',
    int? maxWidth,
    int? maxHeight,
    double quality = 90,
  }) {
    // 使用picsum作为占位图
    final seed = itemId.hashCode.abs();
    return 'https://picsum.photos/seed/$seed/${maxWidth ?? 300}/${maxHeight ?? 450}';
  }
  
  @override
  String getPrimaryImageUrl(String itemId, {String? tag, int? maxWidth}) {
    return getImageUrl(itemId: itemId, imageTag: tag, maxWidth: maxWidth);
  }
  
  @override
  String getBackdropImageUrl(String itemId, {String? tag, int? maxWidth}) {
    return getImageUrl(
      itemId: itemId, 
      imageTag: tag, 
      imageType: 'Backdrop',
      maxWidth: maxWidth ?? 800,
      maxHeight: 450,
    );
  }
}

// ==================== Mock数据生成器 ====================

List<MediaItem> _generateMockItems(int count, {
  String type = 'Movie',
  bool withBackdrop = false,
}) {
  final titles = [
    '进击的巨人', '星际穿越', '千与千寻', '黑暗骑士', '寄生虫',
    '复仇者联盟', '你的名字', '肖申克的救赎', '盗梦空间', '泰坦尼克号',
    '阿甘正传', '辛德勒的名单', '指环王', '黑客帝国', '疯狂动物城',
  ];
  
  return List.generate(count, (index) {
    final title = titles[index % titles.length];
    return MediaItem(
      id: 'item_${DateTime.now().millisecondsSinceEpoch}_$index',
      name: '$title ${index > titles.length ? index + 1 : ""}',
      type: type,
      overview: '这是$title的简介...',
      primaryImageTag: 'tag_$index',
      backdropImageTag: withBackdrop ? 'backdrop_$index' : null,
      communityRating: 7.5 + (index % 20) / 10,
      officialRating: ['PG-13', 'R', 'TV-14', 'TV-MA'][index % 4],
      productionYear: 2020 + (index % 5),
      genres: ['动作', '科幻', '剧情'].sublist(0, 1 + index % 3),
      tags: ['热门', '推荐'],
      runTimeTicks: 54000000000 + index * 600000000,
      userData: UserData(
        playbackPositionTicks: index % 3 == 0 ? 1800000000 : null,
        played: index % 4 == 0,
        isFavorite: index % 5 == 0,
      ),
      seriesName: type == 'Episode' ? title : null,
      indexNumber: type == 'Episode' ? index + 1 : null,
      parentIndexNumber: type == 'Episode' ? 1 : null,
    );
  });
}

List<Person> _generateMockPersons(int count) {
  final names = ['三浦建太郎', '虚渊玄', '新海诚', '宫崎骏', '诺兰', '斯皮尔伯格'];
  return List.generate(count, (index) => Person(
    id: 'person_$index',
    name: names[index % names.length],
    role: index % 2 == 0 ? '导演' : '演员',
    type: index % 2 == 0 ? 'Director' : 'Actor',
  ));
}
