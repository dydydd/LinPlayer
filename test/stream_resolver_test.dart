import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lin_player/services/stream_resolver/stream_resolver.dart';

void main() {
  test('adds browser UA for STRM network targets', () async {
    final bytes = utf8.encode('https://example.com/video.mp4\n');

    final res = await StreamResolver.resolve(
      StreamResolveRequest(
        sourcePathOrUrl: '',
        fileName: 'a.strm',
        bytes: bytes,
      ),
      options: const StreamResolveOptions(
        resolveRedirectsForStrmTargets: false,
      ),
    );

    expect(res.isSuccess, isTrue);
    expect(res.inputWasStrm, isTrue);
    expect(res.candidates, hasLength(1));
    expect(res.candidates.first.fromStrm, isTrue);
    expect(
      res.candidates.first.httpHeaders['User-Agent'],
      StreamResolverUserAgents.chromeLike,
    );
  });

  test('respects STRM-provided UA', () async {
    final bytes = utf8.encode(
      'https://example.com/video.mp4|User-Agent=CustomUA\n',
    );

    final res = await StreamResolver.resolve(
      StreamResolveRequest(
        sourcePathOrUrl: '',
        fileName: 'a.strm',
        bytes: bytes,
      ),
      options: const StreamResolveOptions(
        resolveRedirectsForStrmTargets: false,
      ),
    );

    expect(res.isSuccess, isTrue);
    expect(res.candidates.first.httpHeaders['User-Agent'], 'CustomUA');
  });

  test('direct URL does not inject browser UA', () async {
    final res = await StreamResolver.resolve(
      const StreamResolveRequest(
        sourcePathOrUrl: 'https://example.com/video.mp4',
      ),
    );

    expect(res.isSuccess, isTrue);
    expect(res.inputWasStrm, isFalse);
    expect(res.candidates.first.fromStrm, isFalse);
    expect(res.candidates.first.httpHeaders, isEmpty);
  });
}
