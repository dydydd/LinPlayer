package com.linplayer.tvlegacy;

import android.content.Context;
import com.google.android.exoplayer2.upstream.DataSource;
import com.google.android.exoplayer2.upstream.DefaultDataSource;
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource;
import java.util.Map;

final class ExoNetwork {
    private ExoNetwork() {}

    static DataSource.Factory dataSourceFactory(Context context) {
        return dataSourceFactory(context, null);
    }

    static DataSource.Factory dataSourceFactory(
            Context context, Map<String, String> defaultRequestHeaders) {
        DefaultHttpDataSource.Factory httpFactory =
                new DefaultHttpDataSource.Factory().setUserAgent(NetworkConfig.userAgent());
        if (defaultRequestHeaders != null && !defaultRequestHeaders.isEmpty()) {
            httpFactory.setDefaultRequestProperties(defaultRequestHeaders);
        }
        return new DefaultDataSource.Factory(context, httpFactory);
    }
}
