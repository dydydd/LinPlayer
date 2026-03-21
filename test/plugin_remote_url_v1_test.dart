import 'package:flutter_test/flutter_test.dart';

import 'package:lin_player/services/plugins/plugin_remote_url_v1.dart';

void main() {
  test('normalizes GitHub blob registry URL to raw content URL', () {
    final uri = normalizePluginRemoteUriV1(
      Uri.parse(
        'https://github.com/zzzwannasleep/LinplayerPluginsRepository/blob/main/registry.json',
      ),
    );

    expect(
      uri.toString(),
      'https://raw.githubusercontent.com/zzzwannasleep/LinplayerPluginsRepository/main/registry.json',
    );
  });

  test('normalizes GitHub blob manifest URL and drops page-only suffixes', () {
    final uri = normalizePluginRemoteUriV1(
      Uri.parse(
        'https://github.com/example/plugins/blob/main/plugins/demo/1.0.0/manifest.json?raw=1#L1',
      ),
    );

    expect(
      uri.toString(),
      'https://raw.githubusercontent.com/example/plugins/main/plugins/demo/1.0.0/manifest.json',
    );
  });

  test('keeps non-GitHub remote URLs unchanged apart from fragment cleanup',
      () {
    final uri = normalizePluginRemoteUriV1(
      Uri.parse(
          'https://raw.githubusercontent.com/example/repo/main/registry.json#top'),
    );

    expect(
      uri.toString(),
      'https://raw.githubusercontent.com/example/repo/main/registry.json',
    );
  });
}
