import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/media_providers.dart';
import '../../widgets/desktop_media_card.dart';

/// 桌面端搜索页
class DesktopSearchScreen extends ConsumerStatefulWidget {
  const DesktopSearchScreen({super.key});
  
  @override
  ConsumerState<DesktopSearchScreen> createState() => _DesktopSearchScreenState();
}

class _DesktopSearchScreenState extends ConsumerState<DesktopSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isAggregateSearch = false;
  
  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
  
  void _performSearch(String query) {
    ref.read(searchQueryProvider.notifier).state = query;
    ref.read(aggregateSearchProvider.notifier).state = _isAggregateSearch;
  }
  
  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(searchQueryProvider);
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final searchHistory = ref.watch(searchHistoryProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // 搜索栏
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: '搜索电影、剧集...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _performSearch('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        ref.read(searchHistoryProvider.notifier).addQuery(value);
                        _performSearch(value);
                      }
                    },
                    onChanged: (value) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                // 聚合搜索开关
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('聚合搜索'),
                    const SizedBox(width: 8),
                    Switch(
                      value: _isAggregateSearch,
                      onChanged: (value) {
                        setState(() => _isAggregateSearch = value);
                        if (_searchController.text.isNotEmpty) {
                          _performSearch(_searchController.text);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // 搜索历史
          if (searchQuery.isEmpty && searchHistory.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '搜索历史',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
                        child: const Text('清除'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: searchHistory.map((query) {
                      return ActionChip(
                        label: Text(query),
                        onPressed: () {
                          _searchController.text = query;
                          _performSearch(query);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          
          const Divider(),
          
          // 搜索结果
          Expanded(
            child: searchResultsAsync.when(
              data: (items) {
                if (searchQuery.isEmpty) {
                  return const Center(
                    child: Text('输入关键词开始搜索', style: TextStyle(color: Colors.grey)),
                  );
                }
                if (items.isEmpty) {
                  return const Center(
                    child: Text('未找到结果', style: TextStyle(color: Colors.grey)),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 24,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    return DesktopMediaCard(
                      item: items[index],
                      width: double.infinity,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(
                child: Text('搜索失败', style: TextStyle(color: Colors.grey)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
