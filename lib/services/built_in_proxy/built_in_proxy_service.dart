import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:lin_player_server_api/network/lin_http_client.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BuiltInProxyState {
  unsupported,
  notInstalled,
  stopped,
  starting,
  running,
  error,
}

@immutable
class BuiltInProxyStatus {
  final BuiltInProxyState state;
  final String message;
  final String? executablePath;
  final String? configPath;
  final String? uiPath;
  final int mixedPort;
  final int controllerPort;
  final int? lastExitCode;
  final String? lastError;

  const BuiltInProxyStatus({
    required this.state,
    required this.message,
    required this.executablePath,
    required this.configPath,
    required this.uiPath,
    required this.mixedPort,
    required this.controllerPort,
    required this.lastExitCode,
    required this.lastError,
  });

  bool get isSupported => state != BuiltInProxyState.unsupported;
  bool get isInstalled =>
      state != BuiltInProxyState.unsupported && executablePath != null;
  bool get isRunning =>
      state == BuiltInProxyState.starting || state == BuiltInProxyState.running;
}

class BuiltInProxyService extends ChangeNotifier {
  BuiltInProxyService._();

  static final BuiltInProxyService instance = BuiltInProxyService._();

  static const int mixedPort = 7890;
  static const int controllerPort = 9090;
  static const String _nativeMihomoSoName = 'libmihomo.so';
  static const String _kSubscriptionUrlKey = 'tvBuiltInProxySubscriptionUrl_v1';
  static const String _kMediaServerLinesKey = 'tvBuiltInProxyMediaServerLines_v1';
  static const String _mediaServerGroupName = '媒体服务器';

  static const Duration _startupTimeout = Duration(seconds: 2);
  static const Duration _shutdownTimeout = Duration(seconds: 2);

  Process? _process;
  int? _lastExitCode;
  String? _lastError;

  BuiltInProxyStatus _status = const BuiltInProxyStatus(
    state: BuiltInProxyState.unsupported,
    message: '仅 Android TV 支持',
    executablePath: null,
    configPath: null,
    uiPath: null,
    mixedPort: mixedPort,
    controllerPort: controllerPort,
    lastExitCode: null,
    lastError: null,
  );

  BuiltInProxyStatus get status => _status;

  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      DeviceType.isTv;

  Future<void> refresh() async {
    try {
      final next = await _computeStatus();
      _status = next;
      _syncHttpProxy(next);
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      _status = BuiltInProxyStatus(
        state: BuiltInProxyState.error,
        message: '状态读取失败：$e',
        executablePath: null,
        configPath: null,
        uiPath: null,
        mixedPort: mixedPort,
        controllerPort: controllerPort,
        lastExitCode: _lastExitCode,
        lastError: _lastError,
      );
      _syncHttpProxy(_status);
      notifyListeners();
    }
  }

