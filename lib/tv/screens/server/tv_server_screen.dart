import 'package:flutter/material.dart';
import '../../theme/tv_design_tokens.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_toast.dart';
import '../../widgets/tv_panel.dart';

/// TV 服务器页
/// 展示已添加的服务器列表，支持添加/编辑/删除
class TvServerScreen extends StatefulWidget {
  const TvServerScreen({super.key});

  @override
  State<TvServerScreen> createState() => _TvServerScreenState();
}

class _TvServerScreenState extends State<TvServerScreen> {
  // TODO: 从 Provider 获取服务器列表
  final List<Map<String, dynamic>> _servers = [
    {
      'name': '家庭服务器',
      'url': 'http://192.168.1.100:8096',
      'isOnline': true,
    },
    {
      'name': '公司服务器',
      'url': 'http://192.168.1.101:8096',
      'isOnline': false,
    },
  ];

  int? _selectedServerIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: Padding(
        padding: const EdgeInsets.all(TvDesignTokens.spacingXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            const Text(
              '服务器',
              style: TextStyle(
                fontSize: TvDesignTokens.fontSizeXxl,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: TvDesignTokens.spacingLg),
            // 服务器列表
            Expanded(
              child: ListView.builder(
                itemCount: _servers.length + 1, // +1 添加按钮
                itemBuilder: (context, index) {
                  if (index == _servers.length) {
                    return _buildAddButton();
                  }
                  return _buildServerCard(index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard(int index) {
    final server = _servers[index];
    final isSelected = _selectedServerIndex == index;

    return TvFocusable(
      onSelect: () {
        setState(() => _selectedServerIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.all(TvDesignTokens.spacingLg),
        margin: const EdgeInsets.only(bottom: TvDesignTokens.spacingMd),
        decoration: BoxDecoration(
          color: isSelected
              ? TvDesignTokens.brand.withOpacity(0.15)
              : TvDesignTokens.surface,
          borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
          border: isSelected
              ? Border.all(color: TvDesignTokens.brand, width: 2)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: server['isOnline']
                    ? TvDesignTokens.success.withOpacity(0.2)
                    : TvDesignTokens.error.withOpacity(0.2),
                borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
              ),
              child: Icon(
                Icons.storage,
                color: server['isOnline'] ? TvDesignTokens.success : TvDesignTokens.error,
                size: 32,
              ),
            ),
            const SizedBox(width: TvDesignTokens.spacingLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server['name'],
                    style: TextStyle(
                      fontSize: TvDesignTokens.fontSizeLg,
                      color: isSelected ? TvDesignTokens.brand : TvDesignTokens.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: TvDesignTokens.spacingXs),
                  Text(
                    server['url'],
                    style: const TextStyle(
                      fontSize: TvDesignTokens.fontSizeSm,
                      color: TvDesignTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: TvDesignTokens.spacingXs),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: server['isOnline'] ? TvDesignTokens.success : TvDesignTokens.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: TvDesignTokens.spacingXs),
                      Text(
                        server['isOnline'] ? '在线' : '离线',
                        style: TextStyle(
                          fontSize: TvDesignTokens.fontSizeXs,
                          color: server['isOnline'] ? TvDesignTokens.success : TvDesignTokens.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 操作按钮
            if (isSelected) ...[
              TvFocusable(
                onSelect: () => _showEditPanel(index),
                child: const Icon(
                  Icons.edit,
                  color: TvDesignTokens.brand,
                  size: 28,
                ),
              ),
              const SizedBox(width: TvDesignTokens.spacingMd),
              TvFocusable(
                onSelect: () => _deleteServer(index),
                child: const Icon(
                  Icons.delete,
                  color: TvDesignTokens.error,
                  size: 28,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return TvFocusable(
      onSelect: _showAddPanel,
      child: Container(
        padding: const EdgeInsets.all(TvDesignTokens.spacingLg),
        margin: const EdgeInsets.only(bottom: TvDesignTokens.spacingMd),
        decoration: BoxDecoration(
          color: TvDesignTokens.surface,
          borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
          border: Border.all(
            color: TvDesignTokens.divider,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add,
              color: TvDesignTokens.brand,
              size: 32,
            ),
            SizedBox(width: TvDesignTokens.spacingMd),
            Text(
              '添加服务器',
              style: TextStyle(
                fontSize: TvDesignTokens.fontSizeLg,
                color: TvDesignTokens.brand,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPanel() {
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '添加服务器',
        onClose: () => Navigator.pop(context),
        children: [
          // TODO: 添加服务器表单
          const TvPanelSection(title: '服务器信息'),
          TvPanelOption(
            title: '服务器地址',
            subtitle: 'http://192.168.1.100:8096',
            onTap: () {},
          ),
          TvPanelOption(
            title: '用户名',
            onTap: () {},
          ),
          TvPanelOption(
            title: '密码',
            onTap: () {},
          ),
          const SizedBox(height: TvDesignTokens.spacingLg),
          TvFocusable(
            onSelect: () {
              Navigator.pop(context);
              TvToast.show(context, '添加服务器成功');
            },
            child: Container(
              padding: const EdgeInsets.all(TvDesignTokens.spacingMd),
              decoration: BoxDecoration(
                color: TvDesignTokens.brand,
                borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
              ),
              child: const Center(
                child: Text(
                  '保存',
                  style: TextStyle(
                    fontSize: TvDesignTokens.fontSizeMd,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPanel(int index) {
    final server = _servers[index];
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '编辑服务器',
        onClose: () => Navigator.pop(context),
        children: [
          TvPanelSection(title: server['name']),
          TvPanelOption(
            title: '服务器地址',
            subtitle: server['url'],
            onTap: () {},
          ),
          const SizedBox(height: TvDesignTokens.spacingLg),
          TvFocusable(
            onSelect: () {
              Navigator.pop(context);
              TvToast.show(context, '保存成功');
            },
            child: Container(
              padding: const EdgeInsets.all(TvDesignTokens.spacingMd),
              decoration: BoxDecoration(
                color: TvDesignTokens.brand,
                borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
              ),
              child: const Center(
                child: Text(
                  '保存',
                  style: TextStyle(
                    fontSize: TvDesignTokens.fontSizeMd,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteServer(int index) {
    showDialog(
      context: context,
      builder: (context) => TvPanel(
        title: '删除服务器',
        onClose: () => Navigator.pop(context),
        children: [
          Text(
            '确定要删除 "${_servers[index]['name']}" 吗？',
            style: const TextStyle(
              fontSize: TvDesignTokens.fontSizeMd,
              color: TvDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: TvDesignTokens.spacingLg),
          Row(
            children: [
              Expanded(
                child: TvFocusable(
                  onSelect: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(TvDesignTokens.spacingMd),
                    decoration: BoxDecoration(
                      color: TvDesignTokens.surface,
                      borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                    ),
                    child: const Center(
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: TvDesignTokens.fontSizeMd,
                          color: TvDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: TvDesignTokens.spacingMd),
              Expanded(
                child: TvFocusable(
                  onSelect: () {
                    setState(() => _servers.removeAt(index));
                    Navigator.pop(context);
                    TvToast.show(context, '服务器已删除');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(TvDesignTokens.spacingMd),
                    decoration: BoxDecoration(
                      color: TvDesignTokens.error,
                      borderRadius: BorderRadius.circular(TvDesignTokens.posterRadius),
                    ),
                    child: const Center(
                      child: Text(
                        '删除',
                        style: TextStyle(
                          fontSize: TvDesignTokens.fontSizeMd,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
