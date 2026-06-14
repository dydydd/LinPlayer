import 'dart:io';

/// 桌面端原生 UI 风格。
///
/// 用于在运行时为不同操作系统选择对应的原生组件库：
/// - [fluent]  -> Windows，使用 fluent_ui（仿 WinUI / Fluent Design）
/// - [macos]   -> macOS，使用 macos_ui（仿 AppKit）
/// - [material] -> Linux，使用 Material（暂无统一的原生外观）
enum DesktopUiStyle { fluent, macos, material }

/// 当前平台应采用的原生 UI 风格。
DesktopUiStyle get desktopUiStyle {
  if (Platform.isWindows) return DesktopUiStyle.fluent;
  if (Platform.isMacOS) return DesktopUiStyle.macos;
  return DesktopUiStyle.material;
}

bool get isFluentStyle => desktopUiStyle == DesktopUiStyle.fluent;
bool get isMacosStyle => desktopUiStyle == DesktopUiStyle.macos;
bool get isMaterialDesktopStyle => desktopUiStyle == DesktopUiStyle.material;
