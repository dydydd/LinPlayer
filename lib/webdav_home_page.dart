import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';

import 'mobile_ui/settings/mobile_settings_page.dart';
import 'settings_page.dart';
import 'services/playback/player_core_pages.dart';
import 'webdav_browser_page.dart';

class WebDavHomePage extends StatefulWidget {
  const WebDavHomePage({super.key, required this.appState});

  final AppState appState;

  @override
  State<WebDavHomePage> createState() => _WebDavHomePageState();
}

class _WebDavHomePageState extends State<WebDavHomePage> {
  int _index = 0; // 0 webdav, 1 local, 2 settings

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final server = appState.activeServer;

    final useMobileSettingsPage = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    final pages = [
      if (server == null)
        const Center(child: Text('No active server'))
      else
        WebDavBrowserPage(appState: appState, server: server),
      buildLocalPlayerScreen(appState: appState),
      useMobileSettingsPage
          ? MobileSettingsPage(appState: appState)
          : SettingsPage(appState: appState),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.cloud), label: 'WebDAV'),
          NavigationDestination(icon: Icon(Icons.folder_open), label: '本地'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}
