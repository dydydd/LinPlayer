import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PluginTarget { tv, mobile, pc }

PluginTarget currentPluginTarget() {
  if (DeviceType.isTv) return PluginTarget.tv;
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    return PluginTarget.pc;
  }
  return PluginTarget.mobile;
}

class PluginInstallException implements Exception {
  PluginInstallException(this.message);

  final String message;

  @override
  String toString() => 'PluginInstallException: $message';
}

class PluginFileEntryV1 {
  PluginFileEntryV1({
    required this.path,
    required this.size,
    required this.sha256,
  });

  factory PluginFileEntryV1.fromJson(Object? json) {
    if (json is! Map) {
      throw PluginInstallException('manifest.files[] 格式错误（不是对象）');
    }
    final path = (json['path'] as String? ?? '').trim();
    final size = json['size'];
    final sha256 = (json['sha256'] as String? ?? '').trim().toLowerCase();
    if (path.isEmpty) throw PluginInstallException('manifest.files[].path 不能为空');
    if (size is! int || size < 0) {
      throw PluginInstallException('manifest.files[].size 格式错误');
    }
    final sha256Re = RegExp(r'^[a-f0-9]{64}$');
    if (!sha256Re.hasMatch(sha256)) {
      throw PluginInstallException('manifest.files[].sha256 格式错误（需 64 位小写十六进制）');
    }
    _validateRelativePath(path);
    return PluginFileEntryV1(path: path, size: size, sha256: sha256);
  }

  final String path;
  final int size;
  final String sha256;
}

class PluginNetworkPermissionV1 {
  PluginNetworkPermissionV1({required this.enabled, required this.domains});

  factory PluginNetworkPermissionV1.fromJson(Object? json) {
    if (json is! Map) {
      throw PluginInstallException('manifest.permissions.network 格式错误（不是对象）');
    }
    final enabled = json['enabled'] as bool? ?? false;
    final domainsRaw = json['domains'];
    final domains = <String>[];
    if (domainsRaw is List) {
      for (final v in domainsRaw) {
        final d = (v as String? ?? '').trim();
        if (d.isNotEmpty) domains.add(d);
      }
    }
    return PluginNetworkPermissionV1(enabled: enabled, domains: domains);
  }

  final bool enabled;
  final List<String> domains;
}

class PluginPermissionsV1 {
  PluginPermissionsV1({required this.network});

  factory PluginPermissionsV1.fromJson(Object? json) {
    if (json is! Map) {
      throw PluginInstallException('manifest.permissions 格式错误（不是对象）');
    }
    final network = PluginNetworkPermissionV1.fromJson(json['network']);
    if (!network.enabled) {
      throw PluginInstallException('插件未声明 network.enabled=true（v1 必需）');
    }
    return PluginPermissionsV1(network: network);
  }

  final PluginNetworkPermissionV1 network;
}

class PluginEntryTargetV1 {
  PluginEntryTargetV1({required this.script});

  factory PluginEntryTargetV1.fromJson(Object? json) {
    if (json is! Map) {
      throw PluginInstallException('manifest.entry.<target> 格式错误（不是对象）');
    }
    final script = (json['script'] as String? ?? '').trim();
    if (script.isEmpty) throw PluginInstallException('manifest.entry.<target>.script 不能为空');
    _validateRelativePath(script);
    return PluginEntryTargetV1(script: script);
  }

  final String script;
}

class PluginEntryV1 {
  PluginEntryV1({required this.tv, required this.mobile, required this.pc});

  factory PluginEntryV1.fromJson(Object? json, Set<PluginTarget> targets) {
    if (json is! Map) throw PluginInstallException('manifest.entry 格式错误（不是对象）');
    PluginEntryTargetV1? tv;
    PluginEntryTargetV1? mobile;
    PluginEntryTargetV1? pc;
    if (targets.contains(PluginTarget.tv)) tv = PluginEntryTargetV1.fromJson(json['tv']);
    if (targets.contains(PluginTarget.mobile)) {
      mobile = PluginEntryTargetV1.fromJson(json['mobile']);
    }
    if (targets.contains(PluginTarget.pc)) pc = PluginEntryTargetV1.fromJson(json['pc']);
    return PluginEntryV1(tv: tv, mobile: mobile, pc: pc);
  }

