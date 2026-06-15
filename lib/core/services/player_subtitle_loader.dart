import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_interfaces.dart';
import 'app_logger.dart';
import 'subtitle_processor.dart';
import 'video_player_service.dart';

/// 播放器字幕加载（内封轨道选择 + 外挂下载/转码），三端共用。
///
/// 把原本散在移动端播放页里的字幕逻辑收敛成一处：编解码归一、外挂字幕下载、
/// ExoPlayer 的 ASS（libass 或转 SRT）处理、按首选语言挑轨。TV / 移动端都可调用。
class PlayerSubtitleLoader {
  static final _logger = AppLogger();

  /// 按首选语言加载字幕：内封走播放器轨道选择，外挂下载到本地再加载。
  /// 返回选中的 Emby 字幕流 index（供 UI 记录当前选择），无可用字幕时返回 null。
  static Future<int?> loadPreferred({
    required VideoPlayerService service,
    required ApiClientFactory api,
    required String itemId,
    required MediaSource mediaSource,
    required String? preferredLanguage,
    required bool exoLibassEnabled,
    String? authToken,
  }) async {
    final subtitleStreams =
        mediaSource.mediaStreams.where((s) => s.isSubtitle).toList();
    if (subtitleStreams.isEmpty) return null;

    final target = subtitleStreams.firstWhere(
      (s) => preferredLanguage != null && s.language == preferredLanguage,
      orElse: () => subtitleStreams.first,
    );
    final codec = target.codec?.toLowerCase() ?? 'ass';
    final isExternal = target.isExternal ?? false;
    final core = service.coreType;

    try {
      if (!isExternal) {
        await _selectInternal(service, target, preferredLanguage);
      } else {
        await _loadExternal(
          service: service,
          api: api,
          itemId: itemId,
          mediaSource: mediaSource,
          target: target,
          codec: codec,
          core: core,
          exoLibassEnabled: exoLibassEnabled,
          authToken: authToken,
        );
      }
    } catch (e, st) {
      _logger.eWithStack('SubtitleLoader', '字幕加载失败', e, st);
    }
    return target.index;
  }

  // ---- 内封：按语言在播放器轨道里挑 ----

  static Future<void> _selectInternal(
      VideoPlayerService service, MediaStream target, String? lang) async {
    final subs = service.tracksInfo
        .where((t) =>
            (t['type'] == 'text' || t['type'] == 'bitmap') &&
            t['id'] != 'auto' &&
            t['id'] != 'no')
        .toList();
    if (subs.isEmpty) return;

    // 优先按 trackIndex 对齐 Emby 流，再按语言，最后退首条。
    Map<String, dynamic>? picked;
    for (final t in subs) {
      if (t['trackIndex']?.toString() == target.index.toString()) {
        picked = t;
        break;
      }
    }
    picked ??= subs.firstWhere(
      (t) => lang != null && t['language']?.toString() == lang,
      orElse: () => subs.first,
    );
    final id = picked['id']?.toString();
    if (id != null) await service.selectSubtitleTrack(id);
  }

  // ---- 外挂：下载到临时文件后加载 ----

  static Future<void> _loadExternal({
    required VideoPlayerService service,
    required ApiClientFactory api,
    required String itemId,
    required MediaSource mediaSource,
    required MediaStream target,
    required String codec,
    required PlayerCoreType core,
    required bool exoLibassEnabled,
    String? authToken,
  }) async {
    final embyCodec = embySubtitleCodec(codec, core);
    final subUrl = api.playback
        .getSubtitleStreamUrl(itemId, mediaSource.id, target.index, embyCodec);
    final ext = subtitleFileExtension(codec, core);
    final file = await _prepareFile(
      subtitleUrl: subUrl,
      fileName: 'subtitle_${itemId}_${target.index}.$ext',
      codec: codec,
      core: core,
      exoLibassEnabled: exoLibassEnabled,
      authToken: authToken,
    );
    if (file.existsSync() && await file.length() > 0) {
      await service.loadLibassSubtitle(file.path);
      _logger.i('SubtitleLoader', '外挂字幕加载成功: ${file.path}');
    }
  }

  static Future<File> _prepareFile({
    required String subtitleUrl,
    required String fileName,
    required String codec,
    required PlayerCoreType core,
    required bool exoLibassEnabled,
    String? authToken,
  }) async {
    final source = await _download(subtitleUrl, fileName, authToken);
    if (core != PlayerCoreType.exoPlayer) return source;

    // ExoPlayer：ASS 开了 libass 就保留原文件交原生管线；否则转 SRT 兼容。
    if (isAssSubtitleCodec(codec)) {
      if (exoLibassEnabled) return source;
      final outPath = source.path.replaceFirst(RegExp(r'\.[^.]+$'), '.srt');
      final converted =
          await SubtitleProcessor.convertAssToSrt(source.path, outputPath: outPath);
      return File(converted);
    }
    return source;
  }

  static Future<File> _download(
      String url, String fileName, String? authToken) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    if (!file.existsSync() || await file.length() == 0) {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
      ));
      if (authToken != null) {
        dio.options.headers['X-Emby-Token'] = authToken;
        dio.options.headers['X-MediaBrowser-Token'] = authToken;
      }
      await dio.download(url, file.path);
    }
    return file;
  }

  // ---- 编解码归一（纯函数，可独立复用）----

  static String embySubtitleCodec(String codec, PlayerCoreType core) {
    final lower = codec.toLowerCase();
    final isPgs = lower == 'pgssub' ||
        lower == 'pgs' ||
        lower == 'sup' ||
        lower.contains('hdmv');
    final isMpv =
        core == PlayerCoreType.mpv || core == PlayerCoreType.nativeMpv;
    if (isMpv) {
      switch (lower) {
        case 'srt' || 'subrip':
          return 'srt';
        case 'vtt' || 'webvtt':
          return 'vtt';
        default:
          return isPgs ? 'pgs' : 'ass';
      }
    }
    switch (lower) {
      case 'srt' || 'subrip':
        return 'srt';
      case 'vtt' || 'webvtt':
        return 'vtt';
      case 'ass' || 'ssa':
        return 'ass';
      case 'pgssub' || 'pgs' || 'sup':
        return 'pgs';
      default:
        return isPgs ? 'pgs' : 'srt';
    }
  }

  static String subtitleFileExtension(String codec, PlayerCoreType core) {
    final lower = codec.toLowerCase();
    if (lower == 'srt' || lower == 'subrip') return 'srt';
    if (lower == 'vtt' || lower == 'webvtt') return 'vtt';
    if (lower == 'ass' || lower == 'ssa') return 'ass';
    if (isGraphicalSubtitleCodec(lower)) return 'sup';
    final isMpv =
        core == PlayerCoreType.mpv || core == PlayerCoreType.nativeMpv;
    return isMpv ? 'ass' : 'srt';
  }

  static bool isAssSubtitleCodec(String codec) {
    final lower = codec.toLowerCase();
    return lower == 'ass' || lower == 'ssa';
  }

  static bool isGraphicalSubtitleCodec(String codec) {
    final lower = codec.toLowerCase();
    return lower == 'pgssub' ||
        lower == 'sup' ||
        lower == 'pgs' ||
        lower == 'dvdsub' ||
        lower == 'vobsub' ||
        lower.contains('hdmv') ||
        lower.contains('pgs');
  }
}
