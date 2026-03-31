import 'package:flutter/material.dart';
import 'package:lin_player_server_adapters/lin_player_server_adapters.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'server_adapters/server_access.dart';
import 'tv/tv_focusable.dart';

class PersonPage extends StatefulWidget {
  const PersonPage({
    super.key,
    required this.appState,
    required this.personId,
    this.server,
    this.seedName,
    this.isTv = false,
    this.onOpenItem,
  });

  final AppState appState;
  final String personId;
  final ServerProfile? server;
  final String? seedName;
  final bool isTv;
  final void Function(BuildContext context, MediaItem item)? onOpenItem;

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  bool _loading = true;
  String? _error;
  MediaItem? _person;
  List<MediaItem> _works = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PersonPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId.trim() != widget.personId.trim() ||
        oldWidget.server != widget.server) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.personId.trim();
    if (id.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无效的人员 ID';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    if (access == null) {
      setState(() {
        _loading = false;
        _error = '未连接服务器';
      });
      return;
    }

    try {
      final person = await access.adapter.fetchItemDetail(
        access.auth,
        itemId: id,
      );

      final works = await access.adapter.fetchItems(
        access.auth,
        personIds: [id],
        includeItemTypes: 'Movie,Series',
        recursive: true,
        limit: 60,
        startIndex: 0,
        sortBy: 'PremiereDate',
        sortOrder: 'Descending',
      );

      if (!mounted) return;
      setState(() {
        _person = person;
        _works = works.items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _background(BuildContext context, {required String imageUrl}) {
    if (imageUrl.isEmpty) {
      return const ColoredBox(color: Colors.black26);
    }
    return LinNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      errorWidget: const ColoredBox(color: Colors.black26),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final uiScale = context.uiScale;

    final enableTvLayout = widget.isTv;
    final access =
        resolveServerAccess(appState: widget.appState, server: widget.server);
    final personId = widget.personId.trim();
    final personImage = access == null || personId.isEmpty
        ? ''
        : access.adapter.personImageUrl(
            access.auth,
            personId: personId,
            maxWidth: 1200,
          );

    final title = (_person?.name.trim().isNotEmpty == true)
        ? _person!.name.trim()
        : (widget.seedName?.trim().isNotEmpty == true
            ? widget.seedName!.trim()
            : '演职人员');

    final contentPadding = EdgeInsets.fromLTRB(
      (28 * uiScale).clamp(18.0, 34.0),
      (22 * uiScale).clamp(14.0, 28.0),
      (28 * uiScale).clamp(18.0, 34.0),
      (26 * uiScale).clamp(16.0, 34.0),
    );

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Text(_error!));
    } else {
      final name = title;
      final works = _works;

      final posterWidth = (164 * uiScale).clamp(120.0, 220.0);
      final posterRadius = (18 * uiScale).clamp(14.0, 22.0);
      final cardWidth = (176 * uiScale).clamp(132.0, 220.0);

      String workYear(MediaItem item) {
        final date = (item.premiereDate ?? '').trim();
        final parsed = DateTime.tryParse(date);
        if (parsed != null) return parsed.year.toString();
        if (date.length >= 4) return date.substring(0, 4);
        return '';
      }

      Widget workCard(MediaItem item, {required bool autofocus}) {
        final img = access == null
            ? ''
            : access.adapter.imageUrl(
                access.auth,
                itemId: item.id,
                imageType: 'Primary',
                maxWidth: 520,
              );
        final year = workYear(item);
        final sub = year.isEmpty ? '' : year;

        return SizedBox(
          width: cardWidth,
          child: TvFocusable(
            autofocus: autofocus,
            enabled: widget.onOpenItem != null,
            onPressed: widget.onOpenItem == null
                ? null
                : () => widget.onOpenItem!(context, item),
            borderRadius: BorderRadius.circular(posterRadius),
            surfaceColor: Colors.black.withValues(alpha: 0.22),
            focusedSurfaceColor:
                scheme.primary.withValues(alpha: isDark ? 0.16 : 0.12),
            padding: EdgeInsets.all((10 * uiScale).clamp(8.0, 12.0)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      (14 * uiScale).clamp(10.0, 18.0),
                    ),
                    child: img.isEmpty
                        ? const ColoredBox(
                            color: Colors.black26,
                            child: Center(child: Icon(Icons.image)),
                          )
                        : LinNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            errorWidget: const ColoredBox(
                              color: Colors.black26,
                              child: Center(child: Icon(Icons.broken_image)),
                            ),
                          ),
                  ),
                ),
                SizedBox(height: (8 * uiScale).clamp(6.0, 10.0)),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub.isNotEmpty)
                  Padding(
                    padding:
                        EdgeInsets.only(top: (2 * uiScale).clamp(1.0, 4.0)),
                    child: Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: ListView(
            padding: contentPadding,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: posterWidth,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(posterRadius),
                        child: personImage.isEmpty
                            ? const ColoredBox(
                                color: Colors.black26,
                                child: Center(child: Icon(Icons.person)),
                              )
                            : LinNetworkImage(
                                imageUrl: personImage,
                                fit: BoxFit.cover,
                                errorWidget: const ColoredBox(
                                  color: Colors.black26,
                                  child: Center(child: Icon(Icons.person)),
                                ),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(width: (18 * uiScale).clamp(12.0, 22.0)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        if ((_person?.overview ?? '').trim().isNotEmpty) ...[
                          SizedBox(height: (10 * uiScale).clamp(8.0, 12.0)),
                          Text(
                            _person!.overview.trim(),
                            maxLines: enableTvLayout ? 5 : 8,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: (22 * uiScale).clamp(16.0, 28.0)),
              Text(
                '相关作品',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: (10 * uiScale).clamp(8.0, 14.0)),
              if (works.isEmpty)
                const Text('暂无作品', style: TextStyle(color: Colors.white70))
              else
                SizedBox(
                  height: (cardWidth * 1.70).clamp(240.0, 420.0),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: works.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(width: (14 * uiScale).clamp(10.0, 18.0)),
                    itemBuilder: (context, index) {
                      return workCard(works[index], autofocus: index == 0);
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (!widget.isTv) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: body,
      );
    }

    final scrim = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withValues(alpha: 0.82),
        Colors.black.withValues(alpha: 0.60),
        Colors.black.withValues(alpha: 0.76),
      ],
    );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _background(context, imageUrl: personImage)),
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: scrim)),
          ),
          SafeArea(child: body),
        ],
      ),
    );
  }
}
