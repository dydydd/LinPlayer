import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_items_page.dart';
import 'server_adapters/server_access.dart';

enum _LibraryPageLayout { grid, list }

const _kLibraryPageLayoutPrefsKey = 'library_page_layout_v1';

_LibraryPageLayout _decodeLibraryLayout(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'list':
      return _LibraryPageLayout.list;
    case 'grid':
    default:
      return _LibraryPageLayout.grid;
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  _LibraryPageLayout _layout = _LibraryPageLayout.grid;

  bool _isTv(BuildContext context) => DeviceType.isTv;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLayout());
  }

  Future<void> _restoreLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLibraryPageLayoutPrefsKey);
      final next = _decodeLibraryLayout(raw);
      if (!mounted || _layout == next) return;
      setState(() => _layout = next);
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> _toggleLayout() async {
    final next = _layout == _LibraryPageLayout.grid
        ? _LibraryPageLayout.list
        : _LibraryPageLayout.grid;
    setState(() => _layout = next);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLibraryPageLayoutPrefsKey, next.name);
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> _openLibraryItems(LibraryInfo lib) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LibraryItemsPage(
          appState: widget.appState,
          parentId: lib.id,
          title: lib.name,
          isTv: _isTv(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiScale = context.uiScale;
    final compactMobile =
        !_isTv(context) && MediaQuery.sizeOf(context).shortestSide < 600;
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final enableBlur = !_isTv(context) && widget.appState.enableBlurEffects;
        final access = resolveServerAccess(appState: widget.appState);
        final libs = widget.appState.libraries.toList(growable: false);
        return Scaffold(
          appBar: GlassAppBar(
            enableBlur: enableBlur,
            child: AppBar(
              title: const Text('媒体库'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.sort_by_alpha),
                  tooltip: '名称排序',
                  onPressed: widget.appState.sortLibrariesByName,
                ),
                IconButton(
                  icon: Icon(
                    _layout == _LibraryPageLayout.grid
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                  ),
                  tooltip:
                      _layout == _LibraryPageLayout.grid ? '条形视图' : '矩形视图',
                  onPressed: _toggleLayout,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: widget.appState.isLoading
                      ? null
                      : () => widget.appState.refreshLibraries(),
                ),
              ],
            ),
          ),
          body: widget.appState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : libs.isEmpty
                  ? const Center(child: Text('暂无媒体库，点击右上角刷新重试'))
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: _layout == _LibraryPageLayout.grid
                          ? GridView.builder(
                              gridDelegate: compactMobile
                                  ? const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 1.18,
                                    )
                                  : SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 150 * uiScale,
                                      mainAxisSpacing: 6,
                                      crossAxisSpacing: 6,
                                      childAspectRatio: 1.33,
                                    ),
                              itemCount: libs.length,
                              itemBuilder: (context, index) {
                                final LibraryInfo lib = libs[index];
                                final hidden =
                                    widget.appState.isLibraryHidden(lib.id);
                                final imageUrl = access?.adapter.imageUrl(
                                      access.auth,
                                      itemId: lib.id,
                                      maxWidth: 400,
                                    ) ??
                                    '';

                                return _LibraryGridTile(
                                  title: lib.name,
                                  imageUrl: imageUrl,
                                  hidden: hidden,
                                  onTap: () => _openLibraryItems(lib),
                                  onToggleHidden: () =>
                                      widget.appState.toggleLibraryHidden(
                                    lib.id,
                                  ),
                                );
                              },
                            )
                          : ListView.separated(
                              itemCount: libs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final lib = libs[index];
                                final hidden =
                                    widget.appState.isLibraryHidden(lib.id);
                                return _LibraryListTile(
                                  title: lib.name,
                                  hidden: hidden,
                                  onTap: () => _openLibraryItems(lib),
                                  onToggleHidden: () =>
                                      widget.appState.toggleLibraryHidden(
                                    lib.id,
                                  ),
                                );
                              },
                            ),
                    ),
        );
      },
    );
  }
}

class _LibraryGridTile extends StatefulWidget {
  const _LibraryGridTile({
    required this.title,
    required this.imageUrl,
    required this.hidden,
    required this.onTap,
    required this.onToggleHidden,
  });

  final String title;
  final String imageUrl;
  final bool hidden;
  final VoidCallback onTap;
  final VoidCallback onToggleHidden;

  @override
  State<_LibraryGridTile> createState() => _LibraryGridTileState();
}

class _LibraryGridTileState extends State<_LibraryGridTile> {
  bool _hovered = false;

  bool _hoverSupported() {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final hoverEnabled = _hoverSupported();
    final showAction = !hoverEnabled || _hovered || widget.hidden;
    final scheme = Theme.of(context).colorScheme;

    final tile = MediaBackdropTile(
      title: widget.title,
      imageUrl: widget.imageUrl,
      onTap: widget.onTap,
      onLongPress: widget.onToggleHidden,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: hoverEnabled ? (_) => setState(() => _hovered = true) : null,
      onExit: hoverEnabled ? (_) => setState(() => _hovered = false) : null,
      child: Stack(
        children: [
          Opacity(opacity: widget.hidden ? 0.55 : 1.0, child: tile),
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              ignoring: !showAction,
              child: AnimatedOpacity(
                opacity: showAction ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: Tooltip(
                  message: widget.hidden ? '取消屏蔽' : '屏蔽',
                  child: Material(
                    color: scheme.surface.withValues(alpha: 0.82),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onToggleHidden,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Icon(
                          widget.hidden ? Icons.block : Icons.block_outlined,
                          size: 20,
                          color: widget.hidden
                              ? scheme.error
                              : scheme.onSurface.withValues(alpha: 0.90),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryListTile extends StatelessWidget {
  const _LibraryListTile({
    required this.title,
    required this.hidden,
    required this.onTap,
    required this.onToggleHidden,
  });

  final String title;
  final bool hidden;
  final VoidCallback onTap;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: ListTile(
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hidden
                    ? scheme.onSurface.withValues(alpha: 0.55)
                    : scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Tooltip(
              message: hidden ? '取消屏蔽' : '屏蔽',
              child: IconButton(
                icon: Icon(hidden ? Icons.block : Icons.block_outlined),
                color: hidden ? scheme.error : scheme.onSurfaceVariant,
                onPressed: onToggleHidden,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          ),
        ),
      ),
    );
  }
}
