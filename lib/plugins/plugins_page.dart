import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import '../services/plugins/plugin_manager.dart';
import '../services/plugins/plugin_runtime_v1.dart';
import '../tv/tv_focusable.dart';
import 'plugin_page_host_page.dart';

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  final _manager = PluginManagerV1.instance;

  bool _loading = true;
  String? _error;
  List<InstalledPluginV1> _installed = const [];
  final Map<String, PluginManifestV1> _manifestsById = {};

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final installed = await _manager.listInstalled();
      final manifests = <String, PluginManifestV1>{};
      for (final p in installed) {
        try {
          manifests[p.id] = await _manager.loadManifest(p);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _manifestsById
          ..clear()
          ..addAll(manifests);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<T> _runWithBlockingDialog<T>(
    BuildContext context,
    Future<T> Function() action, {
    required String title,
    String subtitle = '请稍候…',
  }) async {
    final nav = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(subtitle)),
          ],
        ),
      ),
    );
    try {
      return await action();
    } finally {
      if (context.mounted) nav.pop();
    }
  }

  Future<void> _installByUrl(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final url = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('安装插件'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请输入插件 manifest.json 下载链接。'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText:
                      'https://raw.githubusercontent.com/<owner>/<repo>/<ref>/plugins/<pluginId>/<version>/manifest.json',
                ),
                keyboardType: TextInputType.url,
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(controller.text),
              child: const Text('下载并安装'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      final trimmed = (url ?? '').trim();
      if (trimmed.isEmpty) return;

      final installed = await _runWithBlockingDialog(
        context,
        () => _manager.installFromManifestUrl(trimmed),
        title: '正在安装插件',
      );

      if (!context.mounted) return;
      PluginManifestV1? manifest;
      try {
        manifest = await _manager.loadManifest(installed);
      } catch (_) {}
      if (!context.mounted) return;
      final displayName = manifest?.name ?? installed.id;
      final runtimeSupported = pluginRuntimeSupportedV1();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装成功：$displayName (${installed.version})')),
      );
      if (!runtimeSupported) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('注意：当前平台暂不支持脚本插件运行（需要 WebView 支持）')),
        );
      }
      await _reload();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装失败：$e')),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _confirmUninstall(
      BuildContext context, InstalledPluginV1 plugin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确定卸载 ${plugin.id}（${plugin.version}）？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (confirmed != true) return;
    try {
      await _runWithBlockingDialog(
        context,
        () => _manager.uninstall(plugin.id),
        title: '正在卸载插件',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已卸载：${plugin.id}')),
      );
      await _reload();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('卸载失败：$e')),
      );
    }
  }

  Future<void> _openPluginPages(
    BuildContext context,
    InstalledPluginV1 plugin,
  ) async {
    if (!pluginRuntimeSupportedV1()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台暂不支持脚本插件运行（需要 WebView 支持）')),
      );
      return;
    }
    if (!plugin.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先启用该插件')),
      );
      return;
    }
    PluginManifestV1? manifest = _manifestsById[plugin.id];
    manifest ??= await _manager.loadManifest(plugin);
    if (!context.mounted) return;
    final target = currentPluginTarget();
    final pages = manifest.contributions.pages
        .where((p) => p.targets.contains(target))
        .toList();
    if (pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该插件没有可用页面')),
      );
      return;
    }
    PluginPageContributionV1 page;
    if (pages.length == 1) {
      page = pages.first;
    } else {
      final selected = await showDialog<PluginPageContributionV1>(
        context: context,
        builder: (dctx) => SimpleDialog(
          title: const Text('选择页面'),
          children: pages
              .map(
                (p) => SimpleDialogOption(
                  onPressed: () => Navigator.of(dctx).pop(p),
                  child: Text(p.title),
                ),
              )
              .toList(growable: false),
        ),
      );
      if (!context.mounted || selected == null) return;
      page = selected;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PluginPageHostPage(
          appState: widget.appState,
          plugin: plugin,
          manifest: manifest!,
          page: page,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTv = DeviceType.isTv;
    final blurAllowed = !isTv;
    final enableBlur = blurAllowed && widget.appState.enableBlurEffects;

    Widget tvFocusRow(Widget child) {
      if (!isTv) return child;
      final scheme = Theme.of(context).colorScheme;
      final isDark = scheme.brightness == Brightness.dark;
      final uiScale = context.uiScale;
      final radius = (18 * uiScale).clamp(14.0, 22.0);
      return TvFocusFrame(
        borderRadius: BorderRadius.circular(radius),
        surfaceColor: Colors.transparent,
        focusedSurfaceColor:
            scheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
        borderColor: Colors.transparent,
        focusedBorderColor: scheme.primary,
        padding: EdgeInsets.zero,
        focusScale: 1.03,
        child: child,
      );
    }

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null
            ? Center(child: Text(_error!))
            : (_installed.isEmpty
                ? const Center(child: Text('暂无已安装插件'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _installed.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final p = _installed[index];
                      final m = _manifestsById[p.id];
                      final title = m?.name ?? p.id;
                      final desc = (m?.description ?? '').trim();
                      return Card(
                        child: Column(
                          children: [
                            tvFocusRow(
                              SwitchListTile(
                                value: p.enabled,
                                onChanged: (v) async {
                                  await _manager.setEnabled(p.id, v);
                                  await _reload();
                                },
                                title: Text(title),
                                subtitle: Text(
                                  '${p.id}  ·  ${p.version}${desc.isEmpty ? '' : '\n$desc'}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                secondary: const Icon(Icons.extension_outlined),
                              ),
                            ),
                            const Divider(height: 1),
                            Row(
                              children: [
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () =>
                                      _confirmUninstall(context, p),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('卸载'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openPluginPages(context, p),
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('打开'),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _reload,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('刷新'),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  )));

    return Scaffold(
      appBar: GlassAppBar(
        enableBlur: enableBlur,
        child: AppBar(
          title: const Text('插件'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '安装插件',
              onPressed: () => _installByUrl(context),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      body: body,
    );
  }
}
