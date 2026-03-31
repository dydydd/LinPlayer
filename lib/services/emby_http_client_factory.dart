import 'package:http/http.dart' as http;

import 'emby_http_client_factory_stub.dart'
    if (dart.library.io) 'emby_http_client_factory_io.dart' as impl;

class EmbyHttpClientFactory {
  const EmbyHttpClientFactory._();

  static http.Client createClient() => impl.createEmbyHttpClient();

  static String? describeRoute(Uri uri) => impl.describeEmbyHttpRoute(uri);
}