  final PluginEntryTargetV1? tv;
  final PluginEntryTargetV1? mobile;
  final PluginEntryTargetV1? pc;

  PluginEntryTargetV1 entryForTarget(PluginTarget target) {
    final v = switch (target) {
      PluginTarget.tv => tv,
      PluginTarget.mobile => mobile,
      PluginTarget.pc => pc,
    };
    if (v == null) {
      throw PluginInstallException('插件不支持当前端：${target.name}');
    }
    return v;
  }
}

class PluginPageContributionV1 {
  PluginPageContributionV1({
    required this.id,
    required this.title,
    required this.route,
    required this.targets,
    required this.render,
    required this.onEvent,
  });

  factory PluginPageContributionV1.fromJson(
    Object? json, {
    required Set<PluginTarget> defaultTargets,
  }) {
    if (json is! Map) {
      throw PluginInstallException('manifest.contributions.pages[] 格式错误（不是对象）');
    }
    final id = (json['id'] as String? ?? '').trim();
    final title = (json['title'] as String? ?? '').trim();
    final route = (json['route'] as String? ?? '').trim();
    final render = (json['render'] as String? ?? '').trim();
    final onEvent = (json['onEvent'] as String? ?? '').trim();
    if (id.isEmpty) throw PluginInstallException('manifest.contributions.pages[].id 不能为空');
    if (title.isEmpty) throw PluginInstallException('manifest.contributions.pages[].title 不能为空');
    if (route.isEmpty) throw PluginInstallException('manifest.contributions.pages[].route 不能为空');
    if (!route.startsWith('/')) {
      throw PluginInstallException('manifest.contributions.pages[].route 必须以 / 开头');
    }
    if (render.isEmpty) throw PluginInstallException('manifest.contributions.pages[].render 不能为空');
    if (onEvent.isEmpty) throw PluginInstallException('manifest.contributions.pages[].onEvent 不能为空');

    final targetsRaw = json['targets'];
    final targets = <PluginTarget>{};
    if (targetsRaw == null) {
      // Fall back to manifest targets.
    } else if (targetsRaw is List) {
      for (final v in targetsRaw) {
        final s = (v as String? ?? '').trim().toLowerCase();
        switch (s) {
          case 'tv':
            targets.add(PluginTarget.tv);
          case 'mobile':
            targets.add(PluginTarget.mobile);
          case 'pc':
            targets.add(PluginTarget.pc);
        }
      }
      if (targets.isEmpty) {
        throw PluginInstallException('manifest.contributions.pages[].targets 格式错误');
      }
    } else {
      throw PluginInstallException('manifest.contributions.pages[].targets 格式错误（不是数组）');
    }
    final effectiveTargets = targets.isEmpty ? defaultTargets : targets;
    if (effectiveTargets.isEmpty) {
      throw PluginInstallException('manifest.contributions.pages[].targets 不能为空');
    }
    if (effectiveTargets.any((t) => !defaultTargets.contains(t))) {
      throw PluginInstallException(
        'manifest.contributions.pages[].targets 必须是 manifest.targets 的子集',
      );
    }

    return PluginPageContributionV1(
      id: id,
      title: title,
      route: route,
      targets: effectiveTargets,
      render: render,
      onEvent: onEvent,
    );
  }

  final String id;
  final String title;
  final String route;
  final Set<PluginTarget> targets;
  final String render;
  final String onEvent;
}

class PluginContributionsV1 {
  PluginContributionsV1({required this.pages});

  factory PluginContributionsV1.fromJson(
    Object? json, {
    required Set<PluginTarget> defaultTargets,
  }) {
    if (json is! Map) return PluginContributionsV1(pages: const []);
    final pagesRaw = json['pages'];
    if (pagesRaw is! List || pagesRaw.isEmpty) {
      return PluginContributionsV1(pages: const []);
    }
    final pages = pagesRaw
        .map((e) => PluginPageContributionV1.fromJson(e, defaultTargets: defaultTargets))
        .toList(growable: false);
    return PluginContributionsV1(pages: pages);
  }

  final List<PluginPageContributionV1> pages;
}

class PluginManifestV1 {
  PluginManifestV1({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.apiVersion,
    required this.minHostVersion,
    required this.targets,
    required this.entry,
    required this.permissions,
    required this.files,
    required this.contributions,
    required this.raw,
  });

