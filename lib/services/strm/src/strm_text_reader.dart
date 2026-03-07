import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:lin_player_server_api/network/lin_http_client.dart';

typedef StrmTextReadResult = ({String text, bool truncated});

class StrmTextReader {
  const StrmTextReader._();

  static Future<StrmTextReadResult?> read(
    String source, {
    List<int>? bytes,
    Stream<List<int>>? readStream,
    Map<String, String>? httpHeaders,
    required int maxBytes,
  }) async {
    final limit = maxBytes + 1;

    if (bytes != null) {
      final truncated = bytes.length > maxBytes;
      final slice = truncated ? bytes.sublist(0, maxBytes) : bytes;
      return (
        text: utf8.decode(slice, allowMalformed: true),
        truncated: truncated,
      );
    }

    if (readStream != null) {
      try {
        final data = await _readBytesFromStream(readStream, limit: limit);
        final truncated = data.length > maxBytes;
        final slice = truncated ? data.sublist(0, maxBytes) : data;
        return (
          text: utf8.decode(slice, allowMalformed: true),
          truncated: truncated,
        );
      } catch (_) {
        return null;
      }
    }

    final uri = Uri.tryParse(source);
    final isHttpUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    if (isHttpUrl) {
      try {
        final bytes = await _httpGetLimited(
          uri,
          limit: limit,
          headers: httpHeaders,
        );
        if (bytes == null) return null;
        final truncated = bytes.length > maxBytes;
        final slice = truncated ? bytes.sublist(0, maxBytes) : bytes;
        return (
          text: utf8.decode(slice, allowMalformed: true),
          truncated: truncated,
        );
      } catch (_) {
        return null;
      }
    }

    if (kIsWeb) return null;

    try {
      final filePath = (uri != null && uri.scheme.toLowerCase() == 'file')
          ? (() {
              try {
                return uri.toFilePath();
              } catch (_) {
                return source;
              }
            })()
          : source;
      final file = File(filePath);
      if (!await file.exists()) return null;
      final stream = file.openRead(0, limit);
      final data = await _readBytesFromStream(stream, limit: limit);
      final truncated = data.length > maxBytes;
      final slice = truncated ? data.sublist(0, maxBytes) : data;
      return (
        text: utf8.decode(slice, allowMalformed: true),
        truncated: truncated,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> _readBytesFromStream(
    Stream<List<int>> stream, {
    required int limit,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length >= limit) break;
      final remaining = limit - builder.length;
      if (chunk.length <= remaining) {
        builder.add(chunk);
      } else {
        builder.add(chunk.sublist(0, remaining));
      }
      if (builder.length >= limit) break;
    }
    return builder.takeBytes();
  }

  static Future<Uint8List?> _httpGetLimited(
    Uri uri, {
    required int limit,
    Map<String, String>? headers,
  }) async {
    final client = kIsWeb ? http.Client() : LinHttpClientFactory.createClient();
    try {
      final req = http.Request('GET', uri);
      req.followRedirects = true;
      req.maxRedirects = 5;
      req.headers['Accept'] = 'text/plain, */*';
      if (headers != null && headers.isNotEmpty) {
        req.headers.addAll(headers);
      }
      final resp = await client.send(req);
      if (resp.statusCode != 200) return null;
      return _readBytesFromStream(resp.stream, limit: limit);
    } finally {
      client.close();
    }
  }
}
