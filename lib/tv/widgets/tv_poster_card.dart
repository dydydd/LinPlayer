import 'package:flutter/material.dart';
import '../../ui/widgets/common/media_widgets.dart';
import '../theme/tv_design_tokens.dart';

/// TV 海报卡片
/// 16:9 或 2:3 比例，支持焦点效果
class TvPosterCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final double? progress; // 0.0 - 1.0，null 表示不显示进度条
  final bool isNew;
  final String? nextEpisodeLabel;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const TvPosterCard({
    super.key,
    this.imageUrl,
    required this.title,
    this.subtitle,
    this.progress,
    this.isNew = false,
    this.nextEpisodeLabel,
    this.width = TvDesignTokens.posterWidth16_9,
    this.height = TvDesignTokens.posterHeight16_9,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 海报图片
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: imageUrl != null
                      ? MediaImage(
                          imageUrl: imageUrl,
                          width: width,
                          height: height,
                          fit: BoxFit.cover,
                        )
                      : _buildPlaceholder(),
                ),
              ),
              // 进度条
              if (progress != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(TvDesignTokens.posterRadius),
                        bottomRight: Radius.circular(TvDesignTokens.posterRadius),
                      ),
                      color: Colors.black.withOpacity(0.3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress!.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(TvDesignTokens.posterRadius),
                            bottomRight: progress! >= 1.0
                                ? Radius.circular(TvDesignTokens.posterRadius)
                                : Radius.zero,
                          ),
                          color: TvDesignTokens.brand,
                        ),
                      ),
                    ),
                  ),
                ),
              // "新" 标签
              if (isNew)
                Positioned(
                  top: TvDesignTokens.spacingXs,
                  right: TvDesignTokens.spacingXs,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TvDesignTokens.spacingXs,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: TvDesignTokens.brand,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '新',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              // 下一集标签
              if (nextEpisodeLabel != null)
                Positioned(
                  top: TvDesignTokens.spacingXs,
                  right: TvDesignTokens.spacingXs,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TvDesignTokens.spacingXs,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: TvDesignTokens.brand.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      nextEpisodeLabel!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: TvDesignTokens.spacingXs),
          // 标题
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: TvDesignTokens.fontSizeSm,
              color: TvDesignTokens.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          // 副标题
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: TvDesignTokens.fontSizeXs,
                color: TvDesignTokens.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: TvDesignTokens.surfaceElevated,
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: TvDesignTokens.textDisabled,
          size: 48,
        ),
      ),
    );
  }
}
