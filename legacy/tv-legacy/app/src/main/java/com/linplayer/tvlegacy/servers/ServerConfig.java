package com.linplayer.tvlegacy.servers;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.json.JSONException;
import org.json.JSONArray;
import org.json.JSONObject;

public final class ServerConfig {
    public final String id;
    public final String type;
    public final String baseUrl;
    public final String apiKey;
    public final String username;
    public final String password;
    public final String displayName;
    public final String remark;
    public final String iconUrl;
    public final List<ServerLine> lines;

    public ServerConfig(
            String id,
            String type,
            String baseUrl,
            String apiKey,
            String username,
            String password,
            String displayName,
            String remark,
            String iconUrl,
            List<ServerLine> lines) {
        this.id = safeTrim(id);
        this.type = normalizeType(type);

        String b = safeTrim(baseUrl);
        List<ServerLine> normalizedLines = normalizeLines(b, lines);
        if (b.isEmpty() && !normalizedLines.isEmpty()) {
            b = safeTrim(normalizedLines.get(0).url);
        }
        this.baseUrl = b;
        this.lines = normalizedLines;

        this.apiKey = safeTrim(apiKey);
        this.username = safeTrim(username);
        this.password = safe(password);
        this.displayName = safeTrim(displayName);
        this.remark = safeTrim(remark);
        this.iconUrl = safeTrim(iconUrl);
    }

    public static ServerConfig fromJson(JSONObject o) throws JSONException {
        if (o == null) return null;

        List<ServerLine> lines = parseLines(o.optJSONArray("lines"));
        String baseUrl = o.optString("baseUrl", "");
        if ((baseUrl == null || baseUrl.trim().isEmpty()) && lines != null && !lines.isEmpty()) {
            baseUrl = lines.get(0).url;
        }
        return new ServerConfig(
                o.optString("id", ""),
                o.optString("type", ""),
                baseUrl,
                o.optString("apiKey", ""),
                o.optString("username", ""),
                o.optString("password", ""),
                o.optString("displayName", ""),
                o.optString("remark", ""),
                o.optString("iconUrl", ""),
                lines);
    }

    public JSONObject toJson() throws JSONException {
        JSONObject o = new JSONObject();
        o.put("id", safeTrim(id));
        o.put("type", safeTrim(type));
        o.put("baseUrl", safeTrim(baseUrl));
        o.put("apiKey", safeTrim(apiKey));
        o.put("username", safeTrim(username));
        o.put("password", safe(password));
        o.put("displayName", safeTrim(displayName));
        o.put("remark", safeTrim(remark));
        o.put("iconUrl", safeTrim(iconUrl));
        o.put("lines", linesToJson(lines));
        return o;
    }

    public String effectiveName() {
        String n = safeTrim(displayName);
        if (!n.isEmpty()) return n;
        n = safeTrim(baseUrl);
        return !n.isEmpty() ? n : "Server";
    }

    public boolean isType(String t) {
        String a = safeTrim(type).toLowerCase();
        String b = safeTrim(t).toLowerCase();
        return !a.isEmpty() && a.equals(b);
    }

    private static String normalizeType(String type) {
        String t = safeTrim(type).toLowerCase();
        return t.isEmpty() ? "emby" : "emby";
    }

    private static List<ServerLine> parseLines(JSONArray arr) throws JSONException {
        if (arr == null || arr.length() == 0) return Collections.emptyList();
        List<ServerLine> list = new ArrayList<>(arr.length());
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.optJSONObject(i);
            if (o == null) continue;
            ServerLine line = ServerLine.fromJson(o);
            if (line == null) continue;
            if (safeTrim(line.url).isEmpty()) continue;
            list.add(line);
        }
        return Collections.unmodifiableList(list);
    }

    private static JSONArray linesToJson(List<ServerLine> lines) throws JSONException {
        JSONArray arr = new JSONArray();
        if (lines == null) return arr;
        for (int i = 0; i < lines.size(); i++) {
            ServerLine l = lines.get(i);
            if (l == null) continue;
            if (safeTrim(l.url).isEmpty()) continue;
            arr.put(l.toJson());
        }
        return arr;
    }

    private static List<ServerLine> normalizeLines(String baseUrl, List<ServerLine> lines) {
        String b = safeTrim(baseUrl);

        Map<String, ServerLine> map = new LinkedHashMap<>();
        if (lines != null) {
            for (int i = 0; i < lines.size(); i++) {
                ServerLine l = lines.get(i);
                if (l == null) continue;
                String u = safeTrim(l.url);
                if (u.isEmpty()) continue;
                map.put(u, new ServerLine(l.name, u));
            }
        }

        if (!b.isEmpty() && !map.containsKey(b)) {
            map.put(b, new ServerLine("", b));
        }
        if (map.isEmpty()) return Collections.emptyList();
        return Collections.unmodifiableList(new ArrayList<>(map.values()));
    }

    private static String safeTrim(String s) {
        return s != null ? s.trim() : "";
    }

    private static String safe(String s) {
        return s != null ? s : "";
    }
}
