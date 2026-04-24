import 'dart:async';

class PlaybackTransitionGuard {
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
}
