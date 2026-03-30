import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class CenteredMarqueeText extends StatefulWidget {
  const CenteredMarqueeText(
    this.text, {
    super.key,
    this.style,
    this.pause = const Duration(milliseconds: 900),
    this.pixelsPerSecond = 26,
  });

  final String text;
  final TextStyle? style;
  final Duration pause;
  final double pixelsPerSecond;

  @override
  State<CenteredMarqueeText> createState() => _CenteredMarqueeTextState();
}

class _CenteredMarqueeTextState extends State<CenteredMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_handleAnimationStatus);

  Animation<double>? _offsetAnimation;
  Timer? _loopTimer;
  double _edgeOffset = 0;
  bool _needsScroll = false;

  @override
  void didUpdateWidget(covariant CenteredMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.pause != widget.pause ||
        oldWidget.pixelsPerSecond != widget.pixelsPerSecond) {
      _reset();
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (!_needsScroll) return;
    if (status == AnimationStatus.completed) {
      _schedule(() => _controller.reverse());
    } else if (status == AnimationStatus.dismissed) {
      _schedule(() => _controller.forward());
    }
  }

  void _schedule(VoidCallback action) {
    _loopTimer?.cancel();
    _loopTimer = Timer(widget.pause, () {
      if (!mounted || !_needsScroll) return;
      action();
    });
  }

  void _reset() {
    _loopTimer?.cancel();
    _controller
      ..stop()
      ..reset();
    _offsetAnimation = null;
    _edgeOffset = 0;
    _needsScroll = false;
  }

  void _configure(double maxWidth) {
    if (maxWidth <= 0 || !maxWidth.isFinite) return;
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout(minWidth: 0, maxWidth: double.infinity);

    final overflowWidth = painter.width - maxWidth;
    if (overflowWidth <= 1) {
      if (_needsScroll) {
        setState(_reset);
      }
      return;
    }

    final edgeOffset = overflowWidth / 2;
    final duration = Duration(
      milliseconds: math.max(
        2200,
        ((overflowWidth / widget.pixelsPerSecond) * 1000).round(),
      ),
    );

    final shouldRebuild = !_needsScroll ||
        (_edgeOffset - edgeOffset).abs() > 0.5 ||
        _controller.duration != duration;
    if (!shouldRebuild) return;

    _loopTimer?.cancel();
    _controller
      ..stop()
      ..duration = duration
      ..value = 0;

    setState(() {
      _needsScroll = true;
      _edgeOffset = edgeOffset;
      _offsetAnimation = Tween<double>(
        begin: edgeOffset,
        end: -edgeOffset,
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      );
    });

    _schedule(() => _controller.forward(from: 0));
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _configure(constraints.maxWidth);
        });

        if (!_needsScroll) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: style,
          );
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: style,
            ),
            builder: (context, child) {
              return Center(
                child: Transform.translate(
                  offset: Offset(_offsetAnimation?.value ?? _edgeOffset, 0),
                  child: child,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class ExpandableText extends StatefulWidget {
  const ExpandableText(
    this.text, {
    super.key,
    this.style,
    this.collapsedLines = 4,
    this.expandLabel = '展开简介',
    this.collapseLabel = '收起简介',
    this.actionColor,
  });

  final String text;
  final TextStyle? style;
  final int collapsedLines;
  final String expandLabel;
  final String collapseLabel;
  final Color? actionColor;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && _expanded) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth =
            constraints.maxWidth > 0 && constraints.maxWidth.isFinite;
        final hasOverflow = hasBoundedWidth
            ? (TextPainter(
                text: TextSpan(text: widget.text, style: style),
                maxLines: widget.collapsedLines,
                textDirection: Directionality.of(context),
              )..layout(maxWidth: constraints.maxWidth))
                .didExceedMaxLines
            : false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Text(
                widget.text,
                maxLines: _expanded ? null : widget.collapsedLines,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (hasOverflow) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  foregroundColor: widget.actionColor ??
                      Theme.of(context).colorScheme.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child:
                    Text(_expanded ? widget.collapseLabel : widget.expandLabel),
              ),
            ],
          ],
        );
      },
    );
  }
}
