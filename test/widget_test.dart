import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lin_player/main.dart';
import 'package:lin_player/mobile_ui/server/mobile_add_server_page.dart';
import 'package:lin_player/mobile_ui/server/mobile_server_page.dart';
import 'package:lin_player_core/app_config/app_config.dart';
import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_state/app_state.dart';
import 'package:lin_player_state/server_profile.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

const _emptyStateTitle = '\u8fd8\u6ca1\u6709\u670d\u52a1\u5668';
const _addLabel = '\u6dfb\u52a0';
const _connectAndEnterLabel = '\u8fde\u63a5\u5e76\u8fdb\u5165';
const _importBackupLabel = '\u4ece\u5907\u4efd\u5bfc\u5165\u670d\u52a1\u5668';
const _addressFieldIndex = 1;
const _usernameFieldIndex = 3;

Finder _fieldAt(int index) {
  return find.byType(TextFormField).at(index);
}

void main() {
  testWidgets('Shows server screen by default', (WidgetTester tester) async {
    final appState = AppState();
    await tester.pumpWidget(
      AppConfigScope(
        config: AppConfig.current,
        child: LinPlayerApp(appState: appState),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MobileServerPage), findsOneWidget);
    expect(find.text(_emptyStateTitle), findsOneWidget);
    expect(find.widgetWithIcon(FilledButton, Icons.add), findsOneWidget);
  });

  testWidgets('Allows passwordless server login', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appState = _FakeAppState();
    await tester.pumpWidget(
      AppConfigScope(
        config: AppConfig.current,
        child: LinPlayerApp(appState: appState),
      ),
    );
    await tester.pumpAndSettle();

    final addButton = find.widgetWithText(FilledButton, _addLabel);
    expect(addButton, findsOneWidget);

    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.byType(MobileAddServerPage), findsOneWidget);
    expect(find.text(_importBackupLabel), findsOneWidget);

    await tester.tap(find.text('Emby').first);
    await tester.pumpAndSettle();

    final addressField = _fieldAt(_addressFieldIndex);
    final usernameField = _fieldAt(_usernameFieldIndex);
    expect(addressField, findsOneWidget);
    expect(usernameField, findsOneWidget);

    await tester.enterText(addressField, 'emby.example.com');
    await tester.enterText(usernameField, 'demo');

    await tester.ensureVisible(find.text(_connectAndEnterLabel));
    await tester.tap(find.text(_connectAndEnterLabel));
    await tester.pumpAndSettle();

    expect(appState.addServerCalled, isTrue);
    expect(appState.lastPassword, isEmpty);
  });
}

class _FakeAppState extends AppState {
  bool addServerCalled = false;
  String? lastPassword;

  @override
  Future<String?> addServer({
    required String hostOrUrl,
    required String scheme,
    String? port,
    MediaServerType serverType = MediaServerType.emby,
    required String username,
    required String password,
    String? displayName,
    String? remark,
    String? iconUrl,
    List<CustomDomain>? customDomains,
    bool activate = true,
  }) async {
    addServerCalled = true;
    lastPassword = password;
    return 'fake_server_id';
  }
}
