import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ReadBuffer, WriteBuffer;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_vlc_player_platform_interface/flutter_vlc_player_platform_interface.dart';

PlatformException _createConnectionError(String channelName) {
  return PlatformException(
    code: 'channel-error',
    message: 'Unable to establish connection on channel: "$channelName".',
  );
}

class _CompatCreateMessage {
  const _CompatCreateMessage({
    required this.playerId,
    required this.uri,
    required this.type,
    required this.packageName,
    required this.autoPlay,
    required this.hwAcc,
    required this.options,
  });

  final int playerId;
  final String uri;
  final int type;
  final String? packageName;
  final bool autoPlay;
  final int? hwAcc;
  final List<String> options;

  Object encode() {
    return <Object?>[
      playerId,
      uri,
      type,
      packageName,
      autoPlay,
      hwAcc,
      options,
    ];
  }

  static _CompatCreateMessage decode(Object result) {
    result as List<Object?>;
    return _CompatCreateMessage(
      playerId: result[0]! as int,
      uri: result[1]! as String,
      type: result[2]! as int,
      packageName: result[3] as String?,
      autoPlay: result[4]! as bool,
      hwAcc: result[5] as int?,
      options:
          (result[6] as List<Object?>?)?.cast<String>() ?? const <String>[],
    );
  }
}

class _CompatSetMediaMessage {
  const _CompatSetMediaMessage({
    required this.playerId,
    required this.uri,
    required this.type,
    required this.packageName,
    required this.autoPlay,
    required this.hwAcc,
  });

  final int playerId;
  final String uri;
  final int type;
  final String? packageName;
  final bool autoPlay;
  final int? hwAcc;

  Object encode() {
    return <Object?>[playerId, uri, type, packageName, autoPlay, hwAcc];
  }

  static _CompatSetMediaMessage decode(Object result) {
    result as List<Object?>;
    return _CompatSetMediaMessage(
      playerId: result[0]! as int,
      uri: result[1]! as String,
      type: result[2]! as int,
      packageName: result[3] as String?,
      autoPlay: result[4]! as bool,
      hwAcc: result[5] as int?,
    );
  }
}

class _CompatSpuTracksMessage {
  const _CompatSpuTracksMessage({
    required this.playerId,
    required this.subtitles,
  });

  final int playerId;
  final Map<Object?, Object?> subtitles;

  Object encode() {
    return <Object?>[playerId, subtitles];
  }

  static _CompatSpuTracksMessage decode(Object result) {
    result as List<Object?>;
    return _CompatSpuTracksMessage(
      playerId: result[0]! as int,
      subtitles:
          (result[1] as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
    );
  }
}

class _CompatAddSubtitleMessage {
  const _CompatAddSubtitleMessage({
    required this.playerId,
    required this.uri,
    required this.type,
    required this.isSelected,
  });

  final int playerId;
  final String uri;
  final int type;
  final bool isSelected;

  Object encode() {
    return <Object?>[playerId, uri, type, isSelected];
  }

  static _CompatAddSubtitleMessage decode(Object result) {
    result as List<Object?>;
    return _CompatAddSubtitleMessage(
      playerId: result[0]! as int,
      uri: result[1]! as String,
      type: result[2]! as int,
      isSelected: result[3]! as bool,
    );
  }
}

class _CompatAddAudioMessage {
  const _CompatAddAudioMessage({
    required this.playerId,
    required this.uri,
    required this.type,
    required this.isSelected,
  });

  final int playerId;
  final String uri;
  final int type;
  final bool isSelected;

  Object encode() {
    return <Object?>[playerId, uri, type, isSelected];
  }

  static _CompatAddAudioMessage decode(Object result) {
    result as List<Object?>;
    return _CompatAddAudioMessage(
      playerId: result[0]! as int,
      uri: result[1]! as String,
      type: result[2]! as int,
      isSelected: result[3]! as bool,
    );
  }
}

class _CompatVlcPigeonCodec extends StandardMessageCodec {
  const _CompatVlcPigeonCodec();

