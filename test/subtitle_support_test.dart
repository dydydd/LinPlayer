import 'package:flutter_test/flutter_test.dart';

import 'package:lin_player/services/subtitle_support.dart';

void main() {
  test('external subtitle extensions include bitmap subtitle formats', () {
    expect(kSupportedExternalSubtitleExtensions, contains('sup'));
    expect(kSupportedExternalSubtitleExtensions, contains('pgs'));
  });

  test('maps external subtitle paths to expected mime types', () {
    expect(externalSubtitleMimeTypeForPath('a.srt'), 'application/x-subrip');
    expect(externalSubtitleMimeTypeForPath('a.ass'), 'text/x-ssa');
    expect(externalSubtitleMimeTypeForPath('a.ssa'), 'text/x-ssa');
    expect(externalSubtitleMimeTypeForPath('a.vtt'), 'text/vtt');
    expect(externalSubtitleMimeTypeForPath('a.sup'), 'application/pgs');
    expect(externalSubtitleMimeTypeForPath('a.pgs'), 'application/pgs');
    expect(externalSubtitleMimeTypeForPath('a.sub'), 'application/vobsub');
    expect(externalSubtitleMimeTypeForPath('a.unknown'), isNull);
  });
}
