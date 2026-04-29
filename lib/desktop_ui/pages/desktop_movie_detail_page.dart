import 'package:flutter/material.dart';

import '../models/desktop_ui_language.dart';
import '../theme/desktop_theme_scope.dart';
import '../view_models/desktop_detail_view_model.dart';
import 'desktop_detail_page.dart';

class DesktopMovieDetailPage extends StatelessWidget {
  const DesktopMovieDetailPage({
    super.key,
    required this.viewModel,
    this.language = DesktopUiLanguage.zhCn,
    this.onOpenItem,
    this.onPlayPressed,
  });

  final DesktopDetailViewModel viewModel;
  final DesktopUiLanguage language;
  final DesktopDetailOpenItem? onOpenItem;
  final VoidCallback? onPlayPressed;

  @override
  Widget build(BuildContext context) {
    return DesktopThemeScope(
      child: DesktopDetailPage(
        viewModel: viewModel,
        language: language,
        onOpenItem: onOpenItem,
        onPlayPressed: onPlayPressed,
      ),
    );
  }
}