  @override
  void writeValue(WriteBuffer buffer, Object? value) {
    if (value is _CompatCreateMessage) {
      buffer.putUint8(129);
      writeValue(buffer, value.encode());
    } else if (value is _CompatSetMediaMessage) {
      buffer.putUint8(130);
      writeValue(buffer, value.encode());
    } else if (value is _CompatSpuTracksMessage) {
      buffer.putUint8(131);
      writeValue(buffer, value.encode());
    } else if (value is _CompatAddSubtitleMessage) {
      buffer.putUint8(132);
      writeValue(buffer, value.encode());
    } else if (value is _CompatAddAudioMessage) {
      buffer.putUint8(133);
      writeValue(buffer, value.encode());
    } else {
      super.writeValue(buffer, value);
    }
  }

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    switch (type) {
      case 129:
        return _CompatCreateMessage.decode(readValue(buffer)!);
      case 130:
        return _CompatSetMediaMessage.decode(readValue(buffer)!);
      case 131:
        return _CompatSpuTracksMessage.decode(readValue(buffer)!);
      case 132:
        return _CompatAddSubtitleMessage.decode(readValue(buffer)!);
      case 133:
        return _CompatAddAudioMessage.decode(readValue(buffer)!);
      default:
        return super.readValueOfType(type, buffer);
    }
  }
}

class _CompatVlcPlayerApi {
  _CompatVlcPlayerApi({BinaryMessenger? binaryMessenger})
    : _binaryMessenger = binaryMessenger;

  static const MessageCodec<Object?> pigeonChannelCodec =
      _CompatVlcPigeonCodec();
  static const String _prefix =
      'dev.flutter.pigeon.flutter_vlc_player_platform_interface.VlcPlayerApi.';

  final BinaryMessenger? _binaryMessenger;

  Future<List<Object?>> _send(String method, List<Object?>? args) async {
    final channelName = '$_prefix$method';
    final channel = BasicMessageChannel<Object?>(
      channelName,
      pigeonChannelCodec,
      binaryMessenger: _binaryMessenger,
    );
    final reply = await channel.send(args);
    final replyList = reply as List<Object?>?;
    if (replyList == null) {
      throw _createConnectionError(channelName);
    }
    if (replyList.length > 1) {
      throw PlatformException(
        code: replyList[0]! as String,
        message: replyList[1] as String?,
        details: replyList[2],
      );
    }
    return replyList;
  }

  Future<void> _sendVoid(String method, List<Object?>? args) async {
    await _send(method, args);
  }

  Future<T> _sendRequired<T>(String method, List<Object?>? args) async {
    final replyList = await _send(method, args);
    if (replyList.isEmpty || replyList[0] == null) {
      throw PlatformException(
        code: 'null-error',
        message: 'Host platform returned null value for $method.',
      );
    }
    return replyList[0] as T;
  }

  Future<T?> _sendNullable<T>(String method, List<Object?>? args) async {
    final replyList = await _send(method, args);
    if (replyList.isEmpty) return null;
    return replyList[0] as T?;
  }

  Future<void> initialize() => _sendVoid('initialize', null);

  Future<void> create(_CompatCreateMessage msg) =>
      _sendVoid('create', <Object?>[msg]);

  Future<void> dispose(int playerId) =>
      _sendVoid('dispose', <Object?>[playerId]);

  Future<void> setStreamUrl(_CompatSetMediaMessage msg) =>
      _sendVoid('setStreamUrl', <Object?>[msg]);

  Future<void> play(int playerId) => _sendVoid('play', <Object?>[playerId]);

  Future<void> pause(int playerId) => _sendVoid('pause', <Object?>[playerId]);

  Future<void> stop(int playerId) => _sendVoid('stop', <Object?>[playerId]);

  Future<bool> isPlaying(int playerId) =>
      _sendRequired<bool>('isPlaying', <Object?>[playerId]);

  Future<bool> isSeekable(int playerId) =>
      _sendRequired<bool>('isSeekable', <Object?>[playerId]);

  Future<void> setLooping(int playerId, bool looping) =>
      _sendVoid('setLooping', <Object?>[playerId, looping]);

