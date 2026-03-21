import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import 'plugin_webview_node.dart';
import '../tv/tv_focusable.dart';

typedef PluginEventCallback = FutureOr<void> Function(
    Map<String, Object?> event);

class PluginSchemaRenderer extends StatelessWidget {
  const PluginSchemaRenderer({
    super.key,
    required this.schema,
    required this.onEvent,
    this.scrollable = true,
    this.allowWebView = false,
    this.allowedWebViewDomains = const <String>[],
  });

  final Object? schema;
  final PluginEventCallback onEvent;
  final bool scrollable;
  final bool allowWebView;
  final List<String> allowedWebViewDomains;

  @override
  Widget build(BuildContext context) {
    return _renderNode(
      context,
      schema,
      onEvent: onEvent,
      scrollable: scrollable,
      allowWebView: allowWebView,
      allowedWebViewDomains: allowedWebViewDomains,
    );
  }
}

Widget _renderNode(
  BuildContext context,
  Object? node, {
  required PluginEventCallback onEvent,
  required bool scrollable,
  required bool allowWebView,
  required List<String> allowedWebViewDomains,
}) {
  if (node == null) {
    return const Center(child: Text('插件未返回 UI Schema'));
  }
  if (node is List) {
    final children = node
        .map((e) => _renderNode(
              context,
              e,
              onEvent: onEvent,
              scrollable: scrollable,
              allowWebView: allowWebView,
              allowedWebViewDomains: allowedWebViewDomains,
            ))
        .toList(growable: false);
    if (!scrollable) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: children,
    );
  }
  if (node is! Map) {
    return Center(child: Text('不支持的 Schema 类型：${node.runtimeType}'));
  }

  final type = (node['type'] as String? ?? '').trim();
  final props = _asMap(node['props']);
  final childrenRaw = node['children'];
  final children = childrenRaw is List ? childrenRaw : const [];

  final padding = _parsePadding(props['padding']);

  switch (type) {
    case 'page':
      final child = _renderColumnLike(
        context,
        children,
        props,
        onEvent: onEvent,
        scrollable: scrollable,
        allowWebView: allowWebView,
        allowedWebViewDomains: allowedWebViewDomains,
      );
      final effectivePadding =
          padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 24);
      if (!scrollable) {
        return Padding(padding: effectivePadding, child: child);
      }
      return SingleChildScrollView(padding: effectivePadding, child: child);
    case 'column':
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: _renderColumnLike(
          context,
          children,
          props,
          onEvent: onEvent,
          scrollable: scrollable,
          allowWebView: allowWebView,
          allowedWebViewDomains: allowedWebViewDomains,
        ),
      );
    case 'row':
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: _renderRowLike(
          context,
          children,
          props,
          onEvent: onEvent,
          scrollable: scrollable,
          allowWebView: allowWebView,
          allowedWebViewDomains: allowedWebViewDomains,
        ),
      );
    case 'list':
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: _renderColumnLike(
          context,
          children,
          props,
          onEvent: onEvent,
          scrollable: scrollable,
          allowWebView: allowWebView,
          allowedWebViewDomains: allowedWebViewDomains,
        ),
      );
    case 'section':
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: _renderSection(
          context,
          children,
          props,
          onEvent: onEvent,
          scrollable: scrollable,
          allowWebView: allowWebView,
          allowedWebViewDomains: allowedWebViewDomains,
        ),
      );
    case 'card':
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(12),
          child: children.isEmpty
              ? const SizedBox.shrink()
              : _renderColumnLike(
                  context,
                  children,
                  props,
                  onEvent: onEvent,
                  scrollable: scrollable,
                  allowWebView: allowWebView,
                  allowedWebViewDomains: allowedWebViewDomains,
                ),
        ),
      );
    case 'grid':
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: _renderGrid(
          context,
          children,
          props,
          onEvent: onEvent,
          scrollable: scrollable,
          allowWebView: allowWebView,
          allowedWebViewDomains: allowedWebViewDomains,
        ),
      );
    case 'divider':
      return const Divider(height: 1);
    case 'spacer':
      final size = _asDouble(props['size']) ?? 12.0;
      final axis =
          (props['axis'] as String? ?? 'vertical').trim().toLowerCase();
      return axis == 'horizontal'
          ? SizedBox(width: size)
          : SizedBox(height: size);
    case 'text':
    case 'markdown':
      final text = (props['text'] as String? ?? '').trim();
      final style = _textStyle(context, props);
      final align = _parseTextAlign(props['align']);
      final selectable = props['selectable'] as bool? ?? false;
      if (selectable) {
        return SelectableText(
          text,
          style: style,
          textAlign: align,
        );
      }
      return Text(
        text,
        style: style,
        textAlign: align,
      );
    case 'image':
      final url = (props['url'] as String? ?? '').trim();
      if (url.isEmpty) return const SizedBox.shrink();
      final fit = _parseBoxFit(props['fit']);
      final height = _asDouble(props['height']);
      final width = _asDouble(props['width']);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          width: width,
          height: height,
          placeholder: (_, __) => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (_, __, ___) => const SizedBox(
            height: 120,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      );
    case 'webview':
      if (!allowWebView) {
        return _renderNodeNotice(context, '当前区域不支持 webview');
      }
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: PluginWebViewNode(
          props: props,
          allowedDomains: allowedWebViewDomains,
        ),
      );
    case 'button':
      return _renderButton(context, props, onEvent: onEvent);
    case 'iconbutton':
      return _renderIconButton(context, props, onEvent: onEvent);
    case 'chip':
      return _renderChip(context, props, onEvent: onEvent);
    case 'badge':
      return _renderBadge(context, props);
    case 'loading':
      return const Center(child: CircularProgressIndicator());
    case 'empty':
      final message = (props['message'] as String? ?? '暂无数据').trim();
      return Center(child: Text(message));
    case 'error':
      final message = (props['message'] as String? ?? '发生错误').trim();
      return Center(child: Text(message));
    default:
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('不支持的组件：$type'),
      );
  }
}

