import 'dart:async';

import 'package:flutter/material.dart';

import 'plugin_manager.dart';

class PluginGovernanceAutoChecker extends StatefulWidget {
  const PluginGovernanceAutoChecker({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<PluginGovernanceAutoChecker> createState() =>
      _PluginGovernanceAutoCheckerState();
}

class _PluginGovernanceAutoCheckerState
    extends State<PluginGovernanceAutoChecker> with WidgetsBindingObserver {
  static const Duration _auditInterval = Duration(hours: 6);

  Timer? _timer;
  bool _inProgress = false;
  DateTime? _lastCompletedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runAudit(force: true));
    });
    _timer = Timer.periodic(_auditInterval, (_) {
      if (!mounted) return;
      unawaited(_runAudit(force: false));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCompletedAt;
    if (last == null || DateTime.now().difference(last) >= _auditInterval) {
      unawaited(_runAudit(force: false));
    }
  }

  Future<void> _runAudit({required bool force}) async {
    if (_inProgress) return;
    if (!force) {
      final last = _lastCompletedAt;
      if (last != null && DateTime.now().difference(last) < _auditInterval) {
        return;
      }
    }

    _inProgress = true;
    try {
      final blocked =
          await PluginManagerV1.instance.auditInstalledBlockedPlugins();
      _lastCompletedAt = DateTime.now();
      if (!mounted || blocked.isEmpty) return;

      final newlyDisabled = blocked.where((e) => e.wasEnabled).toList();
      if (newlyDisabled.isEmpty) return;

      final first = newlyDisabled.first;
      final message = newlyDisabled.length == 1
          ? '插件已自动禁用：${first.id}${_reasonSuffix(first.reason)}'
          : '已自动禁用 ${newlyDisabled.length} 个被下架插件';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      _lastCompletedAt = DateTime.now();
    } finally {
      _inProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _reasonSuffix(String? reason) {
  final text = (reason ?? '').trim();
  if (text.isEmpty) return '';
  return '：$text';
}
