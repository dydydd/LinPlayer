import 'package:lin_player_core/app_config/app_config.dart';
import 'package:lin_player_core/app_config/app_product.dart';
import 'package:lin_player_core/state/media_server_type.dart';

import 'lin/lin_emby_adapter.dart';
import 'server_adapter.dart';
import 'uhd/uhd_adapter.dart';
import 'uhd/uhd_emby_like_adapter.dart';

class ServerAdapterFactory {
  static MediaServerAdapter forLogin({
    required MediaServerType serverType,
    required String deviceId,
  }) {
    if (serverType == MediaServerType.uhd) {
      return UhdEmbyLikeAdapter(serverType: serverType, deviceId: deviceId);
    }
    switch (AppConfig.current.product) {
      case AppProduct.lin:
        return LinEmbyAdapter(serverType: serverType, deviceId: deviceId);
      case AppProduct.uhd:
        return UhdServerAdapter(serverType: serverType, deviceId: deviceId);
    }
  }
}

