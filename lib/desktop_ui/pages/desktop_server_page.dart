import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../../server_page.dart';
import '../../services/app_back_intent.dart';
import '../theme/desktop_theme_scope.dart';
import '../widgets/desktop_cinematic_shell.dart';
import 'desktop_player_page.dart';
import 'desktop_settings_page.dart';

class DesktopServerPage extends StatefulWidget {
  const DesktopServerPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage> {
  int _index = 0; // 0 servers, 1 local, 2 settings
  final List<bool> _built = <bool>[true, false, false];

  static const _tabs = <DesktopCinematicTab>[
    DesktopCinematicTab(label: 'Servers', icon: Icons.storage_outlined),
    DesktopCinematicTab(label: 'Local', icon: Icons.folder_open_outlined),
    DesktopCinematicTab(label: 'Settings', icon: Icons.settings_outlined),
  ];

  void _selectTab(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      if (index >= 0 && index < _built.length) {
        _built[index] = true;
      }
    });
  }

  void _handleBackRequested() {
    if (_index == 0) return;
    _selectTab(0);
  }

  @override
  Widget build(BuildContext context) {
    return DesktopThemeScope(
      child: Actions(
        actions: <Type, Action<Intent>>{
          AppBackIntent: CallbackAction<AppBackIntent>(
            onInvoke: (_) {
              _handleBackRequested();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: DesktopCinematicShell(
            appState: widget.appState,
            title: 'Workspace',
            tabs: _tabs,
            selectedIndex: _index,
            onSelected: _selectTab,
            trailingLabel:
                widget.appState.activeServer?.name ?? 'No active server',
            trailingIcon: Icons.dns_outlined,
            child: IndexedStack(
              index: _index,
              children: [
                _built[0]
                    ? ServerPage(
                        appState: widget.appState,
                        showInlineLocalEntry: false,
                      )
                    : const SizedBox.shrink(),
                _built[1]
                    ? DesktopPlayerPage.local(appState: widget.appState)
                    : const SizedBox.shrink(),
                _built[2]
                    ? DesktopSettingsPage(appState: widget.appState)
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
