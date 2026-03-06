import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';

import '../services/plugins/plugin_manager.dart';
import '../services/plugins/plugin_runtime_v1.dart';
import 'plugin_page_host_page.dart';
import 'plugin_schema_renderer.dart';

class PluginSlotArea extends StatefulWidget {
  const PluginSlotArea({
    super.key,
    required this.appState,
    required this.slotId,
    this.params = const {},
    this.axis = Axis.vertical,
    this.gap = 12,
    this.padding = EdgeInsets.zero,
  });

  final AppState appState;
  final String slotId;
  final Map<String, Object?> params;
  final Axis axis;
  final double gap;
  final EdgeInsetsGeometry padding;

  @override
  State<PluginSlotArea> createState() => _PluginSlotAreaState();
}

class _PluginSlotAreaState extends State<PluginSlotArea> {
  final _manager = PluginManagerV1.instance;

  Future<List<_SlotInstance>>? _future;

  @override
  void initState() {
    super.initState();
    PluginManagerV1.revision.addListener(_onRevisionChanged);
    _future = _load();
  }

  @override
  void dispose() {
    PluginManagerV1.revision.removeListener(_onRevisionChanged);
    super.dispose();
  }

  void _onRevisionChanged() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<List<_SlotInstance>> _load() async {
    final target = currentPluginTarget();
    final installed = await _manager.listInstalled();
    final out = <_SlotInstance>[];

    for (final p in installed) {
      if (!p.enabled) continue;
      PluginManifestV1 manifest;
      try {
        manifest = await _manager.loadManifest(p);
      } catch (_) {
        continue;
      }
      if (!manifest.targets.contains(target)) continue;
      final slots = manifest.contributions.slots
          .where((s) => s.slotId == widget.slotId && s.targets.contains(target))
          .toList(growable: false);
      for (final s in slots) {
        out.add(_SlotInstance(plugin: p, manifest: manifest, slot: s));
      }
    }

    out.sort((a, b) {
      final prio = b.slot.priority.compareTo(a.slot.priority);
      if (prio != 0) return prio;
      return '${a.plugin.id}@${a.slot.id}'
          .compareTo('${b.plugin.id}@${b.slot.id}');
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_SlotInstance>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data;
        if (items == null || items.isEmpty) return const SizedBox.shrink();
        if (!pluginRuntimeSupportedV1()) {
          if (widget.axis == Axis.horizontal) return const SizedBox.shrink();
          return Padding(
            padding: widget.padding,
            child: const _PluginRuntimeUnsupportedHint(),
          );
        }

        final children = items
            .map(
              (it) => _PluginSlotHost(
                appState: widget.appState,
                plugin: it.plugin,
                manifest: it.manifest,
                slot: it.slot,
                params: widget.params,
              ),
            )
            .toList(growable: false);

        if (widget.axis == Axis.horizontal) {
          return Padding(
            padding: widget.padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _withGap(children, widget.gap, axis: Axis.horizontal),
            ),
          );
        }
        return Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withGap(children, widget.gap, axis: Axis.vertical),
          ),
        );
      },
    );
  }
}

class _PluginRuntimeUnsupportedHint extends StatelessWidget {
  const _PluginRuntimeUnsupportedHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bg = (isDark ? scheme.surface : scheme.surfaceContainerHighest)
        .withValues(alpha: isDark ? 0.38 : 0.90);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.32 : 0.50),
        ),
      ),
      child: Text(
        '当前平台暂不支持脚本插件运行（需要 WebView 支持）。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.3,
            ),
      ),
    );
  }
}

class _SlotInstance {
  _SlotInstance({
    required this.plugin,
    required this.manifest,
    required this.slot,
  });

  final InstalledPluginV1 plugin;
  final PluginManifestV1 manifest;
  final PluginSlotContributionV1 slot;
}

class _PluginSlotHost extends StatefulWidget {
  const _PluginSlotHost({
    required this.appState,
    required this.plugin,
    required this.manifest,
    required this.slot,
    required this.params,
  });

  final AppState appState;
  final InstalledPluginV1 plugin;
  final PluginManifestV1 manifest;
  final PluginSlotContributionV1 slot;
  final Map<String, Object?> params;

  @override
  State<_PluginSlotHost> createState() => _PluginSlotHostState();
}

class _PluginSlotHostState extends State<_PluginSlotHost> {
  PluginRuntimeV1? _runtime;

  bool _loading = true;
  String? _error;

  Map<String, Object?> _state = const {};
  Object? _schema;

