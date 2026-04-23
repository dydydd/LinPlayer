import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lin_player_prefs/lin_player_prefs.dart';
import 'package:lin_player_state/lin_player_state.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

class InteractionSettingsPage extends StatefulWidget {
  const InteractionSettingsPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<InteractionSettingsPage> createState() =>
      _InteractionSettingsPageState();
}

class _InteractionSettingsPageState extends State<InteractionSettingsPage> {
  bool get _isTv => DeviceType.isTv;

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  double? _longPressMultiplierDraft;
  double? _bufferSpeedRefreshSecondsDraft;
  double? _seekBackwardDraft;
  double? _seekForwardDraft;

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final appState = widget.appState;
        final blurAllowed = !_isTv;
        final enableBlur = blurAllowed && appState.enableBlurEffects;
        final desktopShortcuts = appState.desktopShortcutBindings;

        final longPressMultiplier =
            _longPressMultiplierDraft ?? appState.longPressSpeedMultiplier;
        final seekBackward =
            (_seekBackwardDraft ?? appState.seekBackwardSeconds.toDouble())
                .round()
                .clamp(1, 120);
        final seekForward =
            (_seekForwardDraft ?? appState.seekForwardSeconds.toDouble())
                .round()
                .clamp(1, 120);
        final bufferSpeedRefreshSeconds = (_bufferSpeedRefreshSecondsDraft ??
                appState.bufferSpeedRefreshSeconds)
            .clamp(0.2, 3.0)
            .toDouble();

