import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/tv_design_tokens.dart';
import 'tv_focusable.dart';

/// TV 右侧滑入面板
/// 统一面板组件，所有设置/选择用单面板分组
class TvPanel extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback? onClose;
  final double width;

  const TvPanel({
    super.key,
    required this.title,
    required this.children,
    this.onClose,
    this.width = TvDesignTokens.panelWidth,
  });

  @override
  State<TvPanel> createState() => _TvPanelState();
}

class _TvPanelState extends State<TvPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: TvDesignTokens.panelSlideDuration,
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: TvDesignTokens.panelSlideCurve,
    ));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: TvDesignTokens.panelSlideCurve,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _controller.reverse();
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景遮罩
        AnimatedBuilder(
          animation: _opacityAnimation,
          builder: (context, child) => GestureDetector(
            onTap: _close,
            child: Container(
              color: Colors.black.withOpacity(_opacityAnimation.value),
            ),
          ),
        ),
        // 面板
        Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _close();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SlideTransition(
            position: _offsetAnimation,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: widget.width,
                color: TvDesignTokens.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.all(TvDesignTokens.spacingLg),
                      child: Row(
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: TvDesignTokens.fontSizeXl,
                              color: TvDesignTokens.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TvFocusable(
                            onSelect: _close,
                            child: const Icon(
                              Icons.close,
                              color: TvDesignTokens.textSecondary,
                              size: 32,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: TvDesignTokens.divider),
                    // 内容
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(TvDesignTokens.spacingLg),
                        children: widget.children,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// TV 面板选项项
class TvPanelOption extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  const TvPanelOption({
    super.key,
    required this.title,
    this.subtitle,
    this.isSelected = false,
    this.leading,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onSelect: onTap,
      child: Container(
        padding: const EdgeInsets.all(TvDesignTokens.spacingMd),
        decoration: BoxDecoration(
          color: isSelected ? TvDesignTokens.brand.withOpacity(0.15) : null,
          borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: TvDesignTokens.spacingMd),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: TvDesignTokens.fontSizeMd,
                      color: isSelected ? TvDesignTokens.brand : TvDesignTokens.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: TvDesignTokens.fontSizeSm,
                        color: TvDesignTokens.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (isSelected)
              const Icon(
                Icons.check,
                color: TvDesignTokens.brand,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

/// TV 面板分组标题
class TvPanelSection extends StatelessWidget {
  final String title;

  const TvPanelSection({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: TvDesignTokens.spacingLg,
        bottom: TvDesignTokens.spacingSm,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: TvDesignTokens.fontSizeSm,
          color: TvDesignTokens.textSecondary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
