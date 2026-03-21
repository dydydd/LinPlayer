import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import '../services/plugins/plugin_manager.dart';
import '../services/plugins/plugin_runtime_v1.dart';
import 'plugin_host_actions.dart';
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
    PluginManagerV1.revision.addListener(_onManagerRevision);
    unawaited(_init());
  }

  @override
  void dispose() {
    PluginManagerV1.revision.removeListener(_onManagerRevision);
    final rt = _runtime;
    _runtime = null;
    unawaited(rt?.dispose());
    super.dispose();
  }

  void _onManagerRevision() {
    unawaited(_refreshPluginAvailability());
  }

  Future<void> _refreshPluginAvailability() async {
    final installed = await PluginManagerV1.instance.listInstalled();
    if (!mounted) return;
    final available = installed.any(
      (p) =>
          p.id == widget.plugin.id &&
          p.version == widget.plugin.version &&
          p.enabled,
    );
    if (available) return;
    final rt = _runtime;
    _runtime = null;
    unawaited(rt?.dispose());
    setState(() {
      _schema = null;
      _error = '插件已被禁用或卸载';
      _loading = false;
    });
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
    final res = await rt.call(widget.page.render, [widget.params, _state]);
    if (!mounted) return;
    if (res is! Map) {
      setState(() => _error = 'render 返回格式错误（不是对象）');
      return;
    }
    final title = (res['title'] as String? ?? '').trim();
    final stateRaw = res['state'];
    final schema = res['schema'];
    final state =
        stateRaw is Map ? Map<String, Object?>.from(stateRaw) : _state;
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
    await executePluginActionsV1(
      context,
      appState: widget.appState,
      plugin: widget.plugin,
      manifest: widget.manifest,
      actionsRaw: actionsRaw,
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
                allowWebView: true,
                allowedWebViewDomains: widget.manifest.permissions.network.domains,
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
                  child: rt.buildView(),
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
