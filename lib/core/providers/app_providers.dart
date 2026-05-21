import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_interfaces.dart';
import '../api/emby_api.dart';
import '../api/mock_api.dart';

/// 当前API客户端Provider
/// 
/// 基于当前活跃服务器自动创建EmbyApiClient；
/// 未登录时回退MockApiClient（用于首次启动/服务器列表页）。
final apiClientProvider = Provider<ApiClientFactory>((ref) {
  final server = ref.watch(currentServerProvider);
  if (server == null) return MockApiClient();
  final client = EmbyApiClient(
    baseUrl: server.activeLineUrl,
    authToken: server.authToken,
    userId: server.userId,
  );
  return client;
});

/// 认证状态Provider
final authStateProvider = StateProvider<AuthState>((ref) => AuthState.unauthenticated);

enum AuthState { unauthenticated, authenticating, authenticated, error }

/// 当前服务器Provider
final currentServerProvider = StateProvider<ServerConfig?>((ref) => null);

class ServerConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String? iconUrl;
  final String? remark;
  final List<ServerLine> lines;
  final int activeLineIndex;
  final String? username;
  final String? authToken;
  final String? userId;
  
  ServerConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.iconUrl,
    this.remark,
    this.lines = const [],
    this.activeLineIndex = 0,
    this.username,
    this.authToken,
    this.userId,
  });
  
  String get activeLineUrl => lines.isNotEmpty ? lines[activeLineIndex].url : baseUrl;
  
  ServerConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? iconUrl,
    String? remark,
    List<ServerLine>? lines,
    int? activeLineIndex,
    String? username,
    String? authToken,
    String? userId,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      remark: remark ?? this.remark,
      lines: lines ?? this.lines,
      activeLineIndex: activeLineIndex ?? this.activeLineIndex,
      username: username ?? this.username,
      authToken: authToken ?? this.authToken,
      userId: userId ?? this.userId,
    );
  }
}

class ServerLine {
  final String id;
  final String name;
  final String url;
  final String? remark;
  
  ServerLine({
    required this.id,
    required this.name,
    required this.url,
    this.remark,
  });
}

/// 服务器列表Provider
final serverListProvider = StateNotifierProvider<ServerListNotifier, List<ServerConfig>>((ref) {
  return ServerListNotifier();
});

class ServerListNotifier extends StateNotifier<List<ServerConfig>> {
  ServerListNotifier() : super([]);
  
  void addServer(ServerConfig server) {
    state = [...state, server];
  }
  
  void removeServer(String id) {
    state = state.where((s) => s.id != id).toList();
  }
  
  void updateServer(ServerConfig server) {
    state = state.map((s) => s.id == server.id ? server : s).toList();
  }
  
  void reorderServers(int oldIndex, int newIndex) {
    final servers = List<ServerConfig>.from(state);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final server = servers.removeAt(oldIndex);
    servers.insert(newIndex, server);
    state = servers;
  }
  
  void setActiveLine(String serverId, int lineIndex) {
    state = state.map((s) {
      if (s.id == serverId) {
        return s.copyWith(activeLineIndex: lineIndex);
      }
      return s;
    }).toList();
  }
}

/// 当前用户Provider
final currentUserProvider = FutureProvider<User?>((ref) async {
  final api = ref.watch(apiClientProvider);
  final authState = ref.watch(authStateProvider);
  
  if (authState != AuthState.authenticated) return null;
  
  try {
    return await api.user.getUser('current');
  } catch (e) {
    return null;
  }
});

/// 主题模式Provider
final themeModeProvider = StateProvider<ThemeModeOption>((ref) => ThemeModeOption.system);

enum ThemeModeOption { light, dark, system }

/// 播放器内核Provider
final playerCoreProvider = StateProvider<String>((ref) => 'video_player');

/// 默认播放速度Provider
final defaultPlaybackSpeedProvider = StateProvider<double>((ref) => 1.0);

/// 快进步长Provider（秒）
final skipForwardStepProvider = StateProvider<int>((ref) => 10);

