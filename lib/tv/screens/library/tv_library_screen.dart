import 'package:flutter/material.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_toast.dart';

/// TV 媒体库页
/// 2:3 海报网格，可切换行数
class TvLibraryScreen extends StatefulWidget {
  const TvLibraryScreen({super.key});

  @override
  State<TvLibraryScreen> createState() => _TvLibraryScreenState();
}

class _TvLibraryScreenState extends State<TvLibraryScreen> {
  int _columns = 6; // 默认 6 列（高密度）

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Padding(
        padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
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
                // 列数切换
                TvFocusable(
                  onSelect: () {
                    setState(() {
                      _columns = _columns == 6 ? 4 : _columns == 4 ? 3 : 6;
                    });
                    TvToast.show(context, '网格列数: $_columns');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TvDesignTokens.spacingMd,
                      vertical: TvDesignTokens.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: TvDesignTokens.surface,
                      borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _columns == 3 ? Icons.grid_view : Icons.grid_on,
                          color: TvDesignTokens.textSecondary,
                          size: 24,
                        ),
                        const SizedBox(width: TvDesignTokens.spacingXs),
                        Text(
                          '$_columns 列',
                          style: const TextStyle(
                            fontSize: TvDesignTokens.fontSizeSm,
                            color: TvDesignTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TvDesignTokens.spacingLg),
            // 排序选项
            Row(
              children: [
                TvFocusable(
                  onSelect: () => TvToast.show(context, '按名称排序'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TvDesignTokens.spacingMd,
                      vertical: TvDesignTokens.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: TvDesignTokens.brand.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                    ),
                    child: const Text(
                      '名称',
                      style: TextStyle(
                        fontSize: TvDesignTokens.fontSizeSm,
                        color: TvDesignTokens.brand,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: TvDesignTokens.spacingSm),
                TvFocusable(
                  onSelect: () => TvToast.show(context, '按时间排序'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TvDesignTokens.spacingMd,
                      vertical: TvDesignTokens.spacingXs,
                    ),
                    decoration: BoxDecoration(
                      color: TvDesignTokens.surface,
                      borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                    ),
                    child: const Text(
                      '时间',
                      style: TextStyle(
                        fontSize: TvDesignTokens.fontSizeSm,
                        color: TvDesignTokens.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TvDesignTokens.spacingLg),
            // 网格内容
            Expanded(
              child: _buildGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    // TODO: 从 Provider 获取真实数据
    final items = List.generate(24, (index) => '媒体项 $index');

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: TvDesignTokens.spacingMd,
        mainAxisSpacing: TvDesignTokens.spacingMd,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return TvFocusable(
          onSelect: () => TvToast.show(context, '选择 ${items[index]}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: TvDesignTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: TvDesignTokens.textDisabled,
                      size: 48,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: TvDesignTokens.spacingXs),
              Text(
                items[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: TvDesignTokens.fontSizeSm,
                  color: TvDesignTokens.textPrimary,
                ),
              ),
              Text(
                '2024',
                style: const TextStyle(
                  fontSize: TvDesignTokens.fontSizeXs,
                  color: TvDesignTokens.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
