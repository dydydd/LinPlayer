import 'package:http/http.dart' as http;
import 'package:lin_player_server_api/network/lin_http_client.dart';

http.Client createEmbyHttpClient() => LinHttpClientFactory.createClient();

String? describeEmbyHttpRoute(Uri uri) =>
    LinHttpClientFactory.describeProxyRoute(uri);
