import 'package:flutter/material.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../../library_items_page.dart';
import '../theme/desktop_theme_scope.dart';

class DesktopLibraryDetailPage extends StatelessWidget {
  const DesktopLibraryDetailPage({
    super.key,
    required this.appState,
    required this.parentId,
    required this.title,
    this.onOpenItem,
  });

  final AppState appState;
  final String parentId;
  final String title;
  final ValueChanged<MediaItem>? onOpenItem;

  @override
  Widget build(BuildContext context) {
    return DesktopThemeScope(
      child: LibraryItemsPage(
        appState: appState,
        parentId: parentId,
        title: title,
        onOpenItem: onOpenItem,
      ),
    );
  }
}
