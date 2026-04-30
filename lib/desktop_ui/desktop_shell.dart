import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import '../server_adapters/server_access.dart';
import '../library_page.dart';
import '../library_items_page.dart';
import '../services/app_back_intent.dart';
import 'mock/desktop_ui_preview_page.dart';
import 'models/desktop_ui_language.dart';
import 'pages/desktop_episode_detail_page.dart';
import 'pages/desktop_library_page.dart';
import 'pages/desktop_library_detail_page.dart';
import 'pages/desktop_movie_detail_page.dart';
import 'pages/desktop_navigation_layout.dart';
import 'pages/desktop_player_page.dart';
import 'pages/desktop_search_page.dart';
import 'pages/desktop_server_page.dart';
import 'pages/desktop_settings_page.dart';
import 'pages/desktop_show_detail_page.dart';
import 'pages/desktop_webdav_home_page.dart';
import 'theme/desktop_theme_extension.dart';
import 'theme/desktop_theme_scope.dart';
import 'view_models/desktop_detail_view_model.dart';
import 'widgets/desktop_page_route.dart';
import 'widgets/desktop_shared_transition_coordinator.dart';
import 'widgets/desktop_shortcut_wrapper.dart';
import 'widgets/desktop_sidebar.dart';
import 'widgets/desktop_sidebar_item.dart' show DesktopSidebarServerAction;
import 'widgets/desktop_top_bar.dart';
import 'widgets/desktop_unified_background.dart';
import 'widgets/focus_traversal_manager.dart';
import 'widgets/window_padding_container.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key, required this.appState});

  final AppState appState;
  static const bool uiPreviewMode = bool.fromEnvironment(
    'LINPLAYER_DESKTOP_UI_PREVIEW',
    defaultValue: false,
  );

  static bool get isDesktopTarget =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) {
    if (uiPreviewMode) {
      return const DesktopUiPreviewPage();
    }
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final active = appState.activeServer;

        if (active == null || !appState.hasActiveServerProfile) {
          return DesktopServerPage(appState: appState);
        }
        if (active.serverType == MediaServerType.webdav) {
          return DesktopWebDavHomePage(appState: appState);
        }
        if (!appState.hasActiveServer) {
          return DesktopServerPage(appState: appState);
        }

        return _DesktopWorkspace(
          key: ValueKey<String>('desktop-${appState.activeServerId ?? 'none'}'),
          appState: appState,
        );
      },
    );
  }
}

enum _DesktopSection { library, search, detail }

enum _DesktopSectionTransition { push, pull }

class _DesktopDetailStackEntry {
  const _DesktopDetailStackEntry({
    required this.item,
    required this.server,
  });

  final MediaItem item;
  final ServerProfile? server;
}

class _DesktopLibraryItemsBackTarget {
  const _DesktopLibraryItemsBackTarget({
    required this.parentId,
    required this.title,
  });

  final String parentId;
  final String title;
}

class _DesktopWorkspace extends StatefulWidget {
  const _DesktopWorkspace({super.key, required this.appState});

  final AppState appState;

