import 'package:flutter/material.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

import '../theme/tv_design_tokens.dart';
import 'tv_focusable.dart';

/// TV 主操作按钮 —— TV 端「TDesign + 焦点 + flutter_animate」组件基建的范例。
///
/// 以 TDesign 的 [TDButton] 作视觉底座，外层套 [TvFocusable] 叠加 TV 焦点效果
/// （放大 / 白描边 / 品牌色光晕，均由 flutter_animate 驱动）与遥控器确认键触发。
/// 这样既复用了 TDesign 的视觉规范，又满足 TV 十足距离 + 焦点导航的交互。
class TvButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final TDButtonType type;
  final TDButtonTheme theme;
  final TDButtonSize size;

  const TvButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.type = TDButtonType.fill,
    this.theme = TDButtonTheme.primary,
    this.size = TDButtonSize.large,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: onPressed,
      scale: 1.08,
      padding: const EdgeInsets.all(TvDesignTokens.spacingXs),
      child: TDButton(
        text: text,
        icon: icon,
        type: type,
        theme: theme,
        size: size,
        shape: TDButtonShape.round,
        onTap: onPressed,
      ),
    );
  }
}