  Future<void> seekTo(int playerId, int position) =>
      _sendVoid('seekTo', <Object?>[playerId, position]);

  Future<int> position(int playerId) =>
      _sendRequired<int>('position', <Object?>[playerId]);

  Future<int> duration(int playerId) =>
      _sendRequired<int>('duration', <Object?>[playerId]);

  Future<void> setVolume(int playerId, int volume) =>
      _sendVoid('setVolume', <Object?>[playerId, volume]);

  Future<int> getVolume(int playerId) =>
      _sendRequired<int>('getVolume', <Object?>[playerId]);

  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      _sendVoid('setPlaybackSpeed', <Object?>[playerId, speed]);

  Future<double> getPlaybackSpeed(int playerId) =>
      _sendRequired<double>('getPlaybackSpeed', <Object?>[playerId]);

  Future<String?> takeSnapshot(int playerId) =>
      _sendNullable<String>('takeSnapshot', <Object?>[playerId]);

  Future<int> getSpuTracksCount(int playerId) =>
      _sendRequired<int>('getSpuTracksCount', <Object?>[playerId]);

  Future<Map<Object?, Object?>?> getSpuTracks(int playerId) =>
      _sendNullable<Map<Object?, Object?>>('getSpuTracks', <Object?>[playerId]);

  Future<void> setSpuTrack(int playerId, int spuTrackNumber) =>
      _sendVoid('setSpuTrack', <Object?>[playerId, spuTrackNumber]);

  Future<int> getSpuTrack(int playerId) =>
      _sendRequired<int>('getSpuTrack', <Object?>[playerId]);

  Future<void> setSpuDelay(int playerId, int delay) =>
      _sendVoid('setSpuDelay', <Object?>[playerId, delay]);

  Future<int> getSpuDelay(int playerId) =>
      _sendRequired<int>('getSpuDelay', <Object?>[playerId]);

  Future<void> addSubtitleTrack(_CompatAddSubtitleMessage msg) =>
      _sendVoid('addSubtitleTrack', <Object?>[msg]);

  Future<int> getAudioTracksCount(int playerId) =>
      _sendRequired<int>('getAudioTracksCount', <Object?>[playerId]);

  Future<Map<Object?, Object?>?> getAudioTracks(int playerId) =>
      _sendNullable<Map<Object?, Object?>>('getAudioTracks', <Object?>[
        playerId,
      ]);

  Future<void> setAudioTrack(int playerId, int audioTrackNumber) =>
      _sendVoid('setAudioTrack', <Object?>[playerId, audioTrackNumber]);

  Future<int> getAudioTrack(int playerId) =>
      _sendRequired<int>('getAudioTrack', <Object?>[playerId]);

  Future<void> setAudioDelay(int playerId, int delay) =>
      _sendVoid('setAudioDelay', <Object?>[playerId, delay]);

  Future<int> getAudioDelay(int playerId) =>
      _sendRequired<int>('getAudioDelay', <Object?>[playerId]);

  Future<void> addAudioTrack(_CompatAddAudioMessage msg) =>
      _sendVoid('addAudioTrack', <Object?>[msg]);

  Future<int> getVideoTracksCount(int playerId) =>
      _sendRequired<int>('getVideoTracksCount', <Object?>[playerId]);

  Future<Map<Object?, Object?>?> getVideoTracks(int playerId) =>
      _sendNullable<Map<Object?, Object?>>('getVideoTracks', <Object?>[
        playerId,
      ]);

  Future<void> setVideoTrack(int playerId, int videoTrackNumber) =>
      _sendVoid('setVideoTrack', <Object?>[playerId, videoTrackNumber]);

  Future<int> getVideoTrack(int playerId) =>
      _sendRequired<int>('getVideoTrack', <Object?>[playerId]);

  Future<void> setVideoScale(int playerId, double scale) =>
      _sendVoid('setVideoScale', <Object?>[playerId, scale]);

  Future<double> getVideoScale(int playerId) =>
      _sendRequired<double>('getVideoScale', <Object?>[playerId]);

  Future<void> setVideoAspectRatio(int playerId, String aspectRatio) =>
      _sendVoid('setVideoAspectRatio', <Object?>[playerId, aspectRatio]);

