Uri normalizePluginRemoteUriV1(Uri uri) {
  final cleaned =
      uri.hasFragment ? Uri.parse(uri.toString().split('#').first) : uri;
  return _normalizeGitHubContentUriV1(cleaned) ?? cleaned;
}

Uri? _normalizeGitHubContentUriV1(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host != 'github.com' && host != 'www.github.com') {
    return null;
  }

  final segments = uri.pathSegments;
  if (segments.length < 5) return null;

  final owner = segments[0].trim();
  final repo = segments[1].trim();
  final mode = segments[2];
  if (owner.isEmpty || repo.isEmpty) return null;
  if (mode != 'blob' && mode != 'raw') return null;

  final rawSegments = segments.sublist(3);
  if (rawSegments.length < 2) return null;

  return Uri.https(
    'raw.githubusercontent.com',
    [owner, repo, ...rawSegments].join('/'),
  );
}