  factory PluginManifestV1.fromBytes(List<int> bytes) {
    final rawText = utf8.decode(bytes);
    final decoded = jsonDecode(rawText);
    if (decoded is! Map) {
      throw PluginInstallException('manifest.json 顶层格式错误（不是对象）');
    }
    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != 1) {
      throw PluginInstallException('仅支持 schemaVersion=1');
    }
    final apiVersion = decoded['apiVersion'];
    if (apiVersion is! int || apiVersion != 1) {
      throw PluginInstallException('仅支持 apiVersion=1');
    }
    final id = (decoded['id'] as String? ?? '').trim();
    final name = (decoded['name'] as String? ?? '').trim();
    final description = (decoded['description'] as String? ?? '').trim();
    final version = (decoded['version'] as String? ?? '').trim();
    final minHostVersion = (decoded['minHostVersion'] as String? ?? '').trim();
    if (!_validPluginId(id)) {
      throw PluginInstallException('manifest.id 格式错误（建议反向域名，如 com.example.plugin）');
    }
    if (name.isEmpty) throw PluginInstallException('manifest.name 不能为空');
    if (description.isEmpty) throw PluginInstallException('manifest.description 不能为空');
    if (!_SemVer.tryParse(version).isValid) {
      throw PluginInstallException('manifest.version 不是合法 SemVer：$version');
    }
    if (!_SemVer.tryParse(minHostVersion).isValid) {
      throw PluginInstallException('manifest.minHostVersion 不是合法 SemVer：$minHostVersion');
    }

    final targetsRaw = decoded['targets'];
    if (targetsRaw is! List) {
      throw PluginInstallException('manifest.targets 格式错误（不是数组）');
    }
    final targets = <PluginTarget>{};
    for (final v in targetsRaw) {
      final s = (v as String? ?? '').trim().toLowerCase();
      switch (s) {
        case 'tv':
          targets.add(PluginTarget.tv);
        case 'mobile':
          targets.add(PluginTarget.mobile);
        case 'pc':
          targets.add(PluginTarget.pc);
      }
    }
    if (targets.isEmpty) throw PluginInstallException('manifest.targets 不能为空');

    final entry = PluginEntryV1.fromJson(decoded['entry'], targets);
    final permissions = PluginPermissionsV1.fromJson(decoded['permissions']);

    final filesRaw = decoded['files'];
    if (filesRaw is! List || filesRaw.isEmpty) {
      throw PluginInstallException('manifest.files 不能为空');
    }
    final files = filesRaw.map(PluginFileEntryV1.fromJson).toList(growable: false);

    final contributions =
        PluginContributionsV1.fromJson(decoded['contributions'], defaultTargets: targets);

    return PluginManifestV1(
      schemaVersion: schemaVersion,
      id: id,
      name: name,
      description: description,
      version: version,
      apiVersion: apiVersion,
      minHostVersion: minHostVersion,
      targets: targets,
      entry: entry,
      permissions: permissions,
      files: files,
      contributions: contributions,
      raw: rawText,
    );
  }

  final int schemaVersion;
  final String id;
  final String name;
  final String description;
  final String version;
  final int apiVersion;
  final String minHostVersion;
  final Set<PluginTarget> targets;
  final PluginEntryV1 entry;
  final PluginPermissionsV1 permissions;
  final List<PluginFileEntryV1> files;
  final PluginContributionsV1 contributions;
  final String raw;
}

class InstalledPluginV1 {
  InstalledPluginV1({
    required this.id,
    required this.version,
    required this.manifestUrl,
    required this.enabled,
    required this.installedAtMs,
  });

  factory InstalledPluginV1.fromJson(Object? json) {
    if (json is! Map) {
      throw PluginInstallException('已安装插件数据损坏（不是对象）');
    }
    final id = (json['id'] as String? ?? '').trim();
    final version = (json['version'] as String? ?? '').trim();
    final manifestUrl = (json['manifestUrl'] as String? ?? '').trim();
    final enabled = json['enabled'] as bool? ?? true;
    final installedAtMs = json['installedAtMs'] as int? ?? 0;
    if (id.isEmpty || version.isEmpty || manifestUrl.isEmpty) {
      throw PluginInstallException('已安装插件数据损坏（字段缺失）');
    }
    return InstalledPluginV1(
      id: id,
      version: version,
      manifestUrl: manifestUrl,
      enabled: enabled,
      installedAtMs: installedAtMs,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        'manifestUrl': manifestUrl,
        'enabled': enabled,
        'installedAtMs': installedAtMs,
      };

  final String id;
  final String version;
  final String manifestUrl;
  final bool enabled;
  final int installedAtMs;
}

class PluginManagerV1 {
  PluginManagerV1._();