  Future<String> getVideoAspectRatio(int playerId) =>
      _sendRequired<String>('getVideoAspectRatio', <Object?>[playerId]);

  Future<List<Object?>?> getAvailableRendererServices(int playerId) =>
      _sendNullable<List<Object?>>('getAvailableRendererServices', <Object?>[
        playerId,
      ]);

  Future<void> startRendererScanning(int playerId, String rendererService) =>
      _sendVoid('startRendererScanning', <Object?>[playerId, rendererService]);

  Future<void> stopRendererScanning(int playerId) =>
      _sendVoid('stopRendererScanning', <Object?>[playerId]);

  Future<Map<Object?, Object?>?> getRendererDevices(int playerId) =>
      _sendNullable<Map<Object?, Object?>>('getRendererDevices', <Object?>[
        playerId,
      ]);

  Future<void> castToRenderer(int playerId, String rendererId) =>
      _sendVoid('castToRenderer', <Object?>[playerId, rendererId]);

  Future<bool> startRecording(int playerId, String saveDirectory) =>
      _sendRequired<bool>('startRecording', <Object?>[playerId, saveDirectory]);

  Future<bool> stopRecording(int playerId) =>
      _sendRequired<bool>('stopRecording', <Object?>[playerId]);
}

class LinPlayerMethodChannelVlcPlayer extends VlcPlayerPlatform {
  LinPlayerMethodChannelVlcPlayer({BinaryMessenger? binaryMessenger})
    : _api = _CompatVlcPlayerApi(binaryMessenger: binaryMessenger);

  final _CompatVlcPlayerApi _api;
  Future<void>? _initFuture;

  EventChannel _mediaEventChannelFor(int viewId) {
    return EventChannel('flutter_video_plugin/getVideoEvents_$viewId');
  }

  EventChannel _rendererEventChannelFor(int viewId) {
    return EventChannel('flutter_video_plugin/getRendererEvents_$viewId');
  }

  void _ensureSupportedPlatform() {
    if (!Platform.isIOS) {
      throw UnsupportedError('LinPlayer VLC core is only available on iOS.');
    }
  }

