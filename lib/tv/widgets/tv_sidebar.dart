import 'package:flutter/material.dart';
import '../theme/tv_design_tokens.dart';
import 'tv_focusable.dart';

/// TV 左侧导航栏
/// 固定左侧，4 项导航：首页、搜索、服务器、设置
class TvSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool collapsed;

  const TvSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    this.collapsed = false,
  });

  @override
  State<TvSidebar> createState() => _TvSidebarState();
}

class _TvSidebarState extends State<TvSidebar> {
  final List<_NavItem> _items = const [
    _NavItem(Icons.home_rounded, '首页'),
    _NavItem(Icons.search_rounded, '搜索'),
    _NavItem(Icons.storage_rounded, '服务器'),
    _NavItem(Icons.settings_rounded, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = widget.collapsed
        ? TvDesignTokens.sidebarCollapsedWidth
        : TvDesignTokens.sidebarWidth;

    return Container(
      width: width,
      color: TvDesignTokens.surface,
      child: Column(
        children: [
          // Logo 区域
          Padding(
            padding: const EdgeInsets.all(TvDesignTokens.spacingLg),
            child: widget.collapsed
                ? const Icon(
                    Icons.play_circle_filled,
                    color: TvDesignTokens.brand,
                    size: 40,
                  )
                : Row(
                    children: [
                      const Icon(
                        Icons.play_circle_filled,
                        color: TvDesignTokens.brand,
                        size: 40,
                      ),
                      const SizedBox(width: TvDesignTokens.spacingSm),
                      Text(
                        'LinPlayer',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: TvDesignTokens.brand,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
          ),
          const Divider(color: TvDesignTokens.divider),
          // 导航项
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final isSelected = widget.selectedIndex == index;

                return TvFocusable(
                  autofocus: index == 0,
                  onSelect: () => widget.onItemSelected(index),
                  padding: const EdgeInsets.symmetric(
                    horizontal: TvDesignTokens.spacingMd,
                    vertical: TvDesignTokens.spacingSm,
                  ),
                  child: Container(
                    height: TvDesignTokens.sidebarItemHeight,
                    decoration: BoxDecoration(
                      color: isSelected ? TvDesignTokens.brand.withOpacity(0.15) : null,
                      borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                    ),
                    child: Row(
                      mainAxisAlignment: widget.collapsed
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        Icon(
                          item.icon,
                          color: isSelected ? TvDesignTokens.brand : TvDesignTokens.textSecondary,
                          size: TvDesignTokens.sidebarIconSize,
                        ),
                        if (!widget.collapsed) ...[
                          const SizedBox(width: TvDesignTokens.spacingMd),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: TvDesignTokens.sidebarTextSize,
                              color: isSelected ? TvDesignTokens.brand : TvDesignTokens.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}
