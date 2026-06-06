import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'desktop/desktop_app.dart';

/// 平台检测工具
bool get isDesktop {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return true;
  return false;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  
  if (isDesktop) {
    runApp(
      const ProviderScope(
        child: LinPlayerDesktopApp(),
      ),
    );
  } else {
    runApp(
      const ProviderScope(
        child: LinPlayerApp(),
      ),
    );
  }
}