  Future<void> _ensureHostInitialized() {
    _ensureSupportedPlatform();
    return _initFuture ??= _api.initialize().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _initFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  @override
  Future<void> init() => _ensureHostInitialized();

  @override
  Widget buildView(
    PlatformViewCreatedCallback onPlatformViewCreated, {
    bool virtualDisplay = true,
  }) {
    if (!Platform.isIOS) {
      return const Text(
        'LinPlayer VLC core is only available on iOS.',
        textDirection: TextDirection.ltr,
      );
    }
    return UiKitView(
      viewType: 'flutter_video_plugin/getVideoView',
      onPlatformViewCreated: onPlatformViewCreated,
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  @override
  Future<void> create({
    required int viewId,
    required String uri,
    required DataSourceType type,
    String? package,
    bool? autoPlay,
    HwAcc? hwAcc,
    VlcPlayerOptions? options,
  }) async {
    await _ensureHostInitialized();
    final message = _CompatCreateMessage(
      playerId: viewId,
      uri: uri,
      type: type.index,
      packageName: package,
      autoPlay: autoPlay ?? true,
      hwAcc: hwAcc?.index,
      options: List<String>.unmodifiable(options?.get() ?? const <String>[]),
    );
    await _api.create(message);
  }

  @override
  Future<void> dispose(int viewId) async {
    await _ensureHostInitialized();
    await _api.dispose(viewId);
  }

  @override
  Stream<VlcMediaEvent> mediaEventsFor(int viewId) {
    return _mediaEventChannelFor(viewId).receiveBroadcastStream().map((
      dynamic event,
    ) {
      final map = event as Map<Object?, Object?>;
      switch (map['event']) {
        case 'opening':
          return VlcMediaEvent(mediaEventType: VlcMediaEventType.opening);
        case 'paused':
          return VlcMediaEvent(mediaEventType: VlcMediaEventType.paused);
        case 'stopped':
          return VlcMediaEvent(mediaEventType: VlcMediaEventType.stopped);
        case 'playing':
          return VlcMediaEvent(
            mediaEventType: VlcMediaEventType.playing,
            size: Size(
              (map['width'] as num?)?.toDouble() ?? 0.0,
              (map['height'] as num?)?.toDouble() ?? 0.0,
            ),
            playbackSpeed: (map['speed'] as num?)?.toDouble() ?? 1.0,
            duration: Duration(milliseconds: map['duration'] as int? ?? 0),
            audioTracksCount: map['audioTracksCount'] as int? ?? 1,
            activeAudioTrack: map['activeAudioTrack'] as int? ?? 0,
            spuTracksCount: map['spuTracksCount'] as int? ?? 0,
            activeSpuTrack: map['activeSpuTrack'] as int? ?? -1,
          );
        case 'ended':
          return VlcMediaEvent(
            mediaEventType: VlcMediaEventType.ended,
            position: Duration(milliseconds: map['position'] as int? ?? 0),
          );
        case 'buffering':
        case 'timeChanged':
          return VlcMediaEvent(
            mediaEventType: VlcMediaEventType.timeChanged,
            size: Size(
              (map['width'] as num?)?.toDouble() ?? 0.0,
              (map['height'] as num?)?.toDouble() ?? 0.0,
            ),
            playbackSpeed: (map['speed'] as num?)?.toDouble() ?? 1.0,
            position: Duration(milliseconds: map['position'] as int? ?? 0),
            duration: Duration(milliseconds: map['duration'] as int? ?? 0),
            audioTracksCount: map['audioTracksCount'] as int? ?? 1,
            activeAudioTrack: map['activeAudioTrack'] as int? ?? 0,
            spuTracksCount: map['spuTracksCount'] as int? ?? 0,
            activeSpuTrack: map['activeSpuTrack'] as int? ?? -1,
            bufferPercent: (map['buffer'] as num?)?.toDouble() ?? 100.0,
            isPlaying: map['isPlaying'] as bool? ?? false,
          );
        case 'mediaChanged':
          return VlcMediaEvent(mediaEventType: VlcMediaEventType.mediaChanged);
        case 'recording':
          return VlcMediaEvent(
            mediaEventType: VlcMediaEventType.recording,
            isRecording: map['isRecording'] as bool? ?? false,
            recordPath: map['recordPath'] as String? ?? '',
          );
        case 'error':
          return VlcMediaEvent(mediaEventType: VlcMediaEventType.error);
        default:
          return VlcMediaEvent(mediaEventType: VlcMediaEventType.unknown);
      }
    });
  }

  @override
  Future<void> setStreamUrl(
    int viewId, {
    required String uri,
    required DataSourceType type,
    String? package,
    bool? autoPlay,
    HwAcc? hwAcc,
  }) async {
    await _ensureHostInitialized();
    final message = _CompatSetMediaMessage(
      playerId: viewId,
      uri: uri,
      type: type.index,
      packageName: package,
      autoPlay: autoPlay ?? true,
      hwAcc: hwAcc?.index,
    );
    await _api.setStreamUrl(message);
  }

  @override
  Future<void> setLooping(int viewId, bool looping) async {
    await _ensureHostInitialized();
    await _api.setLooping(viewId, looping);
  }

  @override
  Future<void> play(int viewId) async {
    await _ensureHostInitialized();
    await _api.play(viewId);
  }

  @override
  Future<void> pause(int viewId) async {
    await _ensureHostInitialized();
    await _api.pause(viewId);
  }

  @override
  Future<void> stop(int viewId) async {
    await _ensureHostInitialized();
    await _api.stop(viewId);
  }

  @override
  Future<bool?> isPlaying(int viewId) async {
    await _ensureHostInitialized();
    return _api.isPlaying(viewId);
  }

  @override
  Future<bool?> isSeekable(int viewId) async {
    await _ensureHostInitialized();
    return _api.isSeekable(viewId);
  }

  @override
  Future<void> setTime(int viewId, Duration position) {
    return seekTo(viewId, position);
  }

  @override
  Future<void> seekTo(int viewId, Duration position) async {
    await _ensureHostInitialized();
    await _api.seekTo(viewId, position.inMilliseconds);
  }

  @override
  Future<Duration> getTime(int viewId) {
    return getPosition(viewId);
  }

  @override
  Future<Duration> getPosition(int viewId) async {
    await _ensureHostInitialized();
    final position = await _api.position(viewId);
    return Duration(milliseconds: position);
  }

  @override
  Future<Duration> getDuration(int viewId) async {
    await _ensureHostInitialized();
    final duration = await _api.duration(viewId);
    return Duration(milliseconds: duration);
  }

  @override
  Future<void> setVolume(int viewId, int volume) async {
    await _ensureHostInitialized();
    await _api.setVolume(viewId, volume);
  }

  @override
  Future<int?> getVolume(int viewId) async {
    await _ensureHostInitialized();
    return _api.getVolume(viewId);
  }

  @override
  Future<void> setPlaybackSpeed(int viewId, double speed) async {
    await _ensureHostInitialized();
    await _api.setPlaybackSpeed(viewId, speed);
  }

  @override
  Future<double?> getPlaybackSpeed(int viewId) async {
    await _ensureHostInitialized();
    return _api.getPlaybackSpeed(viewId);
  }

  @override
  Future<int?> getSpuTracksCount(int viewId) async {
    await _ensureHostInitialized();
    return _api.getSpuTracksCount(viewId);
  }

  @override
  Future<Map<int, String>> getSpuTracks(int viewId) async {
    await _ensureHostInitialized();
    final response = await _api.getSpuTracks(viewId);
    return (response ?? const <Object?, Object?>{}).cast<int, String>();
  }

  @override
  Future<void> setSpuTrack(int viewId, int spuTrackNumber) async {
    await _ensureHostInitialized();
    await _api.setSpuTrack(viewId, spuTrackNumber);
  }

  @override
  Future<int?> getSpuTrack(int viewId) async {
    await _ensureHostInitialized();
    return _api.getSpuTrack(viewId);
  }

  @override
  Future<void> setSpuDelay(int viewId, int delay) async {
    await _ensureHostInitialized();
    await _api.setSpuDelay(viewId, delay);
  }

  @override
  Future<int?> getSpuDelay(int viewId) async {
    await _ensureHostInitialized();
    return _api.getSpuDelay(viewId);
  }

  @override
  Future<void> addSubtitleTrack(
    int viewId, {
    required String uri,
    required DataSourceType type,
    bool? isSelected,
  }) async {
    await _ensureHostInitialized();
    final message = _CompatAddSubtitleMessage(
      playerId: viewId,
      uri: uri,
      type: type.index,
      isSelected: isSelected ?? true,
    );
    await _api.addSubtitleTrack(message);
  }

  @override
  Future<int?> getAudioTracksCount(int viewId) async {
    await _ensureHostInitialized();
    return _api.getAudioTracksCount(viewId);
  }

  @override
  Future<Map<int, String>> getAudioTracks(int viewId) async {
    await _ensureHostInitialized();
    final response = await _api.getAudioTracks(viewId);
    return (response ?? const <Object?, Object?>{}).cast<int, String>();
  }

  @override
  Future<int?> getAudioTrack(int viewId) async {
    await _ensureHostInitialized();
    return _api.getAudioTrack(viewId);
  }

  @override
  Future<void> setAudioTrack(int viewId, int audioTrackNumber) async {
    await _ensureHostInitialized();
    await _api.setAudioTrack(viewId, audioTrackNumber);
  }

  @override
  Future<void> setAudioDelay(int viewId, int delay) async {
    await _ensureHostInitialized();
    await _api.setAudioDelay(viewId, delay);
  }

  @override
  Future<int?> getAudioDelay(int viewId) async {
    await _ensureHostInitialized();
    return _api.getAudioDelay(viewId);
  }

  @override
  Future<void> addAudioTrack(
    int viewId, {
    required String uri,
    required DataSourceType type,
    bool? isSelected,
  }) async {
    await _ensureHostInitialized();
    final message = _CompatAddAudioMessage(
      playerId: viewId,
      uri: uri,
      type: type.index,
      isSelected: isSelected ?? true,
    );
    await _api.addAudioTrack(message);
  }

  @override
  Future<int?> getVideoTracksCount(int viewId) async {
    await _ensureHostInitialized();
    return _api.getVideoTracksCount(viewId);
  }

  @override
  Future<Map<int, String>> getVideoTracks(int viewId) async {
    await _ensureHostInitialized();
    final response = await _api.getVideoTracks(viewId);
    return (response ?? const <Object?, Object?>{}).cast<int, String>();
  }

  @override
  Future<void> setVideoTrack(int viewId, int videoTrackNumber) async {
    await _ensureHostInitialized();
    await _api.setVideoTrack(viewId, videoTrackNumber);
  }

  @override
  Future<int?> getVideoTrack(int viewId) async {
    await _ensureHostInitialized();
    return _api.getVideoTrack(viewId);
  }

  @override
  Future<void> setVideoScale(int viewId, double scale) async {
    await _ensureHostInitialized();
    await _api.setVideoScale(viewId, scale);
  }

  @override
  Future<double?> getVideoScale(int viewId) async {
    await _ensureHostInitialized();
    return _api.getVideoScale(viewId);
  }

  @override
  Future<void> setVideoAspectRatio(int viewId, String aspect) async {
    await _ensureHostInitialized();
    await _api.setVideoAspectRatio(viewId, aspect);
  }

  @override
  Future<String?> getVideoAspectRatio(int viewId) async {
    await _ensureHostInitialized();
    return _api.getVideoAspectRatio(viewId);
  }

  @override
  Future<Uint8List> takeSnapshot(int viewId) async {
    await _ensureHostInitialized();
    final response = await _api.takeSnapshot(viewId);
    final base64String = response ?? '';
    return Uint8List.fromList(base64.decode(base64.normalize(base64String)));
  }

  @override
  Future<List<String>> getAvailableRendererServices(int viewId) async {
    await _ensureHostInitialized();
    final response = await _api.getAvailableRendererServices(viewId);
    return (response ?? const <Object?>[]).cast<String>();
  }

  @override
  Future<void> startRendererScanning(
    int viewId, {
    String? rendererService,
  }) async {
    await _ensureHostInitialized();
    await _api.startRendererScanning(viewId, rendererService ?? '');
  }

  @override
  Future<void> stopRendererScanning(int viewId) async {
    await _ensureHostInitialized();
    await _api.stopRendererScanning(viewId);
  }

  @override
  Future<Map<String, String>> getRendererDevices(int viewId) async {
    await _ensureHostInitialized();
    final response = await _api.getRendererDevices(viewId);
    return (response ?? const <Object?, Object?>{}).cast<String, String>();
  }

  @override
  Future<void> castToRenderer(int viewId, String rendererDevice) async {
    await _ensureHostInitialized();
    await _api.castToRenderer(viewId, rendererDevice);
  }

  @override
  Stream<VlcRendererEvent> rendererEventsFor(int viewId) {
    return _rendererEventChannelFor(viewId).receiveBroadcastStream().map((
      dynamic event,
    ) {
      final map = event as Map<Object?, Object?>;
      switch (map['event']) {
        case 'attached':
          return VlcRendererEvent(
            eventType: VlcRendererEventType.attached,
            rendererId: map['id']?.toString(),
            rendererName: map['name']?.toString(),
          );
        case 'detached':
          return VlcRendererEvent(
            eventType: VlcRendererEventType.detached,
            rendererId: map['id']?.toString(),
            rendererName: map['name']?.toString(),
          );
        default:
          return VlcRendererEvent(eventType: VlcRendererEventType.unknown);
      }
    });
  }

  @override
  Future<bool?> startRecording(int viewId, String saveDirectory) async {
    await _ensureHostInitialized();
    return _api.startRecording(viewId, saveDirectory);
  }

  @override
  Future<bool?> stopRecording(int viewId) async {
    await _ensureHostInitialized();
    return _api.stopRecording(viewId);
  }
}