  Future<String> getSubscriptionUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSubscriptionUrlKey) ?? '';
  }

  Future<void> setSubscriptionUrl(String url) async {
    final v = url.trim();
    final prefs = await SharedPreferences.getInstance();
    if (v.isEmpty) {
      await prefs.remove(_kSubscriptionUrlKey);
    } else {
      await prefs.setString(_kSubscriptionUrlKey, v);
    }
  }

  Future<List<String>> getMediaServerLines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kMediaServerLinesKey) ?? const [];
    final out = <String>[];
    for (final e in raw) {
      final v = e.trim();
      if (v.isEmpty) continue;
      out.add(v);
    }
    out.sort();
    return out;
  }

  static String mediaServerLineForDisplay(String entry) {
    final e = entry.trim();
    if (e.startsWith('domain:')) return e.substring('domain:'.length);
    if (e.startsWith('ip:')) return e.substring('ip:'.length);
    return e;
  }

  Future<void> clearMediaServerLines() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMediaServerLinesKey);
  }

  Future<bool> removeMediaServerLine(String entry) async {
    final target = entry.trim();
    if (target.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_kMediaServerLinesKey) ?? const [];
    final next = current.where((e) => e.trim() != target).toList(growable: false);
    if (next.length == current.length) return false;

    if (next.isEmpty) {
      await prefs.remove(_kMediaServerLinesKey);
    } else {
      await prefs.setStringList(_kMediaServerLinesKey, next);
    }
    return true;
  }

  Future<int> addMediaServerLinesFromText(String raw) async {
    final lines = raw.split(RegExp(r'\r?\n'));
    final normalized = <String>[];
    for (final line in lines) {
      final v = _normalizeMediaServerLine(line);
      if (v == null) continue;
      normalized.add(v);
    }
    if (normalized.isEmpty) return 0;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_kMediaServerLinesKey) ?? const [];
    final set = <String>{
      ...current.map((e) => e.trim()).where((e) => e.isNotEmpty),
    };
    var added = 0;
    for (final e in normalized) {
      if (set.add(e)) added++;
    }

    final next = set.toList()..sort();
    await prefs.setStringList(_kMediaServerLinesKey, next);
    return added;
  }

  Future<void> applyConfig({bool restartIfRunning = false}) async {
    if (!isSupported) return;

    if (restartIfRunning && _process != null) {
      await stop();
      await start();
      return;
    }

    await prepareConfig();
  }

  Future<void> prepareConfig() async {
    if (!isSupported) return;
    final uiRoot = await _ensureMetacubexdReady();
    await _ensureConfigPatched(externalUiDir: uiRoot);
    await refresh();
  }

  static String? _normalizeMediaServerLine(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;

    // Support basic URL / host(:port) inputs. Keep this tolerant: we only reject
    // entries that are obviously unsafe for rule generation (spaces/commas).
    if (input.contains(RegExp(r'[\s,]'))) return null;

    String hostOrCidr = input;
    if (!hostOrCidr.contains('://')) {
      final parsed = Uri.tryParse('http://$hostOrCidr');
      if (parsed != null && parsed.host.isNotEmpty) {
        hostOrCidr = parsed.host;
      }
    } else {
      final parsed = Uri.tryParse(hostOrCidr);
      if (parsed != null && parsed.host.isNotEmpty) {
        hostOrCidr = parsed.host;
      }
    }

    hostOrCidr = hostOrCidr.trim();
    if (hostOrCidr.isEmpty) return null;

    // Normalize domain wildcards: *.example.com / .example.com -> example.com
    if (hostOrCidr.startsWith('*.')) hostOrCidr = hostOrCidr.substring(2);
    if (hostOrCidr.startsWith('.')) hostOrCidr = hostOrCidr.substring(1);
    hostOrCidr = hostOrCidr.trim();
    if (hostOrCidr.isEmpty) return null;

    // IP / CIDR
    if (hostOrCidr.contains('/')) {
      final parts = hostOrCidr.split('/');
      if (parts.length != 2) return null;
      final ip = InternetAddress.tryParse(parts[0].trim());
      final prefix = int.tryParse(parts[1].trim());
      if (ip == null || ip.type != InternetAddressType.IPv4) return null;
      if (prefix == null || prefix < 0 || prefix > 32) return null;
      return 'ip:${ip.address}/$prefix';
    }
    final ip = InternetAddress.tryParse(hostOrCidr);
    if (ip != null && ip.type == InternetAddressType.IPv4) {
      return 'ip:${ip.address}/32';
    }

    // Domain/host
    final domain = hostOrCidr.toLowerCase();
    if (domain.contains(RegExp(r'[/:]'))) return null;
    final cleaned =
        domain.endsWith('.') ? domain.substring(0, domain.length - 1) : domain;
    if (cleaned.trim().isEmpty) return null;
    return 'domain:$cleaned';
  }

  Future<void> installFromFile(String srcPath) async {
    if (!isSupported) {
      _lastError = '仅 Android TV 支持';
      await refresh();
      throw StateError(_lastError!);
    }

    final src = File(srcPath);
    if (!await src.exists()) {
      throw StateError('文件不存在：$srcPath');
    }

    final exe = await _exeFile();
    await exe.parent.create(recursive: true);
    await src.copy(exe.path);
    await _chmodExecutable(exe.path);
    _lastError = null;
    final uiRoot = await _ensureMetacubexdReady();
    await _ensureConfigPatched(externalUiDir: uiRoot);
    await refresh();
  }

  Future<void> start() async {
    if (!isSupported) {
      _lastError = '仅 Android TV 支持';
      await refresh();
      throw StateError(_lastError!);
    }

    if (_process != null) return;

    var exe = await _resolveMihomoExecutableForStart();

    final uiRoot = await _ensureMetacubexdReady();
    await _ensureConfigPatched(externalUiDir: uiRoot);

    _lastError = null;
    _lastExitCode = null;
    _status = BuiltInProxyStatus(
      state: BuiltInProxyState.starting,
      message: '启动中…',
      executablePath: exe.path,
      configPath: (await _configFile()).path,
      uiPath: uiRoot?.path,
      mixedPort: mixedPort,
      controllerPort: controllerPort,
      lastExitCode: _lastExitCode,
      lastError: _lastError,
    );
    notifyListeners();

    try {
      final workDir = (await _baseDir()).path;
      Process process;
      try {
        process = await Process.start(
          exe.path,
          ['-d', workDir],
          workingDirectory: workDir,
          runInShell: false,
        );
      } on ProcessException catch (e) {
        // Some Android TV ROMs mount app data dirs as "noexec", causing Permission denied.
        // In that case, try running the bundled native-lib executable instead.
        final message = e.toString().toLowerCase();
        final nativeExe = await _nativeMihomoFile();
        final canFallback = nativeExe != null &&
            nativeExe.path != exe.path &&
            await nativeExe.exists() &&
            message.contains('permission denied');
        if (!canFallback) rethrow;

        exe = nativeExe;
        _status = BuiltInProxyStatus(
          state: BuiltInProxyState.starting,
          message: '启动中…',
          executablePath: exe.path,
          configPath: (await _configFile()).path,
          uiPath: uiRoot?.path,
          mixedPort: mixedPort,
          controllerPort: controllerPort,
          lastExitCode: _lastExitCode,
          lastError: _lastError,
        );
        notifyListeners();

        process = await Process.start(
          exe.path,
          ['-d', workDir],
          workingDirectory: workDir,
          runInShell: false,
        );
      }
      _process = process;

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLogLine);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLogLine);

      unawaited(
        process.exitCode.then((code) async {
          _lastExitCode = code;
          _process = null;
          _lastError ??= 'mihomo 已退出：$code';
          await refresh();
        }),
      );

      await _waitForPort(
        InternetAddress.loopbackIPv4,
        controllerPort,
        timeout: _startupTimeout,
      );
    } catch (e) {
      _process = null;
      _lastError = e.toString();
      await refresh();
      rethrow;
    }

    await refresh();
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      await refresh();
      return;
    }

    try {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(_shutdownTimeout);
    } catch (_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    } finally {
      _process = null;
    }

    await refresh();
  }

  void _onLogLine(String line) {
    // MVP: keep last error only; avoid unbounded logs.
    // Capture useful hints for UI.
    if (line.trim().isEmpty) return;
    if (_lastError == null &&
        (line.toLowerCase().contains('fatal') ||
            line.toLowerCase().contains('error') ||
            line.toLowerCase().contains('panic'))) {
      _lastError = line.trim();
      notifyListeners();
    }
  }

  Future<BuiltInProxyStatus> _computeStatus() async {
    if (!isSupported) {
      return BuiltInProxyStatus(
        state: BuiltInProxyState.unsupported,
        message: '仅 Android TV 支持',
        executablePath: null,
        configPath: null,
        uiPath: null,
        mixedPort: mixedPort,
        controllerPort: controllerPort,
        lastExitCode: _lastExitCode,
        lastError: _lastError,
      );
    }

    final exe = await _exeFile();
    final nativeExe = await _nativeMihomoFile();
    final cfg = await _configFile();
    final uiPath = () async {
      try {
        final base = await _uiBaseDir();
        final root = Directory('${base.path}/metacubexd');
        final marker = File('${root.path}/.ready');
        if (!await marker.exists()) return null;
        final uiRoot = await _findUiRoot(root);
        return (uiRoot ?? root).path;
      } catch (_) {
        return null;
      }
    }();

    final exeExists = await exe.exists();
    final nativeExists = nativeExe != null && await nativeExe.exists();
    final effectiveExe = exeExists
        ? exe
        : nativeExists
            ? nativeExe
            : null;

    if (effectiveExe == null) {
      return BuiltInProxyStatus(
        state: BuiltInProxyState.notInstalled,
        message: '未安装 mihomo（启用后会自动安装；如失败可手动导入）',
        executablePath: null,
        configPath: cfg.path,
        uiPath: await uiPath,
        mixedPort: mixedPort,
        controllerPort: controllerPort,
        lastExitCode: _lastExitCode,
        lastError: _lastError,
      );
    }

    if (_process != null) {
      return BuiltInProxyStatus(
        state: BuiltInProxyState.running,
        message: '运行中（mixed: 127.0.0.1:$mixedPort）',
        executablePath: effectiveExe.path,
        configPath: cfg.path,
        uiPath: await uiPath,
        mixedPort: mixedPort,
        controllerPort: controllerPort,
        lastExitCode: _lastExitCode,
        lastError: _lastError,
      );
    }

    if ((_lastError ?? '').trim().isNotEmpty) {
      return BuiltInProxyStatus(
        state: BuiltInProxyState.error,
        message: '启动失败：${_lastError!.trim()}',
        executablePath: effectiveExe.path,
        configPath: cfg.path,
        uiPath: await uiPath,
        mixedPort: mixedPort,
        controllerPort: controllerPort,
        lastExitCode: _lastExitCode,
        lastError: _lastError,
      );
    }

    final suffix = _lastExitCode == null ? '' : '（上次退出：$_lastExitCode）';
    return BuiltInProxyStatus(
      state: BuiltInProxyState.stopped,
      message: '未运行$suffix',
      executablePath: effectiveExe.path,
      configPath: cfg.path,
      uiPath: await uiPath,
      mixedPort: mixedPort,
      controllerPort: controllerPort,
      lastExitCode: _lastExitCode,
      lastError: _lastError,
    );
  }

  Future<Directory> _baseDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/built_in_proxy');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _exeFile() async {
    final dir = await _baseDir();
    return File('${dir.path}/mihomo');
  }

  Future<File?> _nativeMihomoFile() async {
    if (!isSupported) return null;
    final dir = await DeviceType.nativeLibraryDir();
    final base = (dir ?? '').trim();
    if (base.isEmpty) return null;
    return File('$base/$_nativeMihomoSoName');
  }

  Future<File> _resolveMihomoExecutableForStart() async {
    // 1) User imported binary (preferred so users can pin versions).
    final exe = await _exeFile();
    if (await exe.exists()) return exe;

    // 2) Bundled native lib (works on devices that disallow exec from app data dirs).
    final nativeExe = await _nativeMihomoFile();
    if (nativeExe != null && await nativeExe.exists()) return nativeExe;

    // 3) Fallback: extract from Flutter assets.
    await _ensureMihomoInstalled(exe);
    return exe;
  }

  Future<File> _configFile() async {
    final dir = await _baseDir();
    return File('${dir.path}/config.yaml');
  }

  Future<void> _ensureConfigPatched({required Directory? externalUiDir}) async {
    // Ensure working dirs for providers/rules exist before mihomo parses config.
    // (Missing directories can cause config load failure on some versions.)
    final baseDir = await _baseDir();
    await Directory('${baseDir.path}/providers').create(recursive: true);

    final file = await _configFile();
    final subscriptionUrl = (await getSubscriptionUrl()).trim();
    final content = subscriptionUrl.isNotEmpty
        ? await _buildManagedConfigYaml(subscriptionUrl)
        : await _buildDirectConfigYaml();

    // Backward-compat: older default config accidentally created a proxy-group named "DIRECT"
    // which self-referenced and caused mihomo to fail with:
    // "loop is detected in ProxyGroup ... [DIRECT]".
    var patched = _migrateDirectGroupLoop(content);

    String quoteYamlString(String value) {
      final fixed = value.replaceAll("'", "''");
      return "'$fixed'";
    }

    String upsert(String raw, String key, String value) {
      final re = RegExp(
        '^\\s*${RegExp.escape(key)}\\s*:\\s*.*\$',
        multiLine: true,
      );
      if (re.hasMatch(raw)) {
        return raw.replaceAll(re, '$key: $value');
      }
      final suffix = raw.endsWith('\n') ? '' : '\n';
      return '$raw$suffix$key: $value\n';
    }

    patched = upsert(patched, 'mixed-port', '$mixedPort');
    patched = upsert(patched, 'socks-port', '${mixedPort + 1}');
    patched = upsert(patched, 'allow-lan', 'false');
    patched = upsert(patched, 'bind-address', '127.0.0.1');
    patched =
        upsert(patched, 'external-controller', '127.0.0.1:$controllerPort');
    patched = upsert(patched, 'secret', '""');

    if (externalUiDir != null) {
      patched = upsert(
        patched,
        'external-ui',
        quoteYamlString(externalUiDir.path),
      );
    }

    await file.writeAsString(patched, flush: true);
  }

  Future<String> _buildDirectConfigYaml() {
    return _buildRepczLiteConfigYaml(subscriptionUrl: '');
  }

  Future<String> _buildManagedConfigYaml(String subscriptionUrl) {
    return _buildRepczLiteConfigYaml(subscriptionUrl: subscriptionUrl);
  }

  Future<String> _buildRepczLiteConfigYaml({
    required String subscriptionUrl,
  }) async {
    final subUrl = subscriptionUrl.trim();
    final hasSubscription = subUrl.isNotEmpty;
    final mediaRules = await _loadMediaServerRules();

    final b = StringBuffer()
      ..writeln('# Author:https://github.com/Repcz')
      ..writeln('# Template: config_lite.yaml (updated 2025-12-14 10:15)')
      ..writeln('# Generated by LinPlayer. Edits may be overwritten.')
      ..writeln('');

    if (hasSubscription) {
      b
        ..writeln('proxy-providers:')
        ..writeln('  Subscribe:')
        ..writeln('    type: http')
        ..writeln('    url: ${_q(subUrl)}')
        ..writeln('    interval: 86400')
        ..writeln('    path: ./providers/sub.yaml')
        ..writeln('    proxy: DIRECT')
        ..writeln('    health-check:')
        ..writeln('      enable: true')
        ..writeln('      url: http://1.1.1.1/generate_204')
        ..writeln('      interval: 1800')
        ..writeln('      timeout: 5000')
        ..writeln('');
    }

    b
      ..writeln('mode: rule')
      ..writeln('mixed-port: 7893')
      ..writeln('tcp-concurrent: true')
      ..writeln('allow-lan: true')
      ..writeln('ipv6: false')
      ..writeln('log-level: info')
      ..writeln('unified-delay: true')
      ..writeln('global-client-fingerprint: chrome')
      ..writeln('find-process-mode: strict')
      ..writeln('')
      ..writeln('geodata-mode: true')
      ..writeln('geox-url:')
      ..writeln(
        '  geoip: "https://git.repcz.link/raw.githubusercontent.com/Loyalsoldier/geoip/release/geoip.dat"',
      )
      ..writeln(
        '  geosite: "https://git.repcz.link/github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"',
      )
      ..writeln(
        '  mmdb: "https://git.repcz.link/raw.githubusercontent.com/Loyalsoldier/geoip/release/Country.mmdb"',
      )
      ..writeln(
        '  asn: "https://git.repcz.link/raw.githubusercontent.com/Loyalsoldier/geoip/release/GeoLite2-ASN.mmdb"',
      )
      ..writeln('')
      ..writeln('profile: { store-selected: true, store-fake-ip: false }')
      ..writeln(
        'sniffer: { enable: true, sniff: { HTTP: { ports: [80], override-destination: true }, TLS: { ports: [443, 8443] }, QUIC: { ports: [443, 8443] } } }',
      )
      ..writeln('')
      ..writeln('tun:')
      ..writeln('  enable: false')
      ..writeln('  stack: mixed')
      ..writeln('  dns-hijack: [any:53]')
      ..writeln('')
      ..writeln('dns:')
      ..writeln('  enable: true')
      ..writeln('  ipv6: false')
      ..writeln('  enhanced-mode: fake-ip')
      ..writeln('  listen: 127.0.0.1:1053')
      ..writeln('  fake-ip-range: 198.18.0.1/16')
      ..writeln(
        "  fake-ip-filter: ['+.lan', '*', '+.local', '+.cmpassport.com', 'id6.me', 'open.e.189.cn', 'mdn.open.wo.cn', 'opencloud.wostore.cn', 'auth.wosms.cn', '+.10099.com.cn', '+.msftconnecttest.com', '+.msftncsi.com', 'lancache.steamcontent.com']",
      )
      ..writeln('  nameserver: [223.5.5.5, 119.29.29.29]')
      ..writeln('')
      ..writeln('proxy-groups:')
      ..writeln('  - name: Proxy')
      ..writeln('    type: select');

    if (hasSubscription) {
      b.writeln('    use: [Subscribe]');
    }

    b
      ..writeln('    proxies: [DIRECT]')
      ..writeln('')
      ..writeln('  - name: ${_q(_mediaServerGroupName)}')
      ..writeln('    type: select')
      ..writeln('    proxies: [Proxy, DIRECT]')
      ..writeln('')
      ..writeln('rules:')
      ..writeln('  # LinPlayer: 用户添加的“媒体服务器线路”优先匹配')
      ..writeln('  # （在这里添加规则可以覆盖后续的 GEOIP/GEOSITE 等规则）');

    for (final r in mediaRules) {
      b.writeln('  - ${r.toRuleLine(group: _mediaServerGroupName)}');
    }

    b
      ..writeln('')
      ..writeln('  - GEOSITE,openai,Proxy')
      ..writeln('  - GEOSITE,category-games,Proxy')
      ..writeln('  - GEOSITE,github,Proxy')
      ..writeln('  - GEOSITE,telegram,Proxy')
      ..writeln('  - GEOSITE,twitter,Proxy')
      ..writeln('  - GEOSITE,microsoft,Proxy')
      ..writeln('  - GEOSITE,youtube,Proxy')
      ..writeln('  - GEOSITE,google,Proxy')
      ..writeln('  - GEOSITE,geolocation-!cn,Proxy')
      ..writeln('  - GEOSITE,private,DIRECT')
      ..writeln('')
      ..writeln('  - GEOIP,telegram,Proxy')
      ..writeln('  - GEOIP,twitter,Proxy')
      ..writeln('  - GEOIP,google,Proxy')
      ..writeln('  - GEOIP,private,DIRECT')
      ..writeln('  - GEOIP,cn,DIRECT')
      ..writeln('')
      ..writeln('  - MATCH,Proxy')
      ..writeln('');

    return b.toString();
  }

  static String _q(String value) {
    final fixed = value.replaceAll("'", "''");
    return "'$fixed'";
  }

  Future<List<_MediaServerRule>> _loadMediaServerRules() async {
    final entries = await getMediaServerLines();
    final rules = <_MediaServerRule>[];
    for (final entry in entries) {
      final e = entry.trim();
      if (e.isEmpty) continue;
      final rule = _MediaServerRule.tryParse(e);
      if (rule != null) rules.add(rule);
    }
    return rules;
  }

  static String _migrateDirectGroupLoop(String raw) {
    // Only touch configs that match the previous (broken) default group:
    // proxy-groups:
    //   - name: DIRECT
    //     type: select
    //     proxies:
    //       - DIRECT
    //
    // And route-all rule:
    //   - MATCH,DIRECT
    //
    // Fix by renaming the group and updating the MATCH rule.
    final hasBrokenGroup = RegExp(
      r'^\s*-\s*name\s*:\s*DIRECT\s*$[\s\S]*?^\s*proxies\s*:\s*$[\s\S]*?^\s*-\s*DIRECT\s*$',
      multiLine: true,
    ).hasMatch(raw);
    if (!hasBrokenGroup) return raw;

    // Avoid clobbering user configs that already define a PROXY group.
    final targetName = RegExp(
      r'^\s*-\s*name\s*:\s*PROXY\s*$',
      multiLine: true,
    ).hasMatch(raw)
        ? 'LP-PROXY'
        : 'PROXY';

    String out = raw;
    out = out.replaceAll(
      RegExp(
        r'^(\s*-\s*name\s*:\s*)DIRECT(\s*)$',
        multiLine: true,
      ),
      r'$1' + targetName + r'$2',
    );
    out = out.replaceAll(
      RegExp(
        r'^(\s*-\s*MATCH\s*,\s*)DIRECT(\s*)$',
        multiLine: true,
      ),
      r'$1' + targetName + r'$2',
    );
    return out;
  }

  Future<void> _chmodExecutable(String path) async {
    // Best-effort; some ROMs may still block execve from app data.
    try {
      final ok = await DeviceType.setExecutable(path);
      if (ok) return;
    } catch (_) {}

    final attempts = <String>[
      'platform=setExecutable(false)',
    ];

    Future<bool> tryRun(String cmd, List<String> args) async {
      try {
        final res = await Process.run(cmd, args, runInShell: false);
        if (res.exitCode == 0) return true;
        attempts.add('$cmd exit=${res.exitCode}');
        return false;
      } catch (e) {
        attempts.add('$cmd error=$e');
        return false;
      }
    }

    if (await tryRun('chmod', ['700', path])) return;
    if (await tryRun('/system/bin/chmod', ['700', path])) return;
    if (await tryRun('/system/bin/toybox', ['chmod', '700', path])) return;
    if (await tryRun('/system/bin/toolbox', ['chmod', '700', path])) return;

    // Keep error around for user-facing diagnosis if start() fails later.
    _lastError ??= '无法设置 mihomo 可执行权限：${attempts.join(', ')}';
  }

  static Future<bool> _waitForPort(
    InternetAddress host,
    int port, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(host, port)
            .timeout(const Duration(milliseconds: 180));
        socket.destroy();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return false;
  }

  Future<void> _ensureMihomoInstalled(File exe) async {
    if (await exe.exists()) return;

    final ok = await _installBundledMihomo(exe);
    if (!ok) {
      _lastError = '未安装 mihomo（缺少内置资源，或 ABI 不支持）';
      await refresh();
      throw StateError(_lastError!);
    }
  }

  Future<bool> _installBundledMihomo(File exe) async {
    final primaryAbi = await DeviceType.primaryAbi();
    final abi = _normalizeAndroidAbi(primaryAbi);
    if (abi == null) return false;

    final assetPath = 'assets/tv_proxy/mihomo/android/$abi/mihomo.gz';
    ByteData data;
    try {
      data = await rootBundle.load(assetPath);
    } catch (_) {
      return false;
    }
    final gzBytes = data.buffer.asUint8List();

    late final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(gzip.decode(gzBytes));
    } catch (_) {
      return false;
    }

    await exe.parent.create(recursive: true);
    await exe.writeAsBytes(bytes, flush: true);
    await _chmodExecutable(exe.path);
    return true;
  }

  static String? _normalizeAndroidAbi(String? abi) {
    final v = (abi ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v.contains('arm64')) return 'arm64-v8a';
    if (v.contains('armeabi') || v.contains('armv7')) return 'armeabi-v7a';
    if (v.contains('x86_64') || v.contains('amd64')) return 'x86_64';
    if (v.contains('x86') || v.contains('386')) return 'x86';
    return null;
  }

  Future<Directory> _uiBaseDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/built_in_proxy/ui');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory?> _ensureMetacubexdReady() async {
    final base = await _uiBaseDir();
    final root = Directory('${base.path}/metacubexd');
    final marker = File('${root.path}/.ready');
    if (await marker.exists()) {
      final uiRoot = await _findUiRoot(root);
      return uiRoot ?? root;
    }

    ByteData data;
    try {
      data = await rootBundle
          .load('assets/tv_proxy/metacubexd/compressed-dist.tgz');
    } catch (_) {
      // UI assets are optional; proxy can still run without panel.
      return null;
    }

    final tgz = data.buffer.asUint8List();
    late final Archive tar;
    try {
      final gz = GZipDecoder().decodeBytes(tgz, verify: false);
      tar = TarDecoder().decodeBytes(gz, verify: false);
    } catch (_) {
      return null;
    }

    if (await root.exists()) {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    }
    await root.create(recursive: true);

    for (final entry in tar.files) {
      final name = entry.name;
      if (name.trim().isEmpty) continue;

      final fixedName = name.replaceAll('\\', '/');
      final outPath = '${root.path}/$fixedName';

      if (entry.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>, flush: true);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    try {
      await marker.writeAsString('ok', flush: true);
    } catch (_) {}

    final uiRoot = await _findUiRoot(root);
    return uiRoot ?? root;
  }

  Future<Directory?> _findUiRoot(Directory root) async {
    final direct = File('${root.path}/index.html');
    if (await direct.exists()) return root;
    final dist = Directory('${root.path}/dist');
    if (await File('${dist.path}/index.html').exists()) return dist;

    // Fall back: scan one-level children for index.html.
    try {
      await for (final ent in root.list(followLinks: false)) {
        if (ent is Directory) {
          if (await File('${ent.path}/index.html').exists()) return ent;
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _isPrivateIpv4(InternetAddress ip) {
    if (ip.type != InternetAddressType.IPv4) return false;
    final b = ip.rawAddress;
    if (b.length != 4) return false;
    final a = b[0];
    final c = b[1];
    if (a == 10) return true;
    if (a == 127) return true;
    if (a == 169 && c == 254) return true;
    if (a == 192 && c == 168) return true;
    if (a == 172 && c >= 16 && c <= 31) return true;
    return false;
  }

  static String _httpProxyResolver(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return 'DIRECT';

    final host = uri.host.trim();
    if (host.isEmpty) return 'DIRECT';
    if (host == 'localhost') return 'DIRECT';
    if (host == '127.0.0.1') return 'DIRECT';

    final ip = InternetAddress.tryParse(host);
    if (ip != null && _isPrivateIpv4(ip)) return 'DIRECT';

    return 'PROXY 127.0.0.1:$mixedPort';
  }

  static String? proxyUrlForUri(Uri uri) {
    return _httpProxyResolver(uri) == 'DIRECT'
        ? null
        : 'http://127.0.0.1:$mixedPort';
  }

  static void _syncHttpProxy(BuiltInProxyStatus status) {
    final shouldEnable = status.state == BuiltInProxyState.running;
    LinHttpClientFactory.setRuntimeProxyResolver(
      shouldEnable ? _httpProxyResolver : null,
    );

    // ExoPlayer (video_player) uses HttpURLConnection internally; route it through a process-level
    // ProxySelector so only this app is affected (per-app proxy, not system VPN).
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        DeviceType.isTv) {
      unawaited(() async {
        if (shouldEnable) {
          await DeviceType.setHttpProxy(
            host: '127.0.0.1',
            port: mixedPort,
          );
        } else {
          await DeviceType.clearHttpProxy();
        }
      }());
    }
  }
}

enum _MediaServerRuleType { domainSuffix, ipCidr }

class _MediaServerRule {
  final _MediaServerRuleType type;
  final String value;

  const _MediaServerRule({
    required this.type,
    required this.value,
  });

  static _MediaServerRule? tryParse(String entry) {
    final e = entry.trim();
    if (e.isEmpty) return null;

    if (e.startsWith('domain:')) {
      final v = e.substring('domain:'.length).trim();
      if (v.isEmpty) return null;
      return _MediaServerRule(type: _MediaServerRuleType.domainSuffix, value: v);
    }
    if (e.startsWith('ip:')) {
      final v = e.substring('ip:'.length).trim();
      if (v.isEmpty) return null;
      return _MediaServerRule(type: _MediaServerRuleType.ipCidr, value: v);
    }

    // Backward-compat: accept raw domain / ip / cidr forms.
    if (e.contains('/')) {
      final parts = e.split('/');
      if (parts.length != 2) return null;
      final ip = InternetAddress.tryParse(parts[0].trim());
      final prefix = int.tryParse(parts[1].trim());
      if (ip == null || ip.type != InternetAddressType.IPv4) return null;
      if (prefix == null || prefix < 0 || prefix > 32) return null;
      return _MediaServerRule(
        type: _MediaServerRuleType.ipCidr,
        value: '${ip.address}/$prefix',
      );
    }

    final ip = InternetAddress.tryParse(e);
    if (ip != null && ip.type == InternetAddressType.IPv4) {
      return _MediaServerRule(
        type: _MediaServerRuleType.ipCidr,
        value: '${ip.address}/32',
      );
    }

    return _MediaServerRule(type: _MediaServerRuleType.domainSuffix, value: e);
  }

  String toRuleLine({required String group}) {
    switch (type) {
      case _MediaServerRuleType.domainSuffix:
        return 'DOMAIN-SUFFIX,$value,$group';
      case _MediaServerRuleType.ipCidr:
        return 'IP-CIDR,$value,$group,no-resolve';
    }
  }
}
