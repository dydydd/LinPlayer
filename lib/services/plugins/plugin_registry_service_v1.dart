import 'dart:convert';

import 'package:http/http.dart' as http;

import 'plugin_manager.dart';
import 'plugin_remote_url_v1.dart';

class PluginRegistryEntryV1 {
  const PluginRegistryEntryV1({
    required this.registryUrl,
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.manifestUrl,
    required this.targets,
    required this.iconUrl,
  });

  final String registryUrl;
  final String id;
  final String name;
  final String description;
  final String version;
  final String manifestUrl;
  final Set<PluginTarget> targets;
  final String? iconUrl;

  bool supportsTarget(PluginTarget target) =>
      targets.isEmpty || targets.contains(target);
}

class PluginRegistryServiceV1 {
  PluginRegistryServiceV1._();

  static final PluginRegistryServiceV1 instance = PluginRegistryServiceV1._();

  Future<List<PluginRegistryEntryV1>> fetchRegistryFromUrl(
    String registryUrl,
  ) async {
    final uri = _parseAbsoluteUrl(
      registryUrl,
      error: 'registry.json 下载链接不是合法 URL',
    );
    final client = http.Client();
    try {
      final bytes = await _downloadBytes(client, uri);
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        throw PluginInstallException('registry.json 格式错误，链接可能不是原始 JSON 文件');
      }
      final parsed = _parseRegistryEntries(decoded, registryUri: uri);
      if (parsed.isEmpty) {
        throw PluginInstallException('registry.json 未发现可安装插件');
      }
      final deduped = <String, PluginRegistryEntryV1>{};
      for (final entry in parsed) {
        final current = deduped[entry.id];
        if (current == null ||
            comparePluginSemVerV1(entry.version, current.version) > 0) {
          deduped[entry.id] = entry;
        }
      }
      final entries = deduped.values.toList(growable: false)
        ..sort((a, b) {
          final byName = _displayNameOf(a)
              .toLowerCase()
              .compareTo(_displayNameOf(b).toLowerCase());
          if (byName != 0) return byName;
          return a.id.compareTo(b.id);
        });
      return entries;
    } finally {
      client.close();
    }
  }

  Future<PluginRegistryEntryV1?> checkUpdate(InstalledPluginV1 plugin) async {
    Uri manifestUri;
    try {
      manifestUri = Uri.parse(plugin.manifestUrl);
    } catch (_) {
      return null;
    }
    final registryUri = _deriveRegistryUrl(manifestUri);
    if (registryUri == null) return null;
    final entries = await fetchRegistryFromUrl(registryUri.toString());
    final target = currentPluginTarget();
    for (final entry in entries) {
      if (entry.id != plugin.id) continue;
      if (!entry.supportsTarget(target)) continue;
      if (comparePluginSemVerV1(entry.version, plugin.version) <= 0) {
        return null;
      }
      return entry;
    }
    return null;
  }
}

String _displayNameOf(PluginRegistryEntryV1 entry) {
  final name = entry.name.trim();
  return name.isEmpty ? entry.id : name;
}

List<PluginRegistryEntryV1> _parseRegistryEntries(
  Object? raw, {
  required Uri registryUri,
}) {
  final out = <PluginRegistryEntryV1>[];

  void addParsed(Object? candidate, {String? forcedId}) {
    final parsed = _parseRegistryEntry(
      candidate,
      registryUri: registryUri,
      forcedId: forcedId,
    );
    if (parsed != null) out.add(parsed);
  }

  if (raw is List) {
    for (final item in raw) {
      addParsed(item);
    }
    return out;
  }

  if (raw is! Map) return out;

  final containers = <Object?>[
    raw['plugins'],
    raw['items'],
    raw['entries'],
    raw['registry'],
    raw['data'],
  ];
  for (final container in containers) {
    if (container is List) {
      for (final item in container) {
        addParsed(item);
      }
      if (out.isNotEmpty) return out;
    } else if (container is Map) {
      for (final entry in container.entries) {
        final id = entry.key is String ? (entry.key as String).trim() : '';
        addParsed(entry.value, forcedId: id.isEmpty ? null : id);
      }
      if (out.isNotEmpty) return out;
    }
  }

  for (final entry in raw.entries) {
    final id = entry.key is String ? (entry.key as String).trim() : '';
    if (id.isEmpty) continue;
    addParsed(entry.value, forcedId: id);
  }
  return out;
}

