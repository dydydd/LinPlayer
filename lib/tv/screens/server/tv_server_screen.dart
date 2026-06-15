import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_panel.dart';
import '../../widgets/tv_toast.dart';

/// TV 服务器页 —— 真实服务器列表，支持切换当前服务器、删除、跳转添加。
class TvServerScreen extends ConsumerWidget {
  const TvServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider);
    final current = ref.watch(currentServerProvider);

    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Padding(
        padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '服务器',
              style: TextStyle(
                fontSize: TvDesignTokens.fontSizeXxl,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: TvDesignTokens.spacingLg),
            Expanded(
              child: servers.isEmpty
                  ? _buildEmpty(context)
                  : ListView(
                      children: [
                        for (final entry in servers.asMap().entries)
                          _buildServerCard(
                            context,
                            ref,
                            entry.value,
                            isCurrent: entry.value.id == current?.id,
                          ).animate().fadeIn(
                                delay: Duration(milliseconds: 40 * entry.key),
                                duration: TvDesignTokens.contentFadeDuration,
                              ),
                        const SizedBox(height: TvDesignTokens.spacingMd),
                        TvButton(
                          text: '添加服务器',
                          icon: Icons.add,
                          onPressed: () => context.go('/tv/add-server'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dns_outlined,
              color: TvDesignTokens.textSecondary, size: 80),
          const SizedBox(height: TvDesignTokens.spacingLg),
          const Text('还没有服务器',
              style: TextStyle(
                  fontSize: TvDesignTokens.fontSizeXl,
                  color: TvDesignTokens.textPrimary,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: TvDesignTokens.spacingXl),
          TvButton(
            text: '添加服务器',
            icon: Icons.add,
            autofocus: true,
            onPressed: () => context.go('/tv/add-server'),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard(
    BuildContext context,
    WidgetRef ref,
    ServerConfig server, {
    required bool isCurrent,
  }) {
    final online = serverHasUsableAuth(server);
    return Padding(
      padding: const EdgeInsets.only(bottom: TvDesignTokens.spacingMd),
      child: TvFocusable(
        padding: const EdgeInsets.all(6),
        onSelect: () => _selectServer(context, ref, server),
        child: Container(
          padding: const EdgeInsets.all(TvDesignTokens.spacingLg),
          decoration: BoxDecoration(
            color: isCurrent
                ? TvDesignTokens.brand.withValues(alpha: 0.15)
                : TvDesignTokens.surface,
            borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
            border: isCurrent
                ? Border.all(color: TvDesignTokens.brand, width: 2)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: (online ? TvDesignTokens.success : TvDesignTokens.error)
                      .withValues(alpha: 0.2),
                  borderRadius:
                      BorderRadius.circular(TvDesignTokens.posterRadius),
                ),
                child: Icon(Icons.storage,
                    color:
                        online ? TvDesignTokens.success : TvDesignTokens.error,
                    size: 32),
              ),
              const SizedBox(width: TvDesignTokens.spacingLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: TvDesignTokens.fontSizeLg,
                              color: isCurrent
                                  ? TvDesignTokens.brand
                                  : TvDesignTokens.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: TvDesignTokens.spacingSm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: TvDesignTokens.brand,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('当前',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: TvDesignTokens.spacingXs),
                    Text(server.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: TvDesignTokens.fontSizeSm,
                            color: TvDesignTokens.textSecondary)),
                    const SizedBox(height: TvDesignTokens.spacingXs),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: online
                                ? TvDesignTokens.success
                                : TvDesignTokens.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: TvDesignTokens.spacingXs),
                        Text(online ? '已登录' : '未登录',
                            style: TextStyle(
                                fontSize: TvDesignTokens.fontSizeXs,
                                color: online
                                    ? TvDesignTokens.success
                                    : TvDesignTokens.error)),
                      ],
                    ),
                  ],
                ),
              ),
              TvFocusable(
                padding: const EdgeInsets.all(TvDesignTokens.spacingXs),
                onSelect: () => _confirmDelete(context, ref, server),
                child: const Icon(Icons.delete_outline,
                    color: TvDesignTokens.error, size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectServer(BuildContext context, WidgetRef ref, ServerConfig server) {
    ref.read(currentServerProvider.notifier).state = server;
    ref.read(authStateProvider.notifier).state = serverHasUsableAuth(server)
        ? AuthState.authenticated
        : AuthState.unauthenticated;
    ref.invalidate(librariesProvider);
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(randomRecommendationsProvider);
    TvToast.show(context, '已切换到 ${server.name}');
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, ServerConfig server) {
    showDialog(
      context: context,
      builder: (dialogContext) => TvPanel(
        title: '删除服务器',
        onClose: () => Navigator.pop(dialogContext),
        children: [
          Text('确定要删除 “${server.name}” 吗？',
              style: const TextStyle(
                  fontSize: TvDesignTokens.fontSizeMd,
                  color: TvDesignTokens.textPrimary)),
          const SizedBox(height: TvDesignTokens.spacingLg),
          Row(
            children: [
              Expanded(
                child: TvFocusable(
                  autofocus: true,
                  onSelect: () => Navigator.pop(dialogContext),
                  child: _dialogButton('取消', TvDesignTokens.surface,
                      TvDesignTokens.textPrimary),
                ),
              ),
              const SizedBox(width: TvDesignTokens.spacingMd),
              Expanded(
                child: TvFocusable(
                  onSelect: () {
                    ref.read(serverListProvider.notifier).removeServer(server.id);
                    if (ref.read(currentServerProvider)?.id == server.id) {
                      ref.read(currentServerProvider.notifier).clear();
                    }
                    Navigator.pop(dialogContext);
                    TvToast.show(context, '服务器已删除');
                  },
                  child:
                      _dialogButton('删除', TvDesignTokens.error, Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dialogButton(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(TvDesignTokens.spacingMd),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
      ),
      child: Center(
        child: Text(text,
            style: TextStyle(
                fontSize: TvDesignTokens.fontSizeMd,
                color: fg,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}
