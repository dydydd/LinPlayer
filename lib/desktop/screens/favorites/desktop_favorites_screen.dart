import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../widgets/desktop_media_card.dart';

/// 桌面端收藏页
class DesktopFavoritesScreen extends ConsumerWidget {
  const DesktopFavoritesScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoriteItemsProvider);
    final servers = ref.watch(serverListProvider);
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部栏
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: const Row(
                children: [
                  Text(
                    '我的收藏',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (servers.isEmpty)
            const SliverFillRemaining(
              child: _EmptyServerGuide(),
            )
          else
            // 收藏内容
            favoritesAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite_border, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          '暂无收藏',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '在详情页点击收藏按钮添加',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }
              
              return SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 24,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return DesktopMediaCard(
                        item: items[index],
                        width: double.infinity,
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const SliverFillRemaining(
              child: Center(
                child: Text('加载失败', style: TextStyle(color: Colors.grey)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 无服务器引导组件
class _EmptyServerGuide extends StatelessWidget {
  const _EmptyServerGuide();
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            '尚未添加服务器',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '添加 Emby 服务器后即可查看收藏',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 32),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => context.go('/servers'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B8DEF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '前往服务器管理',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
