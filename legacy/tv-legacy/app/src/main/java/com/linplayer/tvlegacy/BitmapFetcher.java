package com.linplayer.tvlegacy;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

final class BitmapFetcher {
    private BitmapFetcher() {}

    private static final int MAX_DOWNLOAD_BYTES = 6 * 1024 * 1024;

    static Bitmap fetch(Context context, String url, int maxSizePx) throws IOException {
        if (context == null) return null;
        String u = url != null ? url.trim() : "";
        if (u.isEmpty()) return null;

        OkHttpClient client = NetworkClients.okHttp(context.getApplicationContext());
        Request req = new Request.Builder().url(u).get().build();
        try (Response resp = client.newCall(req).execute()) {
            if (!resp.isSuccessful()) return null;
            ResponseBody body = resp.body();
            byte[] bytes = body != null ? readUpTo(body, MAX_DOWNLOAD_BYTES) : null;
            if (bytes == null || bytes.length == 0) return null;
            return decodeDownsampled(bytes, maxSizePx);
        }
    }

    private static Bitmap decodeDownsampled(byte[] data, int maxSizePx) {
        if (data == null || data.length == 0) return null;
        try {
            int max = maxSizePx > 0 ? maxSizePx : 0;

            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(data, 0, data.length, bounds);
            int w = bounds.outWidth;
            int h = bounds.outHeight;
            if (w <= 0 || h <= 0) {
                return BitmapFactory.decodeByteArray(data, 0, data.length);
            }

            int sample = 1;
            if (max > 0) {
                while ((w / sample) > max || (h / sample) > max) {
                    sample *= 2;
                }
            }

            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inSampleSize = Math.max(1, sample);
            opts.inPreferredConfig = Bitmap.Config.RGB_565;
            opts.inDither = true;
            return BitmapFactory.decodeByteArray(data, 0, data.length, opts);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static byte[] readUpTo(ResponseBody body, int maxBytes) throws IOException {
        if (body == null) return null;
        int limit = Math.max(0, maxBytes);
        long contentLen = body.contentLength();
        if (contentLen > limit) return null;

        InputStream in = null;
        try {
            in = body.byteStream();
            ByteArrayOutputStream baos =
                    new ByteArrayOutputStream((int) (contentLen > 0 ? Math.min(contentLen, limit) : 8192));
            byte[] buf = new byte[8192];
            int total = 0;
            int n;
            while ((n = in.read(buf)) >= 0) {
                if (n == 0) continue;
                total += n;
                if (total > limit) return null;
                baos.write(buf, 0, n);
            }
            return baos.toByteArray();
        } catch (Throwable ignored) {
            return null;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (IOException ignored) {
                }
            }
        }
    }
}
