import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/plugins/plugin_manager.dart';
import '../services/plugins/plugin_runtime_v1.dart';
import 'plugin_schema_renderer.dart';

class PluginPageHostPage extends StatefulWidget {
  const PluginPageHostPage({
    super.key,
    required this.appState,
    required this.plugin,
    required this.manifest,
    required this.page,
    this.params = const {},
  });

  final AppState appState;
  final InstalledPluginV1 plugin;
  final PluginManifestV1 manifest;
  final PluginPageContributionV1 page;
  final Map<String, Object?> params;

  @override
  State<PluginPageHostPage> createState() => _PluginPageHostPageState();
}

class _PluginPageHostPageState extends State<PluginPageHostPage> {
  PluginRuntimeV1? _runtime;

  bool _loading = true;
  String? _error;

  String? _pageTitle;
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
    try {
      final rt = PluginRuntimeV1(plugin: widget.plugin, manifest: widget.manifest);
      await rt.init();
      if (!mounted) {
        await rt.dispose();
        return;
      }
      setState(() => _runtime = rt);
      await _render();
    } catch (e) {
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
    final res = await rt.call(widget.page.render, [widget.params, _state]);
    if (!mounted) return;
    if (res is! Map) {
      setState(() => _error = 'render 返回格式错误（不是对象）');
      return;
    }
    final title = (res['title'] as String? ?? '').trim();
    final stateRaw = res['state'];
    final schema = res['schema'];
    final state = stateRaw is Map ? Map<String, Object?>.from(stateRaw) : _state;
    setState(() {
      _pageTitle = title.isEmpty ? null : title;
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
      final res = await rt.call(widget.page.onEvent, [event, _state]);
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          break;
        case 'navigate':
          final route = (a['route'] as String? ?? '').trim();
          final paramsRaw = a['params'];
          final params =
              paramsRaw is Map ? Map<String, Object?>.from(paramsRaw) : const <String, Object?>{};
          if (route.isEmpty) continue;
          await _navigateTo(route, params);
          break;
        default:
          // Ignore unsupported actions.
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
    final isTv = DeviceType.isTv;
    final blurAllowed = !isTv;
    final enableBlur = blurAllowed && widget.appState.enableBlurEffects;

    final title = _pageTitle ?? widget.page.title;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null
            ? Center(child: Text(_error!))
            : PluginSchemaRenderer(
                schema: _schema,
                onEvent: _onEvent,
              ));

    final rt = _runtime;

    return Scaffold(
      appBar: GlassAppBar(
        enableBlur: enableBlur,
        child: AppBar(
          title: Text(title),
          centerTitle: true,
        ),
      ),
      body: Stack(
        children: [
          if (rt != null) ...[
            IgnorePointer(
              child: SizedBox(
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: WebViewWidget(controller: rt.controller),
                ),
              ),
            ),
          ],
          Positioned.fill(child: body),
        ],
      ),
    );
  }
}
