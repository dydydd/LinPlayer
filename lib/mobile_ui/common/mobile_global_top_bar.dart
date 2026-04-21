import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

class MobileGlobalTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  const MobileGlobalTopBar({
    super.key,
    required this.topInset,
    required this.visibility,
    required this.enableBlur,
    required this.useGlass,
    required this.serverName,
    required this.iconUrl,
    required this.onTapServer,
    required this.onTapSearch,
    required this.onTapLibrary,
    required this.onTapRoute,
  });

  final double topInset;
  final double visibility;
  final bool enableBlur;
  final bool useGlass;
  final String serverName;
  final String? iconUrl;
  final VoidCallback onTapServer;
  final VoidCallback onTapSearch;
  final VoidCallback onTapLibrary;
  final VoidCallback onTapRoute;

  double get _clampedVisibility => visibility.clamp(0.0, 1.0);

  @override
  Size get preferredSize =>
      Size.fromHeight((topInset + 56) * _clampedVisibility);

  @override
  Widget build(BuildContext context) {
    final progress = _clampedVisibility;
    if (progress <= 0.001) return const SizedBox.shrink();

    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: progress,
        child: Transform.translate(
          offset: Offset(0, -20 * (1 - progress)),
          child: Opacity(
            opacity: progress,
            child: SizedBox(
              height: topInset + 56,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, topInset + 8, 12, 8),
                child: Row(
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: MobileServerGlassButton(
                            enableBlur: enableBlur,
                            useGlass: useGlass,
                            infoStyle: true,
                            serverName: serverName,
                            iconUrl: iconUrl,
                            onTap: onTapServer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MobileTopActionIconButton(
                      icon: Icons.search,
                      tooltip: '搜索',
                      enableBlur: enableBlur,
                      useGlass: useGlass,
                      onPressed: onTapSearch,
                    ),
                    MobileTopActionIconButton(
                      icon: Icons.video_library_outlined,
                      tooltip: '媒体库',
                      enableBlur: enableBlur,
                      useGlass: useGlass,
                      onPressed: onTapLibrary,
                    ),
                    MobileTopActionIconButton(
                      icon: Icons.alt_route_outlined,
                      tooltip: '线路',
                      enableBlur: enableBlur,
                      useGlass: useGlass,
                      onPressed: onTapRoute,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MobileTopActionIconButton extends StatelessWidget {
  const MobileTopActionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enableBlur,
    required this.useGlass,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enableBlur;
  final bool useGlass;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final enabled = onPressed != null;

    final bg =
        scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.72 : 0.92);
    final fg =
        enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.38);
    final shadowColor = scheme.shadow.withValues(alpha: isDark ? 0.30 : 0.16);

    Widget child = Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: enabled ? 8 : 0,
      shadowColor: shadowColor,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Center(child: Icon(icon, color: fg, size: 20)),
      ),
    );

    if (useGlass && enableBlur) {
      final content = child;
      child = ClipOval(
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const SizedBox.expand(),
              ),
            ),
            content,
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(width: 40, height: 40, child: child),
        ),
      ),
    );
  }
}

class MobileServerGlassButton extends StatefulWidget {
  const MobileServerGlassButton({
    super.key,
    required this.serverName,
    required this.iconUrl,
    required this.onTap,
    required this.enableBlur,
    required this.useGlass,
    this.infoStyle = false,
  });

  final String serverName;
  final String? iconUrl;
  final VoidCallback? onTap;
  final bool enableBlur;
  final bool useGlass;
  final bool infoStyle;

  @override
  State<MobileServerGlassButton> createState() =>
      _MobileServerGlassButtonState();
}

class _MobileServerGlassButtonState extends State<MobileServerGlassButton> {
  bool _focused = false;
  bool _hovered = false;

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final enabled = widget.onTap != null;

    final bg =
        scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.74 : 0.94);
    final fg =
        enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.38);
    final shadowColor = scheme.shadow.withValues(alpha: isDark ? 0.30 : 0.16);
    final radius = BorderRadius.circular(widget.infoStyle ? 18 : 999);

    final highlighted = _focused || _hovered;
    final borderColor = highlighted
        ? scheme.primary.withValues(alpha: _focused ? 0.9 : 0.55)
        : (widget.infoStyle
            ? Colors.white.withValues(alpha: isDark ? 0.10 : 0.16)
            : Colors.transparent);

    Widget child = FocusableActionDetector(
      enabled: enabled,
      onShowFocusHighlight: _setFocused,
      onShowHoverHighlight: _setHovered,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.accept): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap?.call(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => widget.onTap?.call(),
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: borderColor,
            width: widget.infoStyle ? 1.2 : 2,
          ),
        ),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: radius),
          elevation: enabled ? (widget.infoStyle ? 6 : 10) : 0,
          shadowColor: shadowColor,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: radius),
            onTap: widget.onTap,
            child: Padding(
              padding: widget.infoStyle
                  ? const EdgeInsets.fromLTRB(10, 6, 10, 6)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ServerIconAvatar(
                    iconUrl: widget.iconUrl,
                    name: widget.serverName,
                    radius: widget.infoStyle ? 11 : 12,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: widget.infoStyle
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '服务器',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: fg.withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w600,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.serverName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: fg,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            widget.serverName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                  ),
                  SizedBox(width: widget.infoStyle ? 2 : 4),
                  Icon(
                    widget.infoStyle
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.swap_horiz,
                    size: widget.infoStyle ? 20 : 18,
                    color: fg.withValues(alpha: widget.infoStyle ? 0.82 : 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.useGlass && widget.enableBlur) {
      final content = child;
      child = ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const SizedBox.expand(),
              ),
            ),
            content,
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: '服务器',
      child: Tooltip(
        message: '服务器',
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.infoStyle ? 280 : 320,
            minHeight: widget.infoStyle ? 44 : 40,
          ),
          child: child,
        ),
      ),
    );
  }
}
