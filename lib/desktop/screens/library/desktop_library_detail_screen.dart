import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/media_providers.dart';
import '../../widgets/desktop_media_card.dart';

/// 桌面端媒体库详情页
class DesktopLibraryDetailScreen extends ConsumerStatefulWidget {
  final String libraryId;
  
  const DesktopLibraryDetailScreen({super.key, required this.libraryId});
  
  @override
  ConsumerState<DesktopLibraryDetailScreen> createState() => _DesktopLibraryDetailScreenState();
}

class _DesktopLibraryDetailScreenState extends ConsumerState<DesktopLibraryDetailScreen> {
  String _sortBy = '加入日期';
  final String _sortOrder = '降序';
  final ScrollController _scrollController = ScrollController();
  
  @override
  Widget build(BuildContext context) {
    final libraryItemsAsync = ref.watch(libraryItemsProvider((
      libraryId: widget.libraryId,
      sortBy: _sortBy,
      sortOrder: _sortOrder,
    )));
    
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // 顶部栏
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '媒体库详情',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  
                  // 排序选项
                  _buildSortDropdown(),
                  
                  const SizedBox(width: 12),
                  
                  // 视图切换
                  IconButton(
                    icon: const Icon(Icons.grid_view),
                    onPressed: () {},
                    tooltip: '网格视图',
                  ),
                  IconButton(
                    icon: const Icon(Icons.view_list),
                    onPressed: () {},
                    tooltip: '列表视图',
                  ),
                ],
              ),
            ),
          ),
          
          // 筛选栏
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  _buildFilterChip('全部'),
                  const SizedBox(width: 8),
                  _buildFilterChip('电影'),
                  const SizedBox(width: 8),
                  _buildFilterChip('剧集'),
                  const SizedBox(width: 8),
                  _buildFilterChip('动画'),
                ],
              ),
            ),
          ),
          
          // 内容网格
          libraryItemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text('暂无内容', style: TextStyle(color: Colors.grey)),
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
                      final item = items[index];
                      return DesktopMediaCard(
                        item: item,
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
  
  Widget _buildSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _sortBy,
          isDense: true,
          items: ['加入日期', '标题', '首映日期', '评分'].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value, style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _sortBy = newValue;
              });
            }
          },
        ),
      ),
    );
  }
  
  Widget _buildFilterChip(String label) {
    final isSelected = label == '全部';
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }
}
