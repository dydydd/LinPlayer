import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlaybackTransitionGuard {
  static const Duration _kIosNativePlayerTeardownDelay =
      Duration(milliseconds: 120);
  static Future<void> _pending = Future<void>.value();

  static Future<void> waitForSettled() async {
    try {
      await _pending;
    } catch (_) {}
  }

  static Future<void> enqueue(Future<void> Function() action) {
    final next = waitForSettled().then((_) => action());
    _pending = next.then<void>((_) {}).catchError((_) {});
    return next;
  }

  static Future<void> waitForPlayerRouteReplacementReady() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {}
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await Future<void>.delayed(_kIosNativePlayerTeardownDelay);
    }
  }

  static PageRoute<T> buildPlayerReplacementRoute<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, __) => builder(context),
    );
  }
}