/// 长按快进倍速Provider
final longPressSpeedProvider = StateProvider<double>((ref) => 2.0);

/// 硬件解码Provider
final hardwareDecodingProvider = StateProvider<bool>((ref) => true);

/// 后台播放Provider
final backgroundPlaybackProvider = StateProvider<bool>((ref) => true);

/// 自动播放下一集Provider
final autoPlayNextProvider = StateProvider<bool>((ref) => true);

/// 弹幕开关Provider
final danmakuEnabledProvider = StateProvider<bool>((ref) => true);

/// 弹幕透明度Provider
final danmakuOpacityProvider = StateProvider<double>((ref) => 0.8);

/// 弹幕字号Provider
final danmakuFontSizeProvider = StateProvider<double>((ref) => 0.5);

/// 弹幕速度Provider
final danmakuSpeedProvider = StateProvider<double>((ref) => 0.5);

/// 弹幕密度Provider
final danmakuDensityProvider = StateProvider<double>((ref) => 0.5);

/// 弹幕屏蔽词列表Provider
final danmakuBlockwordsProvider = StateNotifierProvider<DanmakuBlockwordsNotifier, List<String>>((ref) {
  return DanmakuBlockwordsNotifier();
});

class DanmakuBlockwordsNotifier extends StateNotifier<List<String>> {
  DanmakuBlockwordsNotifier() : super([]);

  void addWord(String word) {
    if (word.isNotEmpty && !state.contains(word)) {
      state = [...state, word];
    }
  }

  void removeWord(String word) {
    state = state.where((w) => w != word).toList();
  }

  void importWords(List<String> words) {
    final newWords = words.where((w) => w.isNotEmpty && !state.contains(w)).toList();
    if (newWords.isNotEmpty) {
      state = [...state, ...newWords];
    }
  }

  void importUserBlocks(List<String> userIds) {
    // 用户ID屏蔽也作为文本屏蔽词存储，前缀为 "uid:"
    final prefixedIds = userIds.map((id) => 'uid:$id').toList();
    importWords(prefixedIds);
  }

  void clear() {
    state = [];
  }
}

/// ==========================================
/// 播放器设置Providers
/// ==========================================

/// 首选字幕语言Provider
final preferredSubtitleLanguageProvider = StateProvider<String>((ref) => 'chi');

/// 首选音频语言Provider
final preferredAudioLanguageProvider = StateProvider<String>((ref) => 'jpn');

/// 首选版本Provider
final preferredVersionProvider = StateProvider<String>((ref) => '原盘');

/// 记忆亮度Provider
final rememberBrightnessProvider = StateProvider<bool>((ref) => true);

/// 当前播放亮度值Provider (0.0 - 1.0)
final playerBrightnessProvider = StateProvider<double>((ref) => 1.0);

/// 字幕字体Provider
final subtitleFontProvider = StateProvider<String>((ref) => '默认');

/// MPV自动修正杜比视界颜色Provider
final mpvDolbyVisionFixProvider = StateProvider<bool>((ref) => false);

/// 启用Impeller渲染引擎Provider
final impellerEnabledProvider = StateProvider<bool>((ref) => false);

/// EXO播放器使用libass渲染ASS字幕Provider
final exoLibassProvider = StateProvider<bool>((ref) => false);

/// ==========================================
/// 外观设置Providers
/// ==========================================

/// 隐藏每日推荐Provider
final hideDailyRecommendationsProvider = StateProvider<bool>((ref) => false);

/// ==========================================
/// WebDAV备份Providers
/// ==========================================

/// WebDAV配置Provider
final webdavConfigProvider = StateNotifierProvider<WebdavConfigNotifier, WebdavConfig?>((ref) {
  return WebdavConfigNotifier();
});

class WebdavConfigNotifier extends StateNotifier<WebdavConfig?> {
  WebdavConfigNotifier() : super(null);

  void setConfig(String serverUrl, String username, String password) {
    state = WebdavConfig(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }

  void clearConfig() {
    state = null;
  }
}

class WebdavConfig {
  final String serverUrl;
  final String username;
  final String password;

  WebdavConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
  });
}
