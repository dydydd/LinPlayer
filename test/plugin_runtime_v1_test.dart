import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/plugins/plugin_runtime_v1.dart';

void main() {
  test('selects flutter_js backend on supported native targets', () {
    const platforms = <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ];

    for (final platform in platforms) {
      expect(
        selectPluginRuntimeBackendKindV1(
          isWeb: false,
          platform: platform,
        ),
        PluginRuntimeBackendKindV1.flutterJs,
        reason: 'expected flutter_js backend on $platform',
      );
    }
  });

  test('treats web host as unsupported for script plugins', () {
    expect(
      selectPluginRuntimeBackendKindV1(
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      PluginRuntimeBackendKindV1.unsupported,
    );
  });

  test('keeps unsupported fallback for unknown native targets', () {
    expect(
      selectPluginRuntimeBackendKindV1(
        isWeb: false,
        platform: TargetPlatform.fuchsia,
      ),
      PluginRuntimeBackendKindV1.unsupported,
    );
  });
}