  bool _calling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    final rt = _runtime;
    _runtime = null;
    unawaited(rt?.dispose());
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    PluginRuntimeV1? rt;
    try {
      rt = PluginRuntimeV1(plugin: widget.plugin, manifest: widget.manifest);
      await rt.init();
      if (!mounted) {
        await rt.dispose();
        return;
      }
      setState(() => _runtime = rt);
      rt = null;
      await _render();
    } catch (e) {
      unawaited(rt?.dispose());
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _render() async {
    final rt = _runtime;
    if (rt == null) return;
    if (_calling) return;
    _calling = true;
    try {
      await _renderInternal(rt);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _calling = false;
    }
  }

  Future<void> _renderInternal(PluginRuntimeV1 rt) async {
    final res = await rt.call(widget.slot.render, [widget.params, _state]);
    if (!mounted) return;
    if (res is! Map) {
      setState(() => _error = 'render 返回格式错误（不是对象）');
      return;
    }
    final stateRaw = res['state'];
    final schema = res['schema'];
    final state =
        stateRaw is Map ? Map<String, Object?>.from(stateRaw) : _state;
    final actionsRaw = res['actions'];
    await _handleActions(actionsRaw);
    if (!mounted) return;
    setState(() {
      _state = state;
      _schema = schema;
      _error = null;
    });
  }

  Future<void> _onEvent(Map<String, Object?> event) async {
    final rt = _runtime;
    if (rt == null) return;
    if (_calling) return;
    _calling = true;
    try {
      final res = await rt.call(widget.slot.onEvent, [event, _state]);
      if (!mounted) return;
      if (res is! Map) {
        setState(() => _error = 'onEvent 返回格式错误（不是对象）');
        return;
      }
      final stateRaw = res['state'];
      final actionsRaw = res['actions'];
      final nextState =
          stateRaw is Map ? Map<String, Object?>.from(stateRaw) : _state;

      await _handleActions(actionsRaw);
      if (!mounted) return;
      setState(() => _state = nextState);
      await _renderInternal(rt);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _calling = false;
    }
  }

  Future<void> _handleActions(Object? actionsRaw) async {
    if (actionsRaw is! List || actionsRaw.isEmpty) return;
    for (final a in actionsRaw) {
      if (a is! Map) continue;
      final type = (a['type'] as String? ?? '').trim().toLowerCase();
      switch (type) {
        case 'toast':
          final message = (a['message'] as String? ?? '').trim();
          if (!mounted || message.isEmpty) continue;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          break;
        case 'navigate':
          final route = (a['route'] as String? ?? '').trim();
          final paramsRaw = a['params'];
          final params = paramsRaw is Map
              ? Map<String, Object?>.from(paramsRaw)
              : const <String, Object?>{};
          if (route.isEmpty) continue;
          await _navigateTo(route, params);
          break;
        default:
          break;
      }
    }
  }

  Future<void> _navigateTo(String route, Map<String, Object?> params) async {
    if (!mounted) return;
    if (!route.startsWith('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('不支持的路由：$route')),
      );
      return;
    }

    final manager = PluginManagerV1.instance;
    final target = currentPluginTarget();

    final installed = await manager.listInstalled();
    if (!mounted) return;
    final candidates = <InstalledPluginV1>[
      widget.plugin,
      ...installed.where((p) => p.id != widget.plugin.id),
    ];

    for (final p in candidates) {
      if (!p.enabled) continue;
      PluginManifestV1 manifest;
      if (p.id == widget.plugin.id && p.version == widget.plugin.version) {
        manifest = widget.manifest;
      } else {
        try {
          manifest = await manager.loadManifest(p);
        } catch (_) {
          continue;
        }
      }
      PluginPageContributionV1? page;
      for (final pg in manifest.contributions.pages) {
        if (pg.route == route && pg.targets.contains(target)) {
          page = pg;
          break;
        }
      }
      if (page == null) continue;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PluginPageHostPage(
            appState: widget.appState,
            plugin: p,
            manifest: manifest,
            page: page!,
            params: params,
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('找不到路由：$route')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 32,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          _error!,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    final rt = _runtime;
    final body = PluginSchemaRenderer(
      schema: _schema,
      onEvent: _onEvent,
      scrollable: false,
    );
    if (rt == null) return body;

    return Stack(
      children: [
        IgnorePointer(
          child: SizedBox(
            width: 1,
            height: 1,
            child: Opacity(
              opacity: 0,
              child: rt.buildView(),
            ),
          ),
        ),
        body,
      ],
    );
  }
}

List<Widget> _withGap(
  List<Widget> children,
  double gap, {
  required Axis axis,
}) {
  if (gap <= 0 || children.length <= 1) return children;
  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) {
      out.add(axis == Axis.horizontal
          ? SizedBox(width: gap)
          : SizedBox(height: gap));
    }
    out.add(children[i]);
  }
  return out;
}
