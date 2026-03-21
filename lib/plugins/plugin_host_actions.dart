import 'package:flutter/material.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../services/plugins/plugin_manager.dart';
import 'plugin_page_host_page.dart';

Future<void> executePluginActionsV1(
  BuildContext context, {
  required AppState appState,
  required InstalledPluginV1 plugin,
  required PluginManifestV1 manifest,
  required Object? actionsRaw,
}) async {
  if (actionsRaw is! List || actionsRaw.isEmpty) return;

  for (final action in actionsRaw) {
    if (action is! Map) continue;
    try {
      final type = (action['type'] as String? ?? '').trim().toLowerCase();
      switch (type) {
        case 'toast':
          final message = (action['message'] as String? ?? '').trim();
          if (!context.mounted || message.isEmpty) continue;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          break;
        case 'navigate':
          final route = (action['route'] as String? ?? '').trim();
          final params = _readObjectMap(action['params']);
          if (!context.mounted || route.isEmpty) continue;
          await _navigateToPluginRoute(
            context,
            appState: appState,
            currentPlugin: plugin,
            currentManifest: manifest,
            route: route,
            params: params,
          );
          break;
        case 'openurl':
          final url = (action['url'] as String? ?? '').trim();
          if (!context.mounted || url.isEmpty) continue;
          await _openExternalUrl(context, url);
          break;
        default:
          break;
      }
    } catch (_) {
      // Action failure must not crash plugin rendering or interaction.
    }
  }
}

Map<String, Object?> _readObjectMap(Object? raw) {
  if (raw is Map) return Map<String, Object?>.from(raw);
  return const <String, Object?>{};
}

Future<void> _navigateToPluginRoute(
  BuildContext context, {
  required AppState appState,
  required InstalledPluginV1 currentPlugin,
  required PluginManifestV1 currentManifest,
  required String route,
  required Map<String, Object?> params,
}) async {
  if (!route.startsWith('/plugin/')) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('不支持的插件路由：$route')),
    );
    return;
  }

  final manager = PluginManagerV1.instance;
  final target = currentPluginTarget();
  final installed = await manager.listInstalled();
  if (!context.mounted) return;

  final candidates = <InstalledPluginV1>[
    currentPlugin,
    ...installed.where((p) => p.id != currentPlugin.id),
  ];

  for (final plugin in candidates) {
    if (!plugin.enabled) continue;
    PluginManifestV1 candidateManifest;
    if (plugin.id == currentPlugin.id && plugin.version == currentPlugin.version) {
      candidateManifest = currentManifest;
    } else {
      try {
        candidateManifest = await manager.loadManifest(plugin);
      } catch (_) {
        continue;
      }
    }

    for (final page in candidateManifest.contributions.pages) {
      if (page.route != route || !page.targets.contains(target)) continue;
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PluginPageHostPage(
            appState: appState,
            plugin: plugin,
            manifest: candidateManifest,
            page: page,
            params: params,
          ),
        ),
      );
      return;
    }
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('找不到插件路由：$route')),
  );
}

Future<void> _openExternalUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null ||
      !uri.isAbsolute ||
      (scheme != 'http' && scheme != 'https')) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('不支持的外链：$url')),
    );
    return;
  }

  final opened = await launchUrlString(url);
  if (!context.mounted || opened) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('无法打开链接，请检查系统浏览器/网络设置')),
  );
}
