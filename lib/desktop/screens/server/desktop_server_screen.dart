import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../ui/widgets/common/media_widgets.dart';

/// 桌面端服务器管理页
class DesktopServerScreen extends ConsumerStatefulWidget {
  const DesktopServerScreen({super.key});
  
  @override
  ConsumerState<DesktopServerScreen> createState() => _DesktopServerScreenState();
}

class _DesktopServerScreenState extends ConsumerState<DesktopServerScreen> {
  bool _isGridView = true;
  
  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serverListProvider);
    final currentServer = ref.watch(currentServerProvider);
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部栏
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Row(
                children: [
                  const Text(
                    '服务器管理',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  
                  // 视图切换
                  IconButton(
                    icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                    onPressed: () => setState(() => _isGridView = !_isGridView),
                    tooltip: _isGridView ? '列表视图' : '网格视图',
                  ),
                ],
              ),
            ),
          ),
          
          // 服务器列表
          if (servers.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.dns_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      '暂无服务器',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => context.push('/add-server'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5B8DEF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '添加服务器',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_isGridView)
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 1.8,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final server = servers[index];
                    final isCurrent = server.id == currentServer?.id;
                    return _ServerGridCard(
                      server: server,
                      isCurrent: isCurrent,
                      onTap: () => _selectServer(server),
                    );
                  },
                  childCount: servers.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final server = servers[index];
                    final isCurrent = server.id == currentServer?.id;
                    return _ServerListTile(
                      server: server,
                      isCurrent: isCurrent,
                      onTap: () => _selectServer(server),
                    );
                  },
                  childCount: servers.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  void _selectServer(ServerConfig server) {
    ref.read(currentServerProvider.notifier).state = server;
    if (server.authToken != null) {
      ref.read(authStateProvider.notifier).state = AuthState.authenticated;
    }
    ref.invalidate(librariesProvider);
    ref.invalidate(resumeItemsProvider);
  }
}

/// 服务器网格卡片
class _ServerGridCard extends StatefulWidget {
  final ServerConfig server;
  final bool isCurrent;
  final VoidCallback onTap;
  
  const _ServerGridCard({
    required this.server,
    required this.isCurrent,
    required this.onTap,
  });
  
  @override
  State<_ServerGridCard> createState() => _ServerGridCardState();
}

class _ServerGridCardState extends State<_ServerGridCard> {
  bool _isHovered = false;
  
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.fastOutSlowIn,
          transform: _isHovered 
              ? (Matrix4.identity()..translateByDouble(0.0, -4.0, 0.0, 0.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isHovered || widget.isCurrent
                ? [
                    BoxShadow(
                      color: widget.isCurrent
                          ? const Color(0xFF5B8DEF).withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 服务器图标
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B8DEF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: widget.server.iconUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: MediaImage(
                                imageUrl: widget.server.iconUrl,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(
                              Icons.dns,
                              size: 24,
                              color: Color(0xFF5B8DEF),
                            ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // 服务器信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.server.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.server.baseUrl,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    
                    // 当前选中标记
                    if (widget.isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B8DEF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '当前',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF5B8DEF),
                          ),
                        ),
                      ),
                  ],
                ),
                
                const Spacer(),
                
                // 底部信息
                Row(
                  children: [
                    if (widget.server.remark != null) ...[
                      Icon(
                        Icons.notes,
                        size: 14,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.server.remark!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const Spacer(),
                    
                    // 操作按钮
                    _buildActionButton(
                      icon: Icons.edit,
                      tooltip: '编辑',
                      onTap: () {},
                    ),
                    const SizedBox(width: 4),
                    _buildActionButton(
                      icon: Icons.refresh,
                      tooltip: '重新登录',
                      onTap: () {},
                    ),
                    const SizedBox(width: 4),
                    _buildActionButton(
                      icon: Icons.more_vert,
                      tooltip: '更多',
                      onTap: () => _showMoreMenu(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: Colors.grey),
          ),
        ),
      ),
    );
  }
  
  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑信息'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重新登录'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.route),
              title: const Text('服务器线路'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('修改图标'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// 服务器列表项
class _ServerListTile extends StatefulWidget {
  final ServerConfig server;
  final bool isCurrent;
  final VoidCallback onTap;
  
  const _ServerListTile({
    required this.server,
    required this.isCurrent,
    required this.onTap,
  });
  
  @override
  State<_ServerListTile> createState() => _ServerListTileState();
}

class _ServerListTileState extends State<_ServerListTile> {
  bool _isHovered = false;
  
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B8DEF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: widget.server.iconUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: MediaImage(
                          imageUrl: widget.server.iconUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.dns, size: 20, color: Color(0xFF5B8DEF)),
              ),
              
              const SizedBox(width: 16),
              
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.server.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.server.baseUrl,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 当前标记
              if (widget.isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B8DEF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '当前',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B8DEF),
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
