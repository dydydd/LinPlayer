import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'danmaku.dart';

class DanmakuStage extends StatefulWidget {
  const DanmakuStage({
    super.key,
    required this.enabled,
    required this.opacity,
    this.scale = 1.0,
    this.speed = 1.0,
    this.timeScale = 1.0,
    this.bold = true,
    this.scrollMaxLines = 10,
    this.topMaxLines = 0,
    this.bottomMaxLines = 0,
    this.preventOverlap = true,
  });

  final bool enabled;
  final double opacity;
  final double scale;
  final double speed;
  final double timeScale;
  final bool bold;
  final int scrollMaxLines;
  final int topMaxLines;
  final int bottomMaxLines;
  final bool preventOverlap;

  @override
  State<DanmakuStage> createState() => DanmakuStageState();
}

class DanmakuStageState extends State<DanmakuStage>
    with TickerProviderStateMixin {
  static const double _baseFontSize = 18.0;
  static const double _lineGap = 8.0;
  static const double _topPadding = 6.0;
  static const double _scrollGapPx = 16.0;
  static const Duration _scrollBaseDuration = Duration(milliseconds: 8000);
  static const Duration _staticBaseDuration = Duration(milliseconds: 4000);
  static const double _scrollMinDurationSec = 1.2;
  static const double _scrollMaxDurationSec = 20.0;

  final List<_ScrollingDanmaku> _scrolling = <_ScrollingDanmaku>[];
  final List<_StaticDanmaku> _static = <_StaticDanmaku>[];

  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  Ticker? _ticker;
  Duration _lastTickerElapsed = Duration.zero;
  double _clockMs = 0.0;

  double _width = 0.0;
  double _height = 0.0;
  bool _paused = false;

  int _scrollRowCursor = 0;
  List<_ScrollingDanmaku?> _scrollRowLast = const [];

  int _topRowCursor = 0;
  List<_StaticDanmaku?> _topRowLast = const [];

  int _bottomRowCursor = 0;
  List<_StaticDanmaku?> _bottomRowLast = const [];

  TextStyle? _paintStyle;
  TextScaler _textScaler = TextScaler.noScaling;
  TextDirection _textDirection = TextDirection.ltr;

  static double _clampSpeed(double v) => v.clamp(0.1, 3.0).toDouble();
  static double _clampTimeScale(double v) => v.clamp(0.25, 4.0).toDouble();

  double get _effectiveTimeScale => _clampTimeScale(widget.timeScale);

  double get _effectiveScrollSpeedMultiplier =>
      _clampSpeed(widget.speed) * _effectiveTimeScale;

  Duration get _effectiveScrollDuration {
    final scaledMs = (_scrollBaseDuration.inMilliseconds /
            _effectiveScrollSpeedMultiplier)
        .clamp(_scrollMinDurationSec * 1000, _scrollMaxDurationSec * 1000);
    return Duration(milliseconds: scaledMs.round().toInt());
  }

  Duration get _effectiveStaticDuration {
    final scaled = _staticBaseDuration.inMilliseconds / _effectiveTimeScale;
    final ms = scaled.round().clamp(800, 20000).toInt();
    return Duration(milliseconds: ms);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePainterConfig();
  }

  @override
  void didUpdateWidget(covariant DanmakuStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      clear();
      return;
    }

    if (widget.enabled &&
        widget.preventOverlap &&
        !oldWidget.preventOverlap &&
        (_scrolling.isNotEmpty || _static.isNotEmpty)) {
      // We don't track row occupancy when overlap prevention is off.
      // Clearing avoids immediately emitting into already-occupied rows.
      clear();
      return;
    }

    final speedChanged = (widget.speed - oldWidget.speed).abs() > 0.0001;
    final timeScaleChanged =
        (widget.timeScale - oldWidget.timeScale).abs() > 0.0001;
    if (widget.enabled && (speedChanged || timeScaleChanged)) {
      _rescaleActiveDanmaku();
    }

    final scaleChanged = (widget.scale - oldWidget.scale).abs() > 0.0001;
    final boldChanged = widget.bold != oldWidget.bold;
    if (widget.enabled && (scaleChanged || boldChanged)) {
      _updatePainterConfig();
    }
  }

  void _updatePainterConfig() {
    if (!mounted) return;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    final textScale = widget.scale.clamp(0.1, 3.0);
    final fontSize = _baseFontSize * textScale;

    final textTheme = Theme.of(context).textTheme;
    final baseStyle = textTheme.bodyMedium ?? const TextStyle();
    final fontWeight = widget.bold ? FontWeight.w600 : FontWeight.w400;
    final style = baseStyle.copyWith(
      fontSize: fontSize,
      color: Colors.white,
      fontWeight: fontWeight,
      shadows: const [
        Shadow(
          blurRadius: 4,
          offset: Offset(1, 1),
          color: Colors.black87,
        ),
      ],
    );

    if (_paintStyle == style &&
        _textScaler == textScaler &&
        _textDirection == direction) {
      return;
    }

    _paintStyle = style;
    _textScaler = textScaler;
    _textDirection = direction;

    for (final a in _scrolling) {
      a.painter
        ..text = TextSpan(text: a.text, style: style)
        ..textDirection = direction
        ..textScaler = textScaler
        ..layout();
    }
    for (final a in _static) {
      a.painter
        ..text = TextSpan(text: a.text, style: style)
        ..textDirection = direction
        ..textScaler = textScaler
        ..layout();
    }

    _repaint.value++;
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastTickerElapsed;
    _lastTickerElapsed = elapsed;
    if (delta.isNegative) return;

    _clockMs += delta.inMicroseconds / 1000.0;

    var changed = false;
    final nowMs = _clockMs;

    for (var i = _scrolling.length - 1; i >= 0; i--) {
      final a = _scrolling[i];
      if (!a.isCompleted(nowMs)) continue;
      _scrolling.removeAt(i);
      if (_scrollRowLast.length > a.row && _scrollRowLast[a.row] == a) {
        _scrollRowLast[a.row] = null;
      }
      changed = true;
    }

    for (var i = _static.length - 1; i >= 0; i--) {
      final a = _static[i];
      if (!a.isCompleted(nowMs)) continue;
      _static.removeAt(i);
      if (a.isBottom) {
        if (_bottomRowLast.length > a.row && _bottomRowLast[a.row] == a) {
          _bottomRowLast[a.row] = null;
        }
      } else {
        if (_topRowLast.length > a.row && _topRowLast[a.row] == a) {
          _topRowLast[a.row] = null;
        }
      }
      changed = true;
    }

    if (_scrolling.isEmpty && _static.isEmpty) {
      _stopTicker();
    }

    if (changed || (_ticker?.isActive ?? false)) {
      _repaint.value++;
    }
  }

  void _ensureTickerRunning() {
    final ticker = _ticker;
    if (ticker == null) return;
    if (!widget.enabled) return;
    if (_paused) return;
    if (_scrolling.isEmpty && _static.isEmpty) return;
    if (ticker.isActive) return;
    _lastTickerElapsed = Duration.zero;
    ticker.start();
  }

  void _stopTicker() {
    final ticker = _ticker;
    if (ticker == null) return;
    if (!ticker.isActive) return;
    ticker.stop();
    _lastTickerElapsed = Duration.zero;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void clear() {
    _scrolling.clear();
    _static.clear();
    _scrollRowLast = const [];
    _topRowLast = const [];
    _bottomRowLast = const [];
    _scrollRowCursor = 0;
    _topRowCursor = 0;
    _bottomRowCursor = 0;
    _paused = false;
    _stopTicker();
    _repaint.value++;
  }

  void pause() {
    if (_paused) return;
    _paused = true;
    _stopTicker();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _ensureTickerRunning();
  }

  void emit(DanmakuItem item) {
    if (!widget.enabled) return;
    if (_width <= 0 || _height <= 0) return;

    _updatePainterConfig();
    final style = _paintStyle;
    if (style == null) return;

    final textScale = widget.scale.clamp(0.1, 3.0);
    final fontSize = _baseFontSize * textScale;
    final lineHeight = _textScaler.scale(fontSize) + _lineGap;

    final totalRows =
        math.min(math.max(1, (_height / lineHeight).floor()), 200);

    final desiredTopRows = widget.topMaxLines.clamp(0, 200);
    final desiredBottomRows = widget.bottomMaxLines.clamp(0, 200);
    final desiredScrollRows = widget.scrollMaxLines.clamp(0, 200);

    if (desiredScrollRows <= 0 &&
        desiredTopRows <= 0 &&
        desiredBottomRows <= 0) {
      return;
    }

    final reservedStaticMin =
        (desiredTopRows > 0 ? 1 : 0) + (desiredBottomRows > 0 ? 1 : 0);
    final maxScrollRows = math.max(0, totalRows - reservedStaticMin);
    final scrollRows = math.min(maxScrollRows, desiredScrollRows);
    final remaining = totalRows - scrollRows;

    int topRows = 0;
    int bottomRows = 0;
    if (remaining <= 0 || (desiredTopRows <= 0 && desiredBottomRows <= 0)) {
      topRows = 0;
      bottomRows = 0;
    } else if (desiredTopRows <= 0) {
      bottomRows = math.min(remaining, desiredBottomRows);
    } else if (desiredBottomRows <= 0) {
      topRows = math.min(remaining, desiredTopRows);
    } else if (remaining == 1) {
      if (desiredTopRows >= desiredBottomRows) {
        topRows = 1;
      } else {
        bottomRows = 1;
      }
    } else {
      topRows = 1;
      bottomRows = 1;
      var extra = remaining - 2;
      if (extra > 0) {
        final topExtraMax = math.max(0, desiredTopRows - topRows);
        final bottomExtraMax = math.max(0, desiredBottomRows - bottomRows);
        final extraMaxSum = topExtraMax + bottomExtraMax;
        if (extraMaxSum > 0) {
          var topExtra = ((extra * topExtraMax) / extraMaxSum)
              .round()
              .clamp(0, topExtraMax);
          var bottomExtra = (extra - topExtra).clamp(0, bottomExtraMax);

          var leftover = extra - topExtra - bottomExtra;
          while (leftover > 0) {
            if (topExtra < topExtraMax) {
              topExtra++;
              leftover--;
              continue;
            }
            if (bottomExtra < bottomExtraMax) {
              bottomExtra++;
              leftover--;
              continue;
            }
            break;
          }

          topRows += topExtra;
          bottomRows += bottomExtra;
        }
      }
    }

    switch (item.type) {
      case DanmakuType.scrolling:
        if (scrollRows <= 0) return;
        _emitScrolling(
          item,
          style: style,
          lineHeight: lineHeight,
          rowStart: topRows,
          rows: scrollRows,
        );
        break;
      case DanmakuType.top:
        if (topRows <= 0) return;
        _emitStatic(
          item,
          style: style,
          lineHeight: lineHeight,
          rowStart: 0,
          rows: topRows,
          isBottom: false,
        );
        break;
      case DanmakuType.bottom:
        if (bottomRows <= 0) return;
        _emitStatic(
          item,
          style: style,
          lineHeight: lineHeight,
          rowStart: totalRows - bottomRows,
          rows: bottomRows,
          isBottom: true,
        );
        break;
    }
  }

  void _emitScrolling(
    DanmakuItem item, {
    required TextStyle style,
    required double lineHeight,
    required int rowStart,
    required int rows,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: item.text, style: style),
      maxLines: 1,
      textDirection: _textDirection,
      textScaler: _textScaler,
    )..layout();
    final textWidth = painter.width;

    final duration = _effectiveScrollDuration;
    final durationMs = duration.inMilliseconds.clamp(1, 1 << 31);
    final durationSec = durationMs / 1000.0;
    if (durationSec <= 0) return;

    final startX = _width + 12;
    final distance = _width + textWidth + 24;
    final speedNew = distance / durationSec;

    int pickedRow;
    if (widget.preventOverlap) {
      if (_scrollRowLast.length != rows) {
        _scrollRowLast =
            List<_ScrollingDanmaku?>.filled(rows, null, growable: false);
        _scrollRowCursor = 0;
      }

      final nowMs = _clockMs;
      var found = -1;
      for (var i = 0; i < rows; i++) {
        final row = (_scrollRowCursor + i) % rows;
        final last = _scrollRowLast[row];
        if (last == null || last.isCompleted(nowMs)) {
          found = row;
          break;
        }

        final lastLeft = last.leftAt(nowMs);
        final lastRightEdge = lastLeft + last.motionTextWidth;
        final gapNow = startX - lastRightEdge;
        if (gapNow < _scrollGapPx) continue;

        final lastDurationSec = last.durationMs / 1000.0;
        if (lastDurationSec <= 0) {
          found = row;
          break;
        }
        final lastDistance = last.canvasWidth + last.motionTextWidth + 24;
        final speedLast = lastDistance / lastDurationSec;

        if (speedNew <= speedLast) {
          found = row;
          break;
        }

        final progress = last.progressAt(nowMs);
        final lastRemainingSec = (1.0 - progress) * lastDurationSec;
        final gapEnd = gapNow - (speedNew - speedLast) * lastRemainingSec;
        if (gapEnd >= _scrollGapPx) {
          found = row;
          break;
        }
      }
      if (found < 0) return;
      pickedRow = found;
      _scrollRowCursor = (pickedRow + 1) % rows;
    } else {
      pickedRow = _scrollRowCursor++ % rows;
    }

    final top = (rowStart + pickedRow) * lineHeight + _topPadding;

    final flying = _ScrollingDanmaku(
      text: item.text,
      painter: painter,
      startClockMs: _clockMs,
      durationMs: durationMs,
      startX: startX,
      endX: -textWidth - 12,
      top: top,
      row: pickedRow,
      canvasWidth: _width,
      motionTextWidth: textWidth,
    );

    _scrolling.add(flying);
    if (widget.preventOverlap &&
        pickedRow >= 0 &&
        pickedRow < _scrollRowLast.length) {
      _scrollRowLast[pickedRow] = flying;
    }

    _ensureTickerRunning();
    _repaint.value++;
  }

  void _emitStatic(
    DanmakuItem item, {
    required TextStyle style,
    required double lineHeight,
    required int rowStart,
    required int rows,
    required bool isBottom,
  }) {
    final duration = _effectiveStaticDuration;
    final durationMs = duration.inMilliseconds.clamp(1, 1 << 31);

    int pickedRow;
    if (widget.preventOverlap) {
      if (isBottom) {
        if (_bottomRowLast.length != rows) {
          _bottomRowLast =
              List<_StaticDanmaku?>.filled(rows, null, growable: false);
          _bottomRowCursor = 0;
        }
        final nowMs = _clockMs;
        var found = -1;
        for (var i = 0; i < rows; i++) {
          final row = (_bottomRowCursor + i) % rows;
          final last = _bottomRowLast[row];
          if (last == null || last.isCompleted(nowMs)) {
            found = row;
            break;
          }
        }
        if (found < 0) return;
        pickedRow = found;
        _bottomRowCursor = (pickedRow + 1) % rows;
      } else {
        if (_topRowLast.length != rows) {
          _topRowLast =
              List<_StaticDanmaku?>.filled(rows, null, growable: false);
          _topRowCursor = 0;
        }
        final nowMs = _clockMs;
        var found = -1;
        for (var i = 0; i < rows; i++) {
          final row = (_topRowCursor + i) % rows;
          final last = _topRowLast[row];
          if (last == null || last.isCompleted(nowMs)) {
            found = row;
            break;
          }
        }
        if (found < 0) return;
        pickedRow = found;
        _topRowCursor = (pickedRow + 1) % rows;
      }
    } else {
      if (isBottom) {
        pickedRow = _bottomRowCursor++ % rows;
      } else {
        pickedRow = _topRowCursor++ % rows;
      }
    }

    final top = (rowStart + pickedRow) * lineHeight + _topPadding;

    final painter = TextPainter(
      text: TextSpan(text: item.text, style: style),
      maxLines: 1,
      textDirection: _textDirection,
      textScaler: _textScaler,
    )..layout();

    final floating = _StaticDanmaku(
      text: item.text,
      painter: painter,
      startClockMs: _clockMs,
      durationMs: durationMs,
      top: top,
      row: pickedRow,
      isBottom: isBottom,
    );

    _static.add(floating);
    if (widget.preventOverlap) {
      if (floating.isBottom) {
        if (pickedRow >= 0 && pickedRow < _bottomRowLast.length) {
          _bottomRowLast[pickedRow] = floating;
        }
      } else {
        if (pickedRow >= 0 && pickedRow < _topRowLast.length) {
          _topRowLast[pickedRow] = floating;
        }
      }
    }

    _ensureTickerRunning();
    _repaint.value++;
  }

  void _rescaleActiveDanmaku() {
    final nowMs = _clockMs;
    final scrollTotalMs =
        _effectiveScrollDuration.inMilliseconds.clamp(1, 1 << 31).toInt();
    final staticTotalMs =
        _effectiveStaticDuration.inMilliseconds.clamp(1, 1 << 31).toInt();

    for (final a in _scrolling) {
      final progress = a.progressAt(nowMs);
      a.durationMs = scrollTotalMs;
      a.startClockMs = nowMs - progress * scrollTotalMs;
    }

    for (final a in _static) {
      final progress = a.progressAt(nowMs);
      a.durationMs = staticTotalMs;
      a.startClockMs = nowMs - progress * staticTotalMs;
    }

    _ensureTickerRunning();
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = constraints.maxWidth;
          _height = constraints.maxHeight;

          return Opacity(
            opacity: widget.opacity.clamp(0, 1),
            child: CustomPaint(
              painter: _DanmakuPainter(
                repaint: _repaint,
                scrolling: _scrolling,
                staticItems: _static,
                clockMs: () => _clockMs,
              ),
              isComplex: true,
              willChange: true,
            ),
          );
        },
      ),
    );
  }
}

