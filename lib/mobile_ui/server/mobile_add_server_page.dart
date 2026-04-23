import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_server_api/services/plex_api.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../server_text_import_sheet.dart';

class MobileAddServerPage extends StatefulWidget {
  const MobileAddServerPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<MobileAddServerPage> createState() => _MobileAddServerPageState();
}

enum _PlexAddMode {
  manual,
  account,
}

enum _BackupImportSource {
  text,
  file,
}

extension _PlexAddModeX on _PlexAddMode {
  String get label {
    switch (this) {
      case _PlexAddMode.manual:
        return '手动输入';
      case _PlexAddMode.account:
        return '浏览器登录';
    }
  }
}

class _MobileAddServerPageState extends State<MobileAddServerPage> {
  static const List<MediaServerType> _preferredServerTypes = <MediaServerType>[
    MediaServerType.emby,
    MediaServerType.jellyfin,
    MediaServerType.plex,
    MediaServerType.webdav,
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _remarkCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  final TextEditingController _plexTokenCtrl = TextEditingController();

  MediaServerType _serverType = MediaServerType.emby;
  _PlexAddMode _plexMode = _PlexAddMode.manual;
  String? _iconUrl;
  bool _iconLoading = false;
  bool _pwdVisible = false;
  bool _plexTokenVisible = false;
  bool _submitting = false;

  PlexPin? _plexPin;
  String? _plexAccountToken;
  List<PlexResource> _plexServers = const <PlexResource>[];
  PlexResource? _selectedPlexServer;
  bool _plexLoading = false;
  String? _plexError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _remarkCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _plexTokenCtrl.dispose();
    super.dispose();
  }

  List<MediaServerType> _availableServerTypes(BuildContext context) {
    final config = AppConfigScope.of(context);
    final allowed = config.features.allowedServerTypes;
    final types =
        _preferredServerTypes.where(allowed.contains).toList(growable: false);
    return types.isEmpty ? _preferredServerTypes : types;
  }

  String? _assetForType(MediaServerType type) {
    switch (type) {
      case MediaServerType.emby:
        return 'assets/images/server_types/emby.webp';
      case MediaServerType.jellyfin:
        return 'assets/images/server_types/jellyfin.png';
      case MediaServerType.plex:
        return 'assets/images/server_types/plex.webp';
      case MediaServerType.webdav:
        return 'assets/images/server_types/webdav.webp';
      case MediaServerType.uhd:
        return null;
    }
  }

