import 'dart:async';

enum StreamMediaType {
  unknown,
  file,
  hls,
  dash,
}

enum StreamErrorCode {
  unknown,
  noCandidates,
  strmReadFailed,
  strmParseFailed,
  redirectResolveFailed,
  rangeUnsupported,
  forbidden,
}

class StreamError {
  const StreamError({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final StreamErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
}

class PlayableSource {
  PlayableSource({
    required String url,
    Map<String, String>? httpHeaders,
    this.mediaTypeHint = StreamMediaType.unknown,
    this.fromStrm = false,
    List<String>? redirectChain,
    this.contentTypeHint,
    this.supportsByteRange,
    this.httpStatusHint,
  })  : url = url.trim(),
        httpHeaders = Map.unmodifiable(
          (httpHeaders ?? const <String, String>{})
              .map((k, v) => MapEntry(k.trim(), v.trim())),
        ),
        redirectChain = List<String>.unmodifiable(
          (redirectChain ?? const <String>[])
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty),
        );

  final String url;
  final Map<String, String> httpHeaders;
  final StreamMediaType mediaTypeHint;
  final bool fromStrm;

  /// Redirect chain (best-effort), including the original URL and the final URL.
  final List<String> redirectChain;

  /// Best-effort MIME type hint (e.g. `application/vnd.apple.mpegurl`).
  final String? contentTypeHint;

  /// Best-effort hint whether server supports `Range: bytes=...`.
  final bool? supportsByteRange;

  /// Best-effort HTTP status hint from resolver probes.
  final int? httpStatusHint;
}

class StreamResolveRequest {
  const StreamResolveRequest({
    required this.sourcePathOrUrl,
    this.fileName,
    this.bytes,
    this.readStream,
    this.httpHeaders,
  });

  final String sourcePathOrUrl;
  final String? fileName;
  final List<int>? bytes;
  final Stream<List<int>>? readStream;
  final Map<String, String>? httpHeaders;
}

class StreamResolveResult {
  const StreamResolveResult._({
    required this.candidates,
    required this.inputWasStrm,
    required this.usedDirectPlayFallback,
    this.error,
  });

  factory StreamResolveResult.success({
    required List<PlayableSource> candidates,
    required bool inputWasStrm,
    required bool usedDirectPlayFallback,
  }) {
    return StreamResolveResult._(
      candidates: List<PlayableSource>.unmodifiable(candidates),
      inputWasStrm: inputWasStrm,
      usedDirectPlayFallback: usedDirectPlayFallback,
    );
  }

  factory StreamResolveResult.failure({
    required StreamError error,
    required bool inputWasStrm,
    required bool usedDirectPlayFallback,
  }) {
    return StreamResolveResult._(
      candidates: const <PlayableSource>[],
      inputWasStrm: inputWasStrm,
      usedDirectPlayFallback: usedDirectPlayFallback,
      error: error,
    );
  }

  final List<PlayableSource> candidates;
  final bool inputWasStrm;
  final bool usedDirectPlayFallback;
  final StreamError? error;

  bool get isSuccess => candidates.isNotEmpty;
}

class StreamResolveOptions {
  const StreamResolveOptions({
    this.preferBrowserUserAgentForStrm = true,
    this.browserUserAgent = StreamResolverUserAgents.chromeLike,
    this.resolveRedirectsForStrmTargets = true,
    this.maxRedirects = 5,
    this.redirectResolveTimeout = const Duration(seconds: 4),
    this.keepOriginalCandidateWhenRedirected = true,
    this.cacheRedirectResolution = true,
    this.redirectCacheTtl = const Duration(minutes: 1),
    this.redirectCacheMaxEntries = 128,
    this.resolveBodyLinkForStrmTargets = true,
    this.bodyLinkResolveMaxBytes = 16 * 1024,
    this.bodyLinkResolveTimeout = const Duration(seconds: 4),
  });

  final bool preferBrowserUserAgentForStrm;
  final String browserUserAgent;

  /// Resolve `3xx Location` redirects for STRM targets before handing them to
  /// the player. This improves compatibility with some cloud-disk links where
  /// the playback engine may drop headers/cookies across redirects.
  final bool resolveRedirectsForStrmTargets;

  /// Maximum number of redirect hops to follow.
  final int maxRedirects;

  /// Per-request timeout when resolving redirects.
  final Duration redirectResolveTimeout;

  /// If true, keep the original URL as a fallback candidate when a different
  /// redirect-resolved URL is produced.
  final bool keepOriginalCandidateWhenRedirected;

  /// Cache redirect resolution results in-memory for a short time.
  final bool cacheRedirectResolution;

  /// TTL for redirect resolution cache entries.
  final Duration redirectCacheTtl;

  /// Max number of redirect cache entries.
  final int redirectCacheMaxEntries;

  /// Some STRM targets are not media URLs themselves, but an API endpoint that
  /// returns a real playable URL (plain text / JSON). If enabled, the resolver
  /// will fetch a small response body to extract that URL.
  final bool resolveBodyLinkForStrmTargets;

  /// Maximum bytes to read when resolving a "body link" endpoint.
  final int bodyLinkResolveMaxBytes;

  /// Per-request timeout when resolving a "body link" endpoint.
  final Duration bodyLinkResolveTimeout;
}

class StreamResolverUserAgents {
  const StreamResolverUserAgents._();

  /// A conservative browser-like UA string for better cloud-disk compatibility.
  static const String chromeLike =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}
