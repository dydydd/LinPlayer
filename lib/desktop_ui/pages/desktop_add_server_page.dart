import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../../mobile_ui/server/mobile_add_server_page.dart';
import '../theme/desktop_theme_scope.dart';

class DesktopAddServerPage extends StatelessWidget {
  const DesktopAddServerPage({
    super.key,
    required this.appState,
  });

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return DesktopThemeScope(
      child: MobileAddServerPage(appState: appState),
    );
  }
}
