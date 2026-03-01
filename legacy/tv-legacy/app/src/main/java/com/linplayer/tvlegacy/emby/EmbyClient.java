package com.linplayer.tvlegacy.emby;

import android.content.Context;
import androidx.annotation.Nullable;
import com.linplayer.tvlegacy.NetworkClients;
import com.linplayer.tvlegacy.servers.EmbyApi;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import okhttp3.HttpUrl;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public final class EmbyClient {
    private final Context appContext;
    private final String apiKey;
    private final String apiPrefix;
    @Nullable private final HttpUrl baseUrl;

    private final Object userLock = new Object();
    @Nullable private String userId;

    public EmbyClient(Context context, String baseUrl, String apiPrefix, String apiKey, @Nullable String userId) {
        if (context == null) throw new IllegalArgumentException("context == null");
        this.appContext = context.getApplicationContext();
        this.apiKey = safeTrim(apiKey);
        this.apiPrefix = normalizeApiPrefix(apiPrefix);
        String b = normalizeBaseUrl(baseUrl);
        this.baseUrl = b.isEmpty() ? null : HttpUrl.parse(b);
        this.userId = safeTrim(userId);
    }

    public boolean isConfigured() {
        return baseUrl != null && apiKey != null && !apiKey.isEmpty();
    }

    public String streamUrl(String itemId) {
        if (baseUrl == null) return "";
        String id = safeTrim(itemId);
        if (id.isEmpty()) return "";
        return apiUrl("Videos/" + id + "/stream").addQueryParameter("static", "true").build().toString();
    }

    public String primaryImageUrl(String itemId, int maxWidth) {
        if (baseUrl == null) return "";
        String id = safeTrim(itemId);
        if (id.isEmpty()) return "";
        HttpUrl.Builder b = apiUrl("Items/" + id + "/Images/Primary");
        if (maxWidth > 0) b.addQueryParameter("maxWidth", String.valueOf(maxWidth));
        return b.build().toString();
    }

    public String backdropImageUrl(String itemId, int maxWidth) {
        if (baseUrl == null) return "";
        String id = safeTrim(itemId);
        if (id.isEmpty()) return "";
        HttpUrl.Builder b = apiUrl("Items/" + id + "/Images/Backdrop/0");
        if (maxWidth > 0) b.addQueryParameter("maxWidth", String.valueOf(maxWidth));
        return b.build().toString();
    }

    public EmbyItemDetails getItemDetails(String itemId) throws IOException, JSONException {
        String uid = requireUserId();
        String id = safeTrim(itemId);
        if (id.isEmpty()) return null;

        HttpUrl url =
                apiUrl("Users/" + uid + "/Items/" + id)
                        .addQueryParameter(
                                "Fields",
                                "Overview,PremiereDate,ProductionYear,RunTimeTicks,UserData,SeriesName,ParentIndexNumber,IndexNumber,SeriesId")
                        .build();
        JSONObject it = getJsonObject(url);
        return parseItemDetails(it);
    }

    public List<EmbySeason> listSeasons(String seriesId) throws IOException, JSONException {
        String uid = requireUserId();
        String id = safeTrim(seriesId);
        if (id.isEmpty()) return Collections.emptyList();

        HttpUrl url =
                apiUrl("Shows/" + id + "/Seasons")
                        .addQueryParameter("UserId", uid)
                        .addQueryParameter("Fields", "IndexNumber")
                        .build();
        JSONObject root = getJsonObject(url);
        JSONArray items = root.optJSONArray("Items");
        return parseSeasons(items);
    }

    public List<EmbyEpisode> listEpisodes(String seriesId, @Nullable String seasonId, int limit)
            throws IOException, JSONException {
        String uid = requireUserId();
        String showId = safeTrim(seriesId);
        if (showId.isEmpty()) return Collections.emptyList();

        HttpUrl.Builder b =
                apiUrl("Shows/" + showId + "/Episodes")
                        .addQueryParameter("UserId", uid)
                        .addQueryParameter("SortBy", "IndexNumber")
                        .addQueryParameter("SortOrder", "Ascending")
                        .addQueryParameter("Limit", String.valueOf(Math.max(1, limit)))
                        .addQueryParameter("Fields", "PremiereDate,RunTimeTicks,UserData");
        String sid = safeTrim(seasonId);
        if (!sid.isEmpty()) b.addQueryParameter("SeasonId", sid);
        HttpUrl url = b.build();

        JSONObject root = getJsonObject(url);
        JSONArray items = root.optJSONArray("Items");
        return parseEpisodes(items);
    }

    public boolean setFavorite(String itemId, boolean favorite) throws IOException, JSONException {
        String uid = requireUserId();
        String id = safeTrim(itemId);
        if (id.isEmpty()) return false;
        HttpUrl url = apiUrl("Users/" + uid + "/FavoriteItems/" + id).build();

        return favorite ? postEmpty(url) : delete(url);
    }

    public boolean setPlayed(String itemId, boolean played) throws IOException, JSONException {
        String uid = requireUserId();
        String id = safeTrim(itemId);
        if (id.isEmpty()) return false;
        HttpUrl url = apiUrl("Users/" + uid + "/PlayedItems/" + id).build();

        return played ? postEmpty(url) : delete(url);
    }

    public List<EmbyItem> listResume(int limit) throws IOException, JSONException {
        String uid = requireUserId();
        HttpUrl url =
                apiUrl("Users/" + uid + "/Items/Resume")
                        .addQueryParameter("Limit", String.valueOf(Math.max(1, limit)))
                        .addQueryParameter(
                                "Fields",
                                "PrimaryImageAspectRatio,ProductionYear,PremiereDate,CommunityRating,UserData,SeriesName,ParentIndexNumber,IndexNumber,SeriesId")
                        .build();
        JSONObject root = getJsonObject(url);
        JSONArray items = root.optJSONArray("Items");
        return parseItems(items, true);
    }

    public List<EmbyView> listViews() throws IOException, JSONException {
        String uid = requireUserId();
        HttpUrl url = apiUrl("Users/" + uid + "/Views").build();
        JSONObject root = getJsonObject(url);
        JSONArray items = root.optJSONArray("Items");
        if (items == null || items.length() == 0) return Collections.emptyList();

        List<EmbyView> out = new ArrayList<>(items.length());
        for (int i = 0; i < items.length(); i++) {
            JSONObject it = items.optJSONObject(i);
            if (it == null) continue;
            String id = safeTrim(it.optString("Id", ""));
            if (id.isEmpty()) continue;
            String name = safeTrim(it.optString("Name", ""));
            String img = primaryImageUrl(id, 520);
            out.add(new EmbyView(id, name.isEmpty() ? id : name, img));
        }
        return Collections.unmodifiableList(out);
    }

    public List<EmbyItem> listItemsByView(String viewId, int limit) throws IOException, JSONException {
        String uid = requireUserId();
        String id = safeTrim(viewId);
        if (id.isEmpty()) return Collections.emptyList();

        HttpUrl url =
                apiUrl("Users/" + uid + "/Items")
                        .addQueryParameter("ParentId", id)
                        .addQueryParameter("Recursive", "true")
                        .addQueryParameter("IncludeItemTypes", "Series,Movie")
                        .addQueryParameter("SortBy", "SortName")
                        .addQueryParameter("SortOrder", "Ascending")
                        .addQueryParameter("Limit", String.valueOf(Math.max(1, limit)))
                        .addQueryParameter("Fields", "ProductionYear,PremiereDate,CommunityRating")
                        .build();
        JSONObject root = getJsonObject(url);
        JSONArray items = root.optJSONArray("Items");
        return parseItems(items, false);
    }

    public List<EmbyItem> listFavorites(String includeItemType, int limit) throws IOException, JSONException {
        String uid = requireUserId();
        String t = safeTrim(includeItemType);
        if (t.isEmpty()) return Collections.emptyList();

        HttpUrl url =
                apiUrl("Users/" + uid + "/Items")
                        .addQueryParameter("Recursive", "true")
                        .addQueryParameter("Filters", "IsFavorite")
                        .addQueryParameter("IncludeItemTypes", t)
                        .addQueryParameter("SortBy", "SortName")
                        .addQueryParameter("SortOrder", "Ascending")
                        .addQueryParameter("Limit", String.valueOf(Math.max(1, limit)))
                        .addQueryParameter(
                                "Fields",
                                "ProductionYear,PremiereDate,CommunityRating,SeriesName,ParentIndexNumber,IndexNumber,SeriesId")
                        .build();
        JSONObject root = getJsonObject(url);
        JSONArray items = root.optJSONArray("Items");
        return parseItems(items, true);
    }

    public List<EmbyItem> search(String term, int limit) throws IOException, JSONException {
        String uid = requireUserId();
        String q = safeTrim(term);
        if (q.isEmpty()) return Collections.emptyList();

        HttpUrl url =
                apiUrl("Users/" + uid + "/Items")
                        .addQueryParameter("Recursive", "true")
                        .addQueryParameter("SearchTerm", q)
                        .addQueryParameter("IncludeItemTypes", "Series,Movie,Episode")
                        .addQueryParameter("Limit", String.valueOf(Math.max(1, limit)))
                        .addQueryParameter(
                                "Fields",
                                "ProductionYear,PremiereDate,CommunityRating,SeriesName,ParentIndexNumber,IndexNumber,SeriesId")
                        .build();
        JSONObject root = getJsonObject(url);
        JSONArray items = root.optJSONArray("Items");
        return parseItems(items, true);
    }

    private String requireUserId() throws IOException, JSONException {
        String cached = userId;
        if (cached != null && !cached.isEmpty()) return cached;
        synchronized (userLock) {
            cached = userId;
            if (cached != null && !cached.isEmpty()) return cached;
            HttpUrl url = apiUrl("Users/Me").build();
            JSONObject obj = getJsonObject(url);
            String id = safeTrim(obj.optString("Id", ""));
            if (id.isEmpty()) throw new IOException("Missing user id");
            userId = id;
            return id;
        }
    }

    private HttpUrl.Builder apiUrl(String path) {
        if (baseUrl == null) throw new IllegalStateException("baseUrl == null");
        String p = safeTrim(path);
        if (p.startsWith("/")) p = p.substring(1);
        HttpUrl.Builder b = baseUrl.newBuilder();
        if (!apiPrefix.isEmpty()) {
            b.addPathSegments(apiPrefix);
        }
        if (!p.isEmpty()) b.addPathSegments(p);
        if (!apiKey.isEmpty()) b.addQueryParameter("api_key", apiKey);
        return b;
    }

    private JSONObject getJsonObject(HttpUrl url) throws IOException, JSONException {
        OkHttpClient client = NetworkClients.okHttp(appContext);
        Request.Builder rb = new Request.Builder().url(url).get().header("Accept", "application/json");
        if (!apiKey.isEmpty()) {
            rb.header("X-Emby-Token", apiKey);
        }
        Request req = rb.build();
        try (Response resp = client.newCall(req).execute()) {
            if (!resp.isSuccessful()) {
                throw new IOException("HTTP " + resp.code() + " " + resp.message());
            }
            ResponseBody body = resp.body();
            String s = body != null ? body.string() : "";
            return new JSONObject(s);
        }
    }

    private boolean postEmpty(HttpUrl url) throws IOException {
        OkHttpClient client = NetworkClients.okHttp(appContext);
        RequestBody body = RequestBody.create(null, new byte[0]);
        Request.Builder rb = new Request.Builder().url(url).post(body);
        if (!apiKey.isEmpty()) {
            rb.header("X-Emby-Token", apiKey);
        }
        Request req = rb.build();
        try (Response resp = client.newCall(req).execute()) {
            if (!resp.isSuccessful()) {
                throw new IOException("HTTP " + resp.code() + " " + resp.message());
            }
            return true;
        }
    }

    private boolean delete(HttpUrl url) throws IOException {
        OkHttpClient client = NetworkClients.okHttp(appContext);
        Request.Builder rb = new Request.Builder().url(url).delete();
        if (!apiKey.isEmpty()) {
            rb.header("X-Emby-Token", apiKey);
        }
        Request req = rb.build();
        try (Response resp = client.newCall(req).execute()) {
            if (!resp.isSuccessful()) {
                throw new IOException("HTTP " + resp.code() + " " + resp.message());
            }
            return true;
        }
    }

    private List<EmbyItem> parseItems(@Nullable JSONArray items, boolean preferSeriesPosterForEpisode) {
        if (items == null || items.length() == 0) return Collections.emptyList();
        List<EmbyItem> out = new ArrayList<>(items.length());
        for (int i = 0; i < items.length(); i++) {
            JSONObject it = items.optJSONObject(i);
            EmbyItem item = parseItem(it, preferSeriesPosterForEpisode);
            if (item != null) out.add(item);
        }
        return Collections.unmodifiableList(out);
    }

    @Nullable
    private EmbyItemDetails parseItemDetails(@Nullable JSONObject it) {
        if (it == null) return null;
        String id = safeTrim(it.optString("Id", ""));
        if (id.isEmpty()) return null;

        String type = safeTrim(it.optString("Type", ""));
        String name = safeTrim(it.optString("Name", ""));
        if (name.isEmpty()) name = id;
        String overview = it.optString("Overview", "");

        String seriesId = safeTrim(it.optString("SeriesId", ""));
        String seriesName = safeTrim(it.optString("SeriesName", ""));
        int season = it.optInt("ParentIndexNumber", 0);
        int ep = it.optInt("IndexNumber", 0);

        String premiereDate = "";
        String pd = safeTrim(it.optString("PremiereDate", ""));
        if (pd.length() >= 10) premiereDate = pd.substring(0, 10);
        else if (pd.length() >= 4) premiereDate = pd.substring(0, 4);
        if (premiereDate.isEmpty()) {
            int yearInt = it.optInt("ProductionYear", 0);
            if (yearInt > 0) premiereDate = String.valueOf(yearInt);
        }

        long runtimeTicks = it.optLong("RunTimeTicks", 0L);

        boolean isFavorite = false;
        boolean played = false;
        long positionMs = 0L;
        JSONObject userData = it.optJSONObject("UserData");
        if (userData != null) {
            isFavorite = userData.optBoolean("IsFavorite", false);
            played = userData.optBoolean("Played", false);
            long ticks = userData.optLong("PlaybackPositionTicks", 0L);
            if (ticks > 0L) positionMs = ticks / 10000L;
        }

        return new EmbyItemDetails(
                id,
                type,
                name,
                overview,
                seriesId,
                seriesName,
                season,
                ep,
                premiereDate,
                runtimeTicks,
                isFavorite,
                played,
                positionMs);
    }

    private List<EmbySeason> parseSeasons(@Nullable JSONArray items) {
        if (items == null || items.length() == 0) return Collections.emptyList();
        List<EmbySeason> out = new ArrayList<>(items.length());
        for (int i = 0; i < items.length(); i++) {
            JSONObject it = items.optJSONObject(i);
            if (it == null) continue;
            String id = safeTrim(it.optString("Id", ""));
            if (id.isEmpty()) continue;
            int index = it.optInt("IndexNumber", 0);
            String name = safeTrim(it.optString("Name", ""));
            out.add(new EmbySeason(id, index, name));
        }
        Collections.sort(
                out,
                (a, b) -> {
                    int an = a != null ? a.seasonNumber : 0;
                    int bn = b != null ? b.seasonNumber : 0;
                    return an - bn;
                });
        return Collections.unmodifiableList(out);
    }

    private List<EmbyEpisode> parseEpisodes(@Nullable JSONArray items) {
        if (items == null || items.length() == 0) return Collections.emptyList();
        List<EmbyEpisode> out = new ArrayList<>(items.length());
        for (int i = 0; i < items.length(); i++) {
            JSONObject it = items.optJSONObject(i);
            if (it == null) continue;
            String id = safeTrim(it.optString("Id", ""));
            if (id.isEmpty()) continue;

            String name = safeTrim(it.optString("Name", ""));
            int season = it.optInt("ParentIndexNumber", 0);
            int ep = it.optInt("IndexNumber", 0);

            String premiereDate = "";
            String pd = safeTrim(it.optString("PremiereDate", ""));
            if (pd.length() >= 10) premiereDate = pd.substring(0, 10);
            else if (pd.length() >= 4) premiereDate = pd.substring(0, 4);

            long runtimeTicks = it.optLong("RunTimeTicks", 0L);

            boolean played = false;
            long positionMs = 0L;
            JSONObject userData = it.optJSONObject("UserData");
            if (userData != null) {
                played = userData.optBoolean("Played", false);
                long ticks = userData.optLong("PlaybackPositionTicks", 0L);
                if (ticks > 0L) positionMs = ticks / 10000L;
            }

            out.add(new EmbyEpisode(id, name, season, ep, premiereDate, runtimeTicks, played, positionMs));
        }
        return Collections.unmodifiableList(out);
    }

    @Nullable
    private EmbyItem parseItem(@Nullable JSONObject it, boolean preferSeriesPosterForEpisode) {
        if (it == null) return null;
        String id = safeTrim(it.optString("Id", ""));
        if (id.isEmpty()) return null;

        String type = safeTrim(it.optString("Type", ""));
        String name = safeTrim(it.optString("Name", ""));
        if (name.isEmpty()) name = id;

        String seriesId = safeTrim(it.optString("SeriesId", ""));
        String seriesName = safeTrim(it.optString("SeriesName", ""));
        int season = it.optInt("ParentIndexNumber", 0);
        int ep = it.optInt("IndexNumber", 0);

        double ratingValue = it.optDouble("CommunityRating", 0);
        String rating = ratingValue > 0 ? String.format(Locale.US, "%.1f", ratingValue) : "";

        int yearInt = it.optInt("ProductionYear", 0);
        String yearOrDate = yearInt > 0 ? String.valueOf(yearInt) : "";
        if (yearOrDate.isEmpty()) {
            String pd = safeTrim(it.optString("PremiereDate", ""));
            if (pd.length() >= 10) yearOrDate = pd.substring(0, 10);
            else if (pd.length() >= 4) yearOrDate = pd.substring(0, 4);
        }

        long positionMs = 0L;
        JSONObject userData = it.optJSONObject("UserData");
        if (userData != null) {
            long ticks = userData.optLong("PlaybackPositionTicks", 0L);
            if (ticks > 0L) positionMs = ticks / 10000L;
        }

        String imageId = id;
        if (preferSeriesPosterForEpisode && "Episode".equalsIgnoreCase(type)) {
            if (!seriesId.isEmpty()) imageId = seriesId;
        }
        String imageUrl = primaryImageUrl(imageId, 520);

        return new EmbyItem(
                id,
                type,
                name,
                seriesId,
                seriesName,
                season,
                ep,
                imageUrl,
                rating,
                yearOrDate,
                positionMs);
    }

    private static String normalizeBaseUrl(String baseUrl) {
        String b = EmbyApi.normalizeBaseUrl(baseUrl);
        while (b.endsWith("/")) b = b.substring(0, b.length() - 1);
        return b;
    }

    private static String safeTrim(String s) {
        return s != null ? s.trim() : "";
    }

    private static String normalizeApiPrefix(String prefix) {
        String p = safeTrim(prefix);
        while (p.startsWith("/")) p = p.substring(1);
        while (p.endsWith("/")) p = p.substring(0, p.length() - 1);
        return p;
    }
}
