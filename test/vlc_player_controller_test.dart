import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class _FakeVlcPlayerPlatform extends VlcPlayerPlatform {
  final List<int> createdViewIds = <int>[];
  final List<int> disposedViewIds = <int>[];

  @override
  Widget buildView(
    PlatformViewCreatedCallback onPlatformViewCreated, {
    bool virtualDisplay = true,
  }) {
    return const SizedBox.shrink();
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
    createdViewIds.add(viewId);
  }

  @override
  Future<void> dispose(int viewId) async {
    disposedViewIds.add(viewId);
  }

  @override
  Stream<VlcMediaEvent> mediaEventsFor(int viewId) =>
      const Stream<VlcMediaEvent>.empty();

  @override
  Stream<VlcRendererEvent> rendererEventsFor(int viewId) =>
      const Stream<VlcRendererEvent>.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VlcPlayerController waits for platform view before initialize',
      () async {
    final originalPlatform = VlcPlayerPlatform.instance;
    final fakePlatform = _FakeVlcPlayerPlatform();
    VlcPlayerPlatform.instance = fakePlatform;
    addTearDown(() {
      VlcPlayerPlatform.instance = originalPlatform;
    });

    final controller = VlcPlayerController.network(
      'https://example.com/video.mp4',
      autoInitialize: false,
      autoPlay: false,
    );

    var completed = false;
    final initializeFuture = controller.initialize().then((_) {
      completed = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(completed, isFalse);
    expect(fakePlatform.createdViewIds, isEmpty);
    expect(controller.viewId, isNull);
    expect(controller.isReadyToInitialize, isNot(true));

    await controller.onPlatformViewCreated(42);
    await initializeFuture.timeout(const Duration(seconds: 1));

    expect(fakePlatform.createdViewIds, <int>[42]);
    expect(controller.viewId, 42);
    expect(controller.isReadyToInitialize, isTrue);
    expect(controller.value.isInitialized, isTrue);

    await controller.dispose();
    expect(fakePlatform.disposedViewIds, <int>[42]);
  });
}