  static final PluginManagerV1 instance = PluginManagerV1._();

  static const _prefsKey = 'linplayer.plugins.installed.v1';

  Future<Directory> _rootDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/plugins_v1');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _pluginVersionDir(String id, String version) async {
    final root = await _rootDir();
    return Directory('${root.path}/$id/$version');
  }

  Future<Directory> pluginDir(InstalledPluginV1 plugin) async {
    return _pluginVersionDir(plugin.id, plugin.version);
  }

  Future<File> pluginFile(InstalledPluginV1 plugin, String relativePath) async {
    _validateRelativePath(relativePath);
    final dir = await pluginDir(plugin);
    return File('${dir.path}/${_toOsPath(relativePath)}');
  }

  Future<List<InstalledPluginV1>> listInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(InstalledPluginV1.fromJson).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveInstalled(List<InstalledPluginV1> plugins) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(plugins.map((e) => e.toJson()).toList(growable: false)),
    );
  }

  Future<PluginManifestV1> loadManifest(InstalledPluginV1 plugin) async {
    final dir = await _pluginVersionDir(plugin.id, plugin.version);
    final f = File('${dir.path}/manifest.json');
    if (!await f.exists()) {
      throw PluginInstallException('manifest.json 不存在（插件可能已损坏）');
    }
    final bytes = await f.readAsBytes();
    return PluginManifestV1.fromBytes(bytes);
  }

  Future<void> uninstall(String pluginId) async {
    final installed = await listInstalled();
    final toRemove = installed.where((e) => e.id == pluginId).toList();
    if (toRemove.isEmpty) return;

    for (final p in toRemove) {
      final dir = await _pluginVersionDir(p.id, p.version);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    final next = installed.where((e) => e.id != pluginId).toList(growable: false);
    await _saveInstalled(next);
  }

  Future<void> setEnabled(String pluginId, bool enabled) async {
    final installed = await listInstalled();
    var changed = false;
    final next = installed.map((p) {
      if (p.id != pluginId) return p;
      if (p.enabled == enabled) return p;
      changed = true;
      return InstalledPluginV1(
        id: p.id,
        version: p.version,
        manifestUrl: p.manifestUrl,
        enabled: enabled,
        installedAtMs: p.installedAtMs,
      );
    }).toList(growable: false);
    if (!changed) return;
    await _saveInstalled(next);
  }

  Future<InstalledPluginV1> installFromManifestUrl(String manifestUrl) async {
    final url = manifestUrl.trim();
    if (url.isEmpty) throw PluginInstallException('下载链接不能为空');
    Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      throw PluginInstallException('下载链接不是合法 URL');
    }
    if (!uri.isAbsolute) throw PluginInstallException('下载链接必须是绝对 URL');

    final client = http.Client();
    try {
      final manifestBytes = await _downloadBytes(client, uri);
      final manifest = PluginManifestV1.fromBytes(manifestBytes);

      final target = currentPluginTarget();
      if (!manifest.targets.contains(target)) {
        throw PluginInstallException('插件不支持当前端：${target.name}');
      }

      // Host version compatibility.
      final hostVersion = await _hostVersion();
      final minHost = _SemVer.tryParse(manifest.minHostVersion);
      if (minHost.isValid && minHost.compareTo(hostVersion) > 0) {
        throw PluginInstallException(
          '宿主版本过低：当前 ${hostVersion.raw}，插件要求 >= ${manifest.minHostVersion}',
        );
      }

      // Optional kill switch: blocked.json at repo root.
      final blockedUrl = _deriveBlockedUrl(uri);
      if (blockedUrl != null) {
        await _enforceBlockedList(client, blockedUrl, manifest, target);
      }

      final entryScriptPath = manifest.entry.entryForTarget(target).script;
      final entryInFiles = manifest.files.any((f) => f.path == entryScriptPath);
      if (!entryInFiles) {
        throw PluginInstallException('入口脚本未出现在 files[]：$entryScriptPath');
      }

      final manifestDir = _dirUri(uri);
      final root = await _rootDir();
      final tmpParent = Directory('${root.path}/.tmp');
      await tmpParent.create(recursive: true);
      final tempDir = await tmpParent
          .createTemp('install_${manifest.id}_${manifest.version}_');

      try {
        // 1) Save manifest.json
        await File('${tempDir.path}/manifest.json').writeAsBytes(manifestBytes);

        // 2) Download & verify all files
        for (final f in manifest.files) {
          final fileUrl = manifestDir.resolve(f.path);
          final bytes = await _downloadBytes(client, fileUrl);
          if (bytes.length != f.size) {
            throw PluginInstallException(
              '文件大小不匹配：${f.path}（期望 ${f.size}，实际 ${bytes.length}）',
            );
          }
          final digest = sha256.convert(bytes).toString();
          if (digest != f.sha256) {
            throw PluginInstallException('文件校验失败（sha256 不匹配）：${f.path}');
          }

          final out = File('${tempDir.path}/${_toOsPath(f.path)}');
          await out.parent.create(recursive: true);
          await out.writeAsBytes(bytes, flush: true);
        }

        // 3) Move into final dir
        final finalDir = await _pluginVersionDir(manifest.id, manifest.version);
        if (await finalDir.exists()) {
          await finalDir.delete(recursive: true);
        }
        await finalDir.parent.create(recursive: true);
        await tempDir.rename(finalDir.path);

        // 4) Update prefs (one version per id)
        final installed = await listInstalled();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final next = [
          ...installed.where((e) => e.id != manifest.id),
          InstalledPluginV1(
            id: manifest.id,
            version: manifest.version,
            manifestUrl: url,
            enabled: true,
            installedAtMs: nowMs,
          ),
        ];
        await _saveInstalled(next);

        // Cleanup older versions on disk
        await _cleanupOtherVersions(manifest.id, keepVersion: manifest.version);

        return next.last;
      } finally {
        if (await tempDir.exists()) {
          // If moved successfully, it no longer exists here; this is best-effort.
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  Future<void> _cleanupOtherVersions(
    String pluginId, {
    required String keepVersion,
  }) async {
    final root = await _rootDir();
    final pluginDir = Directory('${root.path}/$pluginId');
    if (!await pluginDir.exists()) return;
    final children = pluginDir.listSync().whereType<Directory>();
    for (final d in children) {
      if (d.path.endsWith('${Platform.pathSeparator}$keepVersion')) continue;
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  }
}

Future<List<int>> _downloadBytes(http.Client client, Uri url) async {
  http.Response res;
  try {
    res = await client.get(url);
  } catch (e) {
    throw PluginInstallException('下载失败：$e');
  }
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw PluginInstallException('下载失败：HTTP ${res.statusCode} (${url.toString()})');
  }
  return res.bodyBytes;
}

Uri _dirUri(Uri url) {
  final seg = url.pathSegments.toList(growable: false);
  if (seg.isEmpty) return url;
  if (url.path.endsWith('/')) return url;
  return url.replace(pathSegments: seg.sublist(0, seg.length - 1)..add(''));
}

String _toOsPath(String rel) => rel.split('/').join(Platform.pathSeparator);

void _validateRelativePath(String path) {
  final p = path.trim();
  if (p.isEmpty) throw PluginInstallException('路径不能为空');
  if (p.startsWith('/')) throw PluginInstallException('禁止绝对路径：$p');
  if (p.contains('\\')) throw PluginInstallException('路径必须使用 / 分隔：$p');
  if (p.contains(':')) throw PluginInstallException('禁止盘符/协议前缀：$p');
  if (p.contains('\u0000')) throw PluginInstallException('路径包含非法字符：$p');
  final parts = p.split('/');
  for (final part in parts) {
    if (part.isEmpty) throw PluginInstallException('路径包含空段：$p');
    if (part == '.' || part == '..') throw PluginInstallException('禁止路径穿越：$p');
  }
}

bool _validPluginId(String id) {
  final s = id.trim();
  if (s.isEmpty) return false;
  // Conservative: letters/digits/._-
  final re = RegExp(r'^[a-zA-Z0-9._-]+$');
  return re.hasMatch(s);
}

class _SemVer {
  _SemVer(this.major, this.minor, this.patch, {required this.raw, required this.isValid});

  factory _SemVer.tryParse(String raw) {
    final cleaned = raw.trim().split('-').first.split('+').first.trim();
    final parts = cleaned.split('.');
    if (parts.length != 3) {
      return _SemVer(0, 0, 0, raw: raw, isValid: false);
    }
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) {
      return _SemVer(0, 0, 0, raw: raw, isValid: false);
    }
    if (major < 0 || minor < 0 || patch < 0) {
      return _SemVer(0, 0, 0, raw: raw, isValid: false);
    }
    return _SemVer(major, minor, patch, raw: raw, isValid: true);
  }

  final int major;
  final int minor;
  final int patch;
  final String raw;
  final bool isValid;

  int compareTo(_SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }
}

Future<_SemVer> _hostVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final v = _SemVer.tryParse(info.version);
    if (v.isValid) return v;
  } catch (_) {}
  return _SemVer.tryParse('0.0.0');
}

