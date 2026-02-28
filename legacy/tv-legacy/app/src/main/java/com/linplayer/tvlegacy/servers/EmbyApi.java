package com.linplayer.tvlegacy.servers;

import android.content.Context;
import android.provider.Settings;
import androidx.annotation.Nullable;
import com.linplayer.tvlegacy.BuildConfig;
import com.linplayer.tvlegacy.NetworkClients;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import okhttp3.HttpUrl;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public final class EmbyApi {
    private static final MediaType JSON = MediaType.parse("application/json; charset=utf-8");

    private EmbyApi() {}

    public static final class LoginResult {
        public final String baseUrl;
        public final String accessToken;
        public final String userId;

        LoginResult(String baseUrl, String accessToken, String userId) {
            this.baseUrl = safeTrim(baseUrl);
            this.accessToken = safeTrim(accessToken);
            this.userId = safeTrim(userId);
        }
    }

    public static LoginResult authenticateByName(
            Context context, String baseUrl, String username, String password)
            throws IOException, JSONException {
        if (context == null) throw new IllegalArgumentException("context == null");

        String rawBase = normalizeBaseUrl(baseUrl);
        String user = safeTrim(username);
        String pass = password != null ? password : "";
        if (rawBase.isEmpty()) throw new IllegalArgumentException("baseUrl is empty");
        if (user.isEmpty()) throw new IllegalArgumentException("username is empty");

        OkHttpClient client = NetworkClients.okHttp(context.getApplicationContext());

        IOException lastIo = null;
        for (String candidate : apiCandidates(rawBase)) {
            HttpUrl url = buildApiUrl(candidate, "Users/AuthenticateByName");
            if (url == null) continue;

            JSONObject body = new JSONObject();
            body.put("Username", user);
            body.put("Pw", pass);

            Request req =
                    new Request.Builder()
                            .url(url)
                            .post(RequestBody.create(JSON, body.toString()))
                            .header("Accept", "application/json")
                            .header("Content-Type", "application/json")
                            .header("Authorization", authorizationValue(context, null, null))
                            .header("X-Emby-Authorization", authorizationValue(context, null, null))
                            .build();

            try (Response resp = client.newCall(req).execute()) {
                if (!resp.isSuccessful()) {
                    // Most common failure when baseUrl is wrong: 404. Try next.
                    lastIo = new IOException("HTTP " + resp.code() + " " + resp.message());
                    continue;
                }
                ResponseBody respBody = resp.body();
                String s = respBody != null ? respBody.string() : "";
                JSONObject root = new JSONObject(s);
                String token = safeTrim(root.optString("AccessToken", ""));
                JSONObject userObj = root.optJSONObject("User");
                String userId = userObj != null ? safeTrim(userObj.optString("Id", "")) : "";
                if (token.isEmpty()) {
                    lastIo = new IOException("missing AccessToken");
                    continue;
                }
                return new LoginResult(candidate, token, userId);
            } catch (IOException e) {
                lastIo = e;
            }
        }
        if (lastIo != null) throw lastIo;
        throw new IOException("authenticate failed");
    }

    public static String fetchServerName(Context context, String baseUrl, @Nullable String token)
            throws IOException, JSONException {
        if (context == null) throw new IllegalArgumentException("context == null");
        String b = normalizeBaseUrl(baseUrl);
        if (b.isEmpty()) return "";

        OkHttpClient client = NetworkClients.okHttp(context.getApplicationContext());
        String t = safeTrim(token);

        String[] paths = new String[] {"System/Info/Public", "System/Info"};
        IOException last = null;
        for (String p : paths) {
            HttpUrl url = buildApiUrl(b, p);
            if (url == null) continue;
            Request.Builder rb =
                    new Request.Builder()
                            .url(url)
                            .get()
                            .header("Accept", "application/json")
                            .header("Authorization", authorizationValue(context, t, null))
                            .header("X-Emby-Authorization", authorizationValue(context, t, null));
            if (!t.isEmpty()) {
                rb.header("X-Emby-Token", t);
            }
            try (Response resp = client.newCall(rb.build()).execute()) {
                if (!resp.isSuccessful()) {
                    last = new IOException("HTTP " + resp.code() + " " + resp.message());
                    continue;
                }
                ResponseBody body = resp.body();
                String s = body != null ? body.string() : "";
                JSONObject root = new JSONObject(s);
                String name = safeTrim(root.optString("ServerName", ""));
                if (name.isEmpty()) name = safeTrim(root.optString("Name", ""));
                if (name.isEmpty()) name = safeTrim(root.optString("ApplicationName", ""));
                if (!name.isEmpty()) return name;
            } catch (IOException e) {
                last = e;
            }
        }
        if (last != null) throw last;
        return "";
    }

    public static List<ServerLine> fetchExtDomains(
            Context context, String baseUrl, String token, boolean allowFailure) throws IOException {
        if (context == null) throw new IllegalArgumentException("context == null");

        String b = normalizeBaseUrl(baseUrl);
        String t = safeTrim(token);
        if (b.isEmpty() || t.isEmpty()) return Collections.emptyList();

        OkHttpClient client = NetworkClients.okHttp(context.getApplicationContext());

        List<HttpUrl> urls = extDomainUrls(b, t);
        IOException last = null;
        for (HttpUrl url : urls) {
            if (url == null) continue;
            Request req =
                    new Request.Builder()
                            .url(url)
                            .get()
                            .header("Accept", "application/json")
                            .header("X-Emby-Token", t)
                            .header("Authorization", authorizationValue(context, t, null))
                            .header("X-Emby-Authorization", authorizationValue(context, t, null))
                            .build();
            try (Response resp = client.newCall(req).execute()) {
                if (!resp.isSuccessful()) {
                    last = new IOException("HTTP " + resp.code() + " " + resp.message());
                    continue;
                }
                ResponseBody body = resp.body();
                String s = body != null ? body.string() : "";
                List<ServerLine> list = parseExtDomains(s);
                return list;
            } catch (Exception e) {
                last = e instanceof IOException ? (IOException) e : new IOException(e);
            }
        }

        if (allowFailure) return Collections.emptyList();
        if (last != null) throw last;
        throw new IOException("fetch domains failed");
    }

    private static List<ServerLine> parseExtDomains(String json) throws JSONException {
        String raw = json != null ? json.trim() : "";
        if (raw.isEmpty()) return Collections.emptyList();
        JSONObject root = new JSONObject(raw);
        boolean ok = root.optBoolean("ok", false);
        if (!ok) return Collections.emptyList();
        JSONArray data = root.optJSONArray("data");
        if (data == null || data.length() == 0) return Collections.emptyList();

        List<ServerLine> out = new ArrayList<>(data.length());
        for (int i = 0; i < data.length(); i++) {
            JSONObject o = data.optJSONObject(i);
            if (o == null) continue;
            String name = safeTrim(o.optString("name", ""));
            String url = safeTrim(o.optString("url", ""));
            if (url.isEmpty()) continue;
            out.add(new ServerLine(name, normalizeBaseUrl(url)));
        }
        return Collections.unmodifiableList(out);
    }

    private static HttpUrl buildApiUrl(String baseUrl, String path) {
        String b = safeTrim(baseUrl);
        String p = safeTrim(path);
        if (b.isEmpty() || p.isEmpty()) return null;
        HttpUrl base = HttpUrl.parse(b);
        if (base == null) return null;
        HttpUrl.Builder ub = base.newBuilder();
        ub.addPathSegment("emby");
        ub.addPathSegments(p);
        return ub.build();
    }

    private static List<HttpUrl> extDomainUrls(String baseUrl, String token) {
        String b = safeTrim(baseUrl);
        String t = safeTrim(token);
        if (b.isEmpty() || t.isEmpty()) return Collections.emptyList();

        List<String> bases = apiCandidates(b);
        List<HttpUrl> out = new ArrayList<>(bases.size());
        for (String base : bases) {
            HttpUrl url = buildApiUrl(base, "System/Ext/ServerDomains");
            if (url == null) continue;
            out.add(url.newBuilder().addQueryParameter("X-Emby-Token", t).build());
        }
        return Collections.unmodifiableList(out);
    }

    private static List<String> apiCandidates(String baseUrl) {
        String b = safeTrim(baseUrl);
        if (b.isEmpty()) return Collections.emptyList();

        Set<String> out = new LinkedHashSet<>();
        String lower = b.toLowerCase(Locale.US);
        if (lower.endsWith("/emby")) {
            String without = b.substring(0, b.length() - "/emby".length());
            while (without.endsWith("/")) without = without.substring(0, without.length() - 1);
            if (!without.isEmpty()) out.add(without);
            out.add(b);
        } else {
            out.add(b);
            out.add(b + "/emby");
        }

        return Collections.unmodifiableList(new ArrayList<>(out));
    }

    public static String normalizeBaseUrl(String baseUrl) {
        String v = baseUrl != null ? baseUrl.trim() : "";
        if (v.isEmpty()) return "";
        if (!v.contains("://")) v = "http://" + v;

        HttpUrl url = HttpUrl.parse(v);
        if (url == null) {
            while (v.endsWith("/")) v = v.substring(0, v.length() - 1);
            return v;
        }

        List<String> segs = url.pathSegments();
        ArrayList<String> outSegs = new ArrayList<>(segs != null ? segs : Collections.emptyList());

        while (!outSegs.isEmpty()) {
            int n = outSegs.size();
            String last = outSegs.get(n - 1) != null ? outSegs.get(n - 1).trim().toLowerCase() : "";
            String secondLast =
                    n >= 2 && outSegs.get(n - 2) != null ? outSegs.get(n - 2).trim().toLowerCase() : "";
            if ("index.html".equals(last) && "web".equals(secondLast)) {
                outSegs.remove(n - 1);
                outSegs.remove(n - 2);
                continue;
            }
            if ("web".equals(last)) {
                outSegs.remove(n - 1);
                continue;
            }
            break;
        }

        HttpUrl.Builder b = url.newBuilder().query(null).fragment(null);
        b.encodedPath("/");
        for (int i = 0; i < outSegs.size(); i++) {
            String s = outSegs.get(i);
            String t = s != null ? s.trim() : "";
            if (t.isEmpty()) continue;
            b.addPathSegment(t);
        }
        String out = b.build().toString();
        while (out.endsWith("/")) out = out.substring(0, out.length() - 1);
        return out;
    }

    private static String authorizationValue(
            Context context, @Nullable String token, @Nullable String userId) {
        String deviceId = deviceId(context);
        String client = "LinPlayer TV Legacy";
        String device = "Android TV";
        String version = BuildConfig.VERSION_NAME;

        StringBuilder sb = new StringBuilder();
        sb.append("Emby ");
        if (userId != null && !userId.trim().isEmpty()) {
            sb.append("UserId=\"").append(userId.trim()).append("\", ");
        }
        sb.append("Client=\"").append(client).append("\", ");
        sb.append("Device=\"").append(device).append("\", ");
        sb.append("DeviceId=\"").append(deviceId).append("\", ");
        sb.append("Version=\"").append(version).append("\"");
        if (token != null && !token.trim().isEmpty()) {
            sb.append(", Token=\"").append(token.trim()).append("\"");
        }
        return sb.toString();
    }

    private static String deviceId(Context context) {
        if (context == null) return "";
        try {
            String id =
                    Settings.Secure.getString(
                            context.getContentResolver(), Settings.Secure.ANDROID_ID);
            return safeTrim(id);
        } catch (Exception ignored) {
            return "";
        }
    }

    private static String safeTrim(String s) {
        return s != null ? s.trim() : "";
    }
}
