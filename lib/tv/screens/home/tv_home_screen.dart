import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_hero_banner.dart';
import '../../widgets/tv_content_row.dart';
import '../../widgets/tv_toast.dart';

/// TV 首页
/// Hero Banner + 横向内容行（继续观看 + 媒体库 + 最近更新）
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  bool _heroFocused = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            // 按左键将焦点转移到导航栏
            // 由外部 shell 处理
            return KeyEventResult.ignored;
          }
          return KeyEventResult.ignored;
        },
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Banner
              Focus(
                onFocusChange: (focused) => setState(() => _heroFocused = focused),
                child: TvHeroBanner(
                  items: _buildHeroItems(),
                  onAutoPlayStarted: () {},
                  onAutoPlayStopped: () {},
                ),
              ),
              const SizedBox(height: TvDesignTokens.spacingLg),
              // 继续观看行
              TvContentRow(
                title: '继续观看',
                items: _buildContinueWatchingItems(),
                onSeeAll: () {
                  TvToast.show(context, '查看全部继续观看');
                },
                autofocusFirstItem: !_heroFocused,
              ),
              const SizedBox(height: TvDesignTokens.spacingLg),
              // 媒体库行
              TvContentRow(
                title: '媒体库',
                items: _buildLibraryItems(),
                onSeeAll: () {
                  TvToast.show(context, '查看全部媒体库');
                },
              ),
              const SizedBox(height: TvDesignTokens.spacingLg),
              // 最近更新行
              TvContentRow(
                title: '最近更新',
                items: _buildRecentItems(),
              ),
              const SizedBox(height: TvDesignTokens.spacingXxl),
            ],
          ),
        ),
      ),
    );
  }

  List<TvHeroItem> _buildHeroItems() {
    // TODO: 从 Provider 获取真实数据
    return [
      TvHeroItem(
        title: '示例剧集 1',
        subtitle: '第 1 季 · 更新至第 8 集',
        tags: ['剧情', '悬疑'],
        onPlay: () => TvToast.show(context, '播放示例剧集 1'),
      ),
      TvHeroItem(
        title: '示例剧集 2',
        subtitle: '第 2 季 · 全集',
        tags: ['科幻', '动作'],
        onPlay: () => TvToast.show(context, '播放示例剧集 2'),
      ),
    ];
  }

  List<TvPosterCardData> _buildContinueWatchingItems() {
    // TODO: 从 Provider 获取真实数据
    return [
      TvPosterCardData(
        title: '继续观看剧集 1',
        subtitle: 'S1E5 · 剩余 15 分钟',
        progress: 0.6,
        onTap: () => TvToast.show(context, '继续播放剧集 1'),
      ),
      TvPosterCardData(
        title: '继续观看剧集 2',
        subtitle: 'S2E3 · 下一集',
        progress: 1.0,
        nextEpisodeLabel: 'S2E4 · 下一集',
        onTap: () => TvToast.show(context, '播放下一集'),
      ),
      TvPosterCardData(
        title: '继续观看剧集 3',
        subtitle: 'S1E1 · 刚开始',
        progress: 0.05,
        onTap: () => TvToast.show(context, '继续播放剧集 3'),
      ),
    ];
  }

  List<TvPosterCardData> _buildLibraryItems() {
    // TODO: 从 Provider 获取真实数据
    return [
      TvPosterCardData(
        title: '电影库',
        subtitle: '128 部',
        onTap: () => TvToast.show(context, '进入电影库'),
      ),
      TvPosterCardData(
        title: '剧集库',
        subtitle: '45 部',
        onTap: () => TvToast.show(context, '进入剧集库'),
      ),
      TvPosterCardData(
        title: '动漫库',
        subtitle: '32 部',
        onTap: () => TvToast.show(context, '进入动漫库'),
      ),
    ];
  }

  List<TvPosterCardData> _buildRecentItems() {
    // TODO: 从 Provider 获取真实数据
    return [
      TvPosterCardData(
        title: '新剧集 1',
        isNew: true,
        onTap: () => TvToast.show(context, '播放新剧集 1'),
      ),
      TvPosterCardData(
        title: '新剧集 2',
        isNew: true,
        onTap: () => TvToast.show(context, '播放新剧集 2'),
      ),
      TvPosterCardData(
        title: '新剧集 3',
        onTap: () => TvToast.show(context, '播放新剧集 3'),
      ),
    ];
  }
}
