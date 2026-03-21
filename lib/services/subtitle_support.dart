const List<String> kSupportedExternalSubtitleExtensions = <String>[
  'srt',
  'ass',
  'ssa',
  'vtt',
  'sub',
  'sup',
  'pgs',
];

String? externalSubtitleMimeTypeForPath(String path) {
  final lower = path.trim().toLowerCase();
  if (lower.endsWith('.srt')) return 'application/x-subrip';
  if (lower.endsWith('.vtt')) return 'text/vtt';
  if (lower.endsWith('.ass') || lower.endsWith('.ssa')) return 'text/x-ssa';
  if (lower.endsWith('.ttml') || lower.endsWith('.xml')) {
    return 'application/ttml+xml';
  }
  if (lower.endsWith('.sup') || lower.endsWith('.pgs')) {
    return 'application/pgs';
  }
  if (lower.endsWith('.sub')) return 'application/vobsub';
  return null;
}