Uri? _deriveBlockedUrl(Uri manifestUrl) {
  final seg = manifestUrl.pathSegments;
  final idx = seg.indexOf('plugins');
  if (idx < 0) return null;
  final rootSeg = seg.take(idx).toList(growable: false);
  return manifestUrl.replace(pathSegments: [...rootSeg, 'blocked.json']);
}

Future<void> _enforceBlockedList(
  http.Client client,
  Uri blockedUrl,
  PluginManifestV1 manifest,
  PluginTarget target,
) async {
  final bytes = await _downloadBytes(client, blockedUrl);
  final text = utf8.decode(bytes);
  final decoded = jsonDecode(text);
  final rules = _parseBlockRules(decoded);
  for (final r in rules) {
    if (r.matches(manifest.id, manifest.version, target)) {
      final reason = (r.reason ?? '').trim();
      final suffix = reason.isEmpty ? '' : '：$reason';
      throw PluginInstallException('插件已被下架/禁用$suffix');
    }
  }
}

List<_BlockRule> _parseBlockRules(Object? decoded) {
  List<dynamic>? list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map) {
    final candidates = [
      decoded['blocked'],
      decoded['rules'],
      decoded['plugins'],
      decoded['items'],
    ];
    for (final c in candidates) {
      if (c is List) {
        list = c;
        break;
      }
    }
  }
  if (list == null) {
    // Security: if blocked.json exists but format is unknown, fail closed.
    throw PluginInstallException('blocked.json 格式无法识别');
  }
  final rules = <_BlockRule>[];
  for (final item in list) {
    final rule = _BlockRule.tryFromJson(item);
    if (rule != null) rules.add(rule);
  }
  return rules;
}