PluginRegistryEntryV1? _parseRegistryEntry(
  Object? raw, {
  required Uri registryUri,
  String? forcedId,
}) {
  if (raw is! Map) return null;
  final id =
      (forcedId ?? _readString(raw['id']) ?? _readString(raw['pluginId']) ?? '')
          .trim();
  if (id.isEmpty) return null;

  final name = (_readString(raw['name']) ??
          _readString(raw['title']) ??
          _readString(raw['displayName']) ??
          '')
      .trim();
  final description = (_readString(raw['description']) ??
          _readString(raw['summary']) ??
          _readString(raw['subtitle']) ??
          '')
      .trim();
  final baseTargets = _parseTargets(raw['targets'] ?? raw['platforms']);
  final registryRoot = _registryRootUri(registryUri);

  String version = '';
  String manifestUrl = '';
  Set<PluginTarget> targets = baseTargets;

  final versionsRaw = raw['versions'];
  if (versionsRaw is List) {
    for (final item in versionsRaw) {
      final info = _parseRegistryVersionInfo(
        item,
        pluginId: id,
        registryRoot: registryRoot,
        inheritedTargets: baseTargets,
      );
      if (info == null) continue;
      if (version.isEmpty || comparePluginSemVerV1(info.version, version) > 0) {
        version = info.version;
        manifestUrl = info.manifestUrl;
        targets = info.targets;
      }
    }
  }

  if (version.isEmpty || manifestUrl.isEmpty) {
    final latestInfo = _parseRegistryVersionInfo(
      raw['latest'] ?? raw['current'] ?? raw,
      pluginId: id,
      registryRoot: registryRoot,
      inheritedTargets: baseTargets,
    );
    if (latestInfo != null) {
      version = latestInfo.version;
      manifestUrl = latestInfo.manifestUrl;
      targets = latestInfo.targets;
    }
  }

  if (version.isEmpty || manifestUrl.isEmpty) return null;

  String? iconUrl;
  final iconRaw =
      (_readString(raw['icon']) ?? _readString(raw['iconUrl']) ?? '').trim();
  if (iconRaw.isNotEmpty) {
    iconUrl = _resolveUrl(registryRoot, iconRaw);
  }

  return PluginRegistryEntryV1(
    registryUrl: registryUri.toString(),
    id: id,
    name: name,
    description: description,
    version: version,
    manifestUrl: manifestUrl,
    targets: targets,
    iconUrl: iconUrl,
  );
}

_RegistryVersionInfo? _parseRegistryVersionInfo(
  Object? raw, {
  required String pluginId,
  required Uri registryRoot,
  required Set<PluginTarget> inheritedTargets,
}) {
  if (raw is String) {
    final version = raw.trim();
    if (_isEmptyOrInvalidVersion(version)) return null;
    return _RegistryVersionInfo(
      version: version,
      manifestUrl: registryRoot
          .resolve('plugins/$pluginId/$version/manifest.json')
          .toString(),
      targets: inheritedTargets,
    );
  }
  if (raw is! Map) return null;

  final version = (_readString(raw['latestVersion']) ??
          _readString(raw['version']) ??
          _readString(raw['name']) ??
          '')
      .trim();
  if (_isEmptyOrInvalidVersion(version)) return null;

  final manifestRaw = (_readUrlLike(raw['manifestUrl']) ??
          _readUrlLike(raw['manifest']) ??
          _readUrlLike(raw['url']) ??
          _readUrlLike(raw['path']) ??
          '')
      .trim();
  final manifestUrl = manifestRaw.isEmpty
      ? registryRoot
          .resolve('plugins/$pluginId/$version/manifest.json')
          .toString()
      : _resolveUrl(registryRoot, manifestRaw);
  final targets = _parseTargets(raw['targets'] ?? raw['platforms']);

  return _RegistryVersionInfo(
    version: version,
    manifestUrl: manifestUrl,
    targets: targets.isEmpty ? inheritedTargets : targets,
  );
}

bool _isEmptyOrInvalidVersion(String version) {
  return version.trim().isEmpty || !isPluginSemVerV1(version.trim());
}

Set<PluginTarget> _parseTargets(Object? raw) {
  if (raw is! List) return const <PluginTarget>{};
  final targets = <PluginTarget>{};
  for (final value in raw) {
    final v = (value as String? ?? '').trim().toLowerCase();
    switch (v) {
      case 'tv':
        targets.add(PluginTarget.tv);
      case 'mobile':
        targets.add(PluginTarget.mobile);
      case 'pc':
        targets.add(PluginTarget.pc);
    }
  }
  return targets;
}

String _resolveUrl(Uri baseUri, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  final uri = Uri.tryParse(value);
  if (uri != null && uri.isAbsolute) return uri.toString();
  return baseUri.resolve(value).toString();
}

Uri _parseAbsoluteUrl(
  String raw, {
  required String error,
}) {
  Uri uri;
  try {
    uri = Uri.parse(raw.trim());
  } catch (_) {
    throw PluginInstallException(error);
  }
  if (!uri.isAbsolute) {
    throw PluginInstallException(error);
  }
  return normalizePluginRemoteUriV1(uri);
}

Uri? _deriveRegistryUrl(Uri manifestUrl) {
  final seg = manifestUrl.pathSegments;
  final idx = seg.indexOf('plugins');
  if (idx < 0) return null;
  final rootSeg = seg.take(idx).toList(growable: false);
  return manifestUrl.replace(pathSegments: [...rootSeg, 'registry.json']);
}

Uri _registryRootUri(Uri registryUri) {
  final seg = registryUri.pathSegments.toList(growable: false);
  if (seg.isEmpty) return registryUri;
  return registryUri.replace(pathSegments: seg.sublist(0, seg.length - 1));
}

Future<List<int>> _downloadBytes(http.Client client, Uri url) async {
  http.Response res;
  try {
    res = await client.get(url);
  } catch (e) {
    throw PluginInstallException('下载失败：$e');
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw PluginInstallException(
      '下载失败：HTTP ${res.statusCode} (${url.toString()})',
    );
  }
  return res.bodyBytes;
}

String? _readString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _readUrlLike(Object? value) {
  if (value is Map) {
    return _readString(value['url']) ??
        _readString(value['manifestUrl']) ??
        _readString(value['path']);
  }
  return _readString(value);
}

class _RegistryVersionInfo {
  const _RegistryVersionInfo({
    required this.version,
    required this.manifestUrl,
    required this.targets,
  });

  final String version;
  final String manifestUrl;
  final Set<PluginTarget> targets;
}
