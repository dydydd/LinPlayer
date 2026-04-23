import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lin_player_player/lin_player_player.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_server_api/services/http_stream_proxy.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../danmaku_settings_page.dart';
import '../common/mobile_shell_page.dart';
import '../../plugins/plugins_page.dart';
import '../../services/browsing_cache_service.dart';
import '../../services/app_diagnostics_report.dart';
import '../../services/app_update_flow.dart';
import '../../services/app_update_service.dart';
import '../../settings_page.dart';

enum _BackupIoAction { file, clipboard }

enum _MobileSettingsSection {
  appearance,
  playback,
  interaction,
  danmaku,
  app,
}

class MobileSettingsPage extends StatefulWidget {
  const MobileSettingsPage({
    super.key,
    required this.appState,
    this.embeddedInShell = false,
  });

  final AppState appState;
  final bool embeddedInShell;

  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  static const _donateUrl = 'https://afdian.com/a/zzzwannasleep';
  static const _customSentinel = '__custom__';
  static const _subtitleOff = 'off';

  final ScrollController _scrollController = ScrollController();
  late final Map<_MobileSettingsSection, GlobalKey> _sectionKeys = {
    for (final section in _MobileSettingsSection.values) section: GlobalKey(),
  };

  _MobileSettingsSection? _expandedSection = _MobileSettingsSection.appearance;
  double? _mpvCacheDraftMb;
  double? _bufferBackRatioDraft;
  double? _markPlayedThresholdDraftPct;
  double? _longPressMultiplierDraft;
  double? _bufferSpeedRefreshSecondsDraft;
  double? _seekBackwardDraft;
  double? _seekForwardDraft;
  int? _coverCacheSizeBytes;
  bool _checkingUpdate = false;
  String _currentVersionFull = '';

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    unawaited(_refreshCoverCacheSize());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _currentVersionFull = AppUpdateService.packageVersionFull(info);
      });
    } catch (_) {}
  }

  Future<void> _refreshCoverCacheSize() async {
    if (kIsWeb) return;
    try {
      final bytes = await CoverCacheManager.instance.store.getCacheSize();
      if (!mounted) return;
      setState(() => _coverCacheSizeBytes = bytes);
    } catch (_) {}
  }

  Future<void> _toggleSection(_MobileSettingsSection section) async {
    final next = _expandedSection == section ? null : section;
    setState(() => _expandedSection = next);
    if (next == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    final sectionContext = _sectionKeys[section]?.currentContext;
    if (sectionContext == null || !sectionContext.mounted) return;
    unawaited(
      Scrollable.ensureVisible(
        sectionContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context, {bool showTicks = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return theme.sliderTheme.copyWith(
      trackHeight: 8,
      activeTrackColor: cs.primary.withValues(alpha: 0.55),
      inactiveTrackColor: cs.onSurface.withValues(alpha: 0.18),
      thumbColor: cs.primary.withValues(alpha: 0.9),
      overlayColor: cs.primary.withValues(alpha: 0.12),
      thumbShape: const _BarThumbShape(width: 4, height: 28),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      trackShape: const RoundedRectSliderTrackShape(),
      showValueIndicator: ShowValueIndicator.never,
      tickMarkShape: showTicks
          ? const RoundSliderTickMarkShape(tickMarkRadius: 2.4)
          : const RoundSliderTickMarkShape(tickMarkRadius: 0),
      activeTickMarkColor: cs.primary.withValues(alpha: 0.75),
      inactiveTickMarkColor: cs.onSurface.withValues(alpha: 0.25),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => '\u8ddf\u968f\u7cfb\u7edf',
      ThemeMode.light => '\u6d45\u8272',
      ThemeMode.dark => '\u6df1\u8272',
    };
  }

  IconData _themeModeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };
  }

  String _themeTemplateLabel(String template) {
    return AppTheme.labelFor(template);
  }

  String _appearanceSummaryText(AppState appState) {
    final palette = _themeTemplateLabel(appState.themeTemplate);
    final blur = appState.enableBlurEffects
        ? '\u6a21\u7cca\u5df2\u5f00'
        : '\u6a21\u7cca\u5df2\u5173';
    return '${_themeModeLabel(appState.themeMode)} 路 $palette 路 $blur';
  }

  // ignore: unused_element
  String _appearanceSummary(AppState appState) {
    final monet = appState.useDynamicColor
        ? '\u83ab\u5948\u53d6\u8272\u5df2\u5f00'
        : '\u83ab\u5948\u53d6\u8272\u5df2\u5173';
    final blur = appState.enableBlurEffects
        ? '\u6a21\u7cca\u5df2\u5f00'
        : '\u6a21\u7cca\u5df2\u5173';
    return '${_themeModeLabel(appState.themeMode)} · $monet · $blur';
  }

  String _playbackSummary(AppState appState) {
    final preload = appState.preloadEnabled
        ? '\u9884\u52a0\u8f7d\u5df2\u5f00'
        : '\u9884\u52a0\u8f7d\u5df2\u5173';
    return '${appState.preferredVideoVersion.label} · ${appState.playbackBufferPreset.label} · $preload';
  }

  String _interactionSummary(AppState appState) {
    final gestures = <String>[
      if (appState.gestureBrightness) '\u4eae\u5ea6',
      if (appState.gestureVolume) '\u97f3\u91cf',
      if (appState.gestureSeek) '\u8fdb\u5ea6',
    ];
    final gestureText = gestures.isEmpty
        ? '\u624b\u52bf\u5df2\u5168\u90e8\u5173\u95ed'
        : '\u624b\u52bf\uff1a${gestures.join('/')}';
    return '$gestureText · \u53cc\u51fb\u64cd\u4f5c';
  }

  String _danmakuSummary(AppState appState) {
    if (!appState.danmakuEnabled) {
      return '\u5f39\u5e55\u5df2\u5173\u95ed';
    }
    return appState.danmakuLoadMode == DanmakuLoadMode.online
        ? '\u5728\u7ebf\u5f39\u5e55'
        : '\u672c\u5730 XML \u5f39\u5e55';
  }

  String _appSummary(AppState appState) {
    final update = appState.autoUpdateEnabled
        ? '\u81ea\u52a8\u66f4\u65b0\u5df2\u5f00'
        : '\u81ea\u52a8\u66f4\u65b0\u5df2\u5173';
    return '$update · \u8bca\u65ad\u65e5\u5fd7 · \u7f13\u5b58\u7ba1\u7406';
  }

  double _dropdownWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) return 120;
    if (width < 420) return 136;
    return 156;
  }

  List<DropdownMenuItem<String>> _audioLangItems(String current) {
    final base = <MapEntry<String, String>>[
      const MapEntry('', '\u9ed8\u8ba4'),
      const MapEntry('chi', '\u4e2d\u6587'),
      const MapEntry('jpn', '\u65e5\u8bed'),
      const MapEntry('eng', '\u82f1\u8bed'),
      const MapEntry(_customSentinel, '\u81ea\u5b9a\u4e49\u2026'),
    ];
    final isKnown = base.any((entry) => entry.key == current);
    return <DropdownMenuItem<String>>[
      if (current.trim().isNotEmpty && !isKnown)
        DropdownMenuItem(
          value: current,
          child: Text('\u81ea\u5b9a\u4e49\uff1a$current'),
        ),
      ...base.map(
        (entry) => DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value),
        ),
      ),
    ];
  }

  List<DropdownMenuItem<String>> _subtitleLangItems(String current) {
    final base = <MapEntry<String, String>>[
      const MapEntry('', '\u9ed8\u8ba4'),
      const MapEntry(_subtitleOff, '\u5173\u95ed'),
      const MapEntry('chi', '\u4e2d\u6587'),
      const MapEntry('jpn', '\u65e5\u8bed'),
      const MapEntry('eng', '\u82f1\u8bed'),
      const MapEntry(_customSentinel, '\u81ea\u5b9a\u4e49\u2026'),
    ];
    final isKnown = base.any((entry) => entry.key == current);
    return <DropdownMenuItem<String>>[
      if (current.trim().isNotEmpty && !isKnown)
        DropdownMenuItem(
          value: current,
          child: Text('\u81ea\u5b9a\u4e49\uff1a$current'),
        ),
      ...base.map(
        (entry) => DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value),
        ),
      ),
    ];
  }

  Future<String?> _askCustomLang(
    BuildContext context, {
    required String title,
    String? initial,
  }) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'chi / zho / jpn / eng / zh / en / ja',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('\u4fdd\u5b58'),
          ),
        ],
      ),
    );
  }

  String _diagnosticsFileName() {
    final now = DateTime.now();
    String pad2(int value) => value.toString().padLeft(2, '0');
    final y = now.year.toString().padLeft(4, '0');
    final m = pad2(now.month);
    final d = pad2(now.day);
    final hh = pad2(now.hour);
    final mm = pad2(now.minute);
    final ss = pad2(now.second);
    return 'linplayer_diagnostics_$y$m${d}_$hh$mm$ss.txt';
  }

  Future<String?> _saveTextFile({
    required String dialogTitle,
    required String fileName,
    required String text,
    required List<String> allowedExtensions,
    required String fallbackExtension,
  }) async {
    final mobileBytes = (Platform.isAndroid || Platform.isIOS)
        ? Uint8List.fromList(utf8.encode(text))
        : null;
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      bytes: mobileBytes,
    );
    if (path == null || path.trim().isEmpty) return null;

    if (mobileBytes != null) return path;

    final normalized = _ensureKnownFileExtension(
      path,
      allowedExtensions: allowedExtensions,
      fallbackExtension: fallbackExtension,
    );
    await File(normalized).writeAsString(text, flush: true);
    return normalized;
  }

  String _ensureKnownFileExtension(
    String path, {
    required List<String> allowedExtensions,
    required String fallbackExtension,
  }) {
    final lowerPath = path.toLowerCase();
    for (final extension in allowedExtensions) {
      final normalizedExtension = extension.startsWith('.')
          ? extension.toLowerCase()
          : '.${extension.toLowerCase()}';
      if (lowerPath.endsWith(normalizedExtension)) return path;
    }
    final normalizedFallback = fallbackExtension.startsWith('.')
        ? fallbackExtension
        : '.$fallbackExtension';
    return '$path$normalizedFallback';
  }

  Future<T> _runWithBlockingDialog<T>(
    BuildContext context,
    Future<T> Function() action, {
    required String title,
    String subtitle = '\u8bf7\u7a0d\u5019\u2026',
  }) async {
    final navigator = Navigator.of(context);
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
      if (context.mounted) navigator.pop();
    }
  }

  Future<void> _exportDiagnosticsLog(BuildContext context) async {
    final action = await showDialog<_BackupIoAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u5bfc\u51fa\u8bca\u65ad\u65e5\u5fd7'),
        content: const Text(
          '\u5efa\u8bae\u5148\u590d\u73b0\u95ee\u9898\uff0c\u518d\u5bfc\u51fa\u672c\u6b21\u4f1a\u8bdd\u65e5\u5fd7\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('\u53d6\u6d88'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_BackupIoAction.clipboard),
            child: const Text('\u590d\u5236'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_BackupIoAction.file),
            child: const Text('\u4fdd\u5b58\u4e3a\u6587\u4ef6'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;

    try {
      final text = await _runWithBlockingDialog(
        context,
        () async {
          final extraSections = <String, String>{};
          extraSections['Preload Diagnostics'] =
              StreamPreloadService.instance.buildDiagnosticsText(
            maxEntries: 24,
          );
          extraSections['HTTP Stream Proxy Diagnostics'] =
              HttpStreamProxyServer.instance.buildDiagnosticsText(
            maxEntries: 40,
          );
          extraSections['HTTP Stream Active Downloads'] =
              HttpStreamProxyServer.instance.buildActiveDownloadsText(
            maxEntries: 12,
          );
          return AppDiagnosticsReportBuilder.build(
            appState: widget.appState,
            currentVersionFull: _currentVersionFull,
            extraSections: extraSections,
          );
        },
        title: '\u6b63\u5728\u751f\u6210\u8bca\u65ad\u65e5\u5fd7',
        subtitle: '\u6536\u96c6\u5e94\u7528\u65e5\u5fd7\u4e2d\u2026',
      );

      switch (action) {
        case _BackupIoAction.clipboard:
          await Clipboard.setData(ClipboardData(text: text));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('\u5df2\u590d\u5236\u8bca\u65ad\u65e5\u5fd7')),
          );
          return;
        case _BackupIoAction.file:
          final savedPath = await _saveTextFile(
            dialogTitle: '\u4fdd\u5b58\u8bca\u65ad\u65e5\u5fd7',
            fileName: _diagnosticsFileName(),
            text: text,
            allowedExtensions: const ['txt', 'log'],
            fallbackExtension: 'txt',
          );
          if (savedPath == null || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('\u5df2\u5bfc\u51fa\u8bca\u65ad\u65e5\u5fd7')),
          );
          return;
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '\u5bfc\u51fa\u8bca\u65ad\u65e5\u5fd7\u5931\u8d25\uff1a$e')),
      );
    }
  }

  Future<void> _checkUpdates(BuildContext context) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      await AppUpdateFlow.manualCheck(context, appState: widget.appState);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u68c0\u67e5\u66f4\u65b0\u5931\u8d25\uff1a$e')),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  String _formatMb(int? bytes) {
    if (bytes == null) return '--MB';
    if (bytes <= 0) return '0MB';
    final mb = bytes / (1024 * 1024);
    final digits = mb < 10 ? 1 : 0;
    return '${mb.toStringAsFixed(digits)}MB';
  }

  Future<bool> _confirmEnableUnlimitedStreamCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _UnlimitedStreamCacheConfirmDialog(),
    );
    return confirmed == true;
  }

  Future<void> _clearVideoCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u6e05\u7406\u89c6\u9891\u6d41\u7f13\u5b58'),
        content: const Text(
          '\u5c06\u5220\u9664\u5df2\u7f13\u5b58\u7684\u89c6\u9891\u6d41\u6570\u636e\uff0c\u4e0b\u6b21\u64ad\u653e\u65f6\u4f1a\u91cd\u65b0\u7f13\u5b58\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('\u6e05\u7406'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await StreamCache.clear();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('\u5df2\u6e05\u7406\u89c6\u9891\u6d41\u7f13\u5b58')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u6e05\u7406\u5931\u8d25\uff1a$e')),
      );
    }
  }

  Future<void> _clearCoverCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u6e05\u7406\u5c01\u9762\u7f13\u5b58'),
        content: const Text(
          '\u5c06\u5220\u9664\u5df2\u7f13\u5b58\u7684\u5c01\u9762\u3001\u968f\u673a\u63a8\u8350\u56fe\u7247\uff0c\u4e0b\u6b21\u5c55\u793a\u65f6\u4f1a\u91cd\u65b0\u4e0b\u8f7d\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('\u6e05\u7406'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await CoverCacheManager.instance.emptyCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      unawaited(_refreshCoverCacheSize());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('\u5df2\u6e05\u7406\u5c01\u9762\u7f13\u5b58')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u6e05\u7406\u5931\u8d25\uff1a$e')),
      );
    }
  }

  Future<void> _clearBrowsingCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u6e05\u7406\u6d4f\u89c8\u7f13\u5b58'),
        content: const Text(
          '\u5c06\u5220\u9664\u9996\u9875\u3001\u7ee7\u7eed\u89c2\u770b\u3001\u8be6\u60c5\u9875\u7b49\u5185\u5bb9\u7f13\u5b58\uff0c\u4e0b\u6b21\u6253\u5f00\u65f6\u4f1a\u91cd\u65b0\u52a0\u8f7d\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('\u6e05\u7406'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.appState.clearPersistedBrowsingCache();
      await BrowsingCacheService.instance.clearAll();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u5df2\u6e05\u7406\u6d4f\u89c8\u7f13\u5b58'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u6e05\u7406\u5931\u8d25\uff1a$e')),
      );
    }
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required _MobileSettingsSection section,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final expanded = _expandedSection == section;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: _sectionKeys[section],
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.96),
            colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(
          color: expanded
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 10),
            color: colorScheme.shadow.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _toggleSection(section),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: colorScheme.primary.withValues(alpha: 0.12),
                      ),
                      child: Icon(icon, color: colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: expanded ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      height: 1.35,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: expanded
                ? Column(
                    children: [
                      Divider(
                        height: 1,
                        thickness: 1,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.7),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                        child: child,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildCuratedAppearanceSection(
    BuildContext context,
    AppState appState,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u4e3b\u9898\u6a21\u5f0f',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 16) / 3;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ThemeMode.values
                  .map(
                    (mode) => SizedBox(
                      width: itemWidth,
                      child: _ThemeModeCard(
                        label: _themeModeLabel(mode),
                        icon: _themeModeIcon(mode),
                        selected: appState.themeMode == mode,
                        onTap: () => appState.setThemeMode(mode),
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary.withValues(alpha: 0.08),
                colorScheme.secondary.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u914d\u8272\u65b9\u6848',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\u4f7f\u7528\u56fa\u5b9a\u914d\u8272\uff0ciOS \u548c Android \u90fd\u4f1a\u76f4\u63a5\u5957\u7528\u540c\u4e00\u5957\u4e3b\u9898\u3002',
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isTwoColumn = constraints.maxWidth >= 360;
                  final itemWidth = isTwoColumn
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: AppTheme.palettes
                        .map(
                          (palette) => SizedBox(
                            width: itemWidth,
                            child: _ThemePaletteCard(
                              palette: palette,
                              preview: AppTheme.previewScheme(
                                paletteId: palette.id,
                                brightness: brightness,
                              ),
                              selected: appState.themeTemplate == palette.id,
                              onTap: () =>
                                  appState.setThemeTemplate(palette.id),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        SwitchListTile(
          value: appState.enableBlurEffects,
          onChanged: (value) => appState.setEnableBlurEffects(value),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.blur_on_outlined),
          title: const Text('\u5f00\u542f\u6a21\u7cca\u6548\u679c'),
          subtitle: const Text(
            '\u5173\u95ed\u540e\u8bbe\u7f6e\u9875\u548c\u90e8\u5206\u5361\u7247\u4f1a\u66f4\u7b80\u6d01',
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.showHomeLibraryQuickAccess,
          onChanged: (value) => appState.setShowHomeLibraryQuickAccess(value),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.home_outlined),
          title: const Text('\u9996\u9875\u5a92\u4f53\u5e93\u5feb\u6377\u680f'),
          subtitle: const Text(
            '\u5728\u300c\u7ee7\u7eed\u89c2\u770b\u300d\u4e0b\u65b9\u663e\u793a\u5a92\u4f53\u5e93\u5feb\u901f\u5165\u53e3',
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackSection(BuildContext context, AppState appState) {
    final sliderTheme = _sliderTheme(context);
    final dropdownWidth = _dropdownWidth(context);
    final markPlayedThreshold = (_markPlayedThresholdDraftPct ??
            appState.markPlayedThresholdPercent.toDouble())
        .round()
        .clamp(75, 100);
    final cacheMb =
        (_mpvCacheDraftMb ?? appState.mpvCacheSizeMb.toDouble()).round().clamp(
              200,
              2048,
            );
    final ratio = (_bufferBackRatioDraft ?? appState.playbackBufferBackRatio)
        .clamp(0.0, 0.30)
        .toDouble();
    final split = PlaybackBufferSplit.from(totalMb: cacheMb, backRatio: ratio);
    final backPct = (split.backRatio * 100).round();
    final forwardPct = 100 - backPct;

    return Column(
      children: [
        SwitchListTile(
          value: appState.autoSkipIntro,
          onChanged: (value) => appState.setAutoSkipIntro(value),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.skip_next_outlined),
          title: const Text('\u81ea\u52a8\u8df3\u8fc7\u7247\u5934'),
          subtitle: const Text(
            '\u670d\u52a1\u5668\u652f\u6301\u7247\u5934\u6570\u636e\u65f6\uff0c\u5728\u7247\u5934\u6bb5\u4f1a\u63d0\u793a\u662f\u5426\u8df3\u8fc7',
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.preloadEnabled,
          onChanged: (value) => appState.setPreloadEnabled(value),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.download_outlined),
          title: const Text('\u9884\u52a0\u8f7d'),
          subtitle: const Text(
            '\u8be6\u60c5\u9875\u9884\u52a0\u8f7d\u524d 3 \u79d2\uff0c\u7eed\u770b\u65f6\u4ece\u8fdb\u5ea6\u5904\u9884\u52a0\u8f7d\uff0c\u5e76\u5728\u8fbe\u5230\u89c2\u770b\u9608\u503c\u540e\u9884\u52a0\u8f7d\u4e0b\u4e00\u96c6\u524d 3 \u79d2\u3002',
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.unlimitedStreamCache,
          onChanged: (value) async {
            if (value) {
              final confirmed =
                  await _confirmEnableUnlimitedStreamCache(context);
              if (!confirmed) return;
            }
            await appState.setUnlimitedStreamCache(value);
          },
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.all_inclusive),
          title: const Text('\u4e0d\u9650\u5236\u89c6\u9891\u6d41\u7f13\u5b58'),
          subtitle: const Text(
            '\u5f00\u542f\u540e\u5728\u7ebf\u64ad\u653e\u4f1a\u5c3d\u91cf\u7f13\u5b58\u5230\u7ed3\u675f\uff0c\u8bf7\u8c28\u614e\u4f7f\u7528',
          ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.task_alt_outlined),
          title: const Text('\u6807\u8bb0\u5df2\u64ad\u653e\u9608\u503c'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '\u5f53\u524d\uff1a$markPlayedThreshold%  (75-100%)',
                    ),
                  ),
                  TextButton(
                    onPressed: markPlayedThreshold == 90 &&
                            _markPlayedThresholdDraftPct == null
                        ? null
                        : () {
                            setState(() => _markPlayedThresholdDraftPct = null);
                            appState.setMarkPlayedThresholdPercent(90);
                          },
                    child: const Text('\u91cd\u7f6e'),
                  ),
                ],
              ),
              SliderTheme(
                data: sliderTheme,
                child: AppSlider(
                  value: markPlayedThreshold.toDouble(),
                  min: 75,
                  max: 100,
                  divisions: 25,
                  label: '$markPlayedThreshold%',
                  onChanged: (value) =>
                      setState(() => _markPlayedThresholdDraftPct = value),
                  onChangeEnd: (value) {
                    final next = value.round().clamp(75, 100);
                    setState(() => _markPlayedThresholdDraftPct = null);
                    appState.setMarkPlayedThresholdPercent(next);
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storage_outlined),
          title: const Text('\u64ad\u653e\u7f13\u51b2\u5927\u5c0f'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('\u5f53\u524d\uff1a${cacheMb}MB  (200-2048MB)'),
              SliderTheme(
                data: sliderTheme,
                child: AppSlider(
                  value: cacheMb.toDouble(),
                  min: 200,
                  max: 2048,
                  divisions: 2048 - 200,
                  label: '${cacheMb}MB',
                  onChanged: (value) =>
                      setState(() => _mpvCacheDraftMb = value),
                  onChangeEnd: (value) {
                    final next = value.round().clamp(200, 2048);
                    setState(() => _mpvCacheDraftMb = null);
                    appState.setMpvCacheSizeMb(next);
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune_outlined),
          title: const Text('\u7f13\u51b2\u7b56\u7565'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u56de\u9000\uff1a${split.backMb}MB  $backPct%   \u5411\u524d\uff1a${split.forwardMb}MB  $forwardPct%',
              ),
              const SizedBox(height: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<PlaybackBufferPreset>(
                  value: appState.playbackBufferPreset,
                  isExpanded: true,
                  items: PlaybackBufferPreset.values
                      .map(
                        (preset) => DropdownMenuItem(
                          value: preset,
                          child: Text(preset.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _bufferBackRatioDraft = null);
                    await appState.setPlaybackBufferPreset(value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        '\u56de\u9000\u6bd4\u4f8b\uff1a$backPct%  (0-30%)'),
                  ),
                  TextButton(
                    onPressed: appState.playbackBufferPreset ==
                                PlaybackBufferPreset.seekFast &&
                            (appState.playbackBufferBackRatio - 0.05).abs() <
                                0.00001 &&
                            _bufferBackRatioDraft == null
                        ? null
                        : () {
                            appState.setPlaybackBufferPreset(
                              PlaybackBufferPreset.seekFast,
                            );
                            setState(() => _bufferBackRatioDraft = null);
                          },
                    child: const Text('\u91cd\u7f6e'),
                  ),
                ],
              ),
              SliderTheme(
                data: sliderTheme,
                child: AppSlider(
                  value: split.backRatio,
                  min: 0.0,
                  max: 0.30,
                  divisions: 30,
                  label: '$backPct%',
                  onChanged: (value) =>
                      setState(() => _bufferBackRatioDraft = value),
                  onChangeEnd: (value) {
                    setState(() => _bufferBackRatioDraft = null);
                    appState.setPlaybackBufferBackRatio(value);
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.flushBufferOnSeek,
          onChanged: (value) => appState.setFlushBufferOnSeek(value),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.flash_on_outlined),
          title: const Text('\u8df3\u8f6c\u65f6\u6e05\u7a7a\u65e7\u7f13\u51b2'),
          subtitle: const Text(
            '\u5feb\u8fdb\u3001\u5feb\u9000\u6216\u62d6\u52a8\u8fdb\u5ea6\u540e\uff0c\u4f18\u5148\u7f13\u51b2\u65b0\u4f4d\u7f6e',
          ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.video_file_outlined),
          title: const Text('\u4f18\u5148\u89c6\u9891\u7248\u672c'),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dropdownWidth),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<VideoVersionPreference>(
                value: appState.preferredVideoVersion,
                isExpanded: true,
                items: VideoVersionPreference.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  appState.setPreferredVideoVersion(value);
                },
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.audiotrack),
          title: const Text('\u4f18\u5148\u97f3\u8f68'),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dropdownWidth),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: appState.preferredAudioLang,
                isExpanded: true,
                items: _audioLangItems(appState.preferredAudioLang),
                onChanged: (value) async {
                  if (value == null) return;
                  if (value == _customSentinel) {
                    final code = await _askCustomLang(
                      context,
                      title: '\u81ea\u5b9a\u4e49\u97f3\u8f68\u8bed\u8a00',
                      initial: appState.preferredAudioLang,
                    );
                    if (code == null) return;
                    await appState.setPreferredAudioLang(code);
                    return;
                  }
                  await appState.setPreferredAudioLang(value);
                },
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.subtitles_outlined),
          title: const Text('\u4f18\u5148\u5b57\u5e55'),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dropdownWidth),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: appState.preferredSubtitleLang,
                isExpanded: true,
                items: _subtitleLangItems(appState.preferredSubtitleLang),
                onChanged: (value) async {
                  if (value == null) return;
                  if (value == _customSentinel) {
                    final code = await _askCustomLang(
                      context,
                      title: '\u81ea\u5b9a\u4e49\u5b57\u5e55\u8bed\u8a00',
                      initial: appState.preferredSubtitleLang,
                    );
                    if (code == null) return;
                    await appState.setPreferredSubtitleLang(code);
                    return;
                  }
                  await appState.setPreferredSubtitleLang(value);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInteractionSection(BuildContext context, AppState appState) {
    final sliderTheme = _sliderTheme(context);
    final dropdownWidth = _dropdownWidth(context);
    final longPressMultiplier =
        _longPressMultiplierDraft ?? appState.longPressSpeedMultiplier;
    final bufferSpeedRefreshSeconds =
        (_bufferSpeedRefreshSecondsDraft ?? appState.bufferSpeedRefreshSeconds)
            .clamp(0.2, 3.0)
            .toDouble();
    final seekBackward =
        (_seekBackwardDraft ?? appState.seekBackwardSeconds.toDouble())
            .round()
            .clamp(1, 120);
    final seekForward =
        (_seekForwardDraft ?? appState.seekForwardSeconds.toDouble())
            .round()
            .clamp(1, 120);

    return Column(
      children: [
        if (!_isDesktopPlatform) ...[
          SwitchListTile(
            value: appState.gestureBrightness,
            onChanged: (value) => appState.setGestureBrightness(value),
            contentPadding: EdgeInsets.zero,
            title:
                const Text('\u5de6\u4fa7\u5c4f\u5e55\u4e0a\u4e0b\u6ed1\u52a8'),
            subtitle: const Text('\u8c03\u6574\u5c4f\u5e55\u4eae\u5ea6'),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: appState.gestureVolume,
            onChanged: (value) => appState.setGestureVolume(value),
            contentPadding: EdgeInsets.zero,
            title:
                const Text('\u53f3\u4fa7\u5c4f\u5e55\u4e0a\u4e0b\u6ed1\u52a8'),
            subtitle: const Text(
              'Android 调整播放器音量，iOS 调整系统音量',
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: appState.gestureSeek,
            onChanged: (value) => appState.setGestureSeek(value),
            contentPadding: EdgeInsets.zero,
            title: const Text('\u6a2a\u5411\u6ed1\u52a8'),
            subtitle: const Text('\u8c03\u6574\u89c6\u9891\u8fdb\u5ea6'),
          ),
          const Divider(height: 1),
        ],
        SwitchListTile(
          value: appState.gestureLongPressSpeed,
          onChanged: (value) => appState.setGestureLongPressSpeed(value),
          contentPadding: EdgeInsets.zero,
          title: const Text('\u957f\u6309\u52a0\u901f'),
        ),
        const Divider(height: 1),
        _SliderTile(
          leading: const Icon(Icons.speed_outlined),
          title: const Text('\u957f\u6309\u65f6\u7684\u901f\u5ea6\u500d\u7387'),
          subtitle: const Text(
              '\u4f1a\u57fa\u4e8e\u5f53\u524d\u64ad\u653e\u901f\u7387\u53e0\u52a0'),
          value: longPressMultiplier,
          min: 0.25,
          max: 5.0,
          divisions: 19,
          trailing: Text(longPressMultiplier.toStringAsFixed(2)),
          sliderTheme: sliderTheme,
          onChanged: (value) =>
              setState(() => _longPressMultiplierDraft = value),
          onChangeEnd: (value) async {
            setState(() => _longPressMultiplierDraft = null);
            await appState.setLongPressSpeedMultiplier(value);
          },
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.longPressSlideSpeed,
          onChanged: (value) => appState.setLongPressSlideSpeed(value),
          contentPadding: EdgeInsets.zero,
          title: const Text(
              '\u957f\u6309\u65f6\u6ed1\u52a8\u8c03\u6574\u500d\u901f'),
        ),
        const Divider(height: 1),
        _doubleTapTile(
          context,
          title: '\u5c4f\u5e55\u5de6\u4fa7',
          value: appState.doubleTapLeft,
          dropdownWidth: dropdownWidth,
          onChanged: (value) => appState.setDoubleTapLeft(value),
        ),
        const Divider(height: 1),
        _doubleTapTile(
          context,
          title: '\u5c4f\u5e55\u4e2d\u95f4',
          value: appState.doubleTapCenter,
          dropdownWidth: dropdownWidth,
          onChanged: (value) => appState.setDoubleTapCenter(value),
        ),
        const Divider(height: 1),
        _doubleTapTile(
          context,
          title: '\u5c4f\u5e55\u53f3\u4fa7',
          value: appState.doubleTapRight,
          dropdownWidth: dropdownWidth,
          onChanged: (value) => appState.setDoubleTapRight(value),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.home_outlined),
          title: const Text(
              '\u64ad\u653e\u4e2d\u8fd4\u56de\u9996\u9875\u884c\u4e3a'),
          subtitle: Text(appState.returnHomeBehavior.label),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dropdownWidth),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ReturnHomeBehavior>(
                value: appState.returnHomeBehavior,
                isExpanded: true,
                items: ReturnHomeBehavior.values
                    .map(
                      (behavior) => DropdownMenuItem(
                        value: behavior,
                        child: Text(behavior.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  appState.setReturnHomeBehavior(value);
                },
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.showSystemTimeInControls,
          onChanged: (value) => appState.setShowSystemTimeInControls(value),
          contentPadding: EdgeInsets.zero,
          title: const Text(
              '\u5728\u63a7\u5236\u680f\u4e0a\u663e\u793a\u7cfb\u7edf\u65f6\u95f4'),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.showBufferSpeed,
          onChanged: (value) => appState.setShowBufferSpeed(value),
          contentPadding: EdgeInsets.zero,
          title: const Text('\u663e\u793a\u7f51\u901f'),
          subtitle: const Text(
              '\u5728\u7ebf\u64ad\u653e\u65f6\u5de6\u4e0b\u89d2\u5e38\u9a7b\u663e\u793a\u7f13\u51b2\u901f\u5ea6'),
        ),
        const Divider(height: 1),
        _SliderTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('\u7f51\u901f\u5237\u65b0\u95f4\u9694 (\u79d2)'),
          subtitle: const Text('0.2 - 3.0'),
          value: bufferSpeedRefreshSeconds,
          min: 0.2,
          max: 3.0,
          divisions: 28,
          trailing: Text('${bufferSpeedRefreshSeconds.toStringAsFixed(1)}s'),
          sliderTheme: sliderTheme,
          onChanged: (value) =>
              setState(() => _bufferSpeedRefreshSecondsDraft = value),
          onChangeEnd: (value) async {
            final seconds = (value * 10).round() / 10.0;
            setState(() => _bufferSpeedRefreshSecondsDraft = null);
            await appState.setBufferSpeedRefreshSeconds(seconds);
          },
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.showBatteryInControls,
          onChanged: (value) => appState.setShowBatteryInControls(value),
          contentPadding: EdgeInsets.zero,
          title: const Text(
              '\u5728\u63a7\u5236\u680f\u4e0a\u663e\u793a\u7535\u91cf'),
        ),
        const Divider(height: 1),
        _SliderTile(
          leading: const Icon(Icons.replay),
          title: const Text('\u5feb\u9000\u65f6\u95f4 (\u79d2)'),
          value: seekBackward.toDouble(),
          min: 1,
          max: 120,
          divisions: 119,
          trailing: Text('$seekBackward'),
          sliderTheme: sliderTheme,
          onChanged: (value) => setState(() => _seekBackwardDraft = value),
          onChangeEnd: (value) async {
            final seconds = value.round().clamp(1, 120);
            setState(() => _seekBackwardDraft = null);
            await appState.setSeekBackwardSeconds(seconds);
          },
        ),
        const Divider(height: 1),
        _SliderTile(
          leading: const Icon(Icons.forward),
          title: const Text('\u5feb\u8fdb\u65f6\u95f4 (\u79d2)'),
          value: seekForward.toDouble(),
          min: 1,
          max: 120,
          divisions: 119,
          trailing: Text('$seekForward'),
          sliderTheme: sliderTheme,
          onChanged: (value) => setState(() => _seekForwardDraft = value),
          onChangeEnd: (value) async {
            final seconds = value.round().clamp(1, 120);
            setState(() => _seekForwardDraft = null);
            await appState.setSeekForwardSeconds(seconds);
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '\u63d0\u793a\uff1a\u90e8\u5206\u624b\u52bf\u4f1a\u5f71\u54cd\u62d6\u52a8\u548c\u53cc\u51fb\u624b\u611f\uff0c\u53ef\u4ee5\u6309\u9700\u5173\u95ed\u3002',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildDanmakuSection(BuildContext context, AppState appState) {
    final dropdownWidth = _dropdownWidth(context);
    final sourceSubtitle = appState.danmakuLoadMode == DanmakuLoadMode.online
        ? '\u5728\u7ebf\uff1a${appState.danmakuApiUrls.isEmpty ? '\u672a\u914d\u7f6e\u5f39\u5e55\u6e90' : appState.danmakuApiUrls.first}'
        : '\u672c\u5730 XML \u5f39\u5e55';

    return Column(
      children: [
        SwitchListTile(
          value: appState.danmakuEnabled,
          onChanged: (value) => appState.setDanmakuEnabled(value),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.comment_outlined),
          title: const Text('\u542f\u7528\u5f39\u5e55'),
          subtitle: Text(sourceSubtitle),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.source_outlined),
          title: const Text('\u5f39\u5e55\u6765\u6e90'),
          trailing: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dropdownWidth),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DanmakuLoadMode>(
                value: appState.danmakuLoadMode,
                isExpanded: true,
                items: DanmakuLoadMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(mode.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  appState.setDanmakuLoadMode(value);
                },
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune_outlined),
          title: const Text('\u6253\u5f00\u5b8c\u6574\u5f39\u5e55\u8bbe\u7f6e'),
          subtitle: const Text(
            '\u5f39\u5e55\u6e90\u3001\u5c4f\u853d\u8bcd\u3001\u6837\u5f0f\u3001\u5339\u914d\u89c4\u5219',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DanmakuSettingsPage(appState: widget.appState),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAppSection(BuildContext context, AppState appState) {
    final appConfig = AppConfigScope.of(context);
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('\u5bfc\u51fa\u8bca\u65ad\u65e5\u5fd7'),
          subtitle: const Text(
            '\u590d\u73b0\u95ee\u9898\u540e\u5bfc\u51fa\u672c\u6b21\u4f1a\u8bdd\u65e5\u5fd7\uff0c\u65b9\u4fbf\u6392\u67e5',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _exportDiagnosticsLog(context),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.extension_outlined),
          title: const Text('\u63d2\u4ef6'),
          subtitle: const Text(
              '\u5b89\u88c5\u6216\u7ba1\u7406\u811a\u672c\u63d2\u4ef6'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PluginsPage(appState: widget.appState),
              ),
            );
          },
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_outline),
          title: const Text('\u6e05\u7406\u89c6\u9891\u6d41\u7f13\u5b58'),
          subtitle: const Text(
              '\u5220\u9664\u672c\u5730\u7f13\u5b58\u7684\u89c6\u9891\u6d41\u6570\u636e'),
          onTap: () => _clearVideoCache(context),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_outline),
          title: const Text('\u6e05\u7406\u5c01\u9762\u7f13\u5b58'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  '\u5220\u9664\u5df2\u7f13\u5b58\u7684\u5c01\u9762\u3001\u63a8\u8350\u56fe\u7247'),
              const SizedBox(height: 2),
              Text(
                '\u5df2\u7f13\u5b58\uff1a${_formatMb(_coverCacheSizeBytes)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          onTap: () => _clearCoverCache(context),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('\u6e05\u7406\u6d4f\u89c8\u7f13\u5b58'),
          subtitle: const Text(
            '\u5220\u9664\u9996\u9875\u3001\u7ee7\u7eed\u89c2\u770b\u3001\u8be6\u60c5\u9875\u7b49\u5185\u5bb9\u7f13\u5b58',
          ),
          onTap: () => _clearBrowsingCache(context),
        ),
        const Divider(height: 1),
        SwitchListTile(
          value: appState.autoUpdateEnabled,
          onChanged: (value) async {
            await appState.setAutoUpdateEnabled(value);
            if (value && context.mounted) {
              unawaited(
                AppUpdateFlow.maybeAutoCheck(
                  context,
                  appState: appState,
                  force: true,
                ),
              );
            }
          },
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.system_update),
          title: const Text('\u81ea\u52a8\u66f4\u65b0'),
          subtitle: const Text(
              '\u542f\u52a8\u65f6\u81ea\u52a8\u68c0\u67e5\u65b0\u7248\u672c'),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.system_update_alt_outlined),
          title: const Text('\u68c0\u67e5\u66f4\u65b0'),
          subtitle: _currentVersionFull.trim().isEmpty
              ? null
              : Text(
                  '\u5f53\u524d\u7248\u672c\uff1a${_currentVersionFull.trim()}'),
          trailing: _checkingUpdate
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: _checkingUpdate ? null : () => _checkUpdates(context),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.settings_suggest_outlined),
          title: const Text('\u6253\u5f00\u5b8c\u6574\u8bbe\u7f6e\u9875'),
          subtitle: const Text(
            '\u67e5\u770b\u5907\u4efd\u4e0e\u8fc1\u79fb\u3001\u684c\u9762/\u7535\u89c6\u9ad8\u7ea7\u9009\u9879\u7b49',
          ),
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsPage(appState: widget.appState),
              ),
            );
          },
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: const Text('\u5173\u4e8e'),
          subtitle: Text('${appConfig.displayName} (${appConfig.repoUrl})'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () async {
            final ok = await launchUrlString(appConfig.repoUrl);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '\u65e0\u6cd5\u6253\u5f00\u94fe\u63a5\uff0c\u8bf7\u68c0\u67e5\u7cfb\u7edf\u6d4f\u89c8\u5668\u6216\u7f51\u7edc\u8bbe\u7f6e',
                  ),
                ),
              );
            }
          },
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.volunteer_activism_outlined),
          title: const Text('\u6350\u8d60'),
          subtitle:
              const Text('\u652f\u6301\u4f5c\u8005\u7ee7\u7eed\u5f00\u53d1'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () async {
            final ok = await launchUrlString(_donateUrl);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    '\u65e0\u6cd5\u6253\u5f00\u94fe\u63a5\uff0c\u8bf7\u68c0\u67e5\u7cfb\u7edf\u6d4f\u89c8\u5668\u6216\u7f51\u7edc\u8bbe\u7f6e',
                  ),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _doubleTapTile(
    BuildContext context, {
    required String title,
    required DoubleTapAction value,
    required double dropdownWidth,
    required ValueChanged<DoubleTapAction> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.touch_app_outlined),
      title: Text(title),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dropdownWidth),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<DoubleTapAction>(
            value: value,
            isExpanded: true,
            items: DoubleTapAction.values
                .map(
                  (action) => DropdownMenuItem(
                    value: action,
                    child: Text(action.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (next) {
              if (next == null) return;
              onChanged(next);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final appState = widget.appState;
        final enableBlur = appState.enableBlurEffects;
        final colorScheme = Theme.of(context).colorScheme;
        final body = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surface,
                colorScheme.surfaceContainerLowest,
              ],
            ),
          ),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              _buildSectionCard(
                context,
                section: _MobileSettingsSection.appearance,
                icon: Icons.palette_outlined,
                title: '\u5916\u89c2\u8bbe\u7f6e',
                subtitle: _appearanceSummaryText(appState),
                child: _buildCuratedAppearanceSection(context, appState),
              ),
              const SizedBox(height: 12),
              _buildSectionCard(
                context,
                section: _MobileSettingsSection.playback,
                icon: Icons.play_circle_outline_rounded,
                title: '\u64ad\u653e\u8bbe\u7f6e',
                subtitle: _playbackSummary(appState),
                child: _buildPlaybackSection(context, appState),
              ),
              const SizedBox(height: 12),
              _buildSectionCard(
                context,
                section: _MobileSettingsSection.interaction,
                icon: Icons.touch_app_outlined,
                title: '\u4ea4\u4e92\u8bbe\u7f6e',
                subtitle: _interactionSummary(appState),
                child: _buildInteractionSection(context, appState),
              ),
              const SizedBox(height: 12),
              _buildSectionCard(
                context,
                section: _MobileSettingsSection.danmaku,
                icon: Icons.comment_outlined,
                title: '\u5f39\u5e55\u8bbe\u7f6e',
                subtitle: _danmakuSummary(appState),
                child: _buildDanmakuSection(context, appState),
              ),
              const SizedBox(height: 12),
              _buildSectionCard(
                context,
                section: _MobileSettingsSection.app,
                icon: Icons.apps_outlined,
                title: '\u5e94\u7528\u8bbe\u7f6e',
                subtitle: _appSummary(appState),
                child: _buildAppSection(context, appState),
              ),
            ],
          ),
        );

        if (widget.embeddedInShell) {
          return MobileShellPageFrame(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.surface,
                  colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
            header: MobileShellPageHeader(
              title: '设置',
              subtitle: '播放器、交互与应用偏好',
              enableBlur: enableBlur,
            ),
            child: body,
          );
        }

        return Scaffold(
          appBar: GlassAppBar(
            enableBlur: enableBlur,
            child: AppBar(
              title: const Text('\u8bbe\u7f6e'),
              centerTitle: true,
            ),
          ),
          body: body,
        );
      },
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.trailing,
    required this.sliderTheme,
    this.onChanged,
    this.onChangeEnd,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Widget trailing;
  final SliderThemeData sliderTheme;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: title,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) subtitle!,
          SliderTheme(
            data: sliderTheme,
            child: AppSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
      trailing: trailing,
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground =
        selected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : colorScheme.surface.withValues(alpha: 0.52),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.62)
                  : colorScheme.outlineVariant.withValues(alpha: 0.66),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
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

class _ThemePaletteCard extends StatelessWidget {
  const _ThemePaletteCard({
    required this.palette,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final AppThemePalette palette;
  final ColorScheme preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final swatches = <Color>[
      preview.primary,
      preview.secondary,
      preview.tertiary,
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                preview.primary.withValues(alpha: selected ? 0.22 : 0.16),
                preview.secondary.withValues(alpha: selected ? 0.16 : 0.1),
              ],
            ),
            border: Border.all(
              color: selected
                  ? preview.primary.withValues(alpha: 0.72)
                  : colorScheme.outlineVariant.withValues(alpha: 0.64),
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: selected ? 18 : 10,
                offset: const Offset(0, 8),
                color: preview.primary.withValues(
                  alpha: selected ? 0.16 : 0.08,
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      palette.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: preview.primary,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: swatches
                    .map(
                      (color) => Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 10),
              Text(
                palette.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarThumbShape extends SliderComponentShape {
  const _BarThumbShape({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? sliderTheme.activeTrackColor!;
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(width.clamp(2, 20)));
    context.canvas.drawRRect(rrect, paint);
  }
}

class _UnlimitedStreamCacheConfirmDialog extends StatefulWidget {
  const _UnlimitedStreamCacheConfirmDialog();

  @override
  State<_UnlimitedStreamCacheConfirmDialog> createState() =>
      _UnlimitedStreamCacheConfirmDialogState();
}

class _UnlimitedStreamCacheConfirmDialogState
    extends State<_UnlimitedStreamCacheConfirmDialog> {
  static const _waitSeconds = 3;

  int _remaining = _waitSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _remaining -= 1;
        if (_remaining <= 0) {
          _remaining = 0;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _remaining == 0;
    return AlertDialog(
      title: const Text('\u5f00\u542f\u4e0d\u9650\u5236\u7f13\u5b58\uff1f'),
      content: const Text(
        '\u5f00\u542f\u540e\u5c06\u4f1a\u4e00\u76f4\u7f13\u5b58\u5230\u7ed3\u675f\uff0c\u5b58\u5728\u88ab\u8bef\u5224\u4e3a\u4e0b\u8f7d\u7684\u98ce\u9669\u3002\n\n'
        '\u8bf7\u5728\u786e\u8ba4\u9700\u8981\u540e\u518d\u5f00\u542f\u3002',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton(
          onPressed: canConfirm ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            canConfirm ? '\u786e\u5b9a' : '\u786e\u5b9a\uff08$_remaining\uff09',
          ),
        ),
      ],
    );
  }
}
