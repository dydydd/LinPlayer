import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../ui/utils/media_helpers.dart';
import '../../../ui/widgets/common/media_widgets.dart';

/// 桌面端媒体库列表页
class DesktopLibraryScreen extends ConsumerWidget {
  const DesktopLibraryScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(librariesProvider);
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部栏
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  const Text(
                    '媒体库',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.view_list),
                    onPressed: () {},
                    tooltip: '列表视图',
                  ),
                  IconButton(
                    icon: const Icon(Icons.grid_view),
                    onPressed: () {},
                    tooltip: '网格视图',
                  ),
                ],
              ),
            ),
          ),
          
          // 媒体库网格
          librariesAsync.when(
            data: (libraries) {
              if (libraries.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text('暂无媒体库', style: TextStyle(color: Colors.grey)),
                  ),
                );
              }
              
              return SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 1.4,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final library = libraries[index];
                      return _DesktopLibraryGridCard(library: library);
                    },
                    childCount: libraries.length,
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

class _DesktopLibraryGridCard extends ConsumerStatefulWidget {
  final Library library;
  
  const _DesktopLibraryGridCard({required this.library});
  
  @override
  ConsumerState<_DesktopLibraryGridCard> createState() => _DesktopLibraryGridCardState();
}

class _DesktopLibraryGridCardState extends ConsumerState<_DesktopLibraryGridCard> {
  bool _isHovered = false;
  
  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiClientProvider);
    final imageUrls = resolveLibraryImageUrls(api, widget.library, maxWidth: 600);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/library/${widget.library.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: _isHovered 
              ? (Matrix4.identity()..translateByDouble(0.0, -6.0, 0.0, 0.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Theme.of(context).dividerColor.withValues(alpha: 0.2),
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 封面图
              MediaImage(
                imageUrl: imageUrls.isNotEmpty ? imageUrls.first : null,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
              
              // 底部渐变
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 120,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
              
              // 名称
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Text(
                  widget.library.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              
              // 悬停播放图标
              if (_isHovered)
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