        return Scaffold(
          appBar: GlassAppBar(
            enableBlur: enableBlur,
            child: AppBar(
              title: const Text('交互设置'),
              centerTitle: true,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _Section(
                title: _isTv ? '遥控器' : '播放手势',
                enableBlur: enableBlur,
                child: Column(
                  children: [
                    if (!_isDesktopPlatform && !_isTv) ...[
                      SwitchListTile(
                        value: appState.gestureBrightness,
                        onChanged: (v) => appState.setGestureBrightness(v),
                        title: const Text('左侧屏幕上下拖动'),
                        subtitle: const Text('以调整屏幕亮度'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: appState.gestureVolume,
                        onChanged: (v) => appState.setGestureVolume(v),
                        title: const Text('右侧屏幕上下拖动'),
                        subtitle: const Text(
                          'Android 调整播放器音量，iOS 调整系统音量',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: appState.gestureSeek,
                        onChanged: (v) => appState.setGestureSeek(v),
                        title: const Text('横向滑动'),
                        subtitle: const Text('调整视频进度'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Divider(height: 1),
                    ],
                    SwitchListTile(
                      value: appState.gestureLongPressSpeed,
                      onChanged: (v) => appState.setGestureLongPressSpeed(v),
                      title: const Text('长按加速'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 1),
                    _SliderTile(
                      leading: const Icon(Icons.speed_outlined),
                      title: const Text('长按时的速度倍率'),
                      subtitle: const Text('会基于当前播放速率调整倍率'),
                      value: longPressMultiplier,
                      min: 0.25,
                      max: 5.0,
                      divisions: 19,
                      trailing: Text(longPressMultiplier.toStringAsFixed(2)),
                      sliderTheme: _sliderTheme(context),
                      onChanged: (v) =>
                          setState(() => _longPressMultiplierDraft = v),
                      onChangeEnd: (v) async {
                        setState(() => _longPressMultiplierDraft = null);
                        await appState.setLongPressSpeedMultiplier(v);
                      },
                    ),
                    if (!_isTv) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        value: appState.longPressSlideSpeed,
                        onChanged: (v) => appState.setLongPressSlideSpeed(v),
                        title: const Text('长按时滑动调整倍速'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
              ),
              if (!_isTv) ...[
                const SizedBox(height: 12),
                _Section(
                  title: '播放时双击',
                  enableBlur: enableBlur,
                  child: Column(
                    children: [
                      _doubleTapTile(
                        context,
                        title: '屏幕左侧',
                        value: appState.doubleTapLeft,
                        onChanged: (v) => appState.setDoubleTapLeft(v),
                      ),
                      const Divider(height: 1),
                      _doubleTapTile(
                        context,
                        title: '屏幕中间',
                        value: appState.doubleTapCenter,
                        onChanged: (v) => appState.setDoubleTapCenter(v),
                      ),
                      const Divider(height: 1),
                      _doubleTapTile(
                        context,
                        title: '屏幕右侧',
                        value: appState.doubleTapRight,
                        onChanged: (v) => appState.setDoubleTapRight(v),
                      ),
                    ],
                  ),
                ),
              ],
              if (_isDesktopPlatform) ...[
                const SizedBox(height: 12),
                _Section(
                  title: '桌面键盘/鼠标',
                  enableBlur: enableBlur,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          '提示：仅桌面端播放页有效。点击条目后按下新的按键组合。按 Backspace / Delete 清除，按 Esc 取消。',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                      for (final action in DesktopShortcutAction.values) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_desktopShortcutIcon(action)),
                          title: Text('${action.label}${action.hint}'),
                          trailing: Text(
                            desktopShortcuts.bindingOf(action)?.format() ??
                                '未设置',
                          ),
                          onTap: () async {
                            final current = desktopShortcuts.bindingOf(action);
                            final next = await _pickDesktopKeyBinding(
                              context,
                              title: action.label,
                              current: current,
                            );
                            if (!mounted) return;
                            await appState.setDesktopShortcutKeyBinding(
                              action,
                              next,
                            );
                          },
                        ),
                        if (action != DesktopShortcutAction.values.last)
                          const Divider(height: 1),
                      ],
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.mouse_outlined),
                        title: const Text('鼠标侧键（后退键）'),
                        subtitle: const Text('支持：播放页操作 / 返回上一步（全局）'),
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<DesktopMouseSideButtonAction>(
                            value: desktopShortcuts.mouseBackButtonAction,
                            items: DesktopMouseSideButtonAction.values
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) async {
                              if (v == null) return;
                              await appState.setDesktopMouseBackButtonAction(v);
                            },
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.mouse_outlined),
                        title: const Text('鼠标侧键（前进键）'),
                        subtitle: const Text('支持：播放页操作 / 返回上一步（全局）'),
                        trailing: DropdownButtonHideUnderline(
                          child: DropdownButton<DesktopMouseSideButtonAction>(
                            value: desktopShortcuts.mouseForwardButtonAction,
                            items: DesktopMouseSideButtonAction.values
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) async {
                              if (v == null) return;
                              await appState
                                  .setDesktopMouseForwardButtonAction(v);
                            },
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.restart_alt_rounded),
                        title: const Text('恢复默认快捷键'),
                        onTap: () => appState.resetDesktopShortcutBindings(),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _Section(
                title: '杂项',
                enableBlur: enableBlur,
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.home_outlined),
                      title: const Text('播放中返回桌面行为'),
                      subtitle: Text(appState.returnHomeBehavior.label),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<ReturnHomeBehavior>(
                          value: appState.returnHomeBehavior,
                          items: ReturnHomeBehavior.values
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m.label),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            appState.setReturnHomeBehavior(v);
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: appState.showSystemTimeInControls,
                      onChanged: (v) => appState.setShowSystemTimeInControls(v),
                      title: const Text('在控制栏上显示系统时间'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: appState.showBufferSpeed,
                      onChanged: (v) => appState.setShowBufferSpeed(v),
                      title: const Text('显示网速'),
                      subtitle: const Text('在线播放时在播放页左下角常驻显示网络缓冲速度'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 1),
                    _SliderTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('网速刷新间隔 (秒)'),
                      subtitle: const Text('0.2 - 3.0，默认 0.5'),
                      value: bufferSpeedRefreshSeconds,
                      min: 0.2,
                      max: 3.0,
                      divisions: 28,
                      trailing: Text(
                          '${bufferSpeedRefreshSeconds.toStringAsFixed(1)}s'),
                      sliderTheme: _sliderTheme(context),
                      onChanged: (v) =>
                          setState(() => _bufferSpeedRefreshSecondsDraft = v),
                      onChangeEnd: (v) async {
                        final seconds = (v * 10).round() / 10.0;
                        setState(() => _bufferSpeedRefreshSecondsDraft = null);
                        await appState.setBufferSpeedRefreshSeconds(seconds);
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: appState.showBatteryInControls,
                      onChanged: (v) => appState.setShowBatteryInControls(v),
                      title: const Text('在控制栏上显示剩余电量'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 1),
                    _SliderTile(
                      leading: const Icon(Icons.replay),
                      title: const Text('快退时间 (秒)'),
                      value: seekBackward.toDouble(),
                      min: 1,
                      max: 120,
                      divisions: 119,
                      trailing: Text('$seekBackward'),
                      sliderTheme: _sliderTheme(context),
                      onChanged: (v) => setState(() => _seekBackwardDraft = v),
                      onChangeEnd: (v) async {
                        final seconds = v.round().clamp(1, 120);
                        setState(() => _seekBackwardDraft = null);
                        await appState.setSeekBackwardSeconds(seconds);
                      },
                    ),
                    const Divider(height: 1),
                    _SliderTile(
                      leading: const Icon(Icons.forward),
                      title: const Text('快进时间 (秒)'),
                      value: seekForward.toDouble(),
                      min: 1,
                      max: 120,
                      divisions: 119,
                      trailing: Text('$seekForward'),
                      sliderTheme: _sliderTheme(context),
                      onChanged: (v) => setState(() => _seekForwardDraft = v),
                      onChangeEnd: (v) async {
                        final seconds = v.round().clamp(1, 120);
                        setState(() => _seekForwardDraft = null);
                        await appState.setSeekForwardSeconds(seconds);
                      },
                    ),
                    if (_isDesktopPlatform) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        value: appState.forceRemoteControlKeys,
                        onChanged: (v) => appState.setForceRemoteControlKeys(v),
                        title: const Text('强制启用遥控器按键支持'),
                        subtitle: const Text('如果不是 TV 设备，不要启用该选项!!!'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (!_isTv)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '提示：部分手势会影响拖动/双击的手感，可按需关闭。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _doubleTapTile(
    BuildContext context, {
    required String title,
    required DoubleTapAction value,
    required ValueChanged<DoubleTapAction> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.touch_app_outlined),
      title: Text(title),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<DoubleTapAction>(
          value: value,
          items: DoubleTapAction.values
              .map(
                (a) => DropdownMenuItem(
                  value: a,
                  child: Text(a.label),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ),
    );
  }

  static bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  IconData _desktopShortcutIcon(DesktopShortcutAction action) {
    return switch (action) {
      DesktopShortcutAction.playPause => Icons.play_arrow_rounded,
      DesktopShortcutAction.seekBackward => Icons.replay_rounded,
      DesktopShortcutAction.seekForward => Icons.forward_rounded,
      DesktopShortcutAction.levelUp ||
      DesktopShortcutAction.levelDown =>
        Icons.swap_vert_rounded,
      DesktopShortcutAction.volumeUp ||
      DesktopShortcutAction.volumeDown =>
        Icons.volume_up_outlined,
      DesktopShortcutAction.brightnessUp ||
      DesktopShortcutAction.brightnessDown =>
        Icons.brightness_6_outlined,
      DesktopShortcutAction.toggleFullscreen => Icons.fullscreen_rounded,
      DesktopShortcutAction.togglePanelRoute => Icons.alt_route_rounded,
      DesktopShortcutAction.togglePanelVersion => Icons.layers_outlined,
      DesktopShortcutAction.togglePanelAudio => Icons.audiotrack_rounded,
      DesktopShortcutAction.togglePanelSubtitle => Icons.subtitles_outlined,
      DesktopShortcutAction.togglePanelDanmaku => Icons.comment_outlined,
      DesktopShortcutAction.togglePanelEpisode => Icons.list_alt_rounded,
      DesktopShortcutAction.togglePanelAnime4k => Icons.auto_awesome_outlined,
    };
  }

  Future<DesktopKeyBinding?> _pickDesktopKeyBinding(
    BuildContext context, {
    required String title,
    required DesktopKeyBinding? current,
  }) async {
    return showDialog<DesktopKeyBinding?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('设置快捷键：$title'),
          content: Focus(
            autofocus: true,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              if (key == LogicalKeyboardKey.escape) {
                Navigator.of(ctx).pop(current);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.backspace ||
                  key == LogicalKeyboardKey.delete) {
                Navigator.of(ctx).pop(null);
                return KeyEventResult.handled;
              }
              if (_isModifierKey(key)) return KeyEventResult.handled;

              final pressed = HardwareKeyboard.instance.logicalKeysPressed;
              final ctrlPressed =
                  pressed.contains(LogicalKeyboardKey.controlLeft) ||
                      pressed.contains(LogicalKeyboardKey.controlRight);
              final altPressed = pressed.contains(LogicalKeyboardKey.altLeft) ||
                  pressed.contains(LogicalKeyboardKey.altRight);
              final shiftPressed =
                  pressed.contains(LogicalKeyboardKey.shiftLeft) ||
                      pressed.contains(LogicalKeyboardKey.shiftRight);
              final metaPressed =
                  pressed.contains(LogicalKeyboardKey.metaLeft) ||
                      pressed.contains(LogicalKeyboardKey.metaRight);
              Navigator.of(ctx).pop(
                DesktopKeyBinding(
                  keyId: key.keyId,
                  ctrl: ctrlPressed,
                  alt: altPressed,
                  shift: shiftPressed,
                  meta: metaPressed,
                ),
              );
              return KeyEventResult.handled;
            },
            child: Text(
              '当前：${current?.format() ?? '未设置'}\n\n'
              '按任意按键组合完成设置。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(current),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('清除'),
            ),
          ],
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
              divisions: math.max(1, divisions),
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

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    required this.enableBlur,
  });

  final String title;
  final Widget child;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      enableBlur: enableBlur,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
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
