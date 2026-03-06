import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lin_player_ui/lin_player_ui.dart';

import '../tv/tv_focusable.dart';

typedef PluginEventCallback = FutureOr<void> Function(
    Map<String, Object?> event);

class PluginSchemaRenderer extends StatelessWidget {
  const PluginSchemaRenderer({
    super.key,
    required this.schema,
    required this.onEvent,
    this.scrollable = true,
  });

  final Object? schema;
  final PluginEventCallback onEvent;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return _renderNode(
      context,
      schema,
      onEvent: onEvent,
      scrollable: scrollable,
    );
  }
}

Widget _renderNode(
  BuildContext context,
  Object? node, {
  required PluginEventCallback onEvent,
  required bool scrollable,
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
        ),
      );
    case 'card':
      final child = children.isEmpty ? null : children.first;
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(12),
          child: child == null
              ? const SizedBox.shrink()
              : _renderNode(
                  context,
                  child,
                  onEvent: onEvent,
                  scrollable: scrollable,
                ),
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
    case 'button':
      return _renderButton(context, props, onEvent: onEvent);
    case 'loading':
      return const Center(child: CircularProgressIndicator());
    case 'empty':
      final message = (props['message'] as String? ?? '暂无数据').trim();
      return Center(child: Text(message));
    case 'error':
      final message = (props['message'] as String? ?? '发生错误').trim();
      return Center(child: Text(message));
    default:
      return Center(child: Text('不支持的组件：$type'));
  }
}

Widget _renderColumnLike(
  BuildContext context,
  List children, // dynamic list
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
  required bool scrollable,
}) {
  final gap = _asDouble(props['gap']);
  final rendered = children
      .map((e) =>
          _renderNode(context, e, onEvent: onEvent, scrollable: scrollable))
      .toList(growable: false);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: _withGap(rendered, gap, axis: Axis.vertical),
  );
}

Widget _renderRowLike(
  BuildContext context,
  List children, // dynamic list
  Map<String, Object?> props, {
  required PluginEventCallback onEvent,
  required bool scrollable,
}) {
  final gap = _asDouble(props['gap']);
  final rendered = children
      .map((e) =>
          _renderNode(context, e, onEvent: onEvent, scrollable: scrollable))
      .toList(growable: false);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: _withGap(rendered, gap, axis: Axis.horizontal),
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
  final eventRaw = props['event'];
  Map<String, Object?>? event;
  if (eventRaw is Map) {
    event = Map<String, Object?>.from(eventRaw);
  } else if (eventRaw is String) {
    final name = eventRaw.trim();
    if (name.isNotEmpty) event = {'name': name};
  }

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
