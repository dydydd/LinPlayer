typedef StrmParsedTarget = ({String url, Map<String, String> httpHeaders});

class StrmTargetParser {
  const StrmTargetParser._();

  static List<StrmParsedTarget> parse(
    String raw, {
    required int maxTargets,
  }) {
    var text = raw;
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    final out = <StrmParsedTarget>[];
    final pendingHeaders = <String, String>{};

    for (final line in text.split(RegExp(r'\r?\n'))) {
      var v = line.trim();
      if (v.isEmpty) continue;

      if (v.startsWith('\uFEFF')) v = v.substring(1).trim();

      if (v.startsWith('#EXTVLCOPT:') || v.startsWith('#extvlcopt:')) {
        _parseExtVlcOpt(v, pendingHeaders);
        continue;
      }

      if (v.startsWith('#')) continue;
      if (v.startsWith(';')) continue;
      if (v.startsWith('//')) continue;
      if (v.startsWith('/*') || v.startsWith('*')) continue;

      // Strip optional quotes.
      if ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1).trim();
      }

      if (v.startsWith('\uFEFF')) v = v.substring(1).trim();

      final split = _splitUrlAndPipeOptions(v);
      final url = split.$1.trim();
      if (url.isEmpty) continue;

      final headers = <String, String>{};
      if (pendingHeaders.isNotEmpty) {
        headers.addAll(pendingHeaders);
        pendingHeaders.clear();
      }
      final pipeHeaders = _parsePipeHeaderOptions(split.$2);
      if (pipeHeaders.isNotEmpty) headers.addAll(pipeHeaders);

      out.add((url: url, httpHeaders: headers));
      if (out.length >= maxTargets) break;
    }

    return out;
  }

  static String? parseFirstTargetLine(String raw) {
    final targets = parse(raw, maxTargets: 1);
    if (targets.isEmpty) return null;
    final first = targets.first.url.trim();
    return first.isEmpty ? null : first;
  }

  static (String, String?) _splitUrlAndPipeOptions(String input) {
    final idx = input.indexOf('|');
    if (idx < 0) return (input, null);
    final url = input.substring(0, idx);
    final opts = idx + 1 < input.length ? input.substring(idx + 1) : '';
    return (url, opts.isEmpty ? null : opts);
  }

  static void _parseExtVlcOpt(String line, Map<String, String> out) {
    final idx = line.indexOf(':');
    if (idx < 0 || idx + 1 >= line.length) return;
    final rest = line.substring(idx + 1).trim();
    final eq = rest.indexOf('=');
    if (eq <= 0) return;
    final key = rest.substring(0, eq).trim().toLowerCase();
    final value = rest.substring(eq + 1).trim();
    if (value.isEmpty) return;

    String? headerName;
    if (key == 'http-user-agent') headerName = 'User-Agent';
    if (key == 'http-referrer' || key == 'http-referer') headerName = 'Referer';
    if (key == 'http-origin') headerName = 'Origin';
    if (key == 'http-cookie') headerName = 'Cookie';

    if (headerName != null) {
      out[headerName] = value;
      return;
    }

    if (key == 'http-header') {
      final hv = value.trim();
      final sep = hv.indexOf(':');
      if (sep > 0) {
        final name = hv.substring(0, sep).trim();
        final v = hv.substring(sep + 1).trim();
        if (name.isNotEmpty && v.isNotEmpty) {
          out[_canonicalHeaderName(name)] = v;
        }
        return;
      }
      final eq2 = hv.indexOf('=');
      if (eq2 > 0) {
        final name = hv.substring(0, eq2).trim();
        final v = hv.substring(eq2 + 1).trim();
        if (name.isNotEmpty && v.isNotEmpty) {
          out[_canonicalHeaderName(name)] = v;
        }
      }
    }
  }

  static Map<String, String> _parsePipeHeaderOptions(String? raw) {
    final input = (raw ?? '').trim();
    if (input.isEmpty) return const <String, String>{};

    final out = <String, String>{};
    for (final part in input.split('&')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq <= 0) continue;
      final rawKey = p.substring(0, eq).trim();
      final rawVal = p.substring(eq + 1).trim();
      if (rawKey.isEmpty || rawVal.isEmpty) continue;
      try {
        final key = Uri.decodeQueryComponent(rawKey).trim();
        final value = Uri.decodeQueryComponent(rawVal).trim();
        if (key.isEmpty || value.isEmpty) continue;
        out[_canonicalHeaderName(key)] = value;
      } catch (_) {
        out[_canonicalHeaderName(rawKey)] = rawVal;
      }
    }
    return out;
  }

  static String _canonicalHeaderName(String key) {
    final lower = key.trim().toLowerCase();
    if (lower == 'user-agent') return 'User-Agent';
    if (lower == 'referer' || lower == 'referrer') return 'Referer';
    if (lower == 'origin') return 'Origin';
    if (lower == 'cookie') return 'Cookie';
    if (lower == 'authorization') return 'Authorization';
    if (lower == 'accept') return 'Accept';
    if (lower == 'range') return 'Range';
    return key.trim();
  }
}

