import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';

/// 单选按钮组 - 委托给 Material 3.32+ 的 RadioGroup
class RadioGroup<T> extends StatelessWidget {
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Widget child;

  const RadioGroup({
    super.key,
    required this.groupValue,
    required this.onChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return material.RadioGroup<T>(
      groupValue: groupValue,
      onChanged: onChanged ?? (_) {},
      child: child,
    );
  }
}

/// 自动从 RadioGroup 获取 groupValue 和 onChanged 的 RadioListTile
class RadioListTile<T> extends StatelessWidget {
  final T value;
  final Widget? title;
  final Widget? subtitle;
  final bool toggleable;
  final bool? dense;
  final bool isThreeLine;
  final Widget? secondary;
  final bool selected;
  final material.ListTileControlAffinity controlAffinity;
  final material.ShapeBorder? shape;
  final Color? tileColor;
  final Color? selectedTileColor;
  final material.VisualDensity? visualDensity;
  final bool autofocus;
  final EdgeInsetsGeometry? contentPadding;

  const RadioListTile({
    super.key,
    required this.value,
    this.title,
    this.subtitle,
    this.toggleable = false,
    this.dense,
    this.isThreeLine = false,
    this.secondary,
    this.selected = false,
    this.controlAffinity = material.ListTileControlAffinity.platform,
    this.shape,
    this.tileColor,
    this.selectedTileColor,
    this.visualDensity,
    this.autofocus = false,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return material.RadioListTile<T>(
      value: value,
      title: title,
      subtitle: subtitle,
      toggleable: toggleable,
      dense: dense,
      isThreeLine: isThreeLine,
      secondary: secondary,
      selected: selected,
      controlAffinity: controlAffinity,
      shape: shape,
      tileColor: tileColor,
      selectedTileColor: selectedTileColor,
      visualDensity: visualDensity,
      autofocus: autofocus,
      contentPadding: contentPadding,
    );
  }
}
