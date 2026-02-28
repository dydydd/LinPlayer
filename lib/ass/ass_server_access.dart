import 'package:lin_player_core/state/media_server_type.dart';
import 'package:lin_player_server_api/services/ass_api.dart';
import 'package:lin_player_state/lin_player_state.dart';

class AssServerAccess {
  const AssServerAccess({
    required this.api,
    required this.baseUrl,
    required this.token,
  });

  final AssApi api;
  final String baseUrl;
  final String token;
}

AssServerAccess? resolveAssServerAccess({
  required AppState appState,
  ServerProfile? server,
}) {
  final s = server ?? appState.activeServer;
  if (s == null) return null;
  if (s.serverType != MediaServerType.ass) return null;

  final baseUrl = s.baseUrl.trim();
  final token = s.token.trim();
  if (baseUrl.isEmpty || token.isEmpty) return null;

  return AssServerAccess(
    api: AssApi(baseUrl: baseUrl, token: token),
    baseUrl: baseUrl,
    token: token,
  );
}

