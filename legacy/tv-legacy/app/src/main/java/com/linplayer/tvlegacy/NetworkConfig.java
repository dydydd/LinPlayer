package com.linplayer.tvlegacy;

final class NetworkConfig {
    private NetworkConfig() {}

    static String userAgent() {
        return "LinPlayer/" + BuildConfig.VERSION_NAME;
    }
}

