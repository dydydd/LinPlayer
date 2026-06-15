import 'package:flutter/material.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_toast.dart';
import '../../widgets/tv_panel.dart';
import 'tv_sync_settings.dart';

/// TV 设置页
/// 左侧设置分类 + 右侧设置项
class TvSettingsScreen extends StatefulWidget {
  const TvSettingsScreen({super.key});

  @override
  State<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends State<TvSettingsScreen> {
  int _selectedCategory = 0;

  final List<_SettingCategory> _categories = const [
    _SettingCategory(Icons.play_circle_outline, '播放'),
    _SettingCategory(Icons.settings, '通用'),
    _SettingCategory(Icons.subtitles, '字幕'),
    _SettingCategory(Icons.sync, '同步'),
    _SettingCategory(Icons.info_outline, '关于'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Row(
        children: [
          // 左侧分类
          Container(
            width: 240,
            color: TvDesignTokens.surface,
            child: ListView.builder(
              padding: const EdgeInsets.all(TvDesignTokens.spacingLg),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == index;
                return TvFocusable(
                  autofocus: index == 0,
                  onSelect: () => setState(() => _selectedCategory = index),
                  child: Container(
                    padding: const EdgeInsets.all(TvDesignTokens.spacingMd),
                    margin: const EdgeInsets.only(bottom: TvDesignTokens.spacingSm),
                    decoration: BoxDecoration(
                      color: isSelected ? TvDesignTokens.brand.withOpacity(0.15) : null,
                      borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          category.icon,
                          color: isSelected ? TvDesignTokens.brand : TvDesignTokens.textSecondary,
                          size: 28,
                        ),
                        const SizedBox(width: TvDesignTokens.spacingMd),
                        Text(
                          category.name,
                          style: TextStyle(
                            fontSize: TvDesignTokens.fontSizeMd,
                            color: isSelected ? TvDesignTokens.brand : TvDesignTokens.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 右侧内容
          Expanded(
            child: _buildSettingsContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    switch (_selectedCategory) {
      case 0:
        return _buildPlaybackSettings();
      case 1:
        return _buildGeneralSettings();
      case 2:
        return _buildSubtitleSettings();
      case 3:
        return const TvSyncSettings();
      case 4:
        return _buildAboutSettings();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPlaybackSettings() {
    return ListView(
      padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
      children: [
        const Text(
          '播放设置',
          style: TextStyle(
            fontSize: TvDesignTokens.fontSizeXxl,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: TvDesignTokens.spacingLg),
        _buildSettingItem(
          title: '默认倍速',
          subtitle: '1.0x',
          onTap: () => _showSpeedOptions(),
        ),
        _buildSettingItem(
          title: '画面比例',
          subtitle: '默认',
          onTap: () => _showAspectRatioOptions(),
        ),
        _buildSettingItem(
          title: '播放器内核',
          subtitle: 'MPV (默认)',
          onTap: () => _showPlayerEngineOptions(),
        ),
        _buildSettingItem(
          title: '自动播放下一集',
          subtitle: '开启',
          onTap: () => TvToast.show(context, '切换自动播放'),
        ),
        _buildSettingItem(
          title: '快进/快退步进',
          subtitle: '10秒',
          onTap: () => TvToast.show(context, '调整步进'),
        ),
      ],
    );
  }

  Widget _buildGeneralSettings() {
    return ListView(
      padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
      children: [
        const Text(
          '通用设置',
          style: TextStyle(
            fontSize: TvDesignTokens.fontSizeXxl,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: TvDesignTokens.spacingLg),
        _buildSettingItem(
          title: '语言',
          subtitle: '简体中文',
          onTap: () => TvToast.show(context, '切换语言'),
        ),
        _buildSettingItem(
          title: '弹幕',
          subtitle: '关闭（TV 端）',
          onTap: () => TvToast.show(context, 'TV 端弹幕默认关闭'),
        ),
        _buildSettingItem(
          title: '超分',
          subtitle: 'TV 端不可用',
          onTap: () => TvToast.show(context, 'TV 端不支持超分'),
        ),
      ],
    );
  }

  Widget _buildSubtitleSettings() {
    return ListView(
      padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
      children: [
        const Text(
          '字幕设置',
          style: TextStyle(
            fontSize: TvDesignTokens.fontSizeXxl,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: TvDesignTokens.spacingLg),
        _buildSettingItem(
          title: '字幕大小',
          subtitle: '24sp',
          onTap: () => TvToast.show(context, '调整字幕大小'),
        ),
        _buildSettingItem(
          title: '字幕位置',
          subtitle: '底部',
          onTap: () => TvToast.show(context, '调整字幕位置'),
        ),
      ],
    );
  }

  Widget _buildAboutSettings() {
    return ListView(
      padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
      children: [
        const Text(
          '关于',
          style: TextStyle(
            fontSize: TvDesignTokens.fontSizeXxl,
            color: TvDesignTokens.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: TvDesignTokens.spacingLg),
        _buildSettingItem(
          title: '版本',
          subtitle: '1.0.0',
          onTap: () {},
        ),
        _buildSettingItem(
          title: '检查更新',
          subtitle: '当前已是最新版',
          onTap: () => TvToast.show(context, '检查更新中...'),
        ),
        _buildSettingItem(
          title: '日志',
          subtitle: '查看日志',
          onTap: () => TvToast.show(context, '日志功能'),
        ),
        _buildSettingItem(
          title: '重新查看引导',
          subtitle: '查看 TV 引导页',
          onTap: () => TvToast.show(context, '显示引导页'),
        ),
        _buildSettingItem(
          title: '隐私政策',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildSettingItem({
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return TvFocusable(
      onSelect: onTap,
      child: Container(
        padding: const EdgeInsets.all(TvDesignTokens.spacingLg),
        margin: const EdgeInsets.only(bottom: TvDesignTokens.spacingMd),
        decoration: BoxDecoration(
          color: TvDesignTokens.surface,
          borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: TvDesignTokens.fontSizeMd,
                      color: TvDesignTokens.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: TvDesignTokens.fontSizeSm,
                        color: TvDesignTokens.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: TvDesignTokens.textSecondary,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedOptions() {
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '默认倍速',
        onClose: () => Navigator.pop(context),
        children: [
          TvPanelOption(
            title: '0.5x',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '0.75x',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '1.0x',
            isSelected: true,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '1.25x',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '1.5x',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '2.0x',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showAspectRatioOptions() {
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '画面比例',
        onClose: () => Navigator.pop(context),
        children: [
          TvPanelOption(
            title: '默认',
            isSelected: true,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '16:9',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '4:3',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: '填充',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showPlayerEngineOptions() {
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '播放器内核',
        onClose: () => Navigator.pop(context),
        children: [
          TvPanelOption(
            title: 'MPV（默认）',
            subtitle: '推荐，兼容性更好',
            isSelected: true,
            onTap: () => Navigator.pop(context),
          ),
          TvPanelOption(
            title: 'ExoPlayer',
            subtitle: 'Android 原生播放器',
            isSelected: false,
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _SettingCategory {
  final IconData icon;
  final String name;

  const _SettingCategory(this.icon, this.name);
}