class _BlockRule {
  _BlockRule({
    required this.id,
    required this.versions,
    required this.targets,
    required this.reason,
  });

  static _BlockRule? tryFromJson(Object? json) {
    if (json is String) {
      final id = json.trim();
      if (id.isEmpty) return null;
      return _BlockRule(id: id, versions: null, targets: null, reason: null);
    }
    if (json is! Map) return null;
    final id = (json['id'] as String? ?? json['pluginId'] as String? ?? '').trim();
    if (id.isEmpty) return null;
    final versions = _stringSet(json['versions'] ?? json['version']);
    final targets = _stringSet(json['targets'] ?? json['target']);
    final reason = (json['reason'] as String? ?? '').trim();
    return _BlockRule(
      id: id,
      versions: versions,
      targets: targets,
      reason: reason.isEmpty ? null : reason,
    );
  }

  final String id;
  final Set<String>? versions; // null means all
  final Set<String>? targets; // null means all
  final String? reason;

  bool matches(String pluginId, String version, PluginTarget target) {
    if (pluginId != id) return false;
    if (targets != null && targets!.isNotEmpty) {
      final t = target.name.toLowerCase();
      if (!targets!.contains(t) && !targets!.contains('*')) return false;
    }
    if (versions == null || versions!.isEmpty) return true;
    if (versions!.contains('*')) return true;
    return versions!.contains(version);
  }
}

Set<String>? _stringSet(Object? raw) {
  if (raw == null) return null;
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    return {s};
  }
  if (raw is List) {
    final out = <String>{};
    for (final v in raw) {
      final s = (v as String? ?? '').trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out.isEmpty ? null : out;
  }
  return null;
}