  void _setServerType(MediaServerType type) {
    if (_serverType == type) return;
    setState(() {
      _serverType = type;
      _plexMode = _PlexAddMode.manual;
      _plexError = null;
      _plexPin = null;
      _plexAccountToken = null;
      _plexServers = const <PlexResource>[];
      _selectedPlexServer = null;
      _plexTokenCtrl.clear();
    });
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String labelText,
    String? hintText,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      errorBorder: border,
      focusedErrorBorder: border,
      disabledBorder: border,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    );
  }

  Future<void> _openBulkImport() async {
    final importedServerId = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ServerTextImportSheet(appState: widget.appState),
    );
    if (!mounted || importedServerId == null) return;
    Navigator.of(context).pop(importedServerId);
  }

  Future<void> _openBackupImport() async {
    if (_submitting || widget.appState.isLoading) return;

    try {
      final raw = await _pickBackupImportRaw();
      if (!mounted || raw == null || raw.trim().isEmpty) return;

      final version = _peekBackupVersion(raw);
      if (version == null) {
        throw const FormatException('不是有效的备份文件');
      }

      String? passphrase;
      if (version == 2) {
        passphrase = await _askBackupPassphrase(
          title: '输入备份密码',
        );
        if (!mounted || passphrase == null) return;
      } else if (version == 1) {
        final confirmed = await _confirmPlainBackupImport();
        if (!mounted || confirmed != true) return;
      } else {
        throw FormatException('不支持的备份版本：$version');
      }

      setState(() => _submitting = true);
      final result = await widget.appState.importServersFromBackupJson(
        raw,
        passphrase: passphrase,
      );

      if (!mounted) return;
      if (!result.hasImportedServers) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_backupImportEmptyMessage(result))),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_backupImportSummary(result))),
      );
      Navigator.of(context).pop(result.importedServerIds.first);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _backupImportSummary(BackupServerImportResult result) {
    final parts = <String>['已导入 ${result.importedCount} 个服务器'];
    if (result.failedServerLabels.isNotEmpty) {
      parts.add('失败 ${result.failedServerLabels.length} 个');
    }
    if (result.skippedServerLabels.isNotEmpty) {
      parts.add('跳过 ${result.skippedServerLabels.length} 个');
    }
    return parts.join('，');
  }

  String _backupImportEmptyMessage(BackupServerImportResult result) {
    if (result.failedServerLabels.isNotEmpty &&
        result.skippedServerLabels.isNotEmpty) {
      return '没有导入成功（失败 ${result.failedServerLabels.length} 个，跳过 ${result.skippedServerLabels.length} 个）';
    }
    if (result.failedServerLabels.isNotEmpty) {
      return '没有导入成功，请检查备份密码、账号密码或网络连接';
    }
    return '备份中没有可导入的服务器';
  }

  Future<_BackupImportSource?> _askBackupImportSource() {
    return showDialog<_BackupImportSource>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('选择导入方式'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(_BackupImportSource.text),
            child: const Text('从文本导入'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(_BackupImportSource.file),
            child: const Text('从文件导入'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickBackupImportRaw() async {
    final source = await _askBackupImportSource();
    if (!mounted || source == null) return null;

    switch (source) {
      case _BackupImportSource.text:
        return _pickBackupFromText();
      case _BackupImportSource.file:
        return _pickBackupFromFile();
    }
  }

  Future<String?> _pickBackupFromFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '选择备份文件',
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    final file = result?.files.single;
    if (file == null) return null;

    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return utf8.decode(bytes);
    }

    final path = file.path;
    if (path == null || path.trim().isEmpty) {
      throw const FileSystemException('无法读取备份文件');
    }
    return File(path).readAsString();
  }

  Future<String?> _pickBackupFromText() async {
    final ctrl = TextEditingController();
    try {
      final raw = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('从文本导入'),
          content: TextField(
            controller: ctrl,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '粘贴导出的 JSON 文本',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(ctrl.text),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (raw == null || raw.trim().isEmpty) return null;
      return raw;
    } finally {
      ctrl.dispose();
    }
  }

  int? _peekBackupVersion(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final version = decoded['version'];
      if (version is int) return version;
      if (version is num) return version.round();
      if (version is String) return int.tryParse(version.trim());
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _confirmPlainBackupImport() {
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('旧版备份'),
        content: const Text(
          '检测到旧版备份（未加密，通常包含 token）。\n本次只会导入备份里的服务器，不会覆盖当前设置。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('继续导入'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askBackupPassphrase({
    required String title,
  }) async {
    final passCtrl = TextEditingController();
    bool show = false;
    String? error;

    try {
      return showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) => StatefulBuilder(
          builder: (dctx, setState) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: passCtrl,
              obscureText: !show,
              decoration: InputDecoration(
                labelText: '备份密码',
                errorText: error,
                suffixIcon: IconButton(
                  tooltip: show ? '隐藏' : '显示',
                  onPressed: () => setState(() => show = !show),
                  icon: Icon(
                    show
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final value = passCtrl.text.trim();
                  if (value.isEmpty) {
                    setState(() => error = '请输入备份密码');
                    return;
                  }
                  Navigator.of(dctx).pop(passCtrl.text);
                },
                child: const Text('继续'),
              ),
            ],
          ),
        ),
      );
    } finally {
      passCtrl.dispose();
    }
  }

  _ParsedServerAddress? _parseAddress() {
    final raw = _addressCtrl.text.trim();
    if (raw.isEmpty) return null;

    final candidate = raw.contains('://') ? raw : 'https://$raw';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.trim().isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    final normalized = uri
        .replace(
          path: uri.path == '/' ? '' : uri.path,
          query: null,
          fragment: null,
        )
        .toString();

    return _ParsedServerAddress(
      scheme: uri.scheme,
      normalizedBaseUrl: normalized,
    );
  }

  String? _validateAddress(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '请输入服务器地址';
    if (_parseAddress() == null) return '请输入正确的服务器地址';
    return null;
  }

  String? _displayNameOrNull() {
    final value = _nameCtrl.text.trim();
    return value.isEmpty ? null : value;
  }

  String? _remarkOrNull() {
    final value = _remarkCtrl.text.trim();
    return value.isEmpty ? null : value;
  }

  Uri? _buildIconSourceUri() {
    final parsed = _parseAddress();
    if (parsed == null) return null;
    final uri = Uri.tryParse(parsed.normalizedBaseUrl);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.path.isEmpty) {
      return uri.replace(path: '/');
    }
    return uri;
  }

  Future<void> _autoFetchIcon() async {
    if (_iconLoading) return;
    final uri = _buildIconSourceUri();
    if (uri == null) return;

    setState(() => _iconLoading = true);
    try {
      final meta = await WebsiteMetadataService.instance.fetch(uri);
      if (!mounted) return;
      final favicon = (meta.faviconUrl ?? '').trim();
      if (favicon.isNotEmpty) {
        setState(() => _iconUrl = favicon);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('自动获取图标失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _iconLoading = false);
      }
    }
  }

  Future<void> _pickIconFromLibrary() async {
    final pickedUrl = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ServerIconLibrarySheet(
        urlsListenable: widget.appState,
        getLibraryUrls: () => widget.appState.serverIconLibraryUrls,
        addLibraryUrl: widget.appState.addServerIconLibraryUrl,
        removeLibraryUrlAt: widget.appState.removeServerIconLibraryUrlAt,
        reorderLibraryUrls: widget.appState.reorderServerIconLibraryUrls,
        selectedUrl: _iconUrl,
      ),
    );
    if (!mounted || pickedUrl == null) return;
    setState(() {
      _iconUrl = pickedUrl.trim().isEmpty ? null : pickedUrl.trim();
    });
  }

  void _clearIcon() {
    setState(() => _iconUrl = null);
  }

  PlexApi _buildPlexApi() {
    return PlexApi(
      clientIdentifier: widget.appState.deviceId,
      product: AppConfigScope.of(context).displayName,
      device: 'Flutter',
      platform: 'Flutter',
      version: '1.0.0',
    );
  }

  Future<void> _startPlexLogin({required bool fillTokenOnly}) async {
    if (_plexLoading) return;

    setState(() {
      _plexLoading = true;
      _plexError = null;
      if (!fillTokenOnly) {
        _plexServers = const <PlexResource>[];
        _selectedPlexServer = null;
      }
    });

    try {
      final api = _buildPlexApi();
      final pin = await api.createPin();
      if (!mounted) return;
      setState(() {
        _plexPin = pin;
        _plexAccountToken = null;
      });

      final authUrl = api.buildAuthUrl(code: pin.code);
      final launched = await launchUrl(
        Uri.parse(authUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('无法打开浏览器完成 Plex 授权');
      }

      final deadline = (pin.expiresAt ??
              DateTime.now().toUtc().add(const Duration(minutes: 10)))
          .toLocal();
      PlexPin latest = pin;
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        latest = await api.fetchPin(pin.id);
        final token = (latest.authToken ?? '').trim();
        if (token.isNotEmpty) break;
      }

      final authToken = (latest.authToken ?? '').trim();
      if (authToken.isEmpty) {
        throw Exception('等待 Plex 授权超时或授权未完成');
      }

      if (!mounted) return;

      if (fillTokenOnly) {
        _plexTokenCtrl.text = authToken;
        setState(() {
          _plexAccountToken = authToken;
          _plexLoading = false;
        });
        return;
      }

      final resources = await api.fetchResources(authToken: authToken);
      final servers = resources.where((r) => r.isServer).toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _plexAccountToken = authToken;
        _plexServers = servers;
        _selectedPlexServer = servers.isEmpty ? null : servers.first;
        _plexLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _plexLoading = false;
        _plexError = e.toString();
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || widget.appState.isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _plexError = null;
    });

    try {
      final displayName = _displayNameOrNull();
      final remark = _remarkOrNull();
      String? addedId;

      if (_serverType == MediaServerType.plex) {
        if (_plexMode == _PlexAddMode.account) {
          final selected = _selectedPlexServer;
          final serverUri = selected?.pickBestConnectionUri();
          final token =
              (selected?.accessToken ?? _plexAccountToken ?? '').trim();
          if (selected == null || (serverUri ?? '').trim().isEmpty) {
            setState(() => _plexError = '请选择 Plex 服务器');
            return;
          }
          if (token.isEmpty) {
            setState(() => _plexError = '没有获取到 Plex Token，请重新登录');
            return;
          }
          await widget.appState.addPlexServer(
            baseUrl: serverUri!.trim(),
            token: token,
            displayName: displayName ?? selected.name.trim(),
            remark: remark,
            iconUrl: _iconUrl,
          );
        } else {
          final parsed = _parseAddress();
          if (parsed == null) return;
          final token = _plexTokenCtrl.text.trim();
          if (token.isEmpty) {
            setState(() => _plexError = '请输入 Plex Token');
            return;
          }
          await widget.appState.addPlexServer(
            baseUrl: parsed.normalizedBaseUrl,
            token: token,
            displayName: displayName,
            remark: remark,
            iconUrl: _iconUrl,
          );
        }
      } else if (_serverType == MediaServerType.webdav) {
        final parsed = _parseAddress();
        if (parsed == null) return;
        addedId = await widget.appState.addWebDavServer(
          baseUrl: parsed.normalizedBaseUrl,
          username: _userCtrl.text.trim(),
          password: _pwdCtrl.text,
          displayName: displayName,
          remark: remark,
          iconUrl: _iconUrl,
          activate: false,
        );
      } else {
        final parsed = _parseAddress();
        if (parsed == null) return;
        addedId = await widget.appState.addServer(
          hostOrUrl: parsed.normalizedBaseUrl,
          scheme: parsed.scheme,
          port: null,
          serverType: _serverType,
          username: _userCtrl.text.trim(),
          password: _pwdCtrl.text,
          displayName: displayName,
          remark: remark,
          iconUrl: _iconUrl,
          activate: false,
        );
      }

      if (!mounted) return;
      final error = (widget.appState.error ?? '').trim();
      if (error.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }

      Navigator.of(context).pop(addedId);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final availableTypes = _availableServerTypes(context);
    final busy = _submitting || widget.appState.isLoading;
    final showAddressField =
        _serverType != MediaServerType.plex || _plexMode == _PlexAddMode.manual;
    final showUserPass =
        _serverType.isEmbyLike || _serverType == MediaServerType.webdav;
    final showBulkImport = _serverType.isEmbyLike;
    final showPlexToken =
        _serverType == MediaServerType.plex && _plexMode == _PlexAddMode.manual;

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加服务器'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colorScheme.surface,
              colorScheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableTypes.map((type) {
                    final assetPath = _assetForType(type);
                    return _CompactOptionChip(
                      assetPath: assetPath,
                      icon: assetPath == null ? Icons.hd_outlined : null,
                      label: type.label,
                      selected: type == _serverType,
                      onTap: busy ? null : () => _setServerType(type),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: busy ? null : _openBackupImport,
                    icon: const Icon(Icons.settings_backup_restore_outlined),
                    label: const Text('从备份导入服务器'),
                  ),
                ),
                if (showBulkImport) ...<Widget>[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: busy ? null : _openBulkImport,
                      icon: const Icon(Icons.playlist_add_outlined),
                      label: const Text('批量导入分享文本'),
                    ),
                  ),
                ],
                if (_serverType == MediaServerType.plex) ...<Widget>[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _PlexAddMode.values.map((mode) {
                      return _CompactOptionChip(
                        icon: mode == _PlexAddMode.manual
                            ? Icons.edit_outlined
                            : Icons.login_rounded,
                        label: mode.label,
                        selected: mode == _plexMode,
                        onTap: busy
                            ? null
                            : () {
                                setState(() {
                                  _plexMode = mode;
                                  _plexError = null;
                                });
                              },
                      );
                    }).toList(growable: false),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color:
                        colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: <Widget>[
                      ServerIconAvatar(
                        iconUrl: _iconUrl,
                        name: _nameCtrl.text,
                        radius: 18,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('服务器图标'),
                      ),
                      IconButton(
                        tooltip: '自动获取',
                        onPressed:
                            (_iconLoading || busy) ? null : _autoFetchIcon,
                        icon: _iconLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.travel_explore_outlined),
                      ),
                      IconButton(
                        tooltip: '图标库',
                        onPressed: busy ? null : _pickIconFromLibrary,
                        icon: const Icon(Icons.collections_outlined),
                      ),
                      IconButton(
                        tooltip: '清空',
                        onPressed: busy ? null : _clearIcon,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: _inputDecoration(
                    context,
                    labelText: '服务器名称',
                  ),
                ),
                if (showAddressField) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    keyboardType: TextInputType.url,
                    decoration: _inputDecoration(
                      context,
                      labelText: '服务器地址',
                      hintText: 'https://emby.example.com:8096',
                    ),
                    validator: (value) {
                      if (!showAddressField) return null;
                      return _validateAddress(value);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _remarkCtrl,
                  decoration: _inputDecoration(
                    context,
                    labelText: '备注',
                  ),
                ),
                if (showUserPass) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _userCtrl,
                    decoration: _inputDecoration(
                      context,
                      labelText: '账号',
                    ),
                    validator: (value) {
                      if (!showUserPass) return null;
                      if (value == null || value.trim().isEmpty) {
                        return '请输入账号';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pwdCtrl,
                    decoration: _inputDecoration(
                      context,
                      labelText: '密码',
                      suffixIcon: IconButton(
                        tooltip: _pwdVisible ? '隐藏密码' : '显示密码',
                        onPressed: () =>
                            setState(() => _pwdVisible = !_pwdVisible),
                        icon: Icon(
                          _pwdVisible ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                    obscureText: !_pwdVisible,
                  ),
                ],
                if (showPlexToken) ...<Widget>[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: (_plexLoading || busy)
                          ? null
                          : () => _startPlexLogin(fillTokenOnly: true),
                      icon: _plexLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: const Text('Plex Token'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _plexTokenCtrl,
                    decoration: _inputDecoration(
                      context,
                      labelText: 'Plex Token',
                      suffixIcon: IconButton(
                        tooltip: _plexTokenVisible ? '隐藏 Token' : '显示 Token',
                        onPressed: () => setState(
                          () => _plexTokenVisible = !_plexTokenVisible,
                        ),
                        icon: Icon(
                          _plexTokenVisible
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                    obscureText: !_plexTokenVisible,
                    validator: (value) {
                      if (!showPlexToken) return null;
                      if (value == null || value.trim().isEmpty) {
                        return '请输入 Plex Token';
                      }
                      return null;
                    },
                  ),
                ],
                if (_serverType == MediaServerType.plex &&
                    _plexMode == _PlexAddMode.account) ...<Widget>[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: (_plexLoading || busy)
                          ? null
                          : () => _startPlexLogin(fillTokenOnly: false),
                      icon: _plexLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(
                        _plexAccountToken == null ? 'Plex 登录' : 'Plex 重新登录',
                      ),
                    ),
                  ),
                  if ((_plexPin?.code ?? '').trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _plexPin!.code,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (_plexServers.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PlexResource>(
                      initialValue: _selectedPlexServer,
                      decoration: _inputDecoration(
                        context,
                        labelText: 'Plex 服务器',
                      ),
                      items: _plexServers
                          .map(
                            (resource) => DropdownMenuItem<PlexResource>(
                              value: resource,
                              child: Text(
                                resource.name.trim().isEmpty
                                    ? resource.clientIdentifier
                                    : resource.name,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: busy
                          ? null
                          : (value) {
                              setState(() {
                                _selectedPlexServer = value;
                                _plexError = null;
                              });
                            },
                      validator: (value) {
                        if (_plexMode != _PlexAddMode.account) {
                          return null;
                        }
                        return value == null ? '请选择服务器' : null;
                      },
                    ),
                  ],
                ],
                if ((_plexError ?? '').trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _plexError!.trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: busy ? null : _submit,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _serverType == MediaServerType.plex ? '保存服务器' : '连接并进入',
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactOptionChip extends StatelessWidget {
  const _CompactOptionChip({
    this.icon,
    this.assetPath,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData? icon;
  final String? assetPath;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.92)
        : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5);
    final foreground =
        selected ? colorScheme.onPrimaryContainer : colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: background,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if ((assetPath ?? '').trim().isNotEmpty)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Image.asset(
                    assetPath!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParsedServerAddress {
  const _ParsedServerAddress({
    required this.scheme,
    required this.normalizedBaseUrl,
  });

  final String scheme;
  final String normalizedBaseUrl;
}