final class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required Listenable repaint,
    required this.scrolling,
    required this.staticItems,
    required this.clockMs,
  }) : super(repaint: repaint);

  final List<_ScrollingDanmaku> scrolling;
  final List<_StaticDanmaku> staticItems;
  final double Function() clockMs;

  @override
  void paint(Canvas canvas, Size size) {
    final nowMs = clockMs();

    for (final a in scrolling) {
      final progress = a.progressAt(nowMs);
      if (progress >= 1.0) continue;
      final x = a.startX + (a.endX - a.startX) * progress;
      a.painter.paint(canvas, Offset(x, a.top));
    }

    for (final a in staticItems) {
      if (a.isCompleted(nowMs)) continue;
      final w = a.painter.width;
      final x = (size.width - w) / 2.0;
      a.painter.paint(canvas, Offset(x, a.top));
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) {
    return oldDelegate.scrolling != scrolling ||
        oldDelegate.staticItems != staticItems ||
        oldDelegate.clockMs != clockMs;
  }
}

class _ScrollingDanmaku {
  _ScrollingDanmaku({
    required this.text,
    required this.painter,
    required this.startClockMs,
    required this.durationMs,
    required this.startX,
    required this.endX,
    required this.top,
    required this.row,
    required this.canvasWidth,
    required this.motionTextWidth,
  });

  final String text;
  final TextPainter painter;

  double startClockMs;
  int durationMs;

  final double startX;
  final double endX;
  final double top;
  final int row;
  final double canvasWidth;
  final double motionTextWidth;

  double progressAt(double nowMs) {
    final d = durationMs;
    if (d <= 0) return 1.0;
    return ((nowMs - startClockMs) / d).clamp(0.0, 1.0);
  }

  double leftAt(double nowMs) {
    final t = progressAt(nowMs);
    return startX + (endX - startX) * t;
  }

  bool isCompleted(double nowMs) => nowMs - startClockMs >= durationMs;
}

class _StaticDanmaku {
  _StaticDanmaku({
    required this.text,
    required this.painter,
    required this.startClockMs,
    required this.durationMs,
    required this.top,
    required this.row,
    required this.isBottom,
  });

  final String text;
  final TextPainter painter;

  double startClockMs;
  int durationMs;

  final double top;
  final int row;
  final bool isBottom;

  double progressAt(double nowMs) {
    final d = durationMs;
    if (d <= 0) return 1.0;
    return ((nowMs - startClockMs) / d).clamp(0.0, 1.0);
  }

  bool isCompleted(double nowMs) => nowMs - startClockMs >= durationMs;
}
