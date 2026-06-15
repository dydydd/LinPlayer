import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../ui/utils/media_helpers.dart';
import '../../../ui/widgets/common/media_widgets.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_focusable.dart';

/// TV 媒体库页 —— 顶部选库 + 排序，下方 2:3 海报网格（真实数据）。
class TvLibraryScreen extends ConsumerStatefulWidget {
  const TvLibraryScreen({super.key});

  @override
  ConsumerState<TvLibraryScreen> createState() => _TvLibraryScreenState();
}

class _TvLibraryScreenState extends ConsumerState<TvLibraryScreen> {
  int _columns = 6;
  String? _libraryId;
  String _sortBy = 'SortName'; // SortName | DateCreated

  @override
  Widget build(BuildContext context) {
    final librariesAsync = ref.watch(librariesProvider);

    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Padding(
        padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
        child: librariesAsync.when(
          data: (libs) {
            if (libs.isEmpty) {
              return _centerHint('暂无媒体库');
            }
            final libId = _libraryId ?? libs.first.id;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: TvDesignTokens.spacingMd),
                _buildLibraryPicker(libs, libId),
                const SizedBox(height: TvDesignTokens.spacingMd),
                _buildSortRow(),
                const SizedBox(height: TvDesignTokens.spacingLg),
                Expanded(child: _buildGrid(libId)),
              ],
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator(color: TvDesignTokens.brand)),
          error: (e, _) => _centerHint('加载媒体库失败：$e'),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          '媒体库',
          style: TextStyle(
            fontSize: TvDesignTokens.fontSizeXxl,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        TvFocusable(
          onSelect: () => setState(() {
            _columns = _columns == 6 ? 4 : (_columns == 4 ? 3 : 6);
          }),
          child: _chip(
            icon: _columns == 3 ? Icons.grid_view : Icons.grid_on,
            label: '$_columns 列',
            selected: false,
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryPicker(List<Library> libs, String selectedId) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: libs.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: TvDesignTokens.spacingSm),
        itemBuilder: (context, index) {
          final lib = libs[index];
          final selected = lib.id == selectedId;
          return TvFocusable(
            onSelect: () => setState(() => _libraryId = lib.id),
            child: _chip(label: lib.name, selected: selected),
          );
        },
      ),
    );
  }

  Widget _buildSortRow() {
    return Row(
      children: [
        TvFocusable(
          onSelect: () => setState(() => _sortBy = 'SortName'),
          child: _chip(label: '名称', selected: _sortBy == 'SortName'),
        ),
        const SizedBox(width: TvDesignTokens.spacingSm),
        TvFocusable(
          onSelect: () => setState(() => _sortBy = 'DateCreated'),
          child: _chip(label: '最近添加', selected: _sortBy == 'DateCreated'),
        ),
      ],
    );
  }

  Widget _buildGrid(String libraryId) {
    final itemsAsync = ref.watch(libraryItemsProvider((
      libraryId: libraryId,
      sortBy: _sortBy,
      sortOrder: _sortBy == 'DateCreated' ? 'Descending' : 'Ascending',
    )));
    final api = ref.read(apiClientProvider);

    return itemsAsync.when(
      data: (items) {
        if (items.isEmpty) return _centerHint('该媒体库暂无内容');
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columns,
            childAspectRatio: 2 / 3.4,
            crossAxisSpacing: TvDesignTokens.spacingMd,
            mainAxisSpacing: TvDesignTokens.spacingMd,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final urls = resolveMediaItemImageUrls(api, item, maxWidth: 360);
            return TvFocusable(
              padding: const EdgeInsets.all(6),
              onSelect: () => context.push('/tv/detail/${item.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(TvDesignTokens.posterRadius),
                      child: urls.isNotEmpty
                          ? MediaImage(
                              imageUrl: urls.first,
                              imageUrls: urls.length > 1 ? urls.sublist(1) : null,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : const ColoredBox(
                              color: TvDesignTokens.surfaceElevated,
                              child: Icon(Icons.movie_outlined,
                                  color: TvDesignTokens.textDisabled, size: 40),
                            ),
                    ),
                  ),
                  const SizedBox(height: TvDesignTokens.spacingXs),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: TvDesignTokens.fontSizeXs,
                      color: TvDesignTokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(
                  delay: Duration(milliseconds: 12 * (index % _columns)),
                  duration: TvDesignTokens.contentFadeDuration,
                );
          },
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(color: TvDesignTokens.brand)),
      error: (e, _) => _centerHint('加载失败：$e'),
    );
  }

  Widget _chip({IconData? icon, required String label, required bool selected}) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TvDesignTokens.spacingMd,
        vertical: TvDesignTokens.spacingXs,
      ),
      decoration: BoxDecoration(
        color: selected
            ? TvDesignTokens.brand.withValues(alpha: 0.18)
            : TvDesignTokens.surface,
        borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
        border:
            selected ? Border.all(color: TvDesignTokens.brand, width: 2) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 22,
                color: selected
                    ? TvDesignTokens.brand
                    : TvDesignTokens.textSecondary),
            const SizedBox(width: TvDesignTokens.spacingXs),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: TvDesignTokens.fontSizeSm,
              color: selected ? TvDesignTokens.brand : TvDesignTokens.textPrimary,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerHint(String text) => Center(
        child: Text(
          text,
          style: const TextStyle(
            color: TvDesignTokens.textSecondary,
            fontSize: TvDesignTokens.fontSizeMd,
          ),
        ),
      );
}
