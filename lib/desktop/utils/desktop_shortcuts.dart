import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 桌面端全局快捷键提供者
final desktopShortcutsProvider = Provider<DesktopShortcuts>((ref) {
  return DesktopShortcuts(ref);
});

/// 桌面端全局快捷键管理
class DesktopShortcuts {
  final Ref ref;
  
  DesktopShortcuts(this.ref);
  
  /// 处理全局快捷键
  KeyEventResult handleKeyEvent(KeyEvent event, BuildContext context) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    
    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    
    // Ctrl+K: 打开搜索
    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyK) {
      context.push('/search');
      return KeyEventResult.handled;
    }
    
    // Ctrl+T: 切换主题
    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyT) {
      // TODO: 切换主题
      return KeyEventResult.handled;
    }
    
    // Ctrl+R: 刷新当前页面
    if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.keyR) {
      // TODO: 刷新当前页面
      return KeyEventResult.handled;
    }
    
    // Alt+Left: 返回上一页
    if (isAltPressed && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (context.canPop()) {
        context.pop();
      }
      return KeyEventResult.handled;
    }
    
    // F5: 刷新
    if (event.logicalKey == LogicalKeyboardKey.f5) {
      // TODO: 刷新当前页面
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }
}

/// 桌面端全局快捷键包装器
class DesktopShortcutsWrapper extends ConsumerWidget {
  final Widget child;
  
  const DesktopShortcutsWrapper({super.key, required this.child});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = ref.watch(desktopShortcutsProvider);
    
    return Focus(
      autofocus: true,
      canRequestFocus: true,
      onKeyEvent: (node, event) => shortcuts.handleKeyEvent(event, context),
      child: child,
    );
  }
}
