import 'dart:io';

Future<bool> launchExternalMpv({
  String? executablePath,
  required String source,
  Map<String, String>? httpHeaders,
  String? httpProxy,
  Duration? startPosition,
}) async {
  final specified = executablePath?.trim();
  final mpv = (specified != null && specified.isNotEmpty) ? specified : 'mpv';

  final args = <String>[
    '--vo=gpu-next',
    '--hwdec=no',
    '--target-colorspace-hint=yes',
    // Prefer maximum ASS/SSA compatibility for external playback too.
    '--embeddedfonts=yes',
    '--sub-ass=yes',
    '--sub-auto=fuzzy',
    '--sub-codepage=auto',
    '--sub-ass-vsfilter-aspect-compat=yes',
    '--sub-ass-vsfilter-blur-compat=yes',
  ];

  final proxy = (httpProxy ?? '').trim();
  if (proxy.isNotEmpty) {
    args.add('--http-proxy=$proxy');
  }

  if (httpHeaders != null && httpHeaders.isNotEmpty) {
    final headerFields = httpHeaders.entries
        .map((e) => '${e.key.trim()}: ${e.value}')
        .where((s) => s.trim() != ':')
        .join(',');
    if (headerFields.trim().isNotEmpty) {
      args.add('--http-header-fields=$headerFields');
    }
  }

  if (startPosition != null && startPosition > Duration.zero) {
    final seconds = startPosition.inMilliseconds / 1000.0;
    args.add('--start=${seconds.toStringAsFixed(3)}');
  }

  args.add(source);

  Future<bool> tryStart(String executable) async {
    try {
      await Process.start(
        executable,
        args,
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  if (await tryStart(mpv)) return true;
  // Common Windows name when not in PATH.
  if (mpv != 'mpv.exe' && await tryStart('mpv.exe')) return true;
  // Try alongside the running executable (useful for bundled distributions).
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final adjacent = '$exeDir${Platform.pathSeparator}mpv.exe';
  if (mpv != adjacent && await tryStart(adjacent)) return true;
  return false;
}