Widget _renderColumnLike(
  BuildContext context,
  List children, // dynamic list
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
  required bool scrollable,
  required bool allowWebView,
  required List<String> allowedWebViewDomains,
}) {
  final gap = _asDouble(props['gap']);
  final rendered = children
      .map((e) =>
          _renderNode(
            context,
            e,
            onEvent: onEvent,
            scrollable: scrollable,
            allowWebView: allowWebView,
            allowedWebViewDomains: allowedWebViewDomains,
          ))
      .toList(growable: false);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: _withGap(rendered, gap, axis: Axis.vertical),
  );
}

Widget _renderSection(
  BuildContext context,
  List children,
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
  required bool scrollable,
  required bool allowWebView,
  required List<String> allowedWebViewDomains,
}) {
  final title = (props['title'] as String? ?? '').trim();
  final subtitle = (props['subtitle'] as String? ?? '').trim();
  final gap = _asDouble(props['gap']) ?? 10;

  final body = _renderColumnLike(
    context,
    children,
    props,
    onEvent: onEvent,
    scrollable: scrollable,
    allowWebView: allowWebView,
    allowedWebViewDomains: allowedWebViewDomains,
  );

  if (title.isEmpty && subtitle.isEmpty) return body;

  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (title.isNotEmpty)
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      SizedBox(height: gap),
      body,
    ],
  );
}

Widget _renderGrid(
  BuildContext context,
  List children,
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
  required bool scrollable,
  required bool allowWebView,
  required List<String> allowedWebViewDomains,
}) {
  final columns = (_asDouble(props['columns']) ?? 1).round().clamp(1, 6);
  final gap = _asDouble(props['gap']) ?? 12;
  final rendered = children
      .map((e) =>
          _renderNode(
            context,
            e,
            onEvent: onEvent,
            scrollable: scrollable,
            allowWebView: allowWebView,
            allowedWebViewDomains: allowedWebViewDomains,
          ))
      .toList(growable: false);

  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (!width.isFinite || width <= 0) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _withGap(rendered, gap, axis: Axis.vertical),
        );
      }
      final itemWidth = ((width - gap * (columns - 1)) / columns)
          .clamp(0.0, double.infinity);
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: rendered
            .map(
              (child) => SizedBox(
                width: itemWidth,
                child: child,
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

Widget _renderRowLike(
  BuildContext context,
  List children, // dynamic list
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
  required bool scrollable,
  required bool allowWebView,
  required List<String> allowedWebViewDomains,
}) {
  final gap = _asDouble(props['gap']);
  final rendered = children
      .map((e) =>
          _renderNode(
            context,
            e,
            onEvent: onEvent,
            scrollable: scrollable,
            allowWebView: allowWebView,
            allowedWebViewDomains: allowedWebViewDomains,
          ))
      .toList(growable: false);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: _withGap(rendered, gap, axis: Axis.horizontal),
  );
}

Widget _renderNodeNotice(BuildContext context, String message) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message),
  );
}

List<Widget> _withGap(
  List<Widget> children,
  double? gap, {
  required Axis axis,
}) {
  if (gap == null || gap <= 0 || children.length <= 1) return children;
  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) {
      out.add(axis == Axis.horizontal
          ? SizedBox(width: gap)
          : SizedBox(height: gap));
    }
    out.add(children[i]);
  }
  return out;
}

Widget _renderButton(
  BuildContext context,
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
}) {
  final text = (props['text'] as String? ?? '按钮').trim();
  final enabled = props['enabled'] as bool? ?? true;
  final event = _readEvent(props['event']);

  void fire() {
    if (event == null) return;
    onEvent(event);
  }

  if (DeviceType.isTv) {
    return TvFocusable(
      enabled: enabled && event != null,
      onPressed: fire,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Center(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
    );
  }

  return FilledButton(
    onPressed: (enabled && event != null) ? fire : null,
    child: Text(text),
  );
}

Widget _renderIconButton(
  BuildContext context,
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
}) {
  final event = _readEvent(props['event']);
  final enabled = props['enabled'] as bool? ?? true;
  final tooltip = (props['tooltip'] as String? ?? '').trim();
  final iconName = _normalizeIconName(props['icon']);
  final icon = _iconWhitelist[iconName] ?? Icons.extension_outlined;

  void fire() {
    if (event == null) return;
    onEvent(event);
  }

  if (DeviceType.isTv) {
    return TvFocusable(
      enabled: enabled && event != null,
      onPressed: fire,
      padding: const EdgeInsets.all(10),
      child: Icon(icon),
    );
  }

  return IconButton(
    tooltip: tooltip.isEmpty ? null : tooltip,
    onPressed: (enabled && event != null) ? fire : null,
    icon: Icon(icon),
  );
}

