bool pluginDomainAllowedV1(Iterable<String> domains, String host) {
  final normalizedHost = host.trim().toLowerCase();
  if (normalizedHost.isEmpty) return false;

  for (final raw in domains) {
    final domain = raw.trim().toLowerCase();
    if (domain.isEmpty) continue;
    if (domain == '*') return true;
    if (domain == normalizedHost) return true;
    if (normalizedHost.endsWith('.$domain')) return true;
    if (domain.startsWith('*.')) {
      final suffix = domain.substring(2);
      if (suffix.isNotEmpty &&
          (normalizedHost == suffix ||
              normalizedHost.endsWith('.$suffix'))) {
        return true;
      }
    }
  }

  return false;
}

bool pluginUrlAllowedV1(Iterable<String> domains, Uri uri) {
  if (!uri.isAbsolute) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  return pluginDomainAllowedV1(domains, uri.host);
}
