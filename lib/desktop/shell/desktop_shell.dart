import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/app_providers.dart';
import '../platform/desktop_ui_style.dart';
import '../utils/desktop_smooth_scroll.dart';
import 'desktop_nav_model.dart';
import 'fluent_shell.dart';
import 'macos_shell.dart';

/// 桌面端外壳调度器：按平台选择原生导航外壳，并共享“恢复上次服务器”的逻辑。
class DesktopShell extends ConsumerStatefulWidget {
  final Widget child;

  const DesktopShell({super.key, required this.child});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  bool _hasAttemptedRestore = false;

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serverListProvider);
    final currentServer = ref.watch(currentServerProvider);

    if (servers.isNotEmpty && currentServer == null && !_hasAttemptedRestore) {
      _hasAttemptedRestore = true;
      Future.microtask(() async {
        await ref.read(currentServerProvider.notifier).loadFromSaved(servers);
      });
    }

    switch (desktopUiStyle) {
      case DesktopUiStyle.fluent:
        return FluentDesktopShell(child: widget.child);
      case DesktopUiStyle.macos:
        return MacosDesktopShell(child: widget.child);
      case DesktopUiStyle.material:
        return MaterialDesktopShell(child: widget.child);
    }
  }
}

const double _kSidebarWidth = 220;
const double _kSidebarCollapsedWidth = 72;

/// Linux 外壳：Material 侧边栏（保留原桌面端外观）。
class MaterialDesktopShell extends ConsumerStatefulWidget {
  final Widget child;

  const MaterialDesktopShell({super.key, required this.child});

  @override
  ConsumerState<MaterialDesktopShell> createState() =>
      _MaterialDesktopShellState();
}

class _MaterialDesktopShellState extends ConsumerState<MaterialDesktopShell> {
  bool _isSidebarCollapsed = false;
  final ScrollController _navScrollController = DesktopSmoothScrollController();

  @override
  void dispose() {
    _navScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarWidth =
        _isSidebarCollapsed ? _kSidebarCollapsedWidth : _kSidebarWidth;

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.fastOutSlowIn,
            width: sidebarWidth,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA),
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? const Color(0xFF333333)
                      : const Color(0xFFE8EAED),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                SizedBox(height: _isSidebarCollapsed ? 12 : 20),
                Expanded(
                  child: ListView.builder(
                    controller: _navScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: desktopNavItems.length,
                    itemBuilder: (context, index) {
                      final item = desktopNavItems[index];
                      final isSelected =
                          desktopSelectedNavIndex(currentPath) == index;
                      return _buildNavItem(
                          item, isSelected, isDark, currentPath);
                    },
                  ),
                ),
                _buildServerStatus(isDark),
                const SizedBox(height: 8),
                _buildCollapseButton(isDark),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      DesktopNavItem item, bool isSelected, bool isDark, String currentPath) {
    final theme = Theme.of(context);
    final bgColor = isSelected
        ? const Color(0xFF5B8DEF).withValues(alpha: 0.15)
        : Colors.transparent;
    final iconColor = isSelected
        ? const Color(0xFF5B8DEF)
        : isDark
            ? const Color(0xFFAAAAAA)
            : const Color(0xFF666666);
    final textColor = isSelected
        ? const Color(0xFF5B8DEF)
        : isDark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF1A1A1A);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (currentPath != item.path) {
              context.go(item.path);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.fastOutSlowIn,
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarCollapsed ? 0 : 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _isSidebarCollapsed
                ? Center(
                    child: Tooltip(
                      message: item.label,
                      child: Icon(
                        isSelected ? item.selectedIcon : item.icon,
                        color: iconColor,
                        size: 22,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        isSelected ? item.selectedIcon : item.icon,
                        color: iconColor,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        item.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: textColor,
                        ),
                      ),
                      if (isSelected) ...[
                        const Spacer(),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFF5B8DEF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerStatus(bool isDark) {
    final currentServer = ref.watch(currentServerProvider);
    final authState = ref.watch(authStateProvider);
    final theme = Theme.of(context);

    if (currentServer == null) return const SizedBox.shrink();

    final isConnected = authState == AuthState.authenticated;
    final statusColor =
        isConnected ? const Color(0xFF4CAF50) : const Color(0xFFFFA726);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE8EAED),
        ),
      ),
      child: _isSidebarCollapsed
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentServer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCollapseButton(bool isDark) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isSidebarCollapsed = !_isSidebarCollapsed;
          });
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
            size: 18,
            color: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }
}
