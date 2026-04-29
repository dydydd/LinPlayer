import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../../settings_page.dart';
import '../theme/desktop_theme_scope.dart';

class DesktopSettingsPage extends StatelessWidget {
  const DesktopSettingsPage({
    super.key,
    required this.appState,
  });

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return DesktopThemeScope(
      child: SettingsPage(appState: appState),
    );
  }
}
