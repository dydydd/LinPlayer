import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import 'desktop_nav_model.dart';

/// Windows 外壳：fluent_ui 的 [NavigationView]（仿 WinUI 左侧导航）。
///
/// 内容由 go_router 提供（[child]）。为配合 go_router，每个 [PaneItem] 的 body
/// 均指向同一个 [child]，选中项由当前路由推导，点击时通过 go_router 跳转。
class FluentDesktopShell extends ConsumerWidget {
  final m.Widget child;

  const FluentDesktopShell({super.key, required this.child});

  @override
  m.Widget build(m.BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = desktopSelectedNavIndex(currentPath);

    return NavigationView(
      pane: NavigationPane(
        selected: selectedIndex,
        onChanged: (index) {
          final path = desktopNavItems[index].path;
          if (currentPath != path) context.go(path);
        },
        displayMode: PaneDisplayMode.auto,
        items: [
          for (final item in desktopNavItems)
            PaneItem(
              icon: m.Icon(item.icon, size: 18),
              selectedTileColor: WidgetStateProperty.all(
                FluentTheme.of(context).accentColor.withValues(alpha: 0.14),
              ),
              title: m.Text(item.label),
              body: child,
            ),
        ],
        footerItems: [
          PaneItemWidgetAdapter(
            child: _ServerStatus(),
          ),
        ],
      ),
    );
  }
}

class _ServerStatus extends ConsumerWidget {
  @override
  m.Widget build(m.BuildContext context, WidgetRef ref) {
    final currentServer = ref.watch(currentServerProvider);
    final authState = ref.watch(authStateProvider);
    if (currentServer == null) return const m.SizedBox.shrink();

    final isConnected = authState == AuthState.authenticated;
    final statusColor =
        isConnected ? const m.Color(0xFF4CAF50) : const m.Color(0xFFFFA726);

    return m.Padding(
      padding: const m.EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: m.Row(
        children: [
          m.Container(
            width: 8,
            height: 8,
            decoration: m.BoxDecoration(
              color: statusColor,
              shape: m.BoxShape.circle,
            ),
          ),
          const m.SizedBox(width: 8),
          m.Flexible(
            child: m.Text(
              currentServer.name,
              maxLines: 1,
              overflow: m.TextOverflow.ellipsis,
              style: m.TextStyle(
                fontSize: 12,
                color: FluentTheme.of(context).inactiveColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
