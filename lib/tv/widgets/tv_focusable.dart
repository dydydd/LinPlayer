import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tv_design_tokens.dart';

/// TV 焦点包装器
/// 为任何子组件添加 TV 焦点效果（放大、边框、光晕）
/// 支持遥控器方向键导航和确认键触发
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onFocus;
  final VoidCallback? onBlur;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsets padding;
  final double scale;
  final bool enableGlow;

  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onFocus,
    this.onBlur,
    this.autofocus = false,
    this.focusNode,
    this.padding = const EdgeInsets.all(TvDesignTokens.spacingSm),
    this.scale = TvDesignTokens.focusScale,
    this.enableGlow = true,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          widget.onFocus?.call();
        } else {
          widget.onBlur?.call();
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onSelect?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: TvDesignTokens.focusAnimationDuration,
        curve: TvDesignTokens.focusAnimationCurve,
        padding: widget.padding,
        decoration: _isFocused
            ? BoxDecoration(
                border: Border.all(
                  color: TvDesignTokens.focusBorder,
                  width: TvDesignTokens.focusBorderWidth,
                ),
                borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                boxShadow: widget.enableGlow
                    ? [
                        BoxShadow(
                          color: TvDesignTokens.focusGlow,
                          blurRadius: TvDesignTokens.focusGlowBlur,
                          spreadRadius: 4,
                        ),
                      ]
                    : null,
              )
            : null,
        child: AnimatedScale(
          duration: TvDesignTokens.focusAnimationDuration,
          curve: TvDesignTokens.focusAnimationCurve,
          scale: _isFocused ? widget.scale : 1.0,
          child: AnimatedOpacity(
            duration: TvDesignTokens.focusAnimationDuration,
            opacity: _isFocused ? 1.0 : TvDesignTokens.nonFocusOpacity,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// TV 焦点包装器（无动画版本，用于性能敏感场景）
class TvFocusableStatic extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsets padding;

  const TvFocusableStatic({
    super.key,
    required this.child,
    this.onSelect,
    this.autofocus = false,
    this.focusNode,
    this.padding = const EdgeInsets.all(TvDesignTokens.spacingSm),
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            onSelect?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Container(
            padding: padding,
            decoration: focused
                ? BoxDecoration(
                    border: Border.all(
                      color: TvDesignTokens.focusBorder,
                      width: TvDesignTokens.focusBorderWidth,
                    ),
                    borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                    boxShadow: [
                      BoxShadow(
                        color: TvDesignTokens.focusGlow,
                        blurRadius: TvDesignTokens.focusGlowBlur,
                        spreadRadius: 4,
                      ),
                    ],
                  )
                : null,
            child: Transform.scale(
              scale: focused ? TvDesignTokens.focusScale : 1.0,
              child: Opacity(
                opacity: focused ? 1.0 : TvDesignTokens.nonFocusOpacity,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
