const List<String> kSupportedExternalSubtitleExtensions = <String>[
  'srt',
  'ass',
  'ssa',
  'vtt',
  'webvtt',
  'ttml',
  'xml',
  'dfxp',
  'sub',
  'idx',
  'sup',
  'pgs',
];

String subtitleExtensionForPath(String path) {
  var lower = path.trim().toLowerCase();
  final queryIndex = lower.indexOf('?');
  if (queryIndex >= 0) {
    lower = lower.substring(0, queryIndex);
  }
  final hashIndex = lower.indexOf('#');
  if (hashIndex >= 0) {
    lower = lower.substring(0, hashIndex);
  }
  final dotIndex = lower.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == lower.length - 1) {
    return '';
  }
  return lower.substring(dotIndex + 1);
}

String normalizeSubtitleCodec(String codec) {
  final value = codec.trim().toLowerCase();
  if (value.isEmpty) return '';
  if (value == 'srt' ||
      value.contains('subrip') ||
      value.contains('application/x-subrip')) {
    return 'srt';
  }
  if (value == 'vtt' ||
      value == 'webvtt' ||
      value.contains('text/vtt') ||
      value.contains('webvtt')) {
    return 'vtt';
  }
  if (value.contains('ass')) return 'ass';
  if (value.contains('ssa')) return 'ssa';
  if (value.contains('ttml') ||
      value.contains('dfxp') ||
      value.contains('application/ttml+xml')) {
    return 'ttml';
  }
  if (value.contains('pgs') ||
      value.contains('sup') ||
      value.contains('hdmv')) {
    return 'sup';
  }
  if (value.contains('vobsub') ||
      value.contains('dvd_subtitle') ||
      value.contains('application/vobsub') ||
      value == 'idx') {
    return 'vobsub';
  }
  if (value.contains('dvb') || value.contains('dvbsubs')) return 'dvb';
  if (value.contains('xsub')) return 'xsub';
  return value;
}

String? externalSubtitleMimeTypeForPath(String path) {
  final ext = subtitleExtensionForPath(path);
  if (ext == 'srt') return 'application/x-subrip';
  if (ext == 'vtt' || ext == 'webvtt') return 'text/vtt';
  if (ext == 'ass' || ext == 'ssa') return 'text/x-ssa';
  if (ext == 'ttml' || ext == 'xml' || ext == 'dfxp') {
    return 'application/ttml+xml';
  }
  if (ext == 'sup' || ext == 'pgs') {
    return 'application/pgs';
  }
  if (ext == 'sub' || ext == 'idx') return 'application/vobsub';
  return null;
}

String? externalSubtitleMimeTypeForCodec(String codec) {
  switch (normalizeSubtitleCodec(codec)) {
    case 'srt':
      return 'application/x-subrip';
    case 'vtt':
      return 'text/vtt';
    case 'ass':
    case 'ssa':
      return 'text/x-ssa';
    case 'ttml':
      return 'application/ttml+xml';
    case 'sup':
      return 'application/pgs';
    case 'vobsub':
      return 'application/vobsub';
    case 'dvb':
      return 'application/dvbsubs';
  }
  return null;
}

String preferredSubtitleExtensionForCodec(String codec) {
  switch (normalizeSubtitleCodec(codec)) {
    case 'ass':
      return 'ass';
    case 'ssa':
      return 'ssa';
    case 'vtt':
      return 'vtt';
    case 'ttml':
      return 'ttml';
    case 'sup':
      return 'sup';
    case 'vobsub':
    case 'dvb':
      return 'sub';
    case 'srt':
    default:
      return 'srt';
  }
}

bool isSupportedExternalSubtitleCodec(String codec) {
  final normalized = normalizeSubtitleCodec(codec);
  if (normalized.isEmpty) return true;
  return normalized == 'srt' ||
      normalized == 'ass' ||
      normalized == 'ssa' ||
      normalized == 'vtt' ||
      normalized == 'ttml' ||
      normalized == 'sup' ||
      normalized == 'vobsub' ||
      normalized == 'dvb';
}

bool isComplexSubtitleFormat({String? codec, String? mimeType}) {
  final normalizedCodec = normalizeSubtitleCodec(codec ?? '');
  final normalizedMime = normalizeSubtitleCodec(mimeType ?? '');
  const complex = <String>{'ass', 'ssa', 'sup', 'vobsub', 'dvb'};
  return complex.contains(normalizedCodec) || complex.contains(normalizedMime);
}