  @override
  State<_DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<_DesktopWorkspace>
    with SingleTickerProviderStateMixin {
  static const double _kTopBarFadeDistance = 220.0;
  static const Duration _kSharedOpenTransitionDuration = Duration(
    milliseconds: 520,
  );

  _DesktopSection _section = _DesktopSection.library;
  final List<_DesktopSection> _sectionStack = <_DesktopSection>[
    _DesktopSection.library,
  ];
  DesktopHomeTab _homeTab = DesktopHomeTab.home;
  bool _sidebarCollapsed = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _refreshSignal = 0;
  DesktopDetailViewModel? _detailViewModel;
  final List<_DesktopDetailStackEntry> _detailStack =
      <_DesktopDetailStackEntry>[];
  _DesktopLibraryItemsBackTarget? _libraryItemsBackTarget;
  MediaStats? _mediaStats;
  bool _loadingMediaStats = false;
  int _mediaStatsRequestVersion = 0;
  final ValueNotifier<double> _topBarVisibility = ValueNotifier<double>(1.0);
  final GlobalKey _contentTransitionRootKey = GlobalKey();
  final GlobalKey _detailPosterKey = GlobalKey();
  late final AnimationController _sharedOpenController = AnimationController(
    vsync: this,
    duration: _kSharedOpenTransitionDuration,
  )..addStatusListener(_handleSharedOpenTransitionStatus);
  _DesktopSharedOpenTransitionState? _sharedOpenTransition;
  int _sharedOpenResolveAttempts = 0;
  bool _sharedOpenAnimationCompleted = false;
  bool _sharedOpenDetailPosterReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMediaStats());
  }

  @override
  void dispose() {
    _sharedOpenController
      ..removeStatusListener(_handleSharedOpenTransitionStatus)
      ..dispose();
    _sharedOpenTransition?.dispose();
    _searchController.dispose();
    _topBarVisibility.dispose();
    _detailViewModel?.dispose();
    super.dispose();
  }

  void _disposeSharedTransitionLater(
    _DesktopSharedOpenTransitionState? transition,
  ) {
    if (transition == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      transition.dispose();
    });
  }

  void _handleSharedOpenTransitionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (mounted) {
      setState(() => _sharedOpenAnimationCompleted = true);
    } else {
      _sharedOpenAnimationCompleted = true;
    }
    _tryFinishSharedOpenTransitionHandoff();
  }

  void _handleDetailPosterReady() {
    if (_sharedOpenTransition == null) return;
    _sharedOpenDetailPosterReady = true;
    _tryFinishSharedOpenTransitionHandoff();
  }

  void _tryFinishSharedOpenTransitionHandoff() {
    if (!_sharedOpenAnimationCompleted || !_sharedOpenDetailPosterReady) {
      return;
    }
  }

  void _clearSharedOpenTransition({bool clearPendingSource = false}) {
    if (clearPendingSource) {
      DesktopSharedTransitionCoordinator.instance.clear();
    }
    _sharedOpenResolveAttempts = 0;
    _sharedOpenAnimationCompleted = false;
    _sharedOpenDetailPosterReady = false;
    _sharedOpenController.stop();
    final previousTransition = _sharedOpenTransition;
    if (_sharedOpenTransition == null) {
      if (_sharedOpenController.value != 0) {
        _sharedOpenController.value = 0;
      }
      return;
    }
    if (!mounted) {
      _sharedOpenTransition = null;
      previousTransition?.dispose();
      if (_sharedOpenController.value != 0) {
        _sharedOpenController.value = 0;
      }
      return;
    }
    setState(() => _sharedOpenTransition = null);
    if (_sharedOpenController.value != 0) {
      _sharedOpenController.value = 0;
    }
    _disposeSharedTransitionLater(previousTransition);
  }

  void _scheduleSharedOpenTransitionResolution() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveSharedOpenTransitionTargets();
    });
  }

  void _resolveSharedOpenTransitionTargets() {
    final transition = _sharedOpenTransition;
    if (!mounted || transition == null) return;

    final rootContext = _contentTransitionRootKey.currentContext;
    final posterContext = _detailPosterKey.currentContext;
    final rootBox = rootContext?.findRenderObject() as RenderBox?;
    final posterBox = posterContext?.findRenderObject() as RenderBox?;

    if (rootBox == null ||
        posterBox == null ||
        !rootBox.hasSize ||
        !posterBox.hasSize) {
      if (_sharedOpenResolveAttempts < 6) {
        _sharedOpenResolveAttempts += 1;
        _scheduleSharedOpenTransitionResolution();
        return;
      }
      _clearSharedOpenTransition();
      return;
    }

    final rootOrigin = rootBox.localToGlobal(Offset.zero);
    final targetOrigin = posterBox.localToGlobal(Offset.zero);
    final resolvedSourceRect = transition.sourceGlobalRect.shift(-rootOrigin);
    final resolvedTargetRect = Rect.fromLTWH(
      targetOrigin.dx - rootOrigin.dx,
      targetOrigin.dy - rootOrigin.dy,
      posterBox.size.width,
      posterBox.size.height,
    );

    _sharedOpenResolveAttempts = 0;
    setState(() {
      _sharedOpenTransition = transition.copyWith(
        sourceRect: resolvedSourceRect,
        targetRect: resolvedTargetRect,
        contentRect: Offset.zero & rootBox.size,
      );
    });
    if (_sharedOpenAnimationCompleted) {
      return;
    }
    _sharedOpenController
      ..stop()
      ..value = 0
      ..forward();
  }

  DesktopUiLanguage get _uiLanguage =>
      _desktopUiLanguageFromCode(widget.appState.desktopUiLanguage);

  DesktopUiLanguage _desktopUiLanguageFromCode(String code) {
    switch (code.trim().toLowerCase()) {
      case 'en':
      case 'enus':
      case 'en-us':
      case 'en_us':
        return DesktopUiLanguage.enUs;
      default:
        return DesktopUiLanguage.zhCn;
    }
  }

  void _handleServerSelected(String serverId) {
    unawaited(_handleServerSelectedInternal(serverId));
  }

  Future<void> _handleServerSelectedInternal(String serverId) async {
    final server = _serverById(serverId);
    if (server == null) return;

    final hasError = server.lastErrorCode != null ||
        (server.lastErrorMessage ?? '').trim().isNotEmpty;
    if (hasError) {
      final msg = (server.lastErrorMessage ?? '').trim();
      _showInfo(msg.isNotEmpty ? msg : '服务器不可用（${server.lastErrorCode}）');
      return;
    }

    _hideSidebar();
    if (_section != _DesktopSection.library || _topBarVisibility.value < 1.0) {
      setState(() {
        _sectionStack
          ..clear()
          ..add(_DesktopSection.library);
        _section = _DesktopSection.library;
      });
      _resetTopBarVisibility();
    }
    _detailStack.clear();
    _libraryItemsBackTarget = null;
    _detailViewModel?.dispose();
    _detailViewModel = null;
    if (serverId == widget.appState.activeServerId) return;

    final ok = await widget.appState.enterServer(serverId);
    if (!mounted || ok) return;

    final msg = (server.lastErrorMessage ?? widget.appState.error ?? '').trim();
    if (msg.isNotEmpty) {
      _showInfo(msg);
    }
  }

  List<DesktopSidebarServer> _buildSidebarServers() {
    return widget.appState.servers.map(
      (server) {
        final hasError = server.lastErrorCode != null ||
            (server.lastErrorMessage ?? '').trim().isNotEmpty;
        return DesktopSidebarServer(
          id: server.id,
          name: server.name.trim().isEmpty ? server.baseUrl : server.name,
          subtitle: _buildServerSubtitleText(server),
          serverType: server.serverType,
          iconUrl: server.iconUrl,
          enabled: !hasError,
        );
      },
    ).toList(growable: false);
  }

  String _buildServerSubtitleText(ServerProfile server) {
    final remark = (server.remark ?? '').trim();
    return remark;
  }

  ServerProfile? _serverById(String serverId) {
    for (final server in widget.appState.servers) {
      if (server.id == serverId) return server;
    }
    return null;
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleSidebarServerAction(
    String serverId,
    DesktopSidebarServerAction action,
  ) {
    switch (action) {
      case DesktopSidebarServerAction.editIcon:
        unawaited(_editServerIcon(serverId));
        break;
      case DesktopSidebarServerAction.editRemark:
        unawaited(_editServerRemark(serverId));
        break;
      case DesktopSidebarServerAction.editPassword:
        unawaited(_editServerPassword(serverId));
        break;
      case DesktopSidebarServerAction.editRoute:
        unawaited(_editServerRoute(serverId));
        break;
      case DesktopSidebarServerAction.deleteServer:
        unawaited(_deleteServer(serverId));
        break;
    }
  }

  Future<void> _editServerIcon(String serverId) async {
    final server = _serverById(serverId);
    if (server == null) return;

    final iconCtrl = TextEditingController(text: server.iconUrl ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _uiLanguage.pick(
              zh: '修改图标',
              en: 'Edit icon',
            ),
          ),
          content: TextField(
            controller: iconCtrl,
            decoration: InputDecoration(
              labelText: _uiLanguage.pick(zh: '图标地址', en: 'Icon URL'),
              hintText: 'https://example.com/icon.png',
            ),
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final pickedUrl = await showModalBottomSheet<String?>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (ctx) => ServerIconLibrarySheet(
                    urlsListenable: widget.appState,
                    getLibraryUrls: () => widget.appState.serverIconLibraryUrls,
                    addLibraryUrl: widget.appState.addServerIconLibraryUrl,
                    removeLibraryUrlAt:
                        widget.appState.removeServerIconLibraryUrlAt,
                    reorderLibraryUrls:
                        widget.appState.reorderServerIconLibraryUrls,
                    selectedUrl: iconCtrl.text,
                  ),
                );
                if (pickedUrl == null) return;
                final next = pickedUrl.trim();
                iconCtrl.value = iconCtrl.value.copyWith(
                  text: next,
                  selection: TextSelection.collapsed(offset: next.length),
                );
              },
              child: Text(_uiLanguage.pick(zh: '图标库', en: 'Library')),
            ),
            TextButton(
              onPressed: iconCtrl.clear,
              child: Text(_uiLanguage.pick(zh: '清空', en: 'Clear')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_uiLanguage.pick(zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(iconCtrl.text.trim()),
              child: Text(_uiLanguage.pick(zh: '保存', en: 'Save')),
            ),
          ],
        );
      },
    );
    iconCtrl.dispose();
    if (result == null) return;

    await widget.appState.updateServerMeta(serverId, iconUrl: result);
    _showInfo(_uiLanguage.pick(zh: '图标已更新', en: 'Icon updated'));
  }

  Future<void> _editServerRemark(String serverId) async {
    final server = _serverById(serverId);
    if (server == null) return;

    final remarkCtrl = TextEditingController(text: server.remark ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _uiLanguage.pick(
              zh: '修改备注',
              en: 'Edit remark',
            ),
          ),
          content: TextField(
            controller: remarkCtrl,
            decoration: InputDecoration(
              labelText: _uiLanguage.pick(zh: '备注', en: 'Remark'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_uiLanguage.pick(zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(remarkCtrl.text),
              child: Text(_uiLanguage.pick(zh: '保存', en: 'Save')),
            ),
          ],
        );
      },
    );
    remarkCtrl.dispose();
    if (result == null) return;

    await widget.appState.updateServerMeta(serverId, remark: result);
    _showInfo(_uiLanguage.pick(zh: '备注已更新', en: 'Remark updated'));
  }

  Future<void> _editServerPassword(String serverId) async {
    final server = _serverById(serverId);
    if (server == null) return;

    final usernameCtrl = TextEditingController(text: server.username);
    final passwordCtrl = TextEditingController();
    final showUsername = server.serverType != MediaServerType.plex;
    final secretLabel = _uiLanguage.pick(
      zh: server.serverType == MediaServerType.plex ? '令牌' : '密码',
      en: server.serverType == MediaServerType.plex ? 'Token' : 'Password',
    );

    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        var obscure = true;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                _uiLanguage.pick(
                  zh: '修改密码',
                  en: 'Edit password',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showUsername) ...[
                    TextField(
                      controller: usernameCtrl,
                      decoration: InputDecoration(
                        labelText: _uiLanguage.pick(zh: '用户名', en: 'Username'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: secretLabel,
                      suffixIcon: IconButton(
                        tooltip: _uiLanguage.pick(zh: '显示/隐藏', en: 'Show/Hide'),
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(_uiLanguage.pick(zh: '取消', en: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop({
                    'username': usernameCtrl.text.trim(),
                    'password': passwordCtrl.text,
                  }),
                  child: Text(_uiLanguage.pick(zh: '保存', en: 'Save')),
                ),
              ],
            );
          },
        );
      },
    );

    usernameCtrl.dispose();
    passwordCtrl.dispose();
    if (payload == null) return;

    final nextPassword = (payload['password'] ?? '').trim();
    if (nextPassword.isEmpty) {
      _showInfo(_uiLanguage.pick(zh: '密码不能为空', en: 'Password is required'));
      return;
    }

    try {
      await widget.appState.updateServerPassword(
        serverId,
        password: nextPassword,
        username: showUsername ? payload['username'] : null,
      );

      if (serverId == widget.appState.activeServerId &&
          server.serverType.isEmbyLike) {
        await widget.appState.refreshDomains();
        await widget.appState.refreshLibraries();
        await widget.appState.loadHome(forceRefresh: true);
        await _loadMediaStats(forceRefresh: true);
      }

      _showInfo(_uiLanguage.pick(zh: '密码已更新', en: 'Password updated'));
    } catch (e) {
      _showInfo(e.toString());
    }
  }

  Future<void> _editServerRoute(String serverId) async {
    final server = _serverById(serverId);
    if (server == null) return;
    await _openServerRouteManager(serverId);
  }

  Future<void> _openServerRouteManager(String serverId) async {
    final server = _serverById(serverId);
    if (server == null) return;

    final desktopTheme = DesktopThemeExtension.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBackground = desktopTheme.surface.withValues(
      alpha: isDark ? 0.95 : 0.98,
    );

    final canLoadPluginRoutes = server.serverType.isEmbyLike;
    var pluginDomains = <DomainInfo>[];
    var loadingDomains = false;
    var domainError = '';

    Future<void> refreshPluginDomains(StateSetter setSheetState) async {
      if (!canLoadPluginRoutes) return;
      final currentServer = _serverById(serverId);
      if (currentServer == null) return;
      final access = resolveServerAccess(
        appState: widget.appState,
        server: currentServer,
      );
      if (access == null) {
        setSheetState(() {
          loadingDomains = false;
          pluginDomains = const <DomainInfo>[];
          domainError = '';
        });
        return;
      }

      setSheetState(() {
        loadingDomains = true;
        domainError = '';
      });

      try {
        final domains = await access.adapter.fetchDomains(
          access.auth,
          allowFailure: true,
        );
        setSheetState(() {
          pluginDomains = domains;
          loadingDomains = false;
        });
      } catch (e) {
        setSheetState(() {
          loadingDomains = false;
          domainError = e.toString();
        });
      }
    }

    Future<Map<String, String>?> showRouteEditor({
      required String titleZh,
      required String titleEn,
      String initialName = '',
      String initialUrl = '',
      String initialRemark = '',
    }) async {
      final nameCtrl = TextEditingController(text: initialName);
      final urlCtrl = TextEditingController(text: initialUrl);
      final remarkCtrl = TextEditingController(text: initialRemark);

      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_uiLanguage.pick(zh: titleZh, en: titleEn)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: _uiLanguage.pick(zh: '名称', en: 'Name'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: _uiLanguage.pick(zh: '地址', en: 'URL'),
                    hintText: 'https://emby.example.com',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remarkCtrl,
                  decoration: InputDecoration(
                    labelText: _uiLanguage.pick(
                      zh: '备注（可选）',
                      en: 'Remark (optional)',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_uiLanguage.pick(zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop({
                'name': nameCtrl.text.trim(),
                'url': urlCtrl.text.trim(),
                'remark': remarkCtrl.text.trim(),
              }),
              child: Text(_uiLanguage.pick(zh: '保存', en: 'Save')),
            ),
          ],
        ),
      );
      nameCtrl.dispose();
      urlCtrl.dispose();
      remarkCtrl.dispose();
      return result;
    }

    Future<String?> showRemarkEditor(String currentRemark) async {
      final remarkCtrl = TextEditingController(text: currentRemark);
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_uiLanguage.pick(zh: '线路备注', en: 'Route remark')),
          content: TextField(
            controller: remarkCtrl,
            decoration: InputDecoration(
              labelText: _uiLanguage.pick(zh: '备注', en: 'Remark'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_uiLanguage.pick(zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(remarkCtrl.text),
              child: Text(_uiLanguage.pick(zh: '保存', en: 'Save')),
            ),
          ],
        ),
      );
      remarkCtrl.dispose();
      return result;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: sheetBackground,
      builder: (sheetContext) {
        var requestedPluginDomains = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (!requestedPluginDomains && canLoadPluginRoutes) {
              requestedPluginDomains = true;
              unawaited(refreshPluginDomains(setSheetState));
            }

            final currentServer = _serverById(serverId);
            if (currentServer == null) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _uiLanguage.pick(
                      zh: '服务器不存在或已被删除',
                      en: 'Server not found',
                    ),
                  ),
                ),
              );
            }

            final customEntries = widget.appState
                .customDomainsOfServer(serverId)
                .map((d) => DomainInfo(name: d.name, url: d.url))
                .toList(growable: false);
            final entries = buildRouteEntries(
              currentUrl: currentServer.baseUrl,
              customEntries: customEntries,
              pluginDomains: pluginDomains,
            );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _uiLanguage.pick(
                              zh: '修改线路',
                              en: 'Manage routes',
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip:
                              _uiLanguage.pick(zh: '添加自定义线路', en: 'Add route'),
                          onPressed: () async {
                            final result = await showRouteEditor(
                              titleZh: '添加自定义线路',
                              titleEn: 'Add custom route',
                            );
                            if (result == null) return;
                            try {
                              await widget.appState.addCustomDomainForServer(
                                serverId: serverId,
                                name: result['name'] ?? '',
                                url: result['url'] ?? '',
                                remark: (result['remark'] ?? '').trim().isEmpty
                                    ? null
                                    : (result['remark'] ?? '').trim(),
                              );
                              setSheetState(() {});
                            } catch (e) {
                              _showInfo(e.toString());
                            }
                          },
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: _uiLanguage.pick(zh: '刷新', en: 'Refresh'),
                          onPressed: canLoadPluginRoutes && !loadingDomains
                              ? () => unawaited(
                                    refreshPluginDomains(setSheetState),
                                  )
                              : null,
                          icon: loadingDomains
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (domainError.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        domainError,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _uiLanguage.pick(
                            zh: '暂无可用线路',
                            en: 'No routes available',
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final route = entry.domain;
                            final selected = route.url == currentServer.baseUrl;
                            final remark = widget.appState
                                    .serverDomainRemark(serverId, route.url) ??
                                '';

                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                route.name.trim().isEmpty
                                    ? route.url
                                    : route.name.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if (remark.trim().isNotEmpty) remark.trim(),
                                  route.url,
                                ].join(' | '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: _uiLanguage.pick(
                                      zh: '修改备注',
                                      en: 'Edit remark',
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final value =
                                          await showRemarkEditor(remark);
                                      if (value == null) return;
                                      await widget.appState
                                          .setServerDomainRemark(
                                        serverId,
                                        route.url,
                                        value,
                                      );
                                      setSheetState(() {});
                                    },
                                  ),
                                  if (entry.isCustom)
                                    PopupMenuButton<String>(
                                      tooltip: _uiLanguage.pick(
                                          zh: '更多', en: 'More'),
                                      onSelected: (action) async {
                                        if (action == 'edit') {
                                          final result = await showRouteEditor(
                                            titleZh: '编辑自定义线路',
                                            titleEn: 'Edit custom route',
                                            initialName: route.name,
                                            initialUrl: route.url,
                                            initialRemark: remark,
                                          );
                                          if (result == null) return;
                                          try {
                                            await widget.appState
                                                .updateCustomDomainForServer(
                                              serverId,
                                              oldUrl: route.url,
                                              name: result['name'] ?? '',
                                              url: result['url'] ?? '',
                                              remark: (result['remark'] ?? '')
                                                      .trim()
                                                      .isEmpty
                                                  ? null
                                                  : (result['remark'] ?? '')
                                                      .trim(),
                                            );
                                            setSheetState(() {});
                                          } catch (e) {
                                            _showInfo(e.toString());
                                          }
                                          return;
                                        }

                                        if (action == 'delete') {
                                          final confirmed =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (dialogContext) =>
                                                AlertDialog(
                                              title: Text(_uiLanguage.pick(
                                                zh: '删除线路？',
                                                en: 'Delete route?',
                                              )),
                                              content: Text(
                                                _uiLanguage.pick(
                                                  zh: '将删除“${route.name}”。',
                                                  en: 'This will remove "${route.name}".',
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                          dialogContext)
                                                      .pop(false),
                                                  child: Text(_uiLanguage.pick(
                                                      zh: '取消', en: 'Cancel')),
                                                ),
                                                FilledButton(
                                                  onPressed: () => Navigator.of(
                                                          dialogContext)
                                                      .pop(true),
                                                  child: Text(_uiLanguage.pick(
                                                      zh: '删除', en: 'Delete')),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed != true) return;
                                          await widget.appState
                                              .removeCustomDomainForServer(
                                            serverId,
                                            route.url,
                                          );
                                          setSheetState(() {});
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text(_uiLanguage.pick(
                                            zh: '编辑',
                                            en: 'Edit',
                                          )),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text(_uiLanguage.pick(
                                            zh: '删除',
                                            en: 'Delete',
                                          )),
                                        ),
                                      ],
                                      child:
                                          const Icon(Icons.more_horiz_rounded),
                                    ),
                                  if (selected)
                                    Icon(
                                      Icons.check,
                                      color: desktopTheme.accent,
                                    ),
                                ],
                              ),
                              onTap: () async {
                                if (selected) return;
                                try {
                                  await widget.appState.updateServerRoute(
                                    serverId,
                                    url: route.url,
                                  );

                                  if (serverId ==
                                          widget.appState.activeServerId &&
                                      currentServer.serverType.isEmbyLike) {
                                    await widget.appState.refreshDomains();
                                    await widget.appState.refreshLibraries();
                                    await widget.appState.loadHome(
                                      forceRefresh: true,
                                    );
                                    await _loadMediaStats(forceRefresh: true);
                                    await refreshPluginDomains(setSheetState);
                                  } else {
                                    setSheetState(() {});
                                  }
                                } catch (e) {
                                  _showInfo(e.toString());
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteServer(String serverId) async {
    final server = _serverById(serverId);
    if (server == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_uiLanguage.pick(
            zh: '删除服务器？',
            en: 'Delete server?',
          )),
          content: Text(
            _uiLanguage.pick(
              zh: '将删除“${server.name}”。',
              en: 'This will remove "${server.name}".',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_uiLanguage.pick(zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_uiLanguage.pick(zh: '删除', en: 'Delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await widget.appState.removeServer(serverId);
    _showInfo(_uiLanguage.pick(zh: '服务器已删除', en: 'Server deleted'));
  }

  Future<void> _loadMediaStats({bool forceRefresh = false}) async {
    final requestVersion = ++_mediaStatsRequestVersion;
    if (mounted) {
      setState(() => _loadingMediaStats = true);
    }
    try {
      final stats =
          await widget.appState.loadMediaStats(forceRefresh: forceRefresh);
      if (!mounted || requestVersion != _mediaStatsRequestVersion) return;
      setState(() => _mediaStats = stats);
    } catch (_) {
      // Keep existing stats if loading fails.
    } finally {
      if (mounted && requestVersion == _mediaStatsRequestVersion) {
        setState(() => _loadingMediaStats = false);
      }
    }
  }

  void _handleHomeTabChanged(DesktopHomeTab tab) {
    _clearSharedOpenTransition(clearPendingSource: true);
    setState(() {
      _homeTab = tab;
      _sectionStack
        ..clear()
        ..add(_DesktopSection.library);
      _section = _DesktopSection.library;
    });
    _resetTopBarVisibility();
  }

  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
  }

  void _hideSidebar() {
    if (_sidebarCollapsed) return;
    setState(() => _sidebarCollapsed = true);
  }

  Future<void> _openLibraryItems(String parentId, String title) async {
    _clearSharedOpenTransition(clearPendingSource: true);
    final id = parentId.trim();
    if (id.isEmpty) return;
    final normalizedTitle = title.trim().isEmpty
        ? _uiLanguage.pick(zh: '\u5a92\u4f53\u5e93', en: 'Library')
        : title;

    final target = _DesktopLibraryItemsBackTarget(
      parentId: id,
      title: normalizedTitle,
    );
    _libraryItemsBackTarget = target;

    final result = await Navigator.of(context).push<LibraryItemsPageResult>(
      buildDesktopPageRoute(
        transition: DesktopPageTransitionStyle.push,
        builder: (_) => DesktopLibraryDetailPage(
          appState: widget.appState,
          parentId: id,
          title: normalizedTitle,
          onOpenItem: (item) => _openDetailInternal(
            item,
            fromLibraryItems: true,
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (result != LibraryItemsPageResult.openedItem &&
        _libraryItemsBackTarget?.parentId == target.parentId &&
        _libraryItemsBackTarget?.title == target.title) {
      _libraryItemsBackTarget = null;
    }
  }

  void _onBackRequested() {
    unawaited(_handleBackRequested());
  }

  Future<void> _handleBackRequested() async {
    _clearSharedOpenTransition(clearPendingSource: true);
    if (!_sidebarCollapsed) {
      setState(() => _sidebarCollapsed = true);
      return;
    }

    if (_section == _DesktopSection.detail && _detailStack.isNotEmpty) {
      final entry = _detailStack.removeLast();
      _openDetailInternal(
        entry.item,
        server: entry.server,
        pushHistory: false,
        transition: _DesktopSectionTransition.pull,
      );
      return;
    }

    if (_section == _DesktopSection.detail &&
        (_libraryItemsBackTarget?.parentId ?? '').trim().isNotEmpty) {
      final target = _libraryItemsBackTarget!;
      final canLeaveDetail = _sectionStack.length > 1;
      if (canLeaveDetail) {
        _detailViewModel?.dispose();
        _detailViewModel = null;
        _detailStack.clear();
        setState(() {
          _sectionStack.removeLast();
          _section = _sectionStack.last;
        });
        _resetTopBarVisibility();
      }
      await _openLibraryItems(target.parentId, target.title);
      return;
    }

    if (_sectionStack.length > 1) {
      final leavingDetail = _sectionStack.last == _DesktopSection.detail;
      setState(() {
        _sectionStack.removeLast();
        _section = _sectionStack.last;
      });
      _resetTopBarVisibility();
      if (leavingDetail) {
        _detailViewModel?.dispose();
        _detailViewModel = null;
        _detailStack.clear();
        _libraryItemsBackTarget = null;
      }
      return;
    }

    await widget.appState.leaveServer();
  }

  void _openDetail(MediaItem item, [ServerProfile? server]) {
    _openDetailInternal(item, server: server);
  }

  void _openDetailInternal(
    MediaItem item, {
    ServerProfile? server,
    bool pushHistory = true,
    bool fromLibraryItems = false,
    _DesktopSectionTransition transition = _DesktopSectionTransition.push,
  }) {
    final itemId = item.id.trim();
    if (itemId.isEmpty) return;

    final currentVm = _detailViewModel;
    final alreadyInDetail =
        _section == _DesktopSection.detail && currentVm != null;
    final sharedSource =
        (!alreadyInDetail && transition == _DesktopSectionTransition.push)
            ? DesktopSharedTransitionCoordinator.instance.consumePendingSource(
                itemId,
              )
            : null;
    final runSharedOpen = sharedSource != null;

    if (alreadyInDetail && pushHistory) {
      final currentItem = currentVm.detail;
      final currentId = currentItem.id.trim();
      if (currentId.isNotEmpty && currentId != itemId) {
        _detailStack.add(
          _DesktopDetailStackEntry(
            item: currentItem,
            server: currentVm.server,
          ),
        );
        if (_detailStack.length > 32) {
          _detailStack.removeAt(0);
        }
      }
    }

    if (!alreadyInDetail) {
      _detailStack.clear();
      if (!fromLibraryItems) {
        _libraryItemsBackTarget = null;
      }
    }

    final next = DesktopDetailViewModel(
      appState: widget.appState,
      item: item,
      server: server,
    );
    _detailViewModel?.dispose();
    final previousTransition = _sharedOpenTransition;
    setState(() {
      _detailViewModel = next;
      _sharedOpenAnimationCompleted = false;
      _sharedOpenDetailPosterReady = false;
      _sharedOpenTransition = runSharedOpen
          ? _DesktopSharedOpenTransitionState(
              itemId: itemId,
              sourceGlobalRect: sharedSource.globalRect,
              imageUrls: sharedSource.imageUrls,
              sourceImage: sharedSource.snapshotImage,
              fallbackLabel: sharedSource.fallbackLabel,
              sourceBorderRadius: sharedSource.borderRadius,
            )
          : null;
      if (_sectionStack.isEmpty) {
        _sectionStack.add(_DesktopSection.detail);
      } else if (_sectionStack.last != _DesktopSection.detail) {
        _sectionStack.add(_DesktopSection.detail);
      }
      _section = _DesktopSection.detail;
    });
    if (!identical(previousTransition, _sharedOpenTransition)) {
      _disposeSharedTransitionLater(previousTransition);
    }
    _resetTopBarVisibility();
    if (runSharedOpen) {
      _scheduleSharedOpenTransitionResolution();
    } else {
      DesktopSharedTransitionCoordinator.instance.clear();
      _sharedOpenResolveAttempts = 0;
      _sharedOpenController.stop();
      if (_sharedOpenController.value != 0) {
        _sharedOpenController.value = 0;
      }
    }
    unawaited(next.load(forceRefresh: true));
  }

  void _onPlayCurrentDetail() {
    unawaited(_playCurrentDetail());
  }

  Future<void> _playCurrentDetail() async {
    final vm = _detailViewModel;
    if (vm == null) return;

    final playable = _resolvePlayableItem(vm);
    if (playable == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No playable media found for this item'),
        ),
      );
      return;
    }

    final start = playable.playbackPositionTicks > 0
        ? _ticksToDuration(playable.playbackPositionTicks)
        : null;

    await Navigator.of(context).push(
      buildDesktopPageRoute(
        transition: DesktopPageTransitionStyle.push,
        builder: (_) => DesktopPlayerPage.network(
          title: playable.name,
          itemId: playable.id,
          appState: widget.appState,
          server: vm.server,
          startPosition: start,
        ),
      ),
    );

    if (!mounted) return;
    await vm.load(forceRefresh: true);
  }

  MediaItem? _resolvePlayableItem(DesktopDetailViewModel vm) {
    final detail = vm.detail;
    final type = detail.type.trim().toLowerCase();
    if (type == 'series' || type == 'season') {
      if (vm.episodes.isEmpty) return null;
      return vm.episodes.firstWhere(
        (item) => item.playbackPositionTicks > 0,
        orElse: () => vm.episodes.first,
      );
    }
    return detail;
  }

  Duration _ticksToDuration(int ticks) =>
      Duration(microseconds: (ticks / 10).round());

  void _refreshCurrentPage() {
    setState(() => _refreshSignal += 1);
    if (_section == _DesktopSection.detail && _detailViewModel != null) {
      unawaited(_detailViewModel!.load(forceRefresh: true));
    }
    unawaited(_loadMediaStats(forceRefresh: true));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      buildDesktopPageRoute(
        transition: DesktopPageTransitionStyle.push,
        builder: (_) => DesktopSettingsPage(appState: widget.appState),
      ),
    );
  }

  Future<void> _openSettingsFromRect(Rect _) async {
    await Navigator.of(context).push(
      buildDesktopPageRoute(
        transition: DesktopPageTransitionStyle.stack,
        duration: const Duration(milliseconds: 220),
        builder: (_) => DesktopSettingsPage(appState: widget.appState),
      ),
    );
  }

  Future<void> _openLibraryManager() async {
    await Navigator.of(context).push(
      buildDesktopPageRoute(
        transition: DesktopPageTransitionStyle.push,
        builder: (_) => LibraryPage(appState: widget.appState),
      ),
    );
  }

  Future<void> _openRouteManager() async {
    if (widget.appState.domains.isEmpty && !widget.appState.isLoading) {
      unawaited(widget.appState.refreshDomains());
    }

    final desktopTheme = DesktopThemeExtension.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBackground = desktopTheme.surface.withValues(
      alpha: isDark ? 0.95 : 0.98,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: sheetBackground,
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: widget.appState,
          builder: (context, _) {
            final current = widget.appState.baseUrl;
            final customEntries = widget.appState.customDomains
                .map((d) => DomainInfo(name: d.name, url: d.url))
                .toList(growable: false);
            final pluginDomains = widget.appState.domains;
            final entries = buildRouteEntries(
              currentUrl: current,
              customEntries: customEntries,
              pluginDomains: pluginDomains,
            );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _uiLanguage.pick(
                              zh: '\u7ebf\u8def\u7ba1\u7406',
                              en: 'Route Manager',
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: _uiLanguage.pick(
                            zh: '\u6dfb\u52a0\u81ea\u5b9a\u4e49\u7ebf\u8def',
                            en: 'Add custom route',
                          ),
                          onPressed: _addCustomRoute,
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: _uiLanguage.pick(
                            zh: '\u5237\u65b0',
                            en: 'Refresh',
                          ),
                          onPressed: widget.appState.isLoading
                              ? null
                              : widget.appState.refreshDomains,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (entries.isEmpty && !widget.appState.isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          _uiLanguage.pick(
                            zh: '\u6682\u65e0\u53ef\u7528\u7ebf\u8def\uff08\u672a\u90e8\u7f72\u6269\u5c55\u65f6\u5c5e\u4e8e\u6b63\u5e38\u60c5\u51b5\uff09',
                            en: 'No routes available',
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final domain = entry.domain;
                            final selected = current == domain.url;
                            final remark =
                                widget.appState.domainRemark(domain.url);
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                domain.name.trim().isEmpty
                                    ? domain.url
                                    : domain.name.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if ((remark ?? '').trim().isNotEmpty)
                                    remark!.trim(),
                                  domain.url,
                                ].join(' | '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: selected
                                  ? Icon(Icons.check,
                                      color: desktopTheme.accent)
                                  : null,
                              onLongPress: !entry.isCustom
                                  ? null
                                  : () => _removeCustomRoute(domain.url),
                              onTap: () async {
                                if (selected) {
                                  Navigator.of(sheetContext).pop();
                                  return;
                                }
                                await widget.appState.setBaseUrl(domain.url);
                                await widget.appState.refreshLibraries();
                                await widget.appState.loadHome(
                                  forceRefresh: true,
                                );
                                await _loadMediaStats(forceRefresh: true);
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addCustomRoute() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _uiLanguage.pick(
              zh: '\u6dfb\u52a0\u81ea\u5b9a\u4e49\u7ebf\u8def',
              en: 'Add custom route',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: _uiLanguage.pick(zh: '\u540d\u79f0', en: 'Name'),
                    hintText: _uiLanguage.pick(
                      zh: '\u4f8b\u5982\uff1a\u76f4\u8fde / \u5907\u7528',
                      en: 'e.g. Primary / Backup',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: _uiLanguage.pick(zh: '\u5730\u5740', en: 'URL'),
                    hintText: 'https://emby.example.com',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: remarkCtrl,
                  decoration: InputDecoration(
                    labelText: _uiLanguage.pick(
                      zh: '\u5907\u6ce8\uff08\u53ef\u9009\uff09',
                      en: 'Remark (optional)',
                    ),
                    hintText: _uiLanguage.pick(
                      zh: '\u4f8b\u5982\uff1a\u79fb\u52a8\u7f51\u7edc',
                      en: 'e.g. Mobile network',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_uiLanguage.pick(zh: '\u53d6\u6d88', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop({
                  'name': nameCtrl.text.trim(),
                  'url': urlCtrl.text.trim(),
                  'remark': remarkCtrl.text.trim(),
                });
              },
              child: Text(_uiLanguage.pick(zh: '\u4fdd\u5b58', en: 'Save')),
            ),
          ],
        );
      },
    );
    nameCtrl.dispose();
    urlCtrl.dispose();
    remarkCtrl.dispose();

    if (result == null) return;
    try {
      await widget.appState.addCustomDomain(
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

  Future<void> _removeCustomRoute(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_uiLanguage.pick(
            zh: '\u5220\u9664\u7ebf\u8def\uff1f',
            en: 'Delete route?',
          )),
          content: Text(
            _uiLanguage.pick(
              zh: '\u5c06\u5220\u9664\u8be5\u81ea\u5b9a\u4e49\u7ebf\u8def\u3002',
              en: 'This custom route will be removed.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_uiLanguage.pick(zh: '\u53d6\u6d88', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_uiLanguage.pick(zh: '\u5220\u9664', en: 'Delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await widget.appState.removeCustomDomain(url);
  }

  void _handleSearchChanged(String value) {
    _searchQuery = value;
  }

  void _handleSearchSubmitted(String value) {
    setState(() {
      _searchQuery = value.trim();
      _searchController.value = TextEditingValue(
        text: _searchQuery,
        selection: TextSelection.collapsed(offset: _searchQuery.length),
      );
      if (_sectionStack.isEmpty) {
        _sectionStack.add(_DesktopSection.search);
      } else if (_sectionStack.last != _DesktopSection.search) {
        _sectionStack.add(_DesktopSection.search);
      }
      _section = _DesktopSection.search;
    });
    _resetTopBarVisibility();
  }

  void _setTopBarVisibility(double value) {
    final next = value.clamp(0.0, 1.0).toDouble();
    if (!mounted || (next - _topBarVisibility.value).abs() <= 0.001) return;
    _topBarVisibility.value = next;
  }

  void _resetTopBarVisibility() {
    _setTopBarVisibility(1.0);
  }

  void _updateTopBarVisibilityByScrollDelta(double delta) {
    if (delta.abs() < 0.1) return;
    final next = _topBarVisibility.value - (delta / _kTopBarFadeDistance);
    _setTopBarVisibility(next);
  }

  bool _handleContentScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final axis = axisDirectionToAxis(notification.metrics.axisDirection);
    if (axis != Axis.vertical) return false;
    if (_sharedOpenTransition != null && _sharedOpenAnimationCompleted) {
      _scheduleSharedOpenTransitionResolution();
    }

    final pixels = notification.metrics.pixels;
    if (pixels <= 0) {
      _setTopBarVisibility(1.0);
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      _updateTopBarVisibilityByScrollDelta(delta);
      return false;
    }

    if (notification is OverscrollNotification) {
      _updateTopBarVisibilityByScrollDelta(notification.overscroll);
      return false;
    }

    if (notification is ScrollEndNotification && pixels <= 1) {
      _setTopBarVisibility(1.0);
      return false;
    }

    return false;
  }

  Widget _buildDetailContent() {
    final vm = _detailViewModel;
    if (vm == null) {
      return Center(
        child: Text(
          _uiLanguage.pick(
            zh: '\u672a\u9009\u62e9\u8be6\u60c5\u5185\u5bb9',
            en: 'No detail selected',
          ),
        ),
      );
    }

    final type = vm.detail.type.trim().toLowerCase();
    final detailKey = ValueKey<String>(vm.detail.id);
    final posterVisible = _sharedOpenTransition == null;
    final useSharedPosterOverlay = _sharedOpenTransition != null;
    if (type == 'movie') {
      return DesktopMovieDetailPage(
        key: detailKey,
        viewModel: vm,
        language: _uiLanguage,
        onOpenItem: _openDetail,
        onPlayPressed: _onPlayCurrentDetail,
        posterKey: _detailPosterKey,
        posterVisible: posterVisible,
        onPosterReady: _handleDetailPosterReady,
        posterSnapshotImage: _sharedOpenTransition?.sourceImage,
        useSharedPosterOverlay: useSharedPosterOverlay,
      );
    }
    if (type == 'episode') {
      return DesktopEpisodeDetailPage(
        key: detailKey,
        viewModel: vm,
        language: _uiLanguage,
        onOpenItem: _openDetail,
        onPlayPressed: _onPlayCurrentDetail,
        posterKey: _detailPosterKey,
        posterVisible: posterVisible,
        onPosterReady: _handleDetailPosterReady,
        posterSnapshotImage: _sharedOpenTransition?.sourceImage,
        useSharedPosterOverlay: useSharedPosterOverlay,
      );
    }
    return DesktopShowDetailPage(
      key: detailKey,
      viewModel: vm,
      language: _uiLanguage,
      onOpenItem: _openDetail,
      onPlayPressed: _onPlayCurrentDetail,
      posterKey: _detailPosterKey,
      posterVisible: posterVisible,
      onPosterReady: _handleDetailPosterReady,
      posterSnapshotImage: _sharedOpenTransition?.sourceImage,
      useSharedPosterOverlay: useSharedPosterOverlay,
    );
  }

  Widget _buildContentLayers() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Visibility(
          visible: _section == _DesktopSection.library,
          maintainState: true,
          child: DesktopLibraryPage(
            key: const PageStorageKey<String>('desktop-library-section'),
            appState: widget.appState,
            refreshSignal: _refreshSignal,
            onOpenItem: _openDetail,
            onOpenLibraryItems: _openLibraryItems,
            activeTab: _homeTab,
            language: _uiLanguage,
          ),
        ),
        Visibility(
          visible: _section == _DesktopSection.search,
          maintainState: true,
          child: DesktopSearchPage(
            key: const PageStorageKey<String>('desktop-search-section'),
            appState: widget.appState,
            query: _searchQuery,
            refreshSignal: _refreshSignal,
            language: _uiLanguage,
            onOpenItem: _openDetail,
          ),
        ),
        Visibility(
          visible: _section == _DesktopSection.detail,
          maintainState: true,
          child: _buildDetailContent(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DesktopThemeScope(
      child: Builder(
        builder: (context) {
          final desktopTheme = DesktopThemeExtension.of(context);
          final desktopBackgroundImage =
              widget.appState.desktopBackgroundImage.trim();
          final desktopBackgroundOpacity = widget
              .appState.desktopBackgroundOpacity
              .clamp(0.0, 1.0)
              .toDouble();
          final hasCustomBackground = desktopBackgroundImage.isNotEmpty;
          final isDetailSection = _section == _DesktopSection.detail;
          final baseBackground = desktopTheme.background;
          final contentBackgroundStart = isDetailSection
              ? desktopTheme.background
              : desktopTheme.backgroundGradientStart;
          final contentBackgroundEnd = isDetailSection
              ? desktopTheme.background
              : desktopTheme.backgroundGradientEnd;
          final overlayAlpha = hasCustomBackground
              ? (1.0 - desktopBackgroundOpacity).clamp(0.0, 1.0).toDouble()
              : 1.0;
          final overlayBackgroundStart = hasCustomBackground
              ? contentBackgroundStart.withValues(alpha: overlayAlpha)
              : contentBackgroundStart;
          final overlayBackgroundEnd = hasCustomBackground
              ? contentBackgroundEnd.withValues(alpha: overlayAlpha)
              : contentBackgroundEnd;
          final title = switch (_section) {
            _DesktopSection.library => _uiLanguage.pick(
                zh: _homeTab == DesktopHomeTab.home
                    ? '\u4e3b\u9875'
                    : '\u559c\u6b22',
                en: _homeTab == DesktopHomeTab.home ? 'Home' : 'Favorites',
              ),
            _DesktopSection.search => _uiLanguage.pick(
                zh: '\u641c\u7d22',
                en: 'Search',
              ),
            _DesktopSection.detail => _detailViewModel?.detail.name ??
                _uiLanguage.pick(
                  zh: '\u8be6\u60c5',
                  en: 'Media Detail',
                ),
          };
          final sidebarServers = _buildSidebarServers();
          final contentView = _buildContentLayers();

          return ColoredBox(
            color: baseBackground,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: DesktopUnifiedBackground(
                    appState: widget.appState,
                    baseColor: baseBackground,
                  ),
                ),
                SafeArea(
                  child: DesktopShortcutWrapper(
                    enabled: true,
                    shortcuts: <ShortcutActivator, Intent>{
                      const SingleActivator(LogicalKeyboardKey.escape):
                          AppBackIntent(),
                    },
                    actions: <Type, Action<Intent>>{
                      AppBackIntent: CallbackAction<AppBackIntent>(
                        onInvoke: (_) {
                          _onBackRequested();
                          return null;
                        },
                      ),
                    },
                    child: FocusTraversalManager(
                      child: WindowPaddingContainer(
                        padding: EdgeInsets.zero,
                        dragRegionHeight: 0,
                        child: DesktopNavigationLayout(
                          backgroundStartColor: overlayBackgroundStart,
                          backgroundEndColor: overlayBackgroundEnd,
                          sidebarWidth: 264,
                          sidebarVisible: !_sidebarCollapsed,
                          onDismissSidebar: _hideSidebar,
                          sidebar: DesktopSidebar(
                            servers: sidebarServers,
                            selectedServerId: widget.appState.activeServerId,
                            onSelected: _handleServerSelected,
                            onServerAction: _handleSidebarServerAction,
                            collapsed: _sidebarCollapsed,
                          ),
                          topBar: DesktopTopBar(
                            title: title,
                            serverName:
                                widget.appState.activeServer?.name ?? '',
                            movieCount: _mediaStats?.movieCount,
                            seriesCount: _mediaStats?.seriesCount,
                            statsLoading: _loadingMediaStats,
                            enableBlur: widget.appState.enableBlurEffects,
                            language: _uiLanguage,
                            showSearch: _section != _DesktopSection.library,
                            homeTab: _homeTab,
                            onHomeTabChanged: _handleHomeTabChanged,
                            backEnabled: _sectionStack.length > 1 ||
                                widget.appState.hasActiveServer,
                            onBack: _onBackRequested,
                            onToggleSidebar: _toggleSidebar,
                            searchController: _searchController,
                            onSearchChanged: _handleSearchChanged,
                            onSearchSubmitted: _handleSearchSubmitted,
                            onRefresh: _refreshCurrentPage,
                            onOpenLibraryManager: _openLibraryManager,
                            onOpenRouteManager: _openRouteManager,
                            onOpenSettings: _openSettings,
                            onOpenSettingsFromRect: _openSettingsFromRect,
                            searchHint: _uiLanguage.pick(
                              zh: '\u641c\u7d22\u5267\u96c6\u6216\u7535\u5f71',
                              en: 'Search series or movies',
                            ),
                          ),
                          content: RepaintBoundary(
                            key: _contentTransitionRootKey,
                            child: AnimatedBuilder(
                              animation: _sharedOpenController,
                              builder: (context, _) {
                                final sharedTransition = _sharedOpenTransition;
                                final sharedProgress =
                                    _sharedOpenController.value;
                                final sharedResolved =
                                    sharedTransition?.isResolved ?? false;
                                final sharedInteractionLocked =
                                    sharedTransition != null &&
                                        !_sharedOpenAnimationCompleted;
                                final contentOpacity = sharedTransition == null
                                    ? 1.0
                                    : sharedResolved
                                        ? Curves.easeOutCubic.transform(
                                            ((sharedProgress - 0.58) / 0.42)
                                                .clamp(0.0, 1.0),
                                          )
                                        : 0.0;

                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    IgnorePointer(
                                      ignoring: sharedInteractionLocked,
                                      child: Opacity(
                                        opacity: contentOpacity,
                                        child: NotificationListener<
                                            ScrollNotification>(
                                          onNotification:
                                              _handleContentScrollNotification,
                                          child: contentView,
                                        ),
                                      ),
                                    ),
                                    if (sharedTransition != null)
                                      _DesktopSharedOpenOverlay(
                                        transition: sharedTransition,
                                        progress: sharedProgress,
                                        theme: desktopTheme,
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                          topBarVisibilityListenable: _topBarVisibility,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DesktopSharedOpenTransitionState {
  const _DesktopSharedOpenTransitionState({
    required this.itemId,
    required this.sourceGlobalRect,
    required this.imageUrls,
    required this.sourceImage,
    required this.fallbackLabel,
    required this.sourceBorderRadius,
    this.sourceRect,
    this.targetRect,
    this.contentRect,
  });

  final String itemId;
  final Rect sourceGlobalRect;
  final List<String> imageUrls;
  final ui.Image? sourceImage;
  final String fallbackLabel;
  final double sourceBorderRadius;
  final Rect? sourceRect;
  final Rect? targetRect;
  final Rect? contentRect;

  bool get isResolved =>
      sourceRect != null && targetRect != null && contentRect != null;

  void dispose() {
    sourceImage?.dispose();
  }

  _DesktopSharedOpenTransitionState copyWith({
    Rect? sourceRect,
    Rect? targetRect,
    Rect? contentRect,
  }) {
    return _DesktopSharedOpenTransitionState(
      itemId: itemId,
      sourceGlobalRect: sourceGlobalRect,
      imageUrls: imageUrls,
      sourceImage: sourceImage,
      fallbackLabel: fallbackLabel,
      sourceBorderRadius: sourceBorderRadius,
      sourceRect: sourceRect ?? this.sourceRect,
      targetRect: targetRect ?? this.targetRect,
      contentRect: contentRect ?? this.contentRect,
    );
  }
}

class _DesktopSharedOpenOverlay extends StatelessWidget {
  const _DesktopSharedOpenOverlay({
    required this.transition,
    required this.progress,
    required this.theme,
  });

  final _DesktopSharedOpenTransitionState transition;
  final double progress;
  final DesktopThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    final sourceRect = transition.sourceRect;
    final targetRect = transition.targetRect;
    final contentRect = transition.contentRect;
    if (sourceRect == null || targetRect == null || contentRect == null) {
      return const SizedBox.shrink();
    }

    final posterT = Curves.easeOutCubic.transform(
      (progress / 0.72).clamp(0.0, 1.0),
    );
    final posterRect = Rect.lerp(sourceRect, targetRect, posterT)!;
    final posterRadius =
        ui.lerpDouble(transition.sourceBorderRadius, 12, posterT) ?? 12;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fromRect(
            rect: posterRect,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(posterRadius),
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.34),
                    blurRadius: 26,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(posterRadius),
                child: transition.sourceImage != null
                    ? RawImage(
                        image: transition.sourceImage,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      )
                    : _DesktopSharedOpenPosterImage(
                        imageUrls: transition.imageUrls,
                        fallbackLabel: transition.fallbackLabel,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSharedOpenPosterImage extends StatefulWidget {
  const _DesktopSharedOpenPosterImage({
    required this.imageUrls,
    required this.fallbackLabel,
  });

  final List<String> imageUrls;
  final String fallbackLabel;

  @override
  State<_DesktopSharedOpenPosterImage> createState() =>
      _DesktopSharedOpenPosterImageState();
}

class _DesktopSharedOpenPosterImageState
    extends State<_DesktopSharedOpenPosterImage> {
  int _currentIndex = 0;

  @override
  void didUpdateWidget(covariant _DesktopSharedOpenPosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrls.join('|') != widget.imageUrls.join('|')) {
      _currentIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrls = widget.imageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (imageUrls.isEmpty || _currentIndex >= imageUrls.length) {
      return _DesktopSharedOpenFallback(label: widget.fallbackLabel);
    }

    final imageUrl = imageUrls[_currentIndex];
    return CachedNetworkImage(
      key: ValueKey<String>('shared-open-$imageUrl'),
      imageUrl: imageUrl,
      cacheManager: CoverCacheManager.instance,
      httpHeaders: {'User-Agent': LinHttpClientFactory.userAgent},
      fit: BoxFit.cover,
      useOldImageOnUrlChange: true,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      placeholder: (_, __) => _DesktopSharedOpenFallback(
        label: widget.fallbackLabel,
      ),
      errorWidget: (_, __, ___) {
        if (_currentIndex < imageUrls.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _currentIndex += 1);
          });
        }
        return _DesktopSharedOpenFallback(label: widget.fallbackLabel);
      },
    );
  }
}

class _DesktopSharedOpenFallback extends StatelessWidget {
  const _DesktopSharedOpenFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = DesktopThemeExtension.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.surfaceElevated,
            theme.surface,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            label.trim().isEmpty ? 'Media' : label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