Widget _renderChip(
  BuildContext context,
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
}) {
  final text = (props['text'] as String? ?? '标签').trim();
  final event = _readEvent(props['event']);
  final enabled = props['enabled'] as bool? ?? true;

  void fire() {
    if (event == null) return;
    onEvent(event);
  }

  return ActionChip(
    label: Text(text),
    onPressed: (enabled && event != null) ? fire : null,
  );
}

Widget _renderBadge(BuildContext context, Map<String, Object?> props) {
  final text = (props['text'] as String? ?? '').trim();
  if (text.isEmpty) return const SizedBox.shrink();
  final tone = (props['tone'] as String? ?? 'neutral').trim().toLowerCase();
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final (bg, fg) = switch (tone) {
    'success' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    'warning' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    'danger' => (scheme.errorContainer, scheme.onErrorContainer),
    'info' => (scheme.primaryContainer, scheme.onPrimaryContainer),
    _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: fg,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

Map<String, Object?>? _readEvent(Object? eventRaw) {
  if (eventRaw is Map) {
    return Map<String, Object?>.from(eventRaw);
  }
  if (eventRaw is String) {
    final name = eventRaw.trim();
    if (name.isNotEmpty) return {'name': name};
  }
  return null;
}

String _normalizeIconName(Object? raw) {
  final text = (raw as String? ?? '').trim().toLowerCase();
  return text.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

Map<String, Object?> _asMap(Object? raw) {
  if (raw is Map) return Map<String, Object?>.from(raw);
  return const {};
}

double? _asDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim());
  return null;
}

EdgeInsets? _parsePadding(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return EdgeInsets.all(raw.toDouble());
  if (raw is List && raw.length == 4) {
    final l = _asDouble(raw[0]) ?? 0;
    final t = _asDouble(raw[1]) ?? 0;
    final r = _asDouble(raw[2]) ?? 0;
    final b = _asDouble(raw[3]) ?? 0;
    return EdgeInsets.fromLTRB(l, t, r, b);
  }
  if (raw is Map) {
    final l = _asDouble(raw['left']) ?? 0;
    final t = _asDouble(raw['top']) ?? 0;
    final r = _asDouble(raw['right']) ?? 0;
    final b = _asDouble(raw['bottom']) ?? 0;
    return EdgeInsets.fromLTRB(l, t, r, b);
  }
  return null;
}

TextStyle? _textStyle(BuildContext context, Map<String, Object?> props) {
  final theme = Theme.of(context);
  final size = _asDouble(props['size']);
  final bold = props['bold'] as bool?;
  final style = theme.textTheme.bodyMedium;
  if (size == null && bold != true) return style;
  return style?.copyWith(
    fontSize: size ?? style.fontSize,
    fontWeight: bold == true ? FontWeight.w600 : style.fontWeight,
  );
}

TextAlign? _parseTextAlign(Object? raw) {
  final v = (raw as String? ?? '').trim().toLowerCase();
  return switch (v) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    'left' => TextAlign.left,
    _ => null,
  };
}

BoxFit? _parseBoxFit(Object? raw) {
  final v = (raw as String? ?? '').trim().toLowerCase();
  return switch (v) {
    'contain' => BoxFit.contain,
    'cover' => BoxFit.cover,
    'fill' => BoxFit.fill,
    'fitwidth' => BoxFit.fitWidth,
    'fitheight' => BoxFit.fitHeight,
    _ => BoxFit.cover,
  };
}

const Map<String, IconData> _iconWhitelist = <String, IconData>{
  'add': Icons.add,
  'arrowback': Icons.arrow_back,
  'arrowforward': Icons.arrow_forward,
  'calendar': Icons.calendar_today_outlined,
  'check': Icons.check,
  'chevronleft': Icons.chevron_left,
  'chevronright': Icons.chevron_right,
  'close': Icons.close,
  'delete': Icons.delete_outline,
  'download': Icons.download_outlined,
  'favorite': Icons.favorite_border_outlined,
  'filter': Icons.filter_list,
  'home': Icons.home_outlined,
  'info': Icons.info_outline,
  'link': Icons.link,
  'menu': Icons.menu,
  'more': Icons.more_horiz,
  'movie': Icons.movie_outlined,
  'open': Icons.open_in_new,
  'pause': Icons.pause,
  'person': Icons.person_outline,
  'play': Icons.play_arrow,
  'refresh': Icons.refresh,
  'search': Icons.search,
  'settings': Icons.settings_outlined,
  'share': Icons.share_outlined,
  'star': Icons.star_border_outlined,
  'tv': Icons.live_tv_outlined,
  'upload': Icons.upload_outlined,
};
