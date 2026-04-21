import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'mobile_ui/server/mobile_server_page.dart';
import 'settings_page.dart';
import 'services/playback/player_core_pages.dart';
import 'services/tv_remote/tv_remote_service.dart';
import 'server_text_import_sheet.dart';
import 'package:lin_player_server_api/services/plex_api.dart';
import 'package:lin_player_core/state/media_server_type.dart';

class ServerPage extends StatefulWidget {
  const ServerPage({
    super.key,
    required this.appState,
    this.desktopLayout = false,
    this.showInlineLocalEntry = true,
  });

  final AppState appState;
  final bool desktopLayout;
  final bool showInlineLocalEntry;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  int _desktopTabIndex = 0;
  final List<bool> _desktopPagesBuilt = <bool>[true, false, false];

  bool _isTv(BuildContext context) => DeviceType.isTv;

  @override
  void initState() {
    super.initState();
    if (DeviceType.isTv && widget.appState.tvRemoteEnabled) {
      // Make pairing available out-of-box on Android TV.
      unawaited(TvRemoteService.instance.start(appState: widget.appState));
    }
  }

  void _selectDesktopTab(int index) {
    if (index == _desktopTabIndex) return;
    setState(() {
      _desktopTabIndex = index;
      if (index >= 0 && index < _desktopPagesBuilt.length) {
        _desktopPagesBuilt[index] = true;
      }
    });
  }

