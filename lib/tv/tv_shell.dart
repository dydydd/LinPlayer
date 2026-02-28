import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import '../home_page.dart';
import '../ass/ass_home_page.dart';
import '../server_page.dart';
import '../webdav_home_page.dart';
import 'tv_focusable.dart';

class TvShell extends StatefulWidget {
  const TvShell({super.key, required this.appState});

  final AppState appState;

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  bool _exitDialogShowing = false;

  Widget _buildHome() {
    final appState = widget.appState;
    if (appState.servers.isEmpty) {
      return ServerPage(appState: appState);
    }

    final active = appState.activeServer;
    if (active == null || !appState.hasActiveServerProfile) {
      return ServerPage(appState: appState);
    }
    if (active.serverType == MediaServerType.webdav) {
      return WebDavHomePage(appState: appState);
    }
    if (active.serverType == MediaServerType.ass) {
      return AssHomePage(appState: appState);
    }
    if (appState.hasActiveServer) {
      return HomePage(appState: appState);
    }
    return ServerPage(appState: appState);
  }

  Future<void> _confirmExit() async {
    if (_exitDialogShowing) return;
    _exitDialogShowing = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const _TvExitConfirmDialog(),
      );
      if (!mounted) return;
      if (confirmed == true) {
        unawaited(DeviceType.exitApp());
      }
    } finally {
      _exitDialogShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_confirmExit());
      },
      child: _buildHome(),
    );
  }
}

class _TvExitConfirmDialog extends StatelessWidget {
  const _TvExitConfirmDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(
              alpha: isDark ? 0.72 : 0.92,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.75),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '退出应用',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '确定要退出 LinPlayer 吗？',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TvFocusable(
                      autofocus: true,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Center(
                        child: Text(
                          '取消',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TvFocusable(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Center(
                        child: Text(
                          '确定',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
