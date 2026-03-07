import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/strm/strm_resolver.dart';

void main() {
  test('resolve STRM from bytes (basic)', () async {
    final bytes = utf8.encode('''
# comment
; comment
https://example.com/video.mp4
''');

    final res = await StrmResolver.resolve(
      sourcePathOrUrl: '/tmp/test.strm',
      bytes: bytes,
    );

    expect(res.isSuccess, isTrue);
    expect(res.targets, hasLength(1));
    expect(res.targets.first.url, 'https://example.com/video.mp4');
    expect(res.targets.first.httpHeaders, isEmpty);
  });

  test('parse URL pipe headers', () async {
    final bytes = utf8.encode(
      'https://example.com/v.mp4|User-Agent=UA&Referer=https%3A%2F%2Fref.example%2F\n',
    );

    final res = await StrmResolver.resolve(
      sourcePathOrUrl: 'https://example.com/a.strm',
      bytes: bytes,
    );

    expect(res.isSuccess, isTrue);
    expect(res.targets.first.url, 'https://example.com/v.mp4');
    expect(res.targets.first.httpHeaders['User-Agent'], 'UA');
    expect(res.targets.first.httpHeaders['Referer'], 'https://ref.example/');
  });

  test('parse #EXTVLCOPT headers (apply to next URL only)', () async {
    final bytes = utf8.encode('''
#EXTVLCOPT:http-user-agent=MyUA
#EXTVLCOPT:http-referrer=https://ref.example/
https://a.example/1.mp4
https://a.example/2.mp4
''');

    final res = await StrmResolver.resolve(
      sourcePathOrUrl: 'https://example.com/movie.strm',
      bytes: bytes,
    );

    expect(res.isSuccess, isTrue);
    expect(res.targets, hasLength(2));
    expect(res.targets[0].httpHeaders['User-Agent'], 'MyUA');
    expect(res.targets[0].httpHeaders['Referer'], 'https://ref.example/');
    expect(res.targets[1].httpHeaders, isEmpty);
  });

  test('resolve relative URL against HTTP base', () async {
    final bytes = utf8.encode('video.mp4\n');

    final res = await StrmResolver.resolve(
      sourcePathOrUrl: 'https://example.com/dir/movie.strm',
      bytes: bytes,
    );

    expect(res.isSuccess, isTrue);
    expect(res.targets.first.url, 'https://example.com/dir/video.mp4');
  });

  test('resolve relative path against Windows file base', () async {
    if (!Platform.isWindows) return;
    final bytes = utf8.encode('video.mp4\n');

    final res = await StrmResolver.resolve(
      sourcePathOrUrl: r'C:\Videos\movie.strm',
      bytes: bytes,
    );

    expect(res.isSuccess, isTrue);
    expect(res.targets.first.url.toLowerCase(), r'c:\videos\video.mp4');
  });
}