  Future<void> _openLocalPlayer() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildLocalPlayerScreen(appState: widget.appState),
      ),
    );
  }

  Future<void> _showAddServerSheet() async {
    final addedServerId = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AddServerSheet(
        appState: widget.appState,
        onOpenBulkImport: (sheetContext) async {
          Navigator.of(sheetContext).pop();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (!mounted) return;
          final importedServerId = await _showBulkImportSheet();
          if (!mounted || importedServerId == null) return;
          final ok = await widget.appState.enterServer(importedServerId);
          if (!mounted || ok) return;

          String message = (widget.appState.error ?? '').trim();
          if (message.isEmpty) {
            for (final server in widget.appState.servers) {
              if (server.id == importedServerId) {
                message = (server.lastErrorMessage ?? '').trim();
                break;
              }
            }
          }
          if (message.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        },
      ),
    );
    if (!mounted || addedServerId == null) return;
    final ok = await widget.appState.enterServer(addedServerId);
    if (!mounted || ok) return;

    String message = (widget.appState.error ?? '').trim();
    if (message.isEmpty) {
      for (final server in widget.appState.servers) {
        if (server.id == addedServerId) {
          message = (server.lastErrorMessage ?? '').trim();
          break;
        }
      }
    }
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<String?> _showBulkImportSheet() async {
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ServerTextImportSheet(appState: widget.appState),
    );
  }

  Future<void> _showEditServerSheet(ServerProfile server) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) =>
          _EditServerSheet(appState: widget.appState, server: server),
    );
  }

  Widget _buildServerListView(
    BuildContext context, {
    required List<ServerProfile> servers,
    required bool loading,
    required bool isTv,
    required bool showInlineLocalEntry,
    required bool isList,
    required double maxCrossAxisExtent,
  }) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '服务器',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                  ),
                ),
                if (isTv)
                  SegmentedButton<ServerListLayout>(
                    segments: const [
                      ButtonSegment(
                        value: ServerListLayout.grid,
                        label: Text('矩形'),
                        icon: Icon(Icons.grid_view_outlined),
                      ),
                      ButtonSegment(
                        value: ServerListLayout.list,
                        label: Text('条形'),
                        icon: Icon(Icons.view_list_outlined),
                      ),
                    ],
                    selected: {
                      isList ? ServerListLayout.list : ServerListLayout.grid,
                    },
                    showSelectedIcon: false,
                    onSelectionChanged: loading
                        ? null
                        : (selected) async {
                            await widget.appState.setServerListLayout(
                              selected.first,
                            );
                          },
                  )
                else
                  IconButton(
                    tooltip: isList ? '网格显示' : '条状显示',
                    onPressed: loading
                        ? null
                        : () async {
                            await widget.appState.setServerListLayout(
                              isList
                                  ? ServerListLayout.grid
                                  : ServerListLayout.list,
                            );
                          },
                    icon: Icon(
                      isList
                          ? Icons.grid_view_outlined
                          : Icons.view_list_outlined,
                    ),
                  ),
                if (!isTv)
                  IconButton(
                    tooltip: '主题',
                    onPressed: () => showThemeSheet(
                      context,
                      listenable: widget.appState,
                      themeMode: () => widget.appState.themeMode,
                      setThemeMode: widget.appState.setThemeMode,
                      useDynamicColor: () => widget.appState.useDynamicColor,
                      setUseDynamicColor: widget.appState.setUseDynamicColor,
                    ),
                    icon: const Icon(Icons.palette_outlined),
                  ),
                IconButton(
                  tooltip: '添加服务器',
                  onPressed: loading ? null : _showAddServerSheet,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
        if (loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(),
            ),
          ),
        if (!isTv && showInlineLocalEntry)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('本地播放'),
                  subtitle: const Text('无需登录，直接播放本地文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: loading ? null : _openLocalPlayer,
                ),
              ),
            ),
          ),
        if (servers.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  isTv ? '还没有服务器，请用手机扫码右侧二维码添加。' : '还没有服务器，点右上角“+”添加。',
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            sliver: isList
                ? SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final server = servers[index];
                        final isActive =
                            server.id == widget.appState.activeServerId;
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == servers.length - 1 ? 0 : 10,
                          ),
                          child: _ServerListTile(
                            server: server,
                            active: isActive,
                            subtitleText:
                                isTv ? _tvServerSubtitle(server) : null,
                            autofocus: isTv && isActive,
                            onTap: loading
                                ? null
                                : () async {
                                    final hasError =
                                        server.lastErrorCode != null ||
                                            (server.lastErrorMessage ?? '')
                                                .trim()
                                                .isNotEmpty;
                                    if (hasError) {
                                      final msg =
                                          (server.lastErrorMessage ?? '')
                                              .trim();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            msg.isNotEmpty
                                                ? msg
                                                : '服务器不可用（${server.lastErrorCode}）',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (server.serverType ==
                                        MediaServerType.plex) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${server.serverType.label} 暂未支持浏览/播放（仅可保存登录信息）。',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (server.id ==
                                        widget.appState.activeServerId) {
                                      await Navigator.of(context).maybePop();
                                      return;
                                    }
                                    final ok = await widget.appState
                                        .enterServer(server.id);
                                    if (!context.mounted) return;
                                    if (ok) {
                                      await Navigator.of(context).maybePop();
                                      return;
                                    }
                                    final msg = (server.lastErrorMessage ??
                                            widget.appState.error ??
                                            '')
                                        .trim();
                                    if (msg.isNotEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(content: Text(msg)),
                                      );
                                    }
                                  },
                            onLongPress: () => isTv
                                ? unawaited(_showTvServerMenu(server))
                                : _showEditServerSheet(server),
                          ),
                        );
                      },
                      childCount: servers.length,
                    ),
                  )
                : SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: maxCrossAxisExtent,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      final isActive =
                          server.id == widget.appState.activeServerId;
                      return _ServerCard(
                        server: server,
                        active: isActive,
                        subtitleText: isTv ? _tvServerSubtitle(server) : null,
                        autofocus: isTv && isActive,
                        onTap: loading
                            ? null
                            : () async {
                                final hasError = server.lastErrorCode != null ||
                                    (server.lastErrorMessage ?? '')
                                        .trim()
                                        .isNotEmpty;
                                if (hasError) {
                                  final msg =
                                      (server.lastErrorMessage ?? '').trim();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        msg.isNotEmpty
                                            ? msg
                                            : '服务器不可用（${server.lastErrorCode}）',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                if (server.serverType == MediaServerType.plex) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${server.serverType.label} 暂未支持浏览/播放（仅可保存登录信息）。',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                if (server.id ==
                                    widget.appState.activeServerId) {
                                  await Navigator.of(context).maybePop();
                                  return;
                                }
                                final ok = await widget.appState
                                    .enterServer(server.id);
                                if (!context.mounted) return;
                                if (ok) {
                                  await Navigator.of(context).maybePop();
                                  return;
                                }
                                final msg = (server.lastErrorMessage ??
                                        widget.appState.error ??
                                        '')
                                    .trim();
                                if (msg.isNotEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                }
                              },
                        onLongPress: () => isTv
                            ? unawaited(_showTvServerMenu(server))
                            : _showEditServerSheet(server),
                      );
                    },
                  ),
          ),
      ],
    );
  }

  String _tvServerSubtitle(ServerProfile server) {
    final routeRemark =
        (widget.appState.serverDomainRemark(server.id, server.baseUrl) ?? '')
            .trim();
    if (routeRemark.isNotEmpty) return routeRemark;

    final serverRemark = (server.remark ?? '').trim();
    if (serverRemark.isNotEmpty) return serverRemark;

    final uri = Uri.tryParse(server.baseUrl);
    if (uri != null && uri.host.trim().isNotEmpty) return uri.host.trim();
    return server.serverType.label;
  }

  Widget _buildTvQrPanel(BuildContext context) {
    final theme = Theme.of(context);
    final uiScale = context.uiScale;
    final remote = TvRemoteService.instance;

    return AnimatedBuilder(
      animation: remote,
      builder: (context, _) {
        final url = remote.firstRemoteUrl;
        final addressText = url == null ? '正在获取局域网地址…' : url.toString();
        final qrSize = (260 * uiScale).clamp(200.0, 340.0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '手机扫码添加服务器',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '手机与 TV 需在同一局域网。扫码后在手机端填写服务器地址/账号/密码，提交后 TV 会自动添加服务器。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: url == null
                        ? SizedBox(
                            height: qrSize,
                            width: qrSize,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : QrImageView(
                            data: url.toString(),
                            size: qrSize,
                            backgroundColor: Colors.white,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                addressText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '提示：可在 设置 → TV 专区 关闭“手机扫码控制”。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showTvServerMenu(ServerProfile server) async {
    if (!mounted) return;

    final action = await showDialog<_TvServerMenuAction>(
      context: context,
      builder: (dialogContext) {
        Widget item({
          required _TvServerMenuAction value,
          required IconData icon,
          required String label,
          bool danger = false,
        }) {
          final color =
              danger ? Theme.of(dialogContext).colorScheme.error : null;
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text(
              label,
              style: color == null ? null : TextStyle(color: color),
            ),
            onTap: () => Navigator.of(dialogContext).pop(value),
          );
        }

        return AlertDialog(
          title: Text(
            server.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                item(
                  value: _TvServerMenuAction.addRoute,
                  icon: Icons.add,
                  label: '添加线路',
                ),
                item(
                  value: _TvServerMenuAction.switchRoute,
                  icon: Icons.route_outlined,
                  label: '修改线路',
                ),
                item(
                  value: _TvServerMenuAction.editRouteRemark,
                  icon: Icons.edit_note_outlined,
                  label: '修改线路备注',
                ),
                item(
                  value: _TvServerMenuAction.relogin,
                  icon: Icons.lock_reset_outlined,
                  label: '重新登录',
                ),
                const Divider(height: 12),
                item(
                  value: _TvServerMenuAction.deleteServer,
                  icon: Icons.delete_outline,
                  label: '删除服务器',
                  danger: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _TvServerMenuAction.addRoute:
        await _tvAddRoute(server);
        break;
      case _TvServerMenuAction.switchRoute:
        await _tvSwitchRoute(server);
        break;
      case _TvServerMenuAction.editRouteRemark:
        await _tvEditRouteRemark(server);
        break;
      case _TvServerMenuAction.relogin:
        await _tvRelogin(server);
        break;
      case _TvServerMenuAction.deleteServer:
        await _tvDeleteServer(server);
        break;
    }
  }

  Future<Map<String, String>?> _showTvRouteEditorDialog({
    required String title,
  }) async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：直连 / 备用 / 移动',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: '地址',
                    hintText: '例如：https://emby.example.com',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remarkCtrl,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    hintText: '例如：移动 / 低延迟',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop({
                  'name': nameCtrl.text.trim(),
                  'url': urlCtrl.text.trim(),
                  'remark': remarkCtrl.text.trim(),
                });
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    nameCtrl.dispose();
    urlCtrl.dispose();
    remarkCtrl.dispose();
    return result;
  }

  Future<String?> _pickTvRouteUrl(ServerProfile server,
      {required String title}) async {
    final currentUrl = server.baseUrl.trim();
    final customDomains = widget.appState.customDomainsOfServer(server.id);

    final seen = <String>{};
    final items = <({String name, String url})>[];

    void addItem(String name, String url) {
      final fixedUrl = url.trim();
      if (fixedUrl.isEmpty || seen.contains(fixedUrl)) return;
      seen.add(fixedUrl);
      final fixedName = name.trim().isEmpty ? fixedUrl : name.trim();
      items.add((name: fixedName, url: fixedUrl));
    }

    if (currentUrl.isNotEmpty) {
      addItem('当前线路', currentUrl);
    }
    for (final d in customDomains) {
      addItem(d.name, d.url);
    }

    if (items.isEmpty) return null;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 680,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = items[index];
                  final selected = entry.url == currentUrl;
                  final remark = (widget.appState
                              .serverDomainRemark(server.id, entry.url) ??
                          '')
                      .trim();
                  final subtitle =
                      remark.isEmpty ? entry.url : '$remark · ${entry.url}';
                  return ListTile(
                    title: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing:
                        selected ? const Icon(Icons.check, size: 18) : null,
                    onTap: () => Navigator.of(dialogContext).pop(entry.url),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showTvTextInputDialog({
    required String title,
    required String labelText,
    String initialText = '',
    String? hintText,
    bool obscureText = false,
  }) async {
    final ctrl = TextEditingController(text: initialText);
    var visible = !obscureText;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 560,
                child: TextField(
                  controller: ctrl,
                  obscureText: !visible,
                  decoration: InputDecoration(
                    labelText: labelText,
                    hintText: hintText,
                    suffixIcon: obscureText
                        ? IconButton(
                            tooltip: visible ? '隐藏' : '显示',
                            icon: Icon(
                              visible ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setDialogState(() {
                              visible = !visible;
                            }),
                          )
                        : null,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(ctrl.text.trim()),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    ctrl.dispose();
    return result;
  }

  Future<void> _tvAddRoute(ServerProfile server) async {
    final result = await _showTvRouteEditorDialog(title: '添加线路');
    if (result == null) return;

    try {
      await widget.appState.addCustomDomainForServer(
        serverId: server.id,
        name: result['name'] ?? '',
        url: result['url'] ?? '',
        remark: (result['remark'] ?? '').trim().isEmpty
            ? null
            : (result['remark'] ?? '').trim(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _tvSwitchRoute(ServerProfile server) async {
    final picked = await _pickTvRouteUrl(server, title: '修改线路');
    if (picked == null) return;
    final nextUrl = picked.trim();
    final currentUrl = server.baseUrl.trim();
    if (nextUrl.isEmpty || nextUrl == currentUrl) return;

    try {
      await widget.appState.updateServerRoute(server.id, url: nextUrl);
      if (!mounted) return;
      if (server.id == widget.appState.activeServerId &&
          server.serverType.isEmbyLike) {
        await widget.appState.refreshDomains();
        await widget.appState.refreshLibraries();
        unawaited(widget.appState.loadHome(forceRefresh: true));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已切换线路')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('线路切换失败：$e')),
      );
    }
  }

  Future<void> _tvEditRouteRemark(ServerProfile server) async {
    final picked = await _pickTvRouteUrl(server, title: '选择线路');
    if (picked == null) return;
    final url = picked.trim();
    if (url.isEmpty) return;

    final currentRemark =
        (widget.appState.serverDomainRemark(server.id, url) ?? '').trim();
    final next = await _showTvTextInputDialog(
      title: '修改线路备注',
      labelText: '备注',
      hintText: '例如：移动 / 低延迟',
      initialText: currentRemark,
    );
    if (next == null) return;

    await widget.appState.setServerDomainRemark(
      server.id,
      url,
      next.trim().isEmpty ? null : next.trim(),
    );
  }

  Future<void> _tvRelogin(ServerProfile server) async {
    if (server.serverType == MediaServerType.plex) {
      final token = await _showTvTextInputDialog(
        title: '重新登录',
        labelText: 'Plex Token',
        hintText: '从 Plex 授权获取',
        obscureText: true,
      );
      if (token == null) return;
      await widget.appState.addPlexServer(
        baseUrl: server.baseUrl,
        token: token.trim(),
        displayName: server.name,
        remark: server.remark,
        iconUrl: server.iconUrl,
        plexMachineIdentifier: server.plexMachineIdentifier,
      );
      if (!mounted) return;
      if ((widget.appState.error ?? '').trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.appState.error!)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录已更新')),
      );
      return;
    }

    final userCtrl = TextEditingController(text: server.username);
    final pwdCtrl = TextEditingController();
    var pwdVisible = false;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('重新登录'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: userCtrl,
                      decoration: const InputDecoration(labelText: '账号'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: !pwdVisible,
                      decoration: InputDecoration(
                        labelText: '密码',
                        suffixIcon: IconButton(
                          tooltip: pwdVisible ? '隐藏密码' : '显示密码',
                          icon: Icon(
                            pwdVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setDialogState(() {
                            pwdVisible = !pwdVisible;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop({
                      'username': userCtrl.text.trim(),
                      'password': pwdCtrl.text,
                    });
                  },
                  child: const Text('登录'),
                ),
              ],
            );
          },
        );
      },
    );

    userCtrl.dispose();
    pwdCtrl.dispose();

    if (result == null) return;

    try {
      await widget.appState.updateServerPassword(
        server.id,
        username: result['username'],
        password: result['password'] ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _tvDeleteServer(ServerProfile server) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除服务器？'),
          content: Text('将删除“${server.name}”。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await widget.appState.removeServer(server.id);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!DeviceType.isTv && !isDesktopPlatform && !widget.desktopLayout) {
      return MobileServerPage(
        appState: widget.appState,
        showInlineLocalEntry: widget.showInlineLocalEntry,
      );
    }

    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final servers = widget.appState.servers;
        final loading = widget.appState.isLoading;
        final uiScale = context.uiScale;
        final isTv = _isTv(context);
        final useDesktopLayout = widget.desktopLayout && !isTv;
        final listLayout = widget.appState.serverListLayout;
        final isList = listLayout == ServerListLayout.list;
        final maxCrossAxisExtent = (isTv ? 160.0 : 180.0) * uiScale;

        if (useDesktopLayout) {
          final railExtended = MediaQuery.of(context).size.width >= 1280;

          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _desktopTabIndex,
                    onDestinationSelected: _selectDesktopTab,
                    extended: railExtended,
                    minExtendedWidth: 220,
                    leading: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      child: Row(
                        children: [
                          const Icon(Icons.dns_outlined),
                          if (railExtended) ...[
                            const SizedBox(width: 10),
                            Text(
                              'Servers',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.storage_outlined),
                        selectedIcon: Icon(Icons.storage),
                        label: Text('Servers'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.folder_open_outlined),
                        selectedIcon: Icon(Icons.folder_open),
                        label: Text('Local'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('Settings'),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: IndexedStack(
                      index: _desktopTabIndex,
                      children: [
                        _buildServerListView(
                          context,
                          servers: servers,
                          loading: loading,
                          isTv: isTv,
                          showInlineLocalEntry: false,
                          isList: isList,
                          maxCrossAxisExtent: maxCrossAxisExtent,
                        ),
                        _desktopPagesBuilt[1]
                            ? buildLocalPlayerScreen(appState: widget.appState)
                            : const SizedBox.shrink(),
                        _desktopPagesBuilt[2]
                            ? SettingsPage(appState: widget.appState)
                            : const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (isTv) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: _buildServerListView(
                      context,
                      servers: servers,
                      loading: loading,
                      isTv: isTv,
                      showInlineLocalEntry: widget.showInlineLocalEntry,
                      isList: isList,
                      maxCrossAxisExtent: maxCrossAxisExtent,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildTvQrPanel(context)),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: _buildServerListView(
              context,
              servers: servers,
              loading: loading,
              isTv: isTv,
              showInlineLocalEntry: widget.showInlineLocalEntry,
              isList: isList,
              maxCrossAxisExtent: maxCrossAxisExtent,
            ),
          ),
        );
      },
    );
  }
}

class _ServerCard extends StatefulWidget {
  const _ServerCard({
    required this.server,
    required this.active,
    this.subtitleText,
    this.autofocus = false,
    required this.onTap,
    required this.onLongPress,
  });

  final ServerProfile server;
  final bool active;
  final String? subtitleText;
  final bool autofocus;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final active = widget.active;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final highlighted = _focused || _hovered;
    final remark = (server.remark ?? '').trim();
    final subtitleText = widget.subtitleText ??
        (remark.isNotEmpty
            ? '${server.serverType.label} · $remark'
            : server.serverType.label);

    final borderColor = active
        ? colorScheme.primary.withValues(alpha: 0.55)
        : highlighted
            ? colorScheme.secondary.withValues(alpha: isDark ? 0.65 : 0.55)
            : colorScheme.outlineVariant;
    final borderWidth = (active || highlighted) ? 1.35 : 1.0;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onLongPress,
      onFocusChange: (v) => setState(() => _focused = v),
      onHover: (v) => setState(() => _hovered = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surfaceContainerHigh
                  .withValues(alpha: isDark ? 0.78 : 0.92),
              colorScheme.surfaceContainerHigh
                  .withValues(alpha: isDark ? 0.62 : 0.84),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: server.lastErrorCode == null
                  ? const SizedBox.shrink()
                  : _ServerErrorBadge(
                      code: server.lastErrorCode!,
                      message: server.lastErrorMessage,
                    ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: active
                  ? const Icon(Icons.check_circle, size: 16)
                  : const SizedBox.shrink(),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ServerIconAvatar(
                      iconUrl: server.iconUrl,
                      name: server.name,
                      radius: 12,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerListTile extends StatefulWidget {
  const _ServerListTile({
    required this.server,
    required this.active,
    this.subtitleText,
    this.autofocus = false,
    required this.onTap,
    required this.onLongPress,
  });

  final ServerProfile server;
  final bool active;
  final String? subtitleText;
  final bool autofocus;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  State<_ServerListTile> createState() => _ServerListTileState();
}

class _ServerListTileState extends State<_ServerListTile> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final active = widget.active;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final highlighted = _focused || _hovered;
    final remark = (server.remark ?? '').trim();
    final subtitleText = widget.subtitleText ??
        (remark.isNotEmpty
            ? '${server.serverType.label} · $remark'
            : server.serverType.label);

    final borderColor = active
        ? scheme.primary.withValues(alpha: 0.55)
        : highlighted
            ? scheme.secondary.withValues(alpha: isDark ? 0.65 : 0.55)
            : scheme.outlineVariant;
    final borderWidth = (active || highlighted) ? 1.35 : 1.0;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onLongPress,
      onFocusChange: (v) => setState(() => _focused = v),
      onHover: (v) => setState(() => _hovered = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surfaceContainerHigh
                  .withValues(alpha: isDark ? 0.74 : 0.92),
              scheme.surfaceContainerHigh
                  .withValues(alpha: isDark ? 0.6 : 0.86),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Row(
          children: [
            ServerIconAvatar(
              iconUrl: server.iconUrl,
              name: server.name,
              radius: 14,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (server.lastErrorCode != null) ...[
              _ServerErrorBadge(
                code: server.lastErrorCode!,
                message: server.lastErrorMessage,
              ),
              const SizedBox(width: 8),
            ],
            if (active) const Icon(Icons.check_circle, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ServerErrorBadge extends StatelessWidget {
  const _ServerErrorBadge({required this.code, this.message});

  final int code;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    final bg =
        colorScheme.errorContainer.withValues(alpha: isDark ? 0.56 : 0.74);
    final border = colorScheme.error.withValues(alpha: isDark ? 0.55 : 0.4);
    final fg = colorScheme.onErrorContainer;

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        'HTTP $code',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
      ),
    );

    final tooltip = (message ?? '').trim();
    if (tooltip.isEmpty) return child;
    return Tooltip(message: tooltip, child: child);
  }
}

enum _TvServerMenuAction {
  addRoute,
  switchRoute,
  editRouteRemark,
  relogin,
  deleteServer,
}

enum _PlexAddMode {
  account,
  manual,
}

extension _PlexAddModeX on _PlexAddMode {
  String get label {
    switch (this) {
      case _PlexAddMode.account:
        return '账号登录（推荐）';
      case _PlexAddMode.manual:
        return '手动添加';
    }
  }
}

class _AddServerSheet extends StatefulWidget {
  const _AddServerSheet({required this.appState, this.onOpenBulkImport});

  final AppState appState;
  final Future<void> Function(BuildContext sheetContext)? onOpenBulkImport;

  @override
  State<_AddServerSheet> createState() => _AddServerSheetState();
}

class _AddServerSheetState extends State<_AddServerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _plexTokenCtrl = TextEditingController();

  MediaServerType _serverType = MediaServerType.emby;
  _PlexAddMode _plexMode = _PlexAddMode.account;
  String _scheme = 'https';
  bool _pwdVisible = false;
  bool _plexTokenVisible = false;
  bool _handlingHostParse = false;
  bool _nameTouched = false;

  String? _iconUrl;
  bool _iconTouched = false;

  PlexPin? _plexPin;
  String? _plexAccountToken;
  List<PlexResource> _plexServers = const [];
  PlexResource? _selectedPlexServer;
  bool _plexLoading = false;
  String? _plexError;

  Timer? _autoMetaDebounce;
  int _autoMetaReqId = 0;
  bool _autoMetaLoading = false;
  String? _autoMetaError;
  String? _autoMetaLastUrl;

  @override
  void initState() {
    super.initState();
    _hostCtrl.addListener(_onHostChanged);
    _portCtrl.addListener(_scheduleAutoMetaFetch);
  }

  @override
  void dispose() {
    _autoMetaDebounce?.cancel();
    _nameCtrl.dispose();
    _remarkCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _plexTokenCtrl.dispose();
    super.dispose();
  }

  String _defaultPortForScheme(String s) => s == 'http' ? '80' : '443';

  void _maybeParseHostInput() {
    if (_handlingHostParse) return;
    final raw = _hostCtrl.text.trim();
    if (!raw.contains('://')) {
      if (!_nameTouched && _nameCtrl.text.trim().isEmpty && raw.isNotEmpty) {
        _nameCtrl.text = raw.split('/').first;
        _nameCtrl.selection =
            TextSelection.collapsed(offset: _nameCtrl.text.length);
      }
      return;
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
    if (uri.scheme != 'http' && uri.scheme != 'https') return;

    _handlingHostParse = true;
    try {
      if (_scheme != uri.scheme) {
        setState(() => _scheme = uri.scheme);
      }
      if (uri.hasPort) {
        _portCtrl.text = uri.port.toString();
      } else if (_portCtrl.text.trim().isEmpty) {
        _portCtrl.text = _defaultPortForScheme(uri.scheme);
      }

      final hostPart =
          uri.host + ((uri.path.isNotEmpty && uri.path != '/') ? uri.path : '');
      _hostCtrl.value = _hostCtrl.value.copyWith(
        text: hostPart,
        selection: TextSelection.collapsed(offset: hostPart.length),
      );

      if (!_nameTouched && _nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = uri.host;
        _nameCtrl.selection =
            TextSelection.collapsed(offset: _nameCtrl.text.length);
      }
    } finally {
      _handlingHostParse = false;
    }
  }

  void _onHostChanged() {
    _maybeParseHostInput();
    _scheduleAutoMetaFetch();
  }

  Uri? _buildAutoMetaUri() {
    final hostInput = _hostCtrl.text.trim();
    if (hostInput.isEmpty) return null;

    final withScheme =
        hostInput.contains('://') ? hostInput : '$_scheme://$hostInput';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return null;
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;

    var uri = parsed;
    final portText = _portCtrl.text.trim();
    if (portText.isNotEmpty) {
      final port = int.tryParse(portText);
      if (port != null && port > 0 && port <= 65535) {
        uri = uri.replace(port: port);
      }
    }
    if (uri.path.isEmpty) {
      uri = uri.replace(path: '/');
    }
    return uri.replace(query: '', fragment: '');
  }

  void _scheduleAutoMetaFetch({bool force = false}) {
    if (!mounted) return;
    if (widget.appState.isLoading) return;

    _autoMetaDebounce?.cancel();
    final uri = _buildAutoMetaUri();
    if (uri == null) {
      if (_autoMetaLoading || _autoMetaError != null) {
        setState(() {
          _autoMetaLoading = false;
          _autoMetaError = null;
        });
      }
      return;
    }

    final urlKey = uri.toString();
    if (!force && urlKey == _autoMetaLastUrl) return;

    _autoMetaDebounce = Timer(
      const Duration(milliseconds: 650),
      () => _fetchAutoMeta(uri, urlKey: urlKey),
    );
  }

  Future<void> _fetchAutoMeta(
    Uri uri, {
    required String urlKey,
    bool overrideIcon = false,
  }) async {
    final reqId = ++_autoMetaReqId;
    setState(() {
      _autoMetaLoading = true;
      _autoMetaError = null;
      _autoMetaLastUrl = urlKey;
    });

    try {
      final meta = await WebsiteMetadataService.instance.fetch(uri);
      if (!mounted || reqId != _autoMetaReqId) return;

      final displayName = (meta.displayName ?? '').trim();
      if (!_nameTouched && displayName.isNotEmpty) {
        _nameCtrl.value = _nameCtrl.value.copyWith(
          text: displayName,
          selection: TextSelection.collapsed(offset: displayName.length),
        );
      }

      final favicon = (meta.faviconUrl ?? '').trim();
      if ((overrideIcon || !_iconTouched) && favicon.isNotEmpty) {
        setState(() {
          _iconTouched = overrideIcon ? false : _iconTouched;
          _iconUrl = favicon;
        });
      }

      setState(() => _autoMetaLoading = false);
    } catch (e) {
      if (!mounted || reqId != _autoMetaReqId) return;
      setState(() {
        _autoMetaLoading = false;
        _autoMetaError = e.toString();
      });
    }
  }

  Future<void> _forceFetchWebsiteMeta() async {
    final uri = _buildAutoMetaUri();
    if (uri == null) return;
    _autoMetaDebounce?.cancel();
    await _fetchAutoMeta(
      uri,
      urlKey: uri.toString(),
      overrideIcon: true,
    );
  }

  Future<void> _pickIconFromLibrary() async {
    final pickedUrl = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ServerIconLibrarySheet(
        urlsListenable: widget.appState,
        getLibraryUrls: () => widget.appState.serverIconLibraryUrls,
        addLibraryUrl: widget.appState.addServerIconLibraryUrl,
        removeLibraryUrlAt: widget.appState.removeServerIconLibraryUrlAt,
        reorderLibraryUrls: widget.appState.reorderServerIconLibraryUrls,
        selectedUrl: _iconUrl,
      ),
    );
    if (!mounted || pickedUrl == null) return;
    setState(() {
      _iconTouched = true;
      _iconUrl = pickedUrl.trim().isEmpty ? null : pickedUrl.trim();
    });
  }

  void _clearIcon() {
    setState(() {
      _iconTouched = true;
      _iconUrl = null;
    });
  }

  void _applyDefaultPort() {
    _portCtrl.text = _serverType == MediaServerType.plex
        ? '32400'
        : _defaultPortForScheme(_scheme);
    setState(() {});
  }

  void _setServerType(MediaServerType type) {
    if (_serverType == type) return;
    setState(() {
      _serverType = type;
      if (type == MediaServerType.plex && _portCtrl.text.trim().isEmpty) {
        _portCtrl.text = '32400';
      }
      _plexMode = _PlexAddMode.account;
      _plexError = null;
      _plexPin = null;
      _plexAccountToken = null;
      _plexServers = const [];
      _selectedPlexServer = null;
    });
  }

  PlexApi _buildPlexApi() {
    return PlexApi(
      clientIdentifier: widget.appState.deviceId,
      product: AppConfigScope.of(context).displayName,
      device: 'Flutter',
      platform: 'Flutter',
      version: '1.0.0',
    );
  }

  Future<void> _startPlexLogin({required bool fillTokenOnly}) async {
    if (_plexLoading) return;
    setState(() {
      _plexLoading = true;
      _plexError = null;
      if (!fillTokenOnly) {
        _plexServers = const [];
        _selectedPlexServer = null;
      }
    });

    try {
      final api = _buildPlexApi();
      final pin = await api.createPin();
      if (!mounted) return;
      setState(() {
        _plexPin = pin;
        _plexAccountToken = null;
      });

      final authUrl = api.buildAuthUrl(code: pin.code);
      final launched = await launchUrl(
        Uri.parse(authUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('无法打开浏览器进行 Plex 授权');
      }

      final deadline = (pin.expiresAt ??
              DateTime.now().toUtc().add(const Duration(minutes: 10)))
          .toLocal();
      PlexPin latest = pin;
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        latest = await api.fetchPin(pin.id);
        final t = (latest.authToken ?? '').trim();
        if (t.isNotEmpty) break;
      }

      final authToken = (latest.authToken ?? '').trim();
      if (authToken.isEmpty) {
        throw Exception('等待 Plex 授权超时/未完成授权');
      }

      if (!mounted) return;

      if (fillTokenOnly) {
        _plexTokenCtrl.text = authToken;
        setState(() {
          _plexAccountToken = authToken;
          _plexLoading = false;
        });
        return;
      }

      final resources = await api.fetchResources(authToken: authToken);
      final servers = resources.where((r) => r.isServer).toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _plexAccountToken = authToken;
        _plexServers = servers;
        _selectedPlexServer = servers.isEmpty ? null : servers.first;
        _plexLoading = false;
      });

      final picked = servers.isEmpty ? null : servers.first;
      if (picked != null &&
          !_nameTouched &&
          _nameCtrl.text.trim().isEmpty &&
          picked.name.trim().isNotEmpty) {
        _nameCtrl.text = picked.name.trim();
        _nameCtrl.selection =
            TextSelection.collapsed(offset: _nameCtrl.text.length);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _plexLoading = false;
        _plexError = e.toString();
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    String? addedId;

    if (_serverType == MediaServerType.plex) {
      if (_plexMode == _PlexAddMode.account) {
        final selected = _selectedPlexServer;
        final serverUri = selected?.pickBestConnectionUri();
        final token = (selected?.accessToken ?? _plexAccountToken ?? '').trim();
        if (selected == null || (serverUri ?? '').trim().isEmpty) {
          setState(() => _plexError = '请选择 Plex 服务器');
          return;
        }
        if (token.isEmpty) {
          setState(() => _plexError = '未获取到 Plex Token（请重新登录）');
          return;
        }
        await widget.appState.addPlexServer(
          baseUrl: serverUri!.trim(),
          token: token,
          displayName:
              _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
          remark:
              _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
          iconUrl: _iconUrl,
          plexMachineIdentifier: selected.clientIdentifier,
        );
      } else {
        final uri = _buildAutoMetaUri();
        if (uri == null) return;
        await widget.appState.addPlexServer(
          baseUrl: uri.toString(),
          token: _plexTokenCtrl.text.trim(),
          displayName:
              _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
          remark:
              _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
          iconUrl: _iconUrl,
        );
      }
    } else if (_serverType == MediaServerType.webdav) {
      final uri = _buildAutoMetaUri();
      if (uri == null) return;
      addedId = await widget.appState.addWebDavServer(
        baseUrl: uri.toString(),
        username: _userCtrl.text.trim(),
        password: _pwdCtrl.text,
        displayName:
            _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        remark:
            _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
        iconUrl: _iconUrl,
        activate: false,
      );
    } else {
      // Emby/Jellyfin
      final hostInput = _hostCtrl.text.trim();
      addedId = await widget.appState.addServer(
        hostOrUrl: hostInput,
        scheme: _scheme,
        port: _portCtrl.text.trim().isEmpty ? null : _portCtrl.text.trim(),
        serverType: _serverType,
        username: _userCtrl.text.trim(),
        password: _pwdCtrl.text,
        displayName:
            _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        remark:
            _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
        iconUrl: _iconUrl,
        activate: false,
      );
    }
    if (!mounted) return;
    if (widget.appState.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.appState.error!)),
      );
      return;
    }
    Navigator.of(context).pop(addedId);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final config = AppConfigScope.of(context);
    final serverTypes = MediaServerType.values
        .where(config.features.allowedServerTypes.contains)
        .toList(growable: false);
    final loading = widget.appState.isLoading;
    final showHostFields = _serverType.isEmbyLike ||
        _serverType == MediaServerType.webdav ||
        (_serverType == MediaServerType.plex &&
            _plexMode == _PlexAddMode.manual);
    final showUserPass =
        _serverType.isEmbyLike || _serverType == MediaServerType.webdav;
    final showPlexToken =
        _serverType == MediaServerType.plex && _plexMode == _PlexAddMode.manual;

    return Padding(
      padding:
          EdgeInsets.only(left: 16, right: 16, bottom: viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '添加服务器',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (widget.onOpenBulkImport != null &&
                            _serverType.isEmbyLike)
                          TextButton.icon(
                            onPressed: loading
                                ? null
                                : () => unawaited(
                                    widget.onOpenBulkImport!(context)),
                            icon: const Icon(Icons.playlist_add_outlined),
                            label: const Text('批量导入'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<MediaServerType>(
                      segments: serverTypes
                          .map(
                            (t) => ButtonSegment<MediaServerType>(
                              value: t,
                              label: Text(t.label),
                            ),
                          )
                          .toList(growable: false),
                      selected: <MediaServerType>{_serverType},
                      onSelectionChanged:
                          loading ? null : (s) => _setServerType(s.first),
                    ),
                    if (_serverType == MediaServerType.plex) ...[
                      const SizedBox(height: 12),
                      SegmentedButton<_PlexAddMode>(
                        segments: _PlexAddMode.values
                            .map(
                              (m) => ButtonSegment<_PlexAddMode>(
                                value: m,
                                label: Text(m.label),
                              ),
                            )
                            .toList(growable: false),
                        selected: <_PlexAddMode>{_plexMode},
                        onSelectionChanged: loading
                            ? null
                            : (s) => setState(() {
                                  _plexMode = s.first;
                                  _plexError = null;
                                }),
                      ),
                      if (_plexMode == _PlexAddMode.account) ...[
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: (_plexLoading || loading)
                              ? null
                              : () => _startPlexLogin(fillTokenOnly: false),
                          icon: _plexLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            _plexAccountToken == null
                                ? '登录 Plex 获取服务器列表'
                                : '重新登录 Plex',
                          ),
                        ),
                        if ((_plexPin?.code ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '授权码：${_plexPin!.code}（在浏览器完成授权后返回）',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                        if ((_plexError ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            _plexError!.trim(),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ],
                        if (_plexAccountToken != null &&
                            _plexServers.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<PlexResource>(
                            initialValue: _selectedPlexServer,
                            items: _plexServers
                                .map(
                                  (r) => DropdownMenuItem<PlexResource>(
                                    value: r,
                                    child: Text(
                                      r.name.isEmpty
                                          ? r.clientIdentifier
                                          : r.name,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: loading
                                ? null
                                : (v) => setState(() {
                                      _selectedPlexServer = v;
                                      _plexError = null;
                                      if (v != null &&
                                          !_nameTouched &&
                                          _nameCtrl.text.trim().isEmpty &&
                                          v.name.trim().isNotEmpty) {
                                        _nameCtrl.text = v.name.trim();
                                        _nameCtrl.selection =
                                            TextSelection.collapsed(
                                          offset: _nameCtrl.text.length,
                                        );
                                      }
                                    }),
                            decoration: const InputDecoration(
                              labelText: '选择 Plex 服务器',
                            ),
                            validator: (_) =>
                                (_selectedPlexServer == null) ? '请选择服务器' : null,
                          ),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final uri =
                                  _selectedPlexServer?.pickBestConnectionUri();
                              if ((uri ?? '').trim().isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                '连接：$uri',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              );
                            },
                          ),
                        ],
                      ],
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameCtrl,
                      onChanged: (_) => _nameTouched = true,
                      decoration: const InputDecoration(labelText: '服务器名称（可选）'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _remarkCtrl,
                      decoration: const InputDecoration(labelText: '备注（可选）'),
                    ),
                    if (showHostFields) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ServerIconAvatar(
                            iconUrl: _iconUrl,
                            name: _nameCtrl.text,
                            radius: 16,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('服务器图标（可选）'),
                                const SizedBox(height: 2),
                                Text(
                                  _iconTouched
                                      ? '已自定义'
                                      : (_iconUrl == null ||
                                              _iconUrl!.trim().isEmpty)
                                          ? '未设置'
                                          : '已自动获取',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '自动获取网站信息',
                            onPressed: loading ? null : _forceFetchWebsiteMeta,
                            icon: const Icon(Icons.travel_explore_outlined),
                          ),
                          IconButton(
                            tooltip: '从图标库选择',
                            onPressed: loading ? null : _pickIconFromLibrary,
                            icon: const Icon(Icons.collections_outlined),
                          ),
                          IconButton(
                            tooltip: '清除图标',
                            onPressed: loading ? null : _clearIcon,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      if (showPlexToken) ...[
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: (_plexLoading || loading)
                              ? null
                              : () => _startPlexLogin(fillTokenOnly: true),
                          icon: _plexLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            _plexAccountToken == null
                                ? '登录 Plex 获取 Token'
                                : '重新登录 Plex（刷新 Token）',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _plexTokenCtrl,
                          decoration: InputDecoration(
                            labelText: 'Plex Token',
                            suffixIcon: IconButton(
                              tooltip:
                                  _plexTokenVisible ? '隐藏 Token' : '显示 Token',
                              icon: Icon(
                                _plexTokenVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _plexTokenVisible = !_plexTokenVisible,
                              ),
                            ),
                          ),
                          obscureText: !_plexTokenVisible,
                          validator: (v) {
                            if (!showPlexToken) return null;
                            return (v == null || v.trim().isEmpty)
                                ? '请输入 Plex Token'
                                : null;
                          },
                        ),
                      ],
                      if (_autoMetaLoading) ...[
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Expanded(child: Text('正在自动获取网站名称和 favicon…')),
                          ],
                        ),
                      ] else if ((_autoMetaError ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '自动获取失败，可手动设置名称/图标。',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: _scheme,
                              decoration:
                                  const InputDecoration(labelText: '协议'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'https', child: Text('https')),
                                DropdownMenuItem(
                                    value: 'http', child: Text('http')),
                              ],
                              onChanged: loading
                                  ? null
                                  : (v) {
                                      if (v == null) return;
                                      setState(() {
                                        _scheme = v;
                                        if (_portCtrl.text.isEmpty ||
                                            _portCtrl.text == '80' ||
                                            _portCtrl.text == '443') {
                                          _portCtrl.text =
                                              _defaultPortForScheme(v);
                                        }
                                      });
                                      _scheduleAutoMetaFetch(force: true);
                                    },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: _hostCtrl,
                              decoration: const InputDecoration(
                                labelText: '服务器地址',
                                hintText: '例如：emby.example.com 或 1.2.3.4',
                              ),
                              keyboardType: TextInputType.url,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? '请输入服务器地址'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _portCtrl,
                        decoration: InputDecoration(
                          labelText:
                              '端口（留空默认 ${_scheme == 'http' ? '80' : '443'}）',
                          suffixIcon: IconButton(
                            tooltip: '使用默认端口',
                            icon: const Icon(Icons.refresh),
                            onPressed: loading ? null : _applyDefaultPort,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = int.tryParse(v.trim());
                          if (n == null || n <= 0 || n > 65535) return '端口不合法';
                          return null;
                        },
                      ),
                      if (showUserPass) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _userCtrl,
                          decoration: const InputDecoration(labelText: '账号'),
                          validator: (v) {
                            if ((_serverType.isEmbyLike ||
                                    _serverType == MediaServerType.webdav) &&
                                (v == null || v.trim().isEmpty)) {
                              return '请输入账号';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _pwdCtrl,
                          decoration: InputDecoration(
                            labelText: '密码（可选）',
                            suffixIcon: IconButton(
                              tooltip: _pwdVisible ? '隐藏密码' : '显示密码',
                              icon: Icon(
                                _pwdVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () =>
                                  setState(() => _pwdVisible = !_pwdVisible),
                            ),
                          ),
                          obscureText: !_pwdVisible,
                          validator: (_) => null,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: loading ? null : _submit,
                child: loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('连接并保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditServerSheet extends StatefulWidget {
  const _EditServerSheet({required this.appState, required this.server});

  final AppState appState;
  final ServerProfile server;

  @override
  State<_EditServerSheet> createState() => _EditServerSheetState();
}

class _EditServerSheetState extends State<_EditServerSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.server.name);
  late final TextEditingController _remarkCtrl =
      TextEditingController(text: widget.server.remark);

  String? _iconUrl;
  bool _iconLoading = false;

  @override
  void initState() {
    super.initState();
    _iconUrl = widget.server.iconUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIconFromLibrary() async {
    final pickedUrl = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ServerIconLibrarySheet(
        urlsListenable: widget.appState,
        getLibraryUrls: () => widget.appState.serverIconLibraryUrls,
        addLibraryUrl: widget.appState.addServerIconLibraryUrl,
        removeLibraryUrlAt: widget.appState.removeServerIconLibraryUrlAt,
        reorderLibraryUrls: widget.appState.reorderServerIconLibraryUrls,
        selectedUrl: _iconUrl,
      ),
    );
    if (!mounted || pickedUrl == null) return;
    setState(() {
      _iconUrl = pickedUrl.trim().isEmpty ? null : pickedUrl.trim();
    });
  }

  Future<void> _autoFetchIcon() async {
    final uri = Uri.tryParse(widget.server.baseUrl);
    if (uri == null) return;

    setState(() => _iconLoading = true);
    try {
      final meta = await WebsiteMetadataService.instance.fetch(uri);
      if (!mounted) return;
      final favicon = (meta.faviconUrl ?? '').trim();
      if (favicon.isNotEmpty) {
        setState(() => _iconUrl = favicon);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('自动获取失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _iconLoading = false);
    }
  }

  void _clearIcon() {
    setState(() => _iconUrl = null);
  }

  Future<void> _save() async {
    final iconArg = _iconUrl == widget.server.iconUrl ? null : (_iconUrl ?? '');
    await widget.appState.updateServerMeta(
      widget.server.id,
      name: _nameCtrl.text,
      remark: _remarkCtrl.text,
      iconUrl: iconArg,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器？'),
        content: Text('将删除“${widget.server.name}”。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.appState.removeServer(widget.server.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding:
          EdgeInsets.only(left: 16, right: 16, bottom: viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('编辑服务器', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: '服务器名称'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _remarkCtrl,
            decoration: const InputDecoration(labelText: '备注（可选，小字显示）'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ServerIconAvatar(
                iconUrl: _iconUrl,
                name: _nameCtrl.text,
                radius: 16,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('服务器图标'),
                    const SizedBox(height: 2),
                    Text(
                      (_iconUrl == null || _iconUrl!.trim().isEmpty)
                          ? '未设置'
                          : '已设置',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '自动获取 favicon',
                onPressed: _iconLoading ? null : _autoFetchIcon,
                icon: _iconLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.travel_explore_outlined),
              ),
              IconButton(
                tooltip: '从图标库选择',
                onPressed: _pickIconFromLibrary,
                icon: const Icon(Icons.collections_outlined),
              ),
              IconButton(
                tooltip: '清除图标',
                onPressed: _clearIcon,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _confirmDelete,
                  child: const Text('删除'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
