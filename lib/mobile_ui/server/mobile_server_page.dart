import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_api/services/plex_api.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../home_page.dart';
import '../../player_screen.dart';
import '../../player_screen_exo.dart';
import '../../server_text_import_sheet.dart';
import '../../webdav_home_page.dart';

class MobileServerPage extends StatefulWidget {
  const MobileServerPage({
    super.key,
    required this.appState,
    this.showInlineLocalEntry = true,
  });

  final AppState appState;
  final bool showInlineLocalEntry;

  @override
  State<MobileServerPage> createState() => _MobileServerPageState();
}

class _MobileServerPageState extends State<MobileServerPage> {
  Future<void> _openActiveWorkspace() async {
    final active = widget.appState.activeServer;
    if (!mounted || active == null) return;

    if (Navigator.of(context).canPop()) {
      await Navigator.of(context).maybePop();
      return;
    }

    final target = active.serverType == MediaServerType.webdav
        ? WebDavHomePage(appState: widget.appState)
        : HomePage(appState: widget.appState);

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => target),
    );
  }

  Future<void> _openLocalPlayer() async {
    final useExoCore = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        widget.appState.playerCore == PlayerCore.exo;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => useExoCore
            ? ExoPlayerScreen(appState: widget.appState)
            : PlayerScreen(appState: widget.appState),
      ),
    );
  }

  Future<void> _showAddServerSheet() async {
    final entered = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _MobileAddServerSheet(
        appState: widget.appState,
        onOpenBulkImport: (sheetContext) async {
          Navigator.of(sheetContext).pop();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (!mounted) return;
          await _showBulkImportSheet();
        },
      ),
    );
    if (!mounted || entered != true) return;
    await _openActiveWorkspace();
  }

  Future<void> _showBulkImportSheet() async {
    final entered = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ServerTextImportSheet(appState: widget.appState),
    );
    if (!mounted || entered != true) return;
    await _openActiveWorkspace();
  }

  Future<void> _showEditServerSheet(ServerProfile server) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) =>
          _MobileEditServerSheet(appState: widget.appState, server: server),
    );
  }

  Future<void> _enterServer(ServerProfile server) async {
    if (server.serverType == MediaServerType.plex) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${server.serverType.label} 暂不支持浏览和播放，目前只保存登录信息。',
          ),
        ),
      );
      return;
    }

    if (server.id == widget.appState.activeServerId) {
      final canOpenDirectly = server.serverType == MediaServerType.webdav ||
          widget.appState.hasActiveServer;
      if (canOpenDirectly) {
        await _openActiveWorkspace();
        return;
      }
      await widget.appState.leaveServer();
    }

    final ok = await widget.appState.enterServer(server.id);
    if (!mounted) return;
    if (ok) {
      await _openActiveWorkspace();
      return;
    }

    final message = (server.lastErrorMessage ?? widget.appState.error ?? '').trim();
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _serverSubtitle(ServerProfile server) {
    final serverRemark = (server.remark ?? '').trim();
    if (serverRemark.isNotEmpty) return serverRemark;

    final routeRemark =
        (widget.appState.serverDomainRemark(server.id, server.baseUrl) ?? '')
            .trim();
    if (routeRemark.isNotEmpty) return routeRemark;

    final uri = Uri.tryParse(server.baseUrl);
    if (uri != null && uri.host.trim().isNotEmpty) return uri.host.trim();
    return server.serverType.label;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final servers = widget.appState.servers;
        final loading = widget.appState.isLoading;
        final isList = widget.appState.serverListLayout == ServerListLayout.list;
        final colorScheme = Theme.of(context).colorScheme;
        final size = MediaQuery.sizeOf(context);
        final gridAspectRatio = size.width < 390 ? 1.18 : 1.36;

        return Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.surface,
                  colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
            child: SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SegmentedButton<ServerListLayout>(
                                segments: const [
                                  ButtonSegment(
                                    value: ServerListLayout.grid,
                                    icon: Icon(Icons.grid_view_rounded),
                                    label: Text('矩形'),
                                  ),
                                  ButtonSegment(
                                    value: ServerListLayout.list,
                                    icon: Icon(Icons.view_stream_rounded),
                                    label: Text('条形'),
                                  ),
                                ],
                                selected: {
                                  isList
                                      ? ServerListLayout.list
                                      : ServerListLayout.grid,
                                },
                                showSelectedIcon: false,
                                onSelectionChanged: loading
                                    ? null
                                    : (selected) async {
                                        await widget.appState.setServerListLayout(
                                          selected.first,
                                        );
                                      },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            onPressed: loading ? null : _showAddServerSheet,
                            icon: const Icon(Icons.add),
                            label: const Text('添加'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
                        child: LinearProgressIndicator(),
                      ),
                    ),
                  if (widget.showInlineLocalEntry)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: _MobileLocalPlaybackCard(
                          loading: loading,
                          onTap: _openLocalPlayer,
                        ),
                      ),
                    ),
                  if (servers.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.storage_rounded,
                                size: 52,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '还没有服务器',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '点上方“添加”连接服务器，或者先用本地播放直接打开文件。',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color:
                                          colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (isList)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                      sliver: SliverList.builder(
                        itemCount: servers.length,
                        itemBuilder: (context, index) {
                          final server = servers[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == servers.length - 1 ? 0 : 12,
                            ),
                            child: _MobileServerItem(
                              server: server,
                              subtitle: _serverSubtitle(server),
                              active:
                                  server.id == widget.appState.activeServerId,
                              layout: _MobileServerItemLayout.list,
                              onTap: loading ? null : () => _enterServer(server),
                              onLongPress: () => _showEditServerSheet(server),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: gridAspectRatio,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final server = servers[index];
                            return _MobileServerItem(
                              server: server,
                              subtitle: _serverSubtitle(server),
                              active:
                                  server.id == widget.appState.activeServerId,
                              layout: _MobileServerItemLayout.grid,
                              onTap: loading ? null : () => _enterServer(server),
                              onLongPress: () => _showEditServerSheet(server),
                            );
                          },
                          childCount: servers.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _MobileServerItemLayout {
  grid,
  list,
}

class _MobileServerItem extends StatelessWidget {
  const _MobileServerItem({
    required this.server,
    required this.subtitle,
    required this.active,
    required this.layout,
    required this.onTap,
    required this.onLongPress,
  });

  final ServerProfile server;
  final String subtitle;
  final bool active;
  final _MobileServerItemLayout layout;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isGrid = layout == _MobileServerItemLayout.grid;
    final hasError = server.lastErrorCode != null;
    final borderColor = active
        ? colorScheme.primary.withValues(alpha: 0.55)
        : hasError
            ? colorScheme.error.withValues(alpha: 0.28)
            : colorScheme.outlineVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.94),
                colorScheme.surfaceContainerHigh.withValues(alpha: 0.82),
              ],
            ),
            border: Border.all(
              color: borderColor,
              width: active ? 1.4 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 10),
                color: colorScheme.shadow.withValues(alpha: 0.06),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isGrid ? 14 : 16),
            child: isGrid
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ServerIconAvatar(
                            iconUrl: server.iconUrl,
                            name: server.name,
                            radius: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  server.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        height: 1.25,
                                        color:
                                            colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          _ServerMetaChip(
                            label: active ? '当前服务器' : server.serverType.label,
                            highlighted: active,
                          ),
                          const Spacer(),
                          if (hasError)
                            _ServerErrorPill(
                              code: server.lastErrorCode!,
                            ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      ServerIconAvatar(
                        iconUrl: server.iconUrl,
                        name: server.name,
                        radius: 20,
                      ),
                      const SizedBox(width: 14),
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
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    height: 1.25,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (hasError)
                            _ServerErrorPill(code: server.lastErrorCode!),
                          if (hasError) const SizedBox(height: 8),
                          _ServerMetaChip(
                            label: active ? '当前' : '进入',
                            highlighted: active,
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
}

class _ServerMetaChip extends StatelessWidget {
  const _ServerMetaChip({
    required this.label,
    required this.highlighted,
  });

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = highlighted
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerLowest;
    final foreground = highlighted
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ServerErrorPill extends StatelessWidget {
  const _ServerErrorPill({required this.code});

  final int code;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'HTTP $code',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MobileLocalPlaybackCard extends StatelessWidget {
  const _MobileLocalPlaybackCard({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: loading ? null : onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer.withValues(alpha: 0.92),
                colorScheme.secondaryContainer.withValues(alpha: 0.88),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorScheme.onPrimaryContainer
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.folder_open_rounded,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '本地播放',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onPrimaryContainer,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '无需登录服务器，直接播放本地视频文件。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.78),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(
                  onPressed: loading ? null : onTap,
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PlexAddMode {
  account,
  manual,
}

extension _PlexAddModeX on _PlexAddMode {
  String get label {
    switch (this) {
      case _PlexAddMode.account:
        return '账号登录';
      case _PlexAddMode.manual:
        return '手动添加';
    }
  }
}

class _MobileAddServerSheet extends StatefulWidget {
  const _MobileAddServerSheet({
    required this.appState,
    this.onOpenBulkImport,
  });

  final AppState appState;
  final Future<void> Function(BuildContext sheetContext)? onOpenBulkImport;

  @override
  State<_MobileAddServerSheet> createState() => _MobileAddServerSheetState();
}

class _MobileAddServerSheetState extends State<_MobileAddServerSheet> {
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

  String _defaultPortForScheme(String scheme) => scheme == 'http' ? '80' : '443';

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
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return null;
    }
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
    final requestId = ++_autoMetaReqId;
    setState(() {
      _autoMetaLoading = true;
      _autoMetaError = null;
      _autoMetaLastUrl = urlKey;
    });

    try {
      final meta = await WebsiteMetadataService.instance.fetch(uri);
      if (!mounted || requestId != _autoMetaReqId) return;

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
      if (!mounted || requestId != _autoMetaReqId) return;
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
        final token = (latest.authToken ?? '').trim();
        if (token.isNotEmpty) break;
      }

      final authToken = (latest.authToken ?? '').trim();
      if (authToken.isEmpty) {
        throw Exception('等待 Plex 授权超时或授权未完成');
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
          setState(() => _plexError = '没有获取到 Plex Token，请重新登录');
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
      await widget.appState.addWebDavServer(
        baseUrl: uri.toString(),
        username: _userCtrl.text.trim(),
        password: _pwdCtrl.text,
        displayName:
            _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        remark:
            _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
        iconUrl: _iconUrl,
      );
      addedId = widget.appState.activeServerId;
    } else {
      addedId = await widget.appState.addServer(
        hostOrUrl: _hostCtrl.text.trim(),
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
      );
    }

    if (!mounted) return;
    if (widget.appState.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.appState.error!)),
      );
      return;
    }

    final entered =
        _serverType != MediaServerType.plex && (addedId ?? widget.appState.activeServerId) != null;
    Navigator.of(context).pop(entered);
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
                                      widget.onOpenBulkImport!(context),
                                    ),
                            icon: const Icon(Icons.playlist_add_outlined),
                            label: const Text('批量导入'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<MediaServerType>(
                      segments: serverTypes
                          .map(
                            (type) => ButtonSegment<MediaServerType>(
                              value: type,
                              label: Text(type.label),
                            ),
                          )
                          .toList(growable: false),
                      selected: <MediaServerType>{_serverType},
                      onSelectionChanged:
                          loading ? null : (selected) => _setServerType(selected.first),
                    ),
                    if (_serverType == MediaServerType.plex) ...[
                      const SizedBox(height: 12),
                      SegmentedButton<_PlexAddMode>(
                        segments: _PlexAddMode.values
                            .map(
                              (mode) => ButtonSegment<_PlexAddMode>(
                                value: mode,
                                label: Text(mode.label),
                              ),
                            )
                            .toList(growable: false),
                        selected: <_PlexAddMode>{_plexMode},
                        onSelectionChanged: loading
                            ? null
                            : (selected) => setState(() {
                                  _plexMode = selected.first;
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
                            '授权码：${_plexPin!.code}，在浏览器完成授权后返回。',
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
                                  (resource) => DropdownMenuItem<PlexResource>(
                                    value: resource,
                                    child: Text(
                                      resource.name.isEmpty
                                          ? resource.clientIdentifier
                                          : resource.name,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: loading
                                ? null
                                : (value) => setState(() {
                                      _selectedPlexServer = value;
                                      _plexError = null;
                                      if (value != null &&
                                          !_nameTouched &&
                                          _nameCtrl.text.trim().isEmpty &&
                                          value.name.trim().isNotEmpty) {
                                        _nameCtrl.text = value.name.trim();
                                        _nameCtrl.selection =
                                            TextSelection.collapsed(
                                          offset: _nameCtrl.text.length,
                                        );
                                      }
                                    }),
                            decoration: const InputDecoration(
                              labelText: '选择 Plex 服务器',
                            ),
                            validator: (_) => _selectedPlexServer == null
                                ? '请选择服务器'
                                : null,
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
                                '连接地址：$uri',
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
                      decoration:
                          const InputDecoration(labelText: '服务器名称（可选）'),
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
                            tooltip: '自动获取站点信息',
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
                                : '重新登录 Plex',
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
                          validator: (value) {
                            if (!showPlexToken) return null;
                            return (value == null || value.trim().isEmpty)
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
                          '自动获取失败，可以手动设置名称和图标。',
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
                              decoration: const InputDecoration(labelText: '协议'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'https',
                                  child: Text('https'),
                                ),
                                DropdownMenuItem(
                                  value: 'http',
                                  child: Text('http'),
                                ),
                              ],
                              onChanged: loading
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _scheme = value;
                                        if (_portCtrl.text.isEmpty ||
                                            _portCtrl.text == '80' ||
                                            _portCtrl.text == '443') {
                                          _portCtrl.text =
                                              _defaultPortForScheme(value);
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
                                hintText: '例如 emby.example.com 或 1.2.3.4',
                              ),
                              keyboardType: TextInputType.url,
                              validator: (value) => (value == null ||
                                      value.trim().isEmpty)
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
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final port = int.tryParse(value.trim());
                          if (port == null || port <= 0 || port > 65535) {
                            return '端口不合法';
                          }
                          return null;
                        },
                      ),
                      if (showUserPass) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _userCtrl,
                          decoration: const InputDecoration(labelText: '账号'),
                          validator: (value) {
                            if ((_serverType.isEmbyLike ||
                                    _serverType == MediaServerType.webdav) &&
                                (value == null || value.trim().isEmpty)) {
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
              height: 46,
              child: FilledButton(
                onPressed: loading ? null : _submit,
                child: loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('连接并进入'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileEditServerSheet extends StatefulWidget {
  const _MobileEditServerSheet({
    required this.appState,
    required this.server,
  });

  final AppState appState;
  final ServerProfile server;

  @override
  State<_MobileEditServerSheet> createState() => _MobileEditServerSheetState();
}

class _MobileEditServerSheetState extends State<_MobileEditServerSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.server.name);
  late final TextEditingController _remarkCtrl =
      TextEditingController(text: widget.server.remark);

  String? _iconUrl;
  bool _iconLoading = false;
  bool _saving = false;

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

  ServerProfile _currentServer() {
    for (final server in widget.appState.servers) {
      if (server.id == widget.server.id) return server;
    }
    return widget.server;
  }

  String _routeLabel(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.trim().isNotEmpty) {
      return uri.host.trim();
    }
    return url;
  }

  String _routeName(ServerProfile server, String url) {
    for (final route in widget.appState.customDomainsOfServer(server.id)) {
      if (route.url == url) return route.name.trim().isEmpty ? url : route.name;
    }
    return _routeLabel(url);
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
    final server = _currentServer();
    final uri = Uri.tryParse(server.baseUrl);
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
        SnackBar(content: Text('自动获取图标失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _iconLoading = false);
    }
  }

  void _clearIcon() {
    setState(() => _iconUrl = null);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final server = _currentServer();
    final iconArg = _iconUrl == server.iconUrl ? null : (_iconUrl ?? '');
    await widget.appState.updateServerMeta(
      server.id,
      name: _nameCtrl.text,
      remark: _remarkCtrl.text,
      iconUrl: iconArg,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final server = _currentServer();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器？'),
        content: Text('将删除“${server.name}”。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.appState.removeServer(server.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<_RouteDraft?> _showRouteEditor({
    required String title,
    String initialName = '',
    String initialUrl = '',
    String initialRemark = '',
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final urlCtrl = TextEditingController(text: initialUrl);
    final remarkCtrl = TextEditingController(text: initialRemark);

    final result = await showDialog<_RouteDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '线路名称',
                  hintText: '例如：主线 / 备用 / 移动',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '线路地址',
                  hintText: '例如：https://emby.example.com',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(
                  labelText: '线路备注（可选）',
                  hintText: '例如：低延迟 / 走移动网络',
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
              Navigator.of(dialogContext).pop(
                _RouteDraft(
                  name: nameCtrl.text.trim(),
                  url: urlCtrl.text.trim(),
                  remark: remarkCtrl.text.trim(),
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    urlCtrl.dispose();
    remarkCtrl.dispose();
    return result;
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String labelText,
    String initialText = '',
    String? hintText,
  }) async {
    final ctrl = TextEditingController(text: initialText);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
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
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _addRoute() async {
    final server = _currentServer();
    final draft = await _showRouteEditor(title: '新增线路');
    if (draft == null || draft.url.trim().isEmpty) return;

    try {
      await widget.appState.addCustomDomainForServer(
        serverId: server.id,
        name: draft.name,
        url: draft.url,
        remark: draft.remark.isEmpty ? null : draft.remark,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _editRoute(CustomDomain route) async {
    final server = _currentServer();
    final draft = await _showRouteEditor(
      title: '编辑线路',
      initialName: route.name,
      initialUrl: route.url,
      initialRemark:
          (widget.appState.serverDomainRemark(server.id, route.url) ?? '').trim(),
    );
    if (draft == null || draft.url.trim().isEmpty) return;

    try {
      await widget.appState.updateCustomDomainForServer(
        server.id,
        oldUrl: route.url,
        name: draft.name,
        url: draft.url,
        remark: draft.remark.isEmpty ? null : draft.remark,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _removeRoute(CustomDomain route) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除线路？'),
        content: Text('将删除“${route.name}”。'),
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
      ),
    );
    if (ok != true) return;
    final server = _currentServer();
    await widget.appState.removeCustomDomainForServer(server.id, route.url);
  }

  Future<void> _editCurrentRouteRemark(ServerProfile server) async {
    final url = server.baseUrl.trim();
    final currentRemark =
        (widget.appState.serverDomainRemark(server.id, url) ?? '').trim();
    final nextRemark = await _showTextInputDialog(
      title: '编辑当前线路备注',
      labelText: '备注',
      hintText: '例如：家庭宽带 / 低延迟',
      initialText: currentRemark,
    );
    if (nextRemark == null) return;
    await widget.appState.setServerDomainRemark(
      server.id,
      url,
      nextRemark.trim().isEmpty ? null : nextRemark.trim(),
    );
  }

  Future<void> _switchRoute(ServerProfile server, String url) async {
    final nextUrl = url.trim();
    if (nextUrl.isEmpty || nextUrl == server.baseUrl.trim()) return;

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
        SnackBar(content: Text('切换线路失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final server = _currentServer();
        final customRoutes = widget.appState.customDomainsOfServer(server.id);
        final currentUrl = server.baseUrl.trim();
        final currentRemark =
            (widget.appState.serverDomainRemark(server.id, currentUrl) ?? '')
                .trim();

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '编辑服务器',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addRoute,
                            icon: const Icon(Icons.add_link_rounded),
                            label: const Text('新增线路'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: '服务器名称'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _remarkCtrl,
                        decoration: const InputDecoration(
                          labelText: '备注（卡片第二行显示）',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ServerIconAvatar(
                            iconUrl: _iconUrl,
                            name: _nameCtrl.text,
                            radius: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('服务器图标'),
                                const SizedBox(height: 2),
                                Text(
                                  (_iconUrl == null || _iconUrl!.trim().isEmpty)
                                      ? '未设置'
                                      : '已设置',
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
                            tooltip: '自动获取 favicon',
                            onPressed: _iconLoading ? null : _autoFetchIcon,
                            icon: _iconLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
                      const SizedBox(height: 18),
                      Text(
                        '当前线路',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                          leading: const Icon(Icons.radio_button_checked_rounded),
                          title: Text(
                            _routeName(server, currentUrl),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            currentRemark.isEmpty
                                ? currentUrl
                                : '$currentRemark\n$currentUrl',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            onPressed: () => _editCurrentRouteRemark(server),
                            child: const Text('备注'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '自定义线路',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${customRoutes.length} 条',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (customRoutes.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.6),
                          ),
                          child: Text(
                            '还没有自定义线路。可以新增备用线路，也可以点下面现有线路切换为当前。',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        )
                      else
                        ...customRoutes.asMap().entries.map((entry) {
                          final route = entry.value;
                          final isCurrent = route.url == currentUrl;
                          final routeRemark =
                              (widget.appState.serverDomainRemark(
                                        server.id,
                                        route.url,
                                      ) ??
                                      '')
                                  .trim();
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: entry.key == customRoutes.length - 1 ? 0 : 10,
                            ),
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.fromLTRB(16, 10, 6, 10),
                                onTap: isCurrent
                                    ? null
                                    : () => _switchRoute(server, route.url),
                                leading: Icon(
                                  isCurrent
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.route_outlined,
                                ),
                                title: Text(
                                  route.name.trim().isEmpty
                                      ? _routeLabel(route.url)
                                      : route.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  routeRemark.isEmpty
                                      ? route.url
                                      : '$routeRemark\n${route.url}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: PopupMenuButton<_RouteMenuAction>(
                                  onSelected: (action) {
                                    switch (action) {
                                      case _RouteMenuAction.use:
                                        _switchRoute(server, route.url);
                                        break;
                                      case _RouteMenuAction.edit:
                                        _editRoute(route);
                                        break;
                                      case _RouteMenuAction.delete:
                                        _removeRoute(route);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (!isCurrent)
                                      const PopupMenuItem(
                                        value: _RouteMenuAction.use,
                                        child: Text('切换到这条线路'),
                                      ),
                                    const PopupMenuItem(
                                      value: _RouteMenuAction.edit,
                                      child: Text('编辑线路'),
                                    ),
                                    const PopupMenuItem(
                                      value: _RouteMenuAction.delete,
                                      child: Text('删除线路'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _confirmDelete,
                      child: const Text('删除服务器'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _RouteMenuAction {
  use,
  edit,
  delete,
}

class _RouteDraft {
  const _RouteDraft({
    required this.name,
    required this.url,
    required this.remark,
  });

  final String name;
  final String url;
  final String remark;
}
